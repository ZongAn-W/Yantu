import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../shared/models/planner_models.dart';
import '../../shared/models/task_lifecycle.dart';
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

/// Applies the user's conflict decision to a component that owns durable state
/// outside [PlannerData] (currently the study timer's persisted buckets).
///
/// The handlers run *before* the merged plan is persisted and before any new
/// checkpoint is allowed to write, so an already queued checkpoint cannot put
/// the abandoned records back. Throwing from a handler aborts the resolution and
/// keeps the conflict, which makes a failed resolution retryable.
typedef ConflictResolutionHandler =
    Future<void> Function({
      required bool useLocal,
      required List<LogConflict> logConflicts,
    });

class PlannerCoordinator extends ChangeNotifier {
  PlannerCoordinator({
    required this.userId,
    required this.scope,
    required this.storage,
    required this.api,
    this.replanning = const LocalReplanning(),
    Duration? retryInterval = const Duration(seconds: 15),
    this.uploadDebounce = const Duration(milliseconds: 500),
    this.uploadMaxWait = const Duration(seconds: 1),
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

  /// 连续本机编辑的合并上传窗口；窗口内的后续编辑会推迟上传。
  final Duration uploadDebounce;

  /// 合并上传的最长等待时间：连续编辑最多攒 [uploadMaxWait] 就必须上传。
  final Duration uploadMaxWait;
  LocalReplanProposal? replanProposal;
  String get key => 'sjtu-study-planner:items-v2:$scope:cloud:$userId';
  PlannerData? data;
  StorageMetadata metadata = const StorageMetadata();
  SyncStatus status = SyncStatus.connecting;
  String message = '正在读取本机计划…';
  bool blocked = false, ready = false, busy = false;
  List<String> conflicts = [];
  RemoteSnapshot? _remoteConflict;
  List<LogConflict> _conflictLogs = const [];
  final Set<ConflictResolutionHandler> _resolutionHandlers = {};
  Timer? _timer;
  Timer? _uploadTimer;
  DateTime? _uploadDeadline;
  Future<void> _writes = Future.value();
  Future<void>? _syncing;
  bool _disposed = false;
  bool _accountDeletionSuspended = false;

  Future<void> suspendForAccountDeletion() async {
    _accountDeletionSuspended = true;
    _cancelScheduledUpload();
    await _syncing;
    await _writes;
  }

  void resumeAfterAccountDeletionFailure() {
    _accountDeletionSuspended = false;
  }

  /// 服务端明确要求升级客户端（426）后暂停自动同步，避免用旧结构反复覆盖云端。
  bool _upgradeRequired = false;
  bool get upgradeRequired => _upgradeRequired;
  bool get pending => metadata.pending;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _serial(Future<void> Function() operation) {
    final next = _writes.then((_) async {
      if (_accountDeletionSuspended) {
        throw StateError('账号注销处理中，已暂停本机修改');
      }
      if (!_disposed) await operation();
    });
    _writes = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// 临时学习已下线：同步基线（base）里也可能残留 ad-hoc 字段。服务端契约已
  /// 删除 relation 的 ad_hoc 值，旧 base 原样上传会导致 400，因此落盘与上传前
  /// 统一清理。
  StorageMetadata _purgedMetadata(StorageMetadata meta) {
    final base = meta.base;
    if (base == null) return meta;
    final cleaned = purgeAdHocData(base);
    if (identical(cleaned, base)) return meta;
    return meta.copyWith(base: cleaned);
  }

  Future<void> initialize() async {
    final snapshot = await storage.load(key);
    if (_disposed) return;
    var loaded = snapshot.data;
    var meta = _purgedMetadata(snapshot.metadata);
    if (loaded != null) {
      final purged = purgeAdHocData(loaded);
      if (!identical(purged, loaded)) {
        // 临时学习已下线：立即把清理后的数据落盘并标记待上传，让下一次同步
        // 把删除带到服务端；即使落盘失败也先以清理后的内存数据进入工作台。
        meta = meta.copyWith(pending: true, updatedAt: DateTime.now().toUtc());
        loaded = purged;
      }
      if (!identical(meta, snapshot.metadata)) {
        try {
          await storage.save(key, loaded, meta);
        } catch (_) {
          // 后续同步仍会重新持久化并上传清理后的文档。
        }
      }
    }
    data = loaded;
    metadata = meta;
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
    var effective = _purgedMetadata(meta);
    // 时间口径规范化只在确有本机写入（pending）时落盘，避免纯读取/云端拉取
    // 立刻改写文档并触发一次无意义的回传；界面进度始终由日志实时派生。
    final cleaned = effective.pending
        ? normalizeTaskLifecycle(purgeAdHocData(next))
        : purgeAdHocData(next);
    await storage.save(key, cleaned, effective, recovery: recovery);
    if (_disposed) return;
    data = cleaned;
    metadata = effective;
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
    if (conflicts.isEmpty) _scheduleUpload();
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
      _conflictLogs = const [];
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
      _conflictLogs = const [];
      message = '已从备份恢复';
    });
    await sync();
  }

  /// Registers durable-state reconciliation that must run on conflict resolution.
  void addConflictResolutionHandler(ConflictResolutionHandler handler) =>
      _resolutionHandlers.add(handler);

  void removeConflictResolutionHandler(ConflictResolutionHandler handler) =>
      _resolutionHandlers.remove(handler);

  Future<void> resolve({required bool useLocal}) async {
    final remote = _remoteConflict;
    if (remote == null || data == null) return;
    final logConflicts = List<LogConflict>.of(_conflictLogs);
    // Outside the write queue on purpose: handlers may themselves call
    // `edit()` (the timer flushes its own records), and waiting for that while
    // holding the queue would deadlock. Nothing new can be merged before the
    // handlers finish because the conflict remains active.
    for (final handler in List<ConflictResolutionHandler>.of(
      _resolutionHandlers,
    )) {
      await handler(useLocal: useLocal, logConflicts: logConflicts);
    }
    await _serial(() async {
      final merged = mergePlans(
        metadata.base == null ? null : purgeAdHocData(metadata.base!),
        purgeAdHocData(data!),
        remote.data == null ? null : purgeAdHocData(remote.data!),
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
      _conflictLogs = const [];
    });
    await sync();
  }

  /// 立即同步：手动按钮、网络恢复、前台恢复、导入/恢复/冲突处理都会取消合并窗口。
  Future<void> sync() {
    if (_accountDeletionSuspended || _disposed) return Future.value();
    _cancelScheduledUpload();
    return _syncing ??= _sync().whenComplete(() {
      _syncing = null;
    });
  }

  /// 合并连续本机编辑：窗口内的后续编辑推迟上传，最长等待不超过 [uploadMaxWait]。
  void _scheduleUpload() {
    if (_disposed || _accountDeletionSuspended) return;
    if (uploadDebounce <= Duration.zero) {
      unawaited(sync());
      return;
    }
    _uploadTimer?.cancel();
    final deadline = _uploadDeadline ??= DateTime.now().add(uploadMaxWait);
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      unawaited(sync());
      return;
    }
    final wait = uploadDebounce < remaining ? uploadDebounce : remaining;
    _uploadTimer = Timer(wait, () {
      _uploadTimer = null;
      _uploadDeadline = null;
      unawaited(sync());
    });
  }

  void _cancelScheduledUpload() {
    _uploadTimer?.cancel();
    _uploadTimer = null;
    _uploadDeadline = null;
  }

  Future<void> _sync() async {
    if (_disposed ||
        _accountDeletionSuspended ||
        !ready ||
        blocked ||
        conflicts.isNotEmpty) {
      return;
    }
    // 收到升级信号后不再自动重试：同一份旧结构数据不可能被服务端接受，
    // 反复上传只会在“旧写入方无法表达新记录”的云文档上制造无意义的 409/426。
    if (_upgradeRequired) return;
    busy = true;
    status = SyncStatus.syncing;
    _notify();
    try {
      for (var attempt = 0; attempt < 4; attempt++) {
        // 携带已知 revision 做条件读取；老服务端忽略该参数返回完整文档，照常处理。
        var remote = await api.pull(
          revision: data == null ? null : metadata.revision,
        );
        if (_disposed) return;
        if (remote.unchanged && remote.revision != metadata.revision) {
          // 不一致的 unchanged 绝不能当作“无变化”：回退一次完整拉取。
          remote = await api.pull();
          if (_disposed) return;
          if (remote.unchanged) throw const ResponseFailure();
        }
        final snapshot = remote;
        if (snapshot.unchanged) {
          // 服务端确认自已知 revision 起没有变化：不合并、不持久化、不重建。
          // 有待上传修改时 base 仍对应该 revision，可以直接进入上传。
          if (!metadata.pending || data == null) {
            status = SyncStatus.connected;
            message = '云端已同步';
            return;
          }
        } else {
          await _serial(() async {
            if (metadata.pending && data != null) {
              final merged = mergePlans(
                metadata.base == null ? null : purgeAdHocData(metadata.base!),
                purgeAdHocData(data!),
                snapshot.data == null
                    ? null
                    : purgeAdHocData(snapshot.data!),
              );
              if (merged.conflicts.isNotEmpty) {
                conflicts = merged.conflicts;
                _conflictLogs = merged.logConflicts;
                _remoteConflict = snapshot;
                status = SyncStatus.conflict;
                message = '检测到并发修改，本机数据已保留，请选择冲突处理方式';
                return;
              }
              await _persist(
                merged.data,
                metadata.copyWith(
                  base: snapshot.data,
                  revision: snapshot.revision,
                  pending: true,
                ),
              );
            } else if (snapshot.data != null) {
              if (metadata.revision == snapshot.revision &&
                  data != null &&
                  semanticallyEqual(data!.toJson(), snapshot.data!.toJson())) {
                return;
              }
              await _persist(
                snapshot.data!,
                StorageMetadata(
                  base: snapshot.data,
                  revision: snapshot.revision,
                  updatedAt: DateTime.now().toUtc(),
                ),
              );
            } else if (data != null) {
              conflicts = ['云端计划已删除，本机内容已保留'];
              _conflictLogs = const [];
              _remoteConflict = snapshot;
              status = SyncStatus.conflict;
              message = '云端计划已变化，请在设置中处理';
            } else if (data == null) {
              // A brand new account has neither a local nor a server plan. Bootstrap
              // a minimal plan so every page has valid data to edit; the account
              // wizard replaces it when the plan is confirmed. Persisting here also
              // proves local storage works before anything is uploaded.
              await _persist(
                initialPlannerData(userId: userId, nextId: scheduler.newUuid),
                metadata.copyWith(
                  revision: snapshot.revision,
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
      if (error is ValidationFailure && error.statusCode == 426) {
        // 云端已有旧版本无法表达的学习记录：保留本机数据、不按冲突处理，
        // 明确提示升级；升级后可用同一 pending 数据重试。
        _upgradeRequired = true;
        status = SyncStatus.error;
        message = error.message;
      } else {
        status = error is OfflineFailure
            ? SyncStatus.offline
            : SyncStatus.error;
        message = error is AppFailure ? error.message : '同步未完成，本机数据已保留：$error';
      }
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _cancelScheduledUpload();
    super.dispose();
  }
}
