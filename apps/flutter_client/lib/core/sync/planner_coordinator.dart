import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../shared/models/planner_models.dart';
import '../../features/planner/application/local_replanning.dart';
import '../../features/planner/domain/initial_plan.dart';
import '../../features/planner/domain/scheduler/planner_scheduler.dart'
    as scheduler;
import '../errors/app_failure.dart';
import '../storage/planner_json.dart';
import '../storage/storage_repository.dart';
import 'merge_plans.dart';
import 'sync_api.dart';
import 'sync_state.dart';

class PlannerCoordinator extends ChangeNotifier {
  PlannerCoordinator({
    required this.userId,
    required this.scope,
    required this.storage,
    required this.api,
    this.replanning = const LocalReplanning(),
    Duration? retryInterval = const Duration(seconds: 15),
  }) {
    if (retryInterval != null) {
      _timer = Timer.periodic(retryInterval, (_) {
        if (!blocked && conflicts.isEmpty) unawaited(sync());
      });
    }
  }
  final String userId, scope;
  final StorageRepository storage;
  final SyncApi api;
  final LocalReplanning replanning;
  LocalReplanProposal? replanProposal;
  String get key => 'sjtu-study-planner:items-v2:$scope:cloud:$userId';
  PlannerData? data;
  StorageMetadata metadata = const StorageMetadata();
  SyncStatus status = SyncStatus.connecting;
  String message = '正在读取本机计划…';
  bool blocked = false, ready = false, busy = false;
  List<String> conflicts = [];
  RemoteSnapshot? _remoteConflict;
  Timer? _timer;
  Future<void> _writes = Future.value();
  Future<void>? _syncing;
  bool _disposed = false;
  bool get pending => metadata.pending;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() operation) {
    final next = _writes.then((_) async {
      if (!_disposed) await operation();
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> initialize() async {
    final snapshot = await storage.load(key);
    if (_disposed) return;
    data = snapshot.data;
    metadata = snapshot.metadata;
    blocked = snapshot.error != null && snapshot.data == null;
    message = snapshot.error ?? '正在连接云端…';
    ready = true;
    _notify();
    if (!blocked) await sync();
  }

  Future<void> _persist(
    PlannerData next,
    StorageMetadata meta, {
    bool recovery = false,
  }) async {
    await storage.save(key, next, meta, recovery: recovery);
    if (_disposed) return;
    data = next;
    metadata = meta;
    blocked = false;
    _notify();
  }

  Future<void> edit(PlannerData Function(PlannerData) change) async {
    await _serial(() async {
      if (blocked || data == null) throw StateError('本地数据不可编辑，请先恢复备份');
      final next = change(data!);
      validatePlanner(next);
      await _persist(
        next,
        metadata.copyWith(pending: true, updatedAt: DateTime.now().toUtc()),
      );
      message = '已保存到本机，等待同步';
      _notify();
    });
    if (conflicts.isEmpty) unawaited(sync());
  }

  /// No local persistence, pending flag, or network call until confirmation.
  Future<ReplanPreview> previewReplan({
    required String today,
    ReplanMode mode = ReplanMode.unfinished,
    int? excessMinutes,
  }) async {
    late LocalReplanProposal proposal;
    await _serial(() async {
      if (blocked || data == null) throw StateError('本地数据不可编辑，请先恢复备份');
      proposal = replanning.preview(
        data!,
        today: today,
        mode: mode,
        excessMinutes: excessMinutes,
      );
      replanProposal = proposal;
      _notify();
    });
    return proposal.preview;
  }

  void cancelReplan() {
    replanProposal = null;
    _notify();
  }

  /// Bare change notification, so a caller that must not notify during widget
  /// teardown can schedule it for a later microtask.
  void notifyProposalChanged() => _notify();

  /// Uses the same serialized save-before-sync path as all other offline edits.
  Future<void> confirmReplan() async {
    final proposal = replanProposal;
    if (proposal == null) throw StateError('请先生成重排预览');
    await edit((current) => replanning.confirm(current, proposal));
    if (identical(replanProposal, proposal)) replanProposal = null;
    _notify();
  }

  Future<void> undoReplan() => edit(replanning.undo);

  Future<void> recordDayMinutes(String taskId, String date, int minutes) =>
      edit(
        (current) =>
            scheduler.recordTaskDayMinutes(current, taskId, date, minutes),
      );

  Future<void> importJson() async {
    final imported = await storage.importJson();
    if (imported == null || _disposed) return;
    await _serial(() async {
      final next = forAccount(imported, userId);
      await _persist(
        next,
        metadata.copyWith(pending: true, updatedAt: DateTime.now().toUtc()),
        recovery: true,
      );
      conflicts = [];
      _remoteConflict = null;
      message = 'JSON 已恢复到本机，等待同步';
      _notify();
    });
    await sync();
  }

  Future<void> exportJson() async {
    if (data == null) throw StateError('没有可导出的数据');
    final result = await storage.exportJson(data!);
    if (result != null) {
      message = '数据已导出';
      _notify();
    }
  }

  Future<void> recover() async {
    await _serial(() async {
      final recovered = await storage.recoverFromBackup(key);
      if (recovered.data == null) throw StateError(recovered.error ?? '没有有效备份');
      // Restoring an older local snapshot must be treated as a pending change.
      await _persist(
        recovered.data!,
        recovered.metadata.copyWith(
          pending: true,
          updatedAt: DateTime.now().toUtc(),
        ),
        recovery: true,
      );
      conflicts = [];
      _remoteConflict = null;
      message = '已从备份恢复';
    });
    await sync();
  }

  Future<void> resolve({required bool useLocal}) async {
    final remote = _remoteConflict;
    if (remote == null || data == null) return;
    await _serial(() async {
      final merged = mergePlans(
        metadata.base,
        data!,
        remote.data,
        preferLocal: useLocal,
      );
      await _persist(
        merged.data,
        metadata.copyWith(
          base: remote.data,
          revision: remote.revision,
          pending: true,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      conflicts = [];
      _remoteConflict = null;
    });
    await sync();
  }

  Future<void> sync() => _syncing ??= _sync().whenComplete(() {
    _syncing = null;
  });
  Future<void> _sync() async {
    if (_disposed || !ready || blocked || conflicts.isNotEmpty) return;
    busy = true;
    status = SyncStatus.syncing;
    _notify();
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        final remote = await api.pull();
        if (_disposed) return;
        await _serial(() async {
          if (metadata.pending && data != null) {
            final merged = mergePlans(metadata.base, data!, remote.data);
            if (merged.conflicts.isNotEmpty) {
              conflicts = merged.conflicts;
              _remoteConflict = remote;
              status = SyncStatus.conflict;
              message = '检测到并发修改，本机数据已保留，请选择冲突处理方式';
              return;
            }
            await _persist(
              merged.data,
              metadata.copyWith(
                base: remote.data,
                revision: remote.revision,
                pending: true,
              ),
            );
          } else if (remote.data != null) {
            if (metadata.revision == remote.revision &&
                data != null &&
                semanticallyEqual(data!.toJson(), remote.data!.toJson())) {
              return;
            }
            await _persist(
              remote.data!,
              StorageMetadata(
                base: remote.data,
                revision: remote.revision,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          } else if (data != null) {
            conflicts = ['云端计划已删除，本机内容已保留'];
            _remoteConflict = remote;
            status = SyncStatus.conflict;
            message = '云端计划已变化，请在设置中处理';
          } else if (data == null) {
            // A brand new account has neither a local nor a server plan. Bootstrap
            // a minimal plan so every page has valid data to edit; the account
            // wizard replaces it when the plan is confirmed. Persisting here also
            // proves local storage works before anything is uploaded.
            await _persist(
              initialPlannerData(
                userId: userId,
                nextId: scheduler.newUuid,
              ),
              metadata.copyWith(
                revision: remote.revision,
                base: null,
                pending: true,
                updatedAt: DateTime.now().toUtc(),
              ),
            );
          }
        });
        if (_disposed || conflicts.isNotEmpty) return;
        if (!metadata.pending || data == null) {
          status = SyncStatus.connected;
          message = '云端已同步';
          return;
        }
        final sent = data!, base = metadata.base, revision = metadata.revision;
        final response = await api.push(sent, base, revision);
        if (_disposed) return;
        if (response.conflict) continue;
        await _serial(() async {
          final newer = data != sent;
          await _persist(
            newer ? data! : response.data ?? sent,
            metadata.copyWith(
              base: response.data ?? sent,
              revision: response.revision,
              pending: newer,
              updatedAt: DateTime.now().toUtc(),
            ),
          );
        });
        if (!metadata.pending) {
          status = SyncStatus.connected;
          message = '云端已同步';
          return;
        }
      }
      status = SyncStatus.error;
      message = '云端频繁变化，本机修改已保留，可重试同步';
    } catch (error) {
      if (_disposed) return;
      status = error is OfflineFailure ? SyncStatus.offline : SyncStatus.error;
      message = error is AppFailure ? error.message : '同步未完成，本机数据已保留：$error';
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
