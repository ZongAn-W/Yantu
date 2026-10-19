import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/token_store.dart';
import '../config/app_config.dart';
import '../errors/app_failure.dart';
import 'browser_credentials.dart';

typedef SessionExpiredCallback = Future<void> Function();

class ApiClient {
  ApiClient({
    required AppConfig config,
    required this.tokenStore,
    this.onSessionExpired,
    bool? usesBearer,
    Dio? dio,
  }) : usesBearer = usesBearer ?? !kIsWeb,
       _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = config.apiBaseUrl
      ..connectTimeout = const Duration(seconds: 15)
      ..sendTimeout = const Duration(seconds: 45)
      ..receiveTimeout = const Duration(seconds: 45)
      ..headers['accept'] = 'application/json';
    if (dio == null) configureBrowserCredentials(_dio);
    _dio.interceptors.add(_AuthInterceptor(this));
  }

  final Dio _dio;
  final TokenStore tokenStore;
  final bool usesBearer;
  SessionExpiredCallback? onSessionExpired;
  SessionExpiredCallback? onAccountDeleted;
  Future<void>? _refreshing;
  int _sessionGeneration = 0;
  int _credentialRevision = 0;

  Future<Response<dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _request(path, 'GET', query: query);

  Future<Response<dynamic>> post(
    String path, {
    Object? data,
    Options? options,
  }) => _request(path, 'POST', data: data, options: options);

  Future<Response<dynamic>> put(String path, {Object? data}) =>
      _request(path, 'PUT', data: data);

  Future<Response<dynamic>> patch(String path, {Object? data}) =>
      _request(path, 'PATCH', data: data);

  Future<Response<dynamic>> delete(String path, {Object? data}) =>
      _request(path, 'DELETE', data: data);

  Future<Response<dynamic>> _request(
    String path,
    String method, {
    Object? data,
    Map<String, dynamic>? query,
    Options? options,
  }) async {
    try {
      return await _dio.request<dynamic>(
        path,
        data: data,
        queryParameters: query,
        options: (options ?? Options()).copyWith(
          method: method,
          receiveTimeout: path.startsWith('/api/ai/')
              ? const Duration(seconds: 240)
              : null,
        ),
      );
    } catch (error) {
      throw failureFrom(error);
    }
  }

  Future<void> setTokens(TokenPair tokens) async {
    await tokenStore.write(tokens);
    _credentialRevision++;
  }

  Future<void> clearSession() async {
    _sessionGeneration++;
    _credentialRevision++;
    try {
      await tokenStore.clear();
    } finally {
      await onSessionExpired?.call();
    }
  }

  Future<void> refreshTokens() =>
      _refreshing ??= _performRefresh().whenComplete(() {
        _refreshing = null;
      });

  Future<void> _performRefresh() async {
    final generation = _sessionGeneration;
    final tokens = usesBearer ? await tokenStore.read() : null;
    if (usesBearer && tokens == null) {
      await clearSession();
      throw const UnauthorizedFailure();
    }
    try {
      final response = await _dio.post<dynamic>(
        usesBearer ? '/api/auth/token/refresh' : '/api/auth/refresh',
        data: usesBearer ? {'refreshToken': tokens!.refreshToken} : null,
        options: Options(receiveTimeout: const Duration(seconds: 15)),
      );
      if (generation != _sessionGeneration) throw const UnauthorizedFailure();
      if (usesBearer) {
        await acceptSession(response.data);
      } else {
        _credentialRevision++;
      }
    } catch (error) {
      final failure = failureFrom(error);
      if (generation == _sessionGeneration &&
          (failure is UnauthorizedFailure || failure is ResponseFailure)) {
        await clearSession();
      }
      throw failure;
    }
  }

  Future<void> acceptSession(Object? value) async {
    if (!usesBearer) return;
    if (value is! Map ||
        value['accessToken'] is! String ||
        (value['accessToken'] as String).isEmpty ||
        value['refreshToken'] is! String ||
        (value['refreshToken'] as String).isEmpty ||
        value['expiresIn'] is! int ||
        (value['expiresIn'] as int) <= 0) {
      throw const ResponseFailure();
    }
    await setTokens(
      TokenPair(
        accessToken: value['accessToken'] as String,
        refreshToken: value['refreshToken'] as String,
        expiresAt: DateTime.now().add(
          Duration(seconds: value['expiresIn'] as int),
        ),
      ),
    );
  }

  AppFailure failureFrom(Object error) {
    if (error is AppFailure) return error;
    if (error is DioException) {
      if (error.error is AppFailure) return error.error! as AppFailure;
      final status = error.response?.statusCode;
      final data = error.response?.data;
      final message = data is Map && data['error'] is String
          ? data['error'] as String
          : null;
      if (status == 410 && data is Map && data['code'] == 'ACCOUNT_DELETED') {
        return AccountDeletedFailure(message ?? '账号已注销，请重新登录');
      }
      if (status == 401) return UnauthorizedFailure(message ?? '登录已过期，请重新登录');
      if (status == 409) return ConflictFailure(message ?? '数据冲突，请重新加载');
      if (status != null && status >= 500) {
        return ServerFailure(message ?? '服务器暂不可用，请稍后重试');
      }
      if (status != null) {
        return ValidationFailure(
          message ?? '请求失败（$status）',
          statusCode: status,
        );
      }
      return const OfflineFailure();
    }
    return const ResponseFailure();
  }

  void close() => _dio.close();
}

