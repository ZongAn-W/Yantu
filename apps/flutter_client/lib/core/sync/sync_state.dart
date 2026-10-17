enum SyncStatus {
  demo,
  loginRequired,
  connecting,
  syncing,
  connected,
  offline,
  conflict,
  error,
}

class SyncState {
  const SyncState({
    this.status = SyncStatus.loginRequired,
    this.message = '',
    this.pending = false,
  });

  final SyncStatus status;
  final String message;
  final bool pending;
}
