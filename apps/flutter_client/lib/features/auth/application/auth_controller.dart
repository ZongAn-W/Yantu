import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/account_data_store.dart';
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

class AccountDeletionParticipant {
  const AccountDeletionParticipant({
    required this.suspend,
    required this.resume,
  });
  final Future<void> Function() suspend;
  final void Function() resume;
}

class AuthState {
  const AuthState({
    this.user,
    this.loading = false,
    this.restoring = false,
    this.error,
    this.codeSending = false,
    this.retrySeconds = 0,
    this.notice,
    this.deletionPending = false,
  });

  final AuthUser? user;
  final bool loading;
  final bool restoring;
  final String? error;
  final bool codeSending;
  final int retrySeconds;
  final String? notice;
  final bool deletionPending;
  bool get deletionUncertain => deletionPending;
  bool get deletingAccount => loading && user != null;

  AuthState copyWith({
    bool? loading,
    String? error,
    bool? codeSending,
    int? retrySeconds,
    String? notice,
    bool? deletionPending,
  }) => AuthState(
    user: user,
    loading: loading ?? this.loading,
    restoring: restoring,
    error: error,
    codeSending: codeSending ?? this.codeSending,
    retrySeconds: retrySeconds ?? this.retrySeconds,
    notice: notice,
    deletionPending: deletionPending ?? this.deletionPending,
  );
}

class AuthController extends Notifier<AuthState> {
  Timer? _cooldown;
  bool _disposed = false;
  int _generation = 0;
  Future<void>? _signingOut;
  final Set<SessionEndHandler> _sessionEndHandlers = {};
  final Set<AccountDeletionParticipant> _deletionParticipants = {};
  bool _deleting = false;
  bool _endingDeletedAccount = false;
  Future<void>? _deletedCleanup;

  void addDeletionParticipant(AccountDeletionParticipant participant) =>
      _deletionParticipants.add(participant);

  void removeDeletionParticipant(AccountDeletionParticipant participant) =>
      _deletionParticipants.remove(participant);

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
    client.onAccountDeleted = accountDeleted;
    ref.onDispose(() {
      _disposed = true;
      _cooldown?.cancel();
      client.onSessionExpired = null;
      client.onAccountDeleted = null;
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
      if (error is AccountDeletedFailure) {
        await accountDeleted();
        return;
      }
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
    if (_deleting ||
        _endingDeletedAccount ||
        _deletedCleanup != null ||
        state.loading ||
        state.restoring ||
        state.codeSending) {
      return null;
    }
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
    if (_endingDeletedAccount) return;
    _generation++;
    final failure = await _stopLocalState();
    if (_disposed) return;
    state = AuthState(
      error: failure == null ? null : '登录会话已失效，但本机计时记录未能保存：$failure',
    );
  }

  /// Only a successful deletion response or ACCOUNT_DELETED may reach cleanup.
  /// Connectivity failures keep the local data and leave writes suspended until
  /// a retry establishes whether the server committed the deletion.
  Future<bool> deleteAccount(String password) async {
    final user = state.user;
    if (user == null || state.loading || _deleting) return false;
    _deleting = true;
    final generation = ++_generation;
    state = state.copyWith(loading: true);
    var requestStarted = false;
    try {
      await _runSessionEndHandlers();
      for (final participant in List.of(_deletionParticipants)) {
        await participant.suspend();
      }
      requestStarted = true;
      await ref.read(authRepositoryProvider).deleteAccount(password);
      await _completeAccountDeletion(user);
      return true;
    } catch (error) {
      final failure = ref.read(apiClientProvider).failureFrom(error);
      final uncertain =
          requestStarted &&
          (failure is OfflineFailure ||
              failure is ServerFailure ||
              failure is ResponseFailure);
      if (!uncertain) {
        for (final participant in List.of(_deletionParticipants)) {
          participant.resume();
        }
      }
      if (!_disposed && generation == _generation) {
        state = state.copyWith(
          loading: false,
          deletionPending: uncertain,
          error: uncertain
              ? '无法确认注销结果，请联网后重试。本机数据已保留，计时和同步已暂停。'
              : !requestStarted
              ? '注销前无法保存本机状态，请重试：$error'
              : failure.message,
        );
      }
      return false;
    } finally {
      _deleting = false;
    }
  }

  Future<void> accountDeleted() async {
    if (_deleting || _disposed) return;
    await (_deletedCleanup ??= _cleanDeletedAccount().whenComplete(() {
      _deletedCleanup = null;
    }));
  }

  Future<void> _cleanDeletedAccount() async {
    var user = state.user;
    if (user == null) {
      try {
        final cached = await ref.read(identityStoreProvider).load();
        if (cached != null) user = AuthUser.fromJson(cached);
      } catch (_) {
        // Even damaged local storage cannot keep a deleted account signed in.
      }
    }
    try {
      await _runSessionEndHandlers();
    } catch (_) {
      // The server has already deleted this account; its local session must end.
    }
    for (final participant in List.of(_deletionParticipants)) {
      try {
        await participant.suspend();
      } catch (_) {
        // Purge's durable marker also rejects delayed writes from this owner.
      }
    }
    await _completeAccountDeletion(user);
  }

  Future<void> _completeAccountDeletion(AuthUser? user) async {
    final client = ref.read(apiClientProvider);
    final identity = ref.read(identityStoreProvider);
    final store = ref.read(accountDataStoreProvider);
    final scope = ref.read(appConfigProvider).apiBaseUrl;
    _generation++;
    _endingDeletedAccount = true;
    if (!_disposed) state = const AuthState(loading: true);
    Object? cleanupFailure;
    try {
      if (user != null) await store.purge(scope: scope, userId: user.id);
    } catch (error) {
      cleanupFailure = error;
    }
    try {
      await identity.save(null);
    } catch (error) {
      cleanupFailure ??= error;
    }
    try {
      await client.clearSession();
    } catch (error) {
      cleanupFailure ??= error;
    } finally {
      _endingDeletedAccount = false;
    }
    if (!_disposed) {
      state = AuthState(
        notice: cleanupFailure == null ? '账号已注销，云端数据和本机缓存已清理。' : null,
        error: cleanupFailure == null
            ? null
            : cleanupFailure is LocalAccountCleanupIncomplete
            ? '账号已注销。以下历史损坏文件无法自动清理，请手动逐个处理：\n${cleanupFailure.archivePaths.join('\n')}'
            : '账号已注销，但本机缓存未能完整清理，请重新打开应用后重试清理。',
      );
    }
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
      notice: revokeFailure == null ? null : '已退出登录；云端会话撤销未完成，网络恢复后会自动清理。',
    );
  }
}