class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this.client);
  final ApiClient client;

  bool _isAuth(RequestOptions options) =>
      options.path.startsWith('/api/auth/') &&
      options.path != '/api/auth/delete-account';

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final generation = client._sessionGeneration;
    try {
      if (client.usesBearer) {
        if (_isAuth(options)) {
          options.headers['X-Client-Auth'] = 'bearer';
        } else {
          var tokens = await client.tokenStore.read();
          if (tokens != null && !tokens.expiresAt.isAfter(DateTime.now())) {
            await client.refreshTokens();
            tokens = await client.tokenStore.read();
          }
          if (tokens != null) {
            options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
          }
        }
      }
      if (generation != client._sessionGeneration) {
        throw const UnauthorizedFailure();
      }
      options.extra['sessionGeneration'] = generation;
      options.extra['credentialRevision'] = client._credentialRevision;
      handler.next(options);
    } catch (error) {
      handler.reject(DioException(requestOptions: options, error: error));
    }
  }

  @override
  Future<void> onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final request = error.requestOptions;
    if (client.failureFrom(error) is AccountDeletedFailure) {
      // Finish the failing request before cleanup drains the coordinator that
      // owns it; awaiting cleanup here would wait on this very request.
      handler.next(error);
      if (request.extra['sessionGeneration'] == client._sessionGeneration) {
        Future<void>(() async {
          if (request.extra['sessionGeneration'] == client._sessionGeneration) {
            await client.onAccountDeleted?.call();
          }
        });
      }
      return;
    }
    if (error.response?.statusCode != 401 || _isAuth(request)) {
      handler.next(error);
      return;
    }
    try {
      if (request.extra['sessionGeneration'] != client._sessionGeneration) {
        throw const UnauthorizedFailure();
      }
      if (request.extra['retriedAfterRefresh'] == true) {
        await client.clearSession();
        throw const UnauthorizedFailure();
      }
      if (request.extra['credentialRevision'] == client._credentialRevision) {
        await client.refreshTokens();
      }
      request.extra['retriedAfterRefresh'] = true;
      handler.resolve(await client._dio.fetch<dynamic>(request));
    } catch (caught) {
      handler.reject(
        DioException(
          requestOptions: request,
          error: client.failureFrom(caught),
        ),
      );
    }
  }
}
