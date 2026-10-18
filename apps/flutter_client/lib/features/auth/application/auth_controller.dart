import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../data/auth_repository.dart';
import '../../../core/errors/app_failure.dart';

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(identityStoreProvider),
  ),
);

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Runs before the account session is cleared. It must finish persisting any
/// durable local state (for example the study timer checkpoint); a thrown error
/// aborts an explicit sign-out so no learned time is silently lost.
typedef SessionEndHandler = Future<void> Function();

class AuthState {
  const AuthState({
    this.user,
    this.loading = false,
    this.restoring = false,
    this.error,
    this.codeSending = false,
    this.retrySeconds = 0,
    this.notice,
  });

  final AuthUser? user;
  final bool loading;
  final bool restoring;
  final String? error;
  final bool codeSending;
  final int retrySeconds;
  final String? notice;

  AuthState copyWith({
    bool? loading,
    String? error,
    bool? codeSending,
    int? retrySeconds,
    String? notice,
  }) => AuthState(
    user: user,
    loading: loading ?? this.loading,
    restoring: restoring,
    error: error,
    codeSending: codeSending ?? this.codeSending,
    retrySeconds: retrySeconds ?? this.retrySeconds,
    notice: notice,
  );
}

class AuthController extends Notifier<AuthState> {
  Timer? _cooldown;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _signingOut;
  final Set<SessionEndHandler> _sessionEndHandlers = {};

  /// Registered by durable local-state owners (currently the study timer). The
  /// handler list is intentionally small and ordered by registration.
  void addSessionEndHandler(SessionEndHandler handler) =>
      _sessionEndHandlers.add(handler);

  void removeSessionEndHandler(SessionEndHandler handler) =>
      _sessionEndHandlers.remove(handler);

  Future<void> _runSessionEndHandlers() async {
    for (final handler in List<SessionEndHandler>.of(_sessionEndHandlers)) {
      await handler();
    }
  }

  @override
  AuthState build() {
    final client = ref.read(apiClientProvider);
    client.onSessionExpired = expire;
    ref.onDispose(() {
      _disposed = true;
      _cooldown?.cancel();
      client.onSessionExpired = null;
    });
    Future.microtask(restoreSession);
    return const AuthState(restoring: true);
  }

  Future<void> restoreSession() async {
    final generation = ++_generation;
    try {
      final client = ref.read(apiClientProvider);
      if (client.usesBearer && await client.tokenStore.read() == null) {
        if (!_disposed && generation == _generation) state = const AuthState();
        return;
      }
      final user = await ref.read(authRepositoryProvider).currentUser();
      if (!_disposed && generation == _generation) {
        state = AuthState(user: user);
      }
    } catch (error) {
      if (!_disposed && generation == _generation) {
        if (error is OfflineFailure || error is ServerFailure) {
          Map<String, dynamic>? cached;
          try {
            cached = await ref.read(identityStoreProvider).load();
          } catch (_) {
            /* Keep authentication available when the local database needs repair. */
          }
          if (cached != null && !_disposed && generation == _generation) {
            state = AuthState(
              user: AuthUser.fromJson(cached),
              error: '离线模式：已载入本机账号计划',
            );
            return;
          }
        }
        state = AuthState(
          error: ref.read(apiClientProvider).failureFrom(error).message,
        );
      }
    }
  }

  Future<AuthUser?> login(String email, String password) =>
      _run(() => ref.read(authRepositoryProvider).login(email, password));

  Future<AuthUser?> register({
    required String email,
    required String username,
    required String password,
    required String code,
  }) => _run(
    () => ref
        .read(authRepositoryProvider)
        .register(
          email: email,
          username: username,
          password: password,
          code: code,
        ),
  );

  Future<AuthUser?> _run(Future<AuthUser> Function() operation) async {
    if (state.loading || state.restoring || state.codeSending) return null;
    final generation = ++_generation;
    state = state.copyWith(loading: true);
    try {
      final user = await operation();
      if (_disposed || generation != _generation) return null;
      state = AuthState(user: user);
      return user;
    } catch (error) {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(
          loading: false,
          error: ref.read(apiClientProvider).failureFrom(error).message,
        );
      }
      return null;
    }
  }

  Future<void> requestRegistrationCode(String email) async {
    if (state.codeSending || state.retrySeconds > 0) return;
    state = state.copyWith(codeSending: true);
    try {
      final seconds = await ref
          .read(authRepositoryProvider)
          .requestRegistrationCode(email);
      if (_disposed) return;
      final until = DateTime.now().add(Duration(seconds: seconds));
      state = state.copyWith(
        codeSending: false,
        retrySeconds: seconds,
        notice: '验证码已发送，有效期 10 分钟，请查收邮箱。',
      );
      _cooldown?.cancel();
      _cooldown = Timer.periodic(const Duration(seconds: 1), (timer) {
        final remaining = until.difference(DateTime.now()).inMilliseconds;
        final seconds = remaining <= 0 ? 0 : (remaining / 1000).ceil();
        state = state.copyWith(
          retrySeconds: seconds,
          notice: state.notice,
          error: state.error,
        );
        if (seconds == 0) timer.cancel();
      });
    } catch (error) {
      if (!_disposed) {
        state = state.copyWith(
          codeSending: false,
          error: ref.read(apiClientProvider).failureFrom(error).message,
        );
      }
    }
  }

  Future<void> expire() async {
    _generation++;
    final failure = await _stopLocalState();
    if (_disposed) return;
    state = AuthState(
      error: failure == null
          ? null
          : '登录会话已失效，但本机计时记录未能保存：$failure',
    );
  }

  /// Stops durable local state before the session is dropped.
  ///
  /// Expiry cannot be cancelled, so failures are reported instead of thrown.
  Future<Object?> _stopLocalState() async {
    Object? failure;
    try {
      await _runSessionEndHandlers();
    } catch (error) {
      failure = error;
    }
    try {
      await ref.read(identityStoreProvider).save(null);
    } catch (error) {
      failure ??= error;
    }
    return failure;
  }

  /// Explicit sign-out: persist durable local state first, then clear the local
  /// session. The server revocation is best effort so an offline user can still
  /// sign out after the timer checkpoint was saved.
  Future<void> signOut() => _signingOut ??= _signOut().whenComplete(() {
    _signingOut = null;
  });

  Future<void> _signOut() async {
    if (state.loading) return;
    final generation = ++_generation;
    state = state.copyWith(loading: true);
    try {
      await _runSessionEndHandlers();
    } catch (error) {
      if (!_disposed && generation == _generation) {
        state = state.copyWith(
          loading: false,
          error: '退出前无法保存本机计时记录：$error，账号保持登录。',
        );
      }
      return;
    }
    if (_disposed || generation != _generation) return;
    Object? revokeFailure;
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (error) {
      // Local credentials were already cleared by the repository; only the
      // server-side revocation could not complete.
      revokeFailure = error;
    }
    if (_disposed || generation != _generation) return;
    state = AuthState(
      notice: revokeFailure == null
          ? null
          : '已退出登录；云端会话撤销未完成，网络恢复后会自动清理。',
    );
  }
}
