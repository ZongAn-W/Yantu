import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/study_timer_store.dart';
import '../../../core/sync/merge_plans.dart';
import '../../../core/sync/planner_coordinator.dart';
import '../../../shared/models/planner_models.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/planner_format.dart';
import '../domain/scheduler/planner_scheduler.dart' as scheduler;
import '../domain/scheduler/strategy_scheduler.dart' as strategy;
import '../domain/study_day.dart' as day_ops;
import 'planner_sync.dart';

final studyTimerStoreProvider = Provider<StudyTimerStore>(
  (ref) => LocalStudyTimerStore(ref.watch(localDatabaseProvider)),
);

final studyTimerProvider = ChangeNotifierProvider<StudyTimer>((ref) {
  final timer = StudyTimer(
    coordinator: ref.watch(plannerSyncProvider.notifier),
    store: ref.watch(studyTimerStoreProvider),
  );
  // An explicit sign-out and an expired session both persist the running timer
  // before the account session is dropped.
  final auth = ref.read(authControllerProvider.notifier);
  auth.addSessionEndHandler(timer.pauseForSessionEnd);
  final participant = AccountDeletionParticipant(
    suspend: timer.suspendForAccountDeletion,
    resume: timer.resumeAfterAccountDeletionFailure,
  );
  auth.addDeletionParticipant(participant);
  final observer = _TimerLifecycleObserver(timer);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() {
    auth.removeSessionEndHandler(timer.pauseForSessionEnd);
    auth.removeDeletionParticipant(participant);
    WidgetsBinding.instance.removeObserver(observer);
  });
  return timer;
});

/// A complete start-to-pause interval. Legacy totals have no individual intervals.
class StudyTimerSession {
  const StudyTimerSession({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.elapsed,
    required this.isLegacy,
    this.taskId,
    this.adHocId,
    this.relation,
  });

  final String id;
  final DateTime startedAt, endedAt;
  final Duration elapsed;
  final bool isLegacy;

  /// Recorded owner and relation of the interval; null for legacy aggregates.
  final String? taskId;
  final String? adHocId;
  final TimeLogRelation? relation;
}

/// One running timer per signed-in account and API endpoint. Its stable log IDs
/// make the local checkpoint and planner write safe to retry independently.
///
/// Buckets are keyed by (owner, Shanghai date, relation): the same task can hold
/// a scheduled and an extra bucket on one day without mixing the two, and a
/// task's session may overflow its scheduled quota into an extra bucket while
/// every elapsed second stays counted exactly once. Temporary learning buckets
/// are owned by an ad-hoc entity (task-less logs) until the user converts or
/// links them.
class StudyTimer extends ChangeNotifier {
  StudyTimer({
    required this.coordinator,
    required this.store,
    DateTime Function()? now,
    Duration Function()? monotonicNow,
    String Function()? nextId,
    this.tickInterval = const Duration(seconds: 1),
  }) : _now = now ?? DateTime.now,
       _nextId = nextId ?? scheduler.newUuid {
    _stopwatch.start();
    _monotonicNow = monotonicNow ?? (() => _stopwatch.elapsed);
    coordinator.addListener(_planChanged);
    coordinator.addConflictResolutionHandler(_onConflictResolution);
    if (coordinator.data != null && coordinator.userId.isNotEmpty) {
      unawaited(initialize());
    }
  }

  final PlannerCoordinator coordinator;
  final StudyTimerStore store;
  final DateTime Function() _now;
  final String Function() _nextId;
  final Duration? tickInterval;
  final _stopwatch = Stopwatch();
  late final Duration Function() _monotonicNow;
  Timer? _ticker;
  _TimerState _state = const _TimerState();
  Duration _anchorMonotonic = Duration.zero;
  Future<void> _writes = Future.value();
  Future<void>? _initializing;
  bool _disposed = false;
  bool _accountDeletionSuspended = false;

  Future<void> suspendForAccountDeletion() async {
    _accountDeletionSuspended = true;
    _ticker?.cancel();
    _ticker = null;
    await _initializing;
    await _writes;
  }

  void resumeAfterAccountDeletionFailure() {
    _accountDeletionSuspended = false;
    _updateTicker();
  }

  bool _needsPlannerFlush = false;
  bool _checkActiveAfterWrite = false;
  bool _invalidPauseQueued = false;

  bool ready = false;
  bool busy = false;
  String? error;

  String get storageKey => '${coordinator.key}:study-timer-v1';
  String? get activeTaskId => _state.active?.taskId;
  String? get activeAdHocId => _state.active?.adHocId;

  /// Relation chosen for the running interval (null when paused).
  TimeLogRelation? get activeRelation => _state.active?.intent;

  bool isRunning(String taskId, String date) =>
      activeTaskId == taskId && date == shanghaiToday(_logicalNow());

  bool isRunningAdHoc(String adHocId, String date) =>
      activeAdHocId == adHocId && date == shanghaiToday(_logicalNow());

  StudyTimerSession? lastSessionFor(String taskId, String date) =>
      _lastSession(taskId: taskId, date: date);

  StudyTimerSession? lastSessionForAdHoc(String adHocId, String date) =>
      _lastSession(adHocId: adHocId, date: date);

  StudyTimerSession? _lastSession({
    String? taskId,
    String? adHocId,
    required String date,
  }) {
    final session = _state.sessions
        .where(
          (session) =>
              session.taskId == taskId &&
              session.adHocId == adHocId &&
              !session.discarded &&
              session.id != _state.active?.sessionId &&
              _effectiveSessionMilliseconds(session, date) > 0,
        )
        .lastOrNull;
    if (session == null) return null;
    var effective = 0;
    for (final day in session.millisecondsByDate.keys) {
      effective += _effectiveSessionMilliseconds(session, day);
    }
    return StudyTimerSession(
      id: session.id,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      elapsed: Duration(milliseconds: effective),
      isLegacy: session.isLegacy,
      taskId: session.taskId,
      adHocId: session.adHocId,
      relation: session.relation,
    );
  }

  Duration elapsedFor(String taskId, String date) =>
      _elapsed(taskId: taskId, adHocId: null, date: date);

  Duration elapsedForAdHoc(String adHocId, String date) =>
      _elapsed(taskId: null, adHocId: adHocId, date: date);

  Duration _elapsed({
    required String? taskId,
    required String? adHocId,
    required String date,
  }) {
    final data = coordinator.data;
    if (data == null) return Duration.zero;
    final buckets = _project().buckets;
    final owned = buckets.map((bucket) => bucket.id).toSet();
    final existing = data.logs
        .where(
          (log) =>
              log.taskId == taskId &&
              log.adHocId == adHocId &&
              log.date == date,
        )
        .toList();
    var milliseconds = existing
        .where((log) => !owned.contains(log.id))
        .fold<int>(0, (sum, log) => sum + log.minutes * 60000);
    for (final bucket in buckets) {
      if (bucket.taskId != taskId ||
          bucket.adHocId != adHocId ||
          bucket.date != date) {
        continue;
      }
      milliseconds += _effectiveBucketMilliseconds(bucket, buckets);
    }
    return Duration(milliseconds: milliseconds);
  }

  /// Minutes the user explicitly gave up for one owner/day when they chose the
  /// cloud copy of a conflicting day.
  int _discardedMilliseconds({
    String? taskId,
    String? adHocId,
    required String date,
  }) {
    var total = 0;
    for (final record in _state.discards) {
      if (record.taskId == taskId &&
          record.adHocId == adHocId &&
          record.date == date) {
        total += record.milliseconds;
      }
    }
    return total;
  }

  /// Effective minutes of one bucket after distributing user discards across the
  /// buckets of the same owner and day (scheduled first, then extra/ad-hoc).
  int _effectiveBucketMilliseconds(
    _TimerBucket bucket,
    Iterable<_TimerBucket> buckets,
  ) {
    final discarded = _discardedMilliseconds(
      taskId: bucket.taskId,
      adHocId: bucket.adHocId,
      date: bucket.date,
    );
    if (discarded == 0) return bucket.milliseconds;
    final siblings =
        buckets
            .where(
              (item) =>
                  item.taskId == bucket.taskId &&
                  item.adHocId == bucket.adHocId &&
                  item.date == bucket.date,
            )
            .toList()
          ..sort(_compareBuckets);
    var remaining = discarded;
    for (final sibling in siblings) {
      final deducted = math.min(remaining, sibling.milliseconds);
      remaining -= deducted;
      if (sibling.id == bucket.id) return sibling.milliseconds - deducted;
    }
    return bucket.milliseconds;
  }

  /// Discarded minutes are subtracted chronologically from the earliest sessions,
  /// so a session started after the resolution keeps all of its time.
  int _effectiveSessionMilliseconds(_TimerSession session, String date) {
    final raw = session.millisecondsForDate(date);
    if (raw == 0) return 0;
    final discarded = _discardedMilliseconds(
      taskId: session.taskId,
      adHocId: session.adHocId,
      date: date,
    );
    if (discarded == 0) return raw;
    final siblings =
        _state.sessions
            .where(
              (item) =>
                  item.taskId == session.taskId &&
                  item.adHocId == session.adHocId,
            )
            .toList()
          ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    var remaining = discarded;
    for (final item in siblings) {
      final amount = item.millisecondsForDate(date);
      if (amount == 0) continue;
      final deducted = math.min(remaining, amount);
      remaining -= deducted;
      if (item.id == session.id) return amount - deducted;
    }
    return raw;
  }

  Future<void> initialize() => _initializing ??= _initialize().whenComplete(() {
    _initializing = null;
  });

  Future<void> _initialize() async {
    if (ready || _disposed || coordinator.data == null) return;
    try {
      final saved = await store.load(storageKey);
      if (_disposed) return;
      var next = saved == null
          ? const _TimerState()
          : _TimerState.fromJson(saved);
      // 临时学习已下线：先丢弃计时器本地状态里的临时学习会话，避免暂停/
      // 检查点时再生成已失效的 ad-hoc 日志。
      final purgedState = _withoutAdHocTimerData(next);
      if (!identical(purgedState, next)) {
        next = purgedState;
        try {
          await store.save(storageKey, next.toJson());
        } catch (_) {
          // 清理失败不阻塞进入工作台；后续保存会写入清理后的状态。
        }
      }
      var anchor = _monotonicNow();
      final active = next.active;
      if (active != null) {
        final now = _now().toUtc();
        anchor = _monotonicNow();
        final end = now.isBefore(active.checkpoint) ? active.checkpoint : now;
        next = _accrue(next, end);
        if (!_canActiveTime(active)) next = next.copyWith(active: null);
        try {
          next = await _saveSnapshot(next);
        } on StudyTimerConflict catch (conflict) {
          next = _restoreCheckpoint(conflict.latest);
          anchor = _monotonicNow();
        }
        if (_disposed) return;
      }
      _state = next;
      _anchorMonotonic = anchor;
      ready = true;
      error = null;
      _needsPlannerFlush = true;
      await _flushPlanner();
    } catch (failure) {
      error = '计时保存失败：$failure';
    }
    _updateTicker();
    _notify();
  }

  /// 丢弃本地计时状态中属于临时学习的活动计时、会话、时段与撤销标记。
  _TimerState _withoutAdHocTimerData(_TimerState state) {
    final active = state.active;
    final hasAdHoc =
        active?.adHocId != null ||
        state.buckets.any((bucket) => bucket.adHocId != null) ||
        state.sessions.any((session) => session.adHocId != null) ||
        state.discards.any((discard) => discard.adHocId != null);
    if (!hasAdHoc) return state;
    return state.copyWith(
      active: active?.adHocId == null ? active : null,
      buckets: [
        for (final bucket in state.buckets)
          if (bucket.adHocId == null) bucket,
      ],
      sessions: [
        for (final session in state.sessions)
          if (session.adHocId == null) session,
      ],
      discards: [
        for (final discard in state.discards)
          if (discard.adHocId == null) discard,
      ],
    );
  }

  /// Starts the timer for an existing task.
  ///
  /// When the task still has an arranged quota for [date] the interval is
  /// recorded as [TimeLogRelation.scheduled] and its overflow becomes extra;
  /// otherwise (no block, no remaining quota) it is an active extra-study
  /// interval. Use [startExtra] to explicitly record extra study or a review of
  /// a completed task.
  Future<void> start(String taskId, String date) => _serial(() async {
    await _ensureReady();
    if (date != shanghaiToday(_now())) {
      throw StateError('只能为今天的学习开始计时');
    }
    final plan = coordinator.data;
    final task = plan?.tasks.where((task) => task.id == taskId).firstOrNull;
    if (plan != null && task != null) {
      final reason = strategy.strategyExecutionError(plan, task, date);
      if (reason != null) throw StateError(reason);
    }
    if (!_canStartTask(taskId, allowCompleted: false)) {
      throw StateError('当前事项不可计时');
    }
    if (activeTaskId == taskId && activeAdHocId == null) return;
    final quota = _scheduledQuotaFor(taskId, date);
    await _startSession(
      taskId: taskId,
      intent: quota > 0 ? TimeLogRelation.scheduled : TimeLogRelation.extra,
    );
  });

  /// Records study of an existing task outside today's arrangement (extra study
  /// of future content, catching up, or a review of a completed task).
  ///
  /// No today block is required. AI-suggested dates are not a hard block, but
  /// real prerequisites and activity state are still checked with a clear reason.
  /// Completed tasks may be reviewed without reopening them or adding scope.
  Future<void> startExtra(String taskId) => _serial(() async {
    await _ensureReady();
    final data = coordinator.data;
    final task = data?.tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null) throw StateError('事项已不存在，请刷新后重试');
    if (task.status == TaskStatus.archived) throw StateError('已归档事项不可计时');
    if (task.status != TaskStatus.completed && data != null) {
      final reason = strategy.strategyExecutionError(
        data,
        task,
        shanghaiToday(_now()),
      );
      if (reason != null) throw StateError(reason);
    }
    if (coordinator.blocked) throw StateError('本机计划暂时不可写入');
    if (activeTaskId == taskId && activeRelation == TimeLogRelation.extra) {
      return;
    }
    await _startSession(taskId: taskId, intent: TimeLogRelation.extra);
  });

  /// Starts temporary learning by name. Only the name is required: no budget,
  /// deadline, priority or schedule is fabricated, and no AI plan is requested.
  /// An exact-title non-archived entity is reused so repeated sessions continue
  /// the same temporary content instead of duplicating it.
  Future<void> startAdHoc({required String title, String? subjectId}) =>
      _serial(() async {
        await _ensureReady();
        final data = coordinator.data;
        if (data == null || coordinator.blocked) {
          throw StateError('本机计划暂时不可写入');
        }
        final trimmed = title.trim();
        if (trimmed.isEmpty) throw StateError('请填写临时学习名称');
        var learning = data.adHocLearnings
            .where((item) => !item.archived && item.title == trimmed)
            .firstOrNull;
        if (learning == null) {
          final id = _nextId();
          late AdHocLearning created;
          await coordinator.edit((current) {
            final result = day_ops.upsertAdHocLearning(
              current,
              title: trimmed,
              id: id,
              updatedAt: _now().toUtc().toIso8601String(),
            );
            created = result.learning;
            return result.data;
          });
          learning = created;
        }
        if (_disposed) return;
        if (activeAdHocId == learning.id) return;
        await _startSession(
          adHocId: learning.id,
          intent: TimeLogRelation.adHoc,
        );
      });

  Future<void> _startSession({
    String? taskId,
    String? adHocId,
    required TimeLogRelation intent,
  }) async {
    final now = _logicalNow();
    final projected = _accrue(_state, now);
    final sessionId = _nextId();
    final next = projected.copyWith(
      active: _ActiveTimer(
        taskId: taskId,
        adHocId: adHocId,
        intent: intent,
        checkpoint: now,
        sessionId: sessionId,
      ),
      sessions: [
        ...projected.sessions,
        _TimerSession(
          id: sessionId,
          taskId: taskId,
          adHocId: adHocId,
          relation: intent,
          startedAt: now,
          endedAt: now,
        ),
      ],
    );
    await _commit(next);
  }

  Future<void> _ensureReady() async {
    if (!ready) {
      await initialize();
      if (!ready) throw StateError(error ?? '计时记录尚未读取完成');
    }
  }

  Future<void> pause() => _serial(() async {
    if (!ready || _state.active == null) return;
    await _commit(_project().copyWith(active: null));
  });

  /// Ends the running interval before the account session is cleared.
  ///
  /// The durable checkpoint (active = null) is written first; a failure throws so
  /// an explicit sign-out can be aborted instead of silently losing time. The
  /// planner write is best effort: a failed flush stays pending in the timer
  /// state and is replayed on the next sign-in.
  Future<void> pauseForSessionEnd() async {
    if (_disposed || _accountDeletionSuspended || !ready) return;
    await _serial(() async {
      if (_disposed || _state.active == null) return;
      final saved = await _saveSnapshot(_project().copyWith(active: null));
      if (_disposed) return;
      _state = saved;
      _anchorMonotonic = _monotonicNow();
      _needsPlannerFlush = true;
      try {
        await _flushPlanner();
      } catch (_) {
        // Keep the pending checkpoint for replay after the next sign-in.
      }
    });
  }

  Future<void> discardLastSession(
    String taskId,
    String date, {
    required String expectedSessionId,
  }) => _discardSession(
    taskId: taskId,
    date: date,
    expectedSessionId: expectedSessionId,
  );

  /// Removes the latest paused temporary-learning interval.
  Future<void> discardLastAdHocSession(
    String adHocId,
    String date, {
    required String expectedSessionId,
  }) => _discardSession(
    adHocId: adHocId,
    date: date,
    expectedSessionId: expectedSessionId,
  );

  Future<void> _discardSession({
    String? taskId,
    String? adHocId,
    required String date,
    required String expectedSessionId,
  }) => _serial(() async {
    if (!ready) throw StateError('计时记录尚未读取完成');
    if (activeTaskId == taskId && activeAdHocId == adHocId && taskId != null) {
      throw StateError('请先暂停计时，再删除上一段记录');
    }
    if (activeAdHocId == adHocId && adHocId != null) {
      throw StateError('请先暂停计时，再删除上一段记录');
    }
    final index = _state.sessions.indexWhere(
      (session) => session.id == expectedSessionId,
    );
    if (index >= 0 && _state.sessions[index].discarded) {
      await _flushPlanner();
      return;
    }
    final latest = _lastSession(taskId: taskId, adHocId: adHocId, date: date);
    if (latest?.id != expectedSessionId || index < 0) {
      throw StateError('计时记录已变化，请重新确认要删除的记录');
    }
    final session = _state.sessions[index];
    final projected = _project();
    final buckets = _subtractSession(projected.buckets, session);
    final sessions = [...projected.sessions];
    sessions[index] = session.copyWith(discarded: true);
    await _commit(
      projected.copyWith(
        active: projected.active,
        buckets: buckets,
        sessions: sessions,
        discards: _clampedDiscards(projected.discards, buckets),
      ),
    );
  });

  /// Removes exactly the session's contributed milliseconds from the buckets.
  List<_TimerBucket> _subtractSession(
    List<_TimerBucket> buckets,
    _TimerSession session,
  ) {
    final result = [...buckets];
    for (final slot in session.slots.entries) {
      final split = slot.key.split('|');
      if (split.length != 2) continue;
      final date = split[0];
      final relation = TimeLogRelation.values
          .where((value) => value.name == split[1])
          .firstOrNull;
      if (relation == null) continue;
      final index = result.indexWhere(
        (bucket) =>
            bucket.taskId == session.taskId &&
            bucket.adHocId == session.adHocId &&
            bucket.date == date &&
            bucket.relation == relation,
      );
      if (index < 0) continue;
      result[index] = result[index].subtract(slot.value, sessionId: session.id);
    }
    return result;
  }

  /// Used on lifecycle changes and whole-minute boundaries, never by a time input.
  Future<void> checkpoint() => _serial(() async {
    if (!ready) return;
    await _commit(_project());
  });

  /// Applies an ad-hoc conversion/link to the durable timer state.
  ///
  /// The planner operation (see `study_day.convertAdHocToTask`) moves the original
  /// logs to the target task while keeping `relation = ad_hoc` and `ad_hoc_id`.
  /// The timer buckets must follow, otherwise the next checkpoint would write the
  /// old owner back and duplicate or lose attribution.
  Future<void> adoptAdHocConversion(
    String adHocId,
    String taskId,
  ) => _serial(() async {
    if (!ready) return;
    final buckets = [
      for (final bucket in _state.buckets)
        bucket.adHocId == adHocId ? bucket.withTaskId(taskId) : bucket,
    ];
    final sessions = [
      for (final session in _state.sessions)
        session.adHocId == adHocId ? session.copyWith(taskId: taskId) : session,
    ];
    final discards = [
      for (final discard in _state.discards)
        discard.adHocId == adHocId ? discard.copyWith(taskId: taskId) : discard,
    ];
    final active = _state.active;
    await _commit(
      _state.copyWith(
        active: active != null && active.adHocId == adHocId
            ? _ActiveTimer(
                taskId: taskId,
                adHocId: active.adHocId,
                intent: active.intent,
                checkpoint: active.checkpoint,
                sessionId: active.sessionId,
              )
            : active,
        buckets: buckets,
        sessions: sessions,
        discards: discards,
      ),
    );
  });

  Future<void> _serial(Future<void> Function() action) {
    final result = _writes.then((_) async {
      if (_disposed) return;
      if (_accountDeletionSuspended) {
        throw StateError('账号注销处理中，已暂停学习计时');
      }
      busy = true;
      _notify();
      try {
        await action();
        error = null;
      } catch (failure) {
        error = '计时保存失败：$failure';
        rethrow;
      } finally {
        busy = false;
        if (_checkActiveAfterWrite) {
          _checkActiveAfterWrite = false;
          _pauseInvalidActive();
        }
        _updateTicker();
        _notify();
      }
    });
    _writes = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<void> _commit(_TimerState next) async {
    // Save the clock before changing the planner. A failed planner write can then
    // be replayed using the same log IDs without duplicating any learned time.
    final anchor = _monotonicNow();
    _TimerState saved;
    try {
      saved = await _saveSnapshot(next);
    } on StudyTimerConflict catch (conflict) {
      if (!_disposed) {
        _state = _restoreCheckpoint(conflict.latest);
        _anchorMonotonic = _monotonicNow();
        _needsPlannerFlush = true;
      }
      rethrow;
    }
    if (_disposed) return;
    _state = saved;
    _anchorMonotonic = anchor;
    _needsPlannerFlush = true;
    await _flushPlanner();
  }

  Future<_TimerState> _saveSnapshot(_TimerState next) async {
    final saved = next.withRevision(next.revision + 1);
    await store.save(storageKey, saved.toJson());
    return saved;
  }

  /// Applies the user's conflict decision to the durable timer state before the
  /// merged plan is persisted.
  ///
  /// Adopting the cloud copy marks exactly the conflicting owner/day buckets as
  /// user-discarded and rebases a running timer to "now", so only time after the
  /// resolution is counted. Adopting the local copy lifts any discard markers
  /// left by an earlier failed resolution.
  Future<void> _onConflictResolution({
    required bool useLocal,
    required List<LogConflict> logConflicts,
  }) async {
    if (_disposed || logConflicts.isEmpty) return;
    if (!ready && coordinator.data != null) {
      // A decision made before the persisted timer state finished loading must
      // still be applied to that state, otherwise the next checkpoint would
      // replay the abandoned minutes.
      await initialize();
    }
    if (_disposed || !ready) return;
    final scopes = _discardScopes(logConflicts);
    await _serial(() async {
      if (useLocal) {
        await _persistResolution(
          (state) => state.withoutDiscards(scopes),
          skipWhenUnchanged: true,
        );
        return;
      }
      await _persistResolution((state) {
        final now = _logicalNow();
        var next = _accrue(state, now);
        next = next.withDiscards(scopes);
        final active = next.active;
        if (active != null) {
          // Rebuild the timing anchor: minutes before the resolution are
          // discarded, and only later accrual is written back.
          next = next.copyWith(
            active: _ActiveTimer(
              taskId: active.taskId,
              adHocId: active.adHocId,
              intent: active.intent,
              checkpoint: now,
              sessionId: active.sessionId,
            ),
          );
        }
        return next;
      });
    });
  }

  /// Merge conflicts describe one owner (task or temporary learning) and day.
  List<_DiscardScope> _discardScopes(List<LogConflict> conflicts) => [
    for (final conflict in conflicts)
      _DiscardScope(
        taskId: conflict.taskId,
        adHocId: conflict.adHocId,
        date: conflict.date,
      ),
  ];

  Future<void> _persistResolution(
    _TimerState Function(_TimerState state) apply, {
    bool skipWhenUnchanged = false,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        final next = apply(_state);
        if (skipWhenUnchanged && identical(next, _state)) return;
        final anchor = _monotonicNow();
        final saved = await _saveSnapshot(next);
        if (_disposed) return;
        _state = saved;
        _anchorMonotonic = anchor;
        _needsPlannerFlush = true;
        return;
      } on StudyTimerConflict catch (conflict) {
        // Another window moved the checkpoint forward: replay the decision on the
        // newest state instead of overwriting it.
        _state = _restoreCheckpoint(conflict.latest);
        _anchorMonotonic = _monotonicNow();
        if (attempt == 1) rethrow;
      }
    }
  }

  List<_TimerDiscard> _clampedDiscards(
    List<_TimerDiscard> discards,
    List<_TimerBucket> buckets,
  ) {
    final result = <_TimerDiscard>[];
    for (final record in discards) {
      final limit = buckets
          .where(
            (bucket) =>
                bucket.taskId == record.taskId &&
                bucket.adHocId == record.adHocId &&
                bucket.date == record.date,
          )
          .fold<int>(0, (sum, bucket) => sum + bucket.milliseconds);
      final milliseconds = math.min(record.milliseconds, limit);
      if (milliseconds > 0) {
        result.add(
          _TimerDiscard(
            taskId: record.taskId,
            adHocId: record.adHocId,
            date: record.date,
            milliseconds: milliseconds,
          ),
        );
      }
    }
    return result;
  }

  _TimerState _restoreCheckpoint(JsonMap? saved) {
    final next = saved == null
        ? const _TimerState()
        : _TimerState.fromJson(saved);
    final active = next.active;
    if (active == null) return next;
    final now = _now().toUtc();
    return _accrue(
      next,
      now.isBefore(active.checkpoint) ? active.checkpoint : now,
    );
  }

  Future<void> _flushPlanner() async {
    final data = coordinator.data;
    if (data == null || coordinator.blocked) {
      throw StateError('本机计划暂时不可写入');
    }
    final buckets = _state.buckets;
    if (_plannerNeedsUpdate(data)) {
      await coordinator.edit((current) {
        final logs = [...current.logs];
        final affected = <String>{};
        for (final bucket in buckets) {
          final ownerError = _bucketOwnerError(current, bucket);
          if (ownerError != null) continue;
          final index = logs.indexWhere((log) => log.id == bucket.id);
          final minutes =
              _effectiveBucketMilliseconds(bucket, buckets) ~/ 60000;
          final sessionId = _bucketSessionId(bucket);
          final existing = index < 0 ? null : logs[index];
          final unchanged =
              existing != null &&
              existing.minutes == minutes &&
              existing.taskId == bucket.taskId &&
              existing.adHocId == bucket.adHocId &&
              existing.relation == bucket.relation &&
              existing.sessionId == sessionId &&
              existing.quotaMinutes == bucket.quotaMinutes;
          if (unchanged) continue;
          if (bucket.taskId != null) {
            affected.add('${bucket.taskId}:${bucket.date}');
          }
          if (minutes == 0) {
            if (index >= 0) logs.removeAt(index);
            continue;
          }
          final log = TimeLog(
            id: bucket.id,
            userId: current.profile.userId,
            taskId: bucket.taskId,
            blockId: null,
            date: bucket.date,
            minutes: minutes,
            startedAt: bucket.startedAt.toIso8601String(),
            endedAt: bucket.endedAt.toIso8601String(),
            source: LogSource.timer,
            relation: bucket.relation,
            sessionId: sessionId,
            adHocId: bucket.adHocId,
            quotaMinutes: bucket.quotaMinutes,
          );
          if (index >= 0) {
            logs[index] = log;
          } else {
            logs.add(log);
          }
        }
        var next = current.copyWith(logs: logs);
        // Blocks only receive scheduled / legacy-covered minutes; extra and
        // temporary learning never inflate the original-plan execution.
        final coverageByDay = <String, int>{};
        final stamp = _logicalNow().toIso8601String();
        final sorted = [...next.blocks]
          ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
        final replacements = <String, ScheduleBlock>{};
        for (final block in sorted) {
          final key = '${block.taskId}:${block.date}';
          if (!affected.contains(key)) continue;
          final remaining = coverageByDay.putIfAbsent(
            key,
            () => day_ops.scheduledMinutesForTaskDay(
              next,
              block.taskId,
              block.date,
            ),
          );
          final actual = math.min(remaining, block.durationMinutes);
          coverageByDay[key] = remaining - actual;
          replacements[block.id] = block.copyWith(
            actualMinutes: actual,
            status: actual >= block.durationMinutes
                ? BlockStatus.completed
                : BlockStatus.planned,
            completionStatus: actual >= block.durationMinutes
                ? CompletionStatus.completed
                : actual > 0
                ? CompletionStatus.partial
                : CompletionStatus.notStarted,
            updatedAt: stamp,
          );
        }
        next = next.copyWith(
          blocks: [
            for (final block in next.blocks) replacements[block.id] ?? block,
          ],
        );
        return day_ops.refreshTaskProgress(next, updatedAt: stamp);
      });
    }
    _needsPlannerFlush = false;
  }

  /// Null when the bucket owner still exists in the current plan.
  String? _bucketOwnerError(PlannerData data, _TimerBucket bucket) {
    if (bucket.relation == TimeLogRelation.adHoc &&
        (bucket.adHocId == null ||
            !data.adHocLearnings.any(
              (learning) => learning.id == bucket.adHocId,
            ))) {
      return '临时学习实体不存在';
    }
    if (bucket.taskId != null &&
        !data.tasks.any((task) => task.id == bucket.taskId)) {
      return '事项不存在';
    }
    if (bucket.taskId == null && bucket.adHocId == null) {
      return '计时归属缺失';
    }
    return null;
  }

  String? _bucketSessionId(_TimerBucket bucket) =>
      bucket.sessionIds.length == 1 ? bucket.sessionIds.single : null;

  bool _plannerNeedsUpdate(PlannerData data) => _state.buckets.any((bucket) {
    if (_bucketOwnerError(data, bucket) != null) return false;
    final existing = data.logs.where((log) => log.id == bucket.id).firstOrNull;
    final minutes =
        _effectiveBucketMilliseconds(bucket, _state.buckets) ~/ 60000;
    return existing == null
        ? minutes > 0
        : existing.minutes != minutes ||
              existing.taskId != bucket.taskId ||
              existing.adHocId != bucket.adHocId ||
              existing.relation != bucket.relation ||
              existing.sessionId != _bucketSessionId(bucket) ||
              existing.quotaMinutes != bucket.quotaMinutes;
  });

  DateTime _logicalNow() {
    final active = _state.active;
    if (active == null) return _now().toUtc();
    final delta = _monotonicNow() - _anchorMonotonic;
    return active.checkpoint.add(delta.isNegative ? Duration.zero : delta);
  }

  _TimerState _project() => _accrue(_state, _logicalNow());

  TimeLogRelation _relationForDate(_ActiveTimer active, String date) {
    if (active.intent == TimeLogRelation.adHoc) return TimeLogRelation.adHoc;
    if (active.intent == TimeLogRelation.extra) return TimeLogRelation.extra;
    // A scheduled interval re-evaluates the relation for a new Shanghai day: the
    // previous day's quota never carries over to the new date.
    final taskId = active.taskId;
    if (taskId == null) return TimeLogRelation.extra;
    return _scheduledQuotaFor(taskId, date) > 0
        ? TimeLogRelation.scheduled
        : TimeLogRelation.extra;
  }

  /// Remaining scheduled minutes for a task/day, from the latest planner data.
  int _scheduledQuotaFor(String taskId, String date) {
    final data = coordinator.data;
    if (data == null) return 0;
    final planned = day_ops.taskDayPlannedMinutes(data, taskId, date);
    if (planned <= 0) return 0;
    return math.max(
      0,
      planned - day_ops.scheduledMinutesForTaskDay(data, taskId, date),
    );
  }

  _TimerState _accrue(_TimerState state, DateTime end) {
    final active = state.active;
    if (active == null || !end.isAfter(active.checkpoint)) return state;
    var cursor = active.checkpoint;
    final buckets = [...state.buckets];
    final sessions = [...state.sessions];
    var sessionIndex = sessions.indexWhere(
      (session) => session.id == active.sessionId,
    );
    if (sessionIndex < 0) {
      // A corrupted/legacy checkpoint without its session: keep the interval but
      // recreate the session instead of silently dropping accumulated time.
      sessions.add(
        _TimerSession(
          id: active.sessionId,
          taskId: active.taskId,
          adHocId: active.adHocId,
          relation: active.intent,
          startedAt: active.checkpoint,
          endedAt: active.checkpoint,
        ),
      );
      sessionIndex = sessions.length - 1;
    }
    var session = sessions[sessionIndex];
    while (cursor.isBefore(end)) {
      final date = shanghaiToday(cursor);
      final midnight = DateTime.parse(
        '${addDate(date, 1)}T00:00:00Z',
      ).subtract(const Duration(hours: 8));
      final until = end.isBefore(midnight) ? end : midnight;
      var remaining = until.difference(cursor).inMilliseconds;
      if (remaining <= 0) break;
      final relationForDate = _relationForDate(active, date);
      if (relationForDate == TimeLogRelation.scheduled) {
        // Scheduled interval: keep the scheduled bucket within the quota captured
        // when the day's scheduled segment first started.
        final discarded = _discardedMilliseconds(
          taskId: active.taskId,
          adHocId: active.adHocId,
          date: date,
        );
        var index = buckets.indexWhere(
          (bucket) =>
              bucket.taskId == active.taskId &&
              bucket.adHocId == active.adHocId &&
              bucket.date == date &&
              bucket.relation == TimeLogRelation.scheduled,
        );
        _TimerBucket? scheduled = index < 0 ? null : buckets[index];
        var quota = scheduled?.quotaMinutes;
        if (scheduled == null) {
          final remainingQuota = _scheduledQuotaFor(active.taskId!, date);
          if (remainingQuota > 0) {
            quota = remainingQuota;
            scheduled = _TimerBucket(
              id: _nextId(),
              taskId: active.taskId,
              adHocId: active.adHocId,
              date: date,
              relation: TimeLogRelation.scheduled,
              milliseconds: 0,
              startedAt: cursor,
              endedAt: cursor,
              quotaMinutes: quota,
            );
            buckets.add(scheduled);
            index = buckets.length - 1;
          }
        }
        if (scheduled != null) {
          final effectiveScheduled = math.max(
            0,
            scheduled.milliseconds - discarded,
          );
          final available = math.max(
            0,
            (quota ?? 0) * 60000 - effectiveScheduled,
          );
          final take = math.min(remaining, available);
          if (take > 0) {
            buckets[index] = scheduled.add(take, until, active.sessionId);
            session = session.add(date, TimeLogRelation.scheduled, take, until);
            remaining -= take;
          }
        }
      }
      if (remaining > 0) {
        // No scheduled quota left (or an explicit extra/ad-hoc interval): all
        // remaining seconds of this date segment become extra/temporary time.
        final relation = relationForDate == TimeLogRelation.scheduled
            ? TimeLogRelation.extra
            : relationForDate;
        _appendBucket(
          buckets,
          taskId: active.taskId,
          adHocId: active.adHocId,
          date: date,
          relation: relation,
          milliseconds: remaining,
          start: cursor,
          end: until,
          sessionId: active.sessionId,
        );
        session = session.add(date, relation, remaining, until);
        remaining = 0;
      }
      cursor = until;
    }
    sessions[sessionIndex] = session;
    return _TimerState(
      revision: state.revision,
      buckets: buckets,
      sessions: sessions,
      discards: state.discards,
      active: _ActiveTimer(
        taskId: active.taskId,
        adHocId: active.adHocId,
        intent: active.intent,
        checkpoint: end,
        sessionId: active.sessionId,
      ),
    );
  }

  /// Appends [milliseconds] to the bucket matching (owner, date, relation),
  /// creating it when needed, and returns its index.
  int _appendBucket(
    List<_TimerBucket> buckets, {
    required String? taskId,
    required String? adHocId,
    required String date,
    required TimeLogRelation relation,
    required int milliseconds,
    required DateTime start,
    required DateTime end,
    required String sessionId,
  }) {
    final index = buckets.indexWhere(
      (bucket) =>
          bucket.taskId == taskId &&
          bucket.adHocId == adHocId &&
          bucket.date == date &&
          bucket.relation == relation,
    );
    if (index < 0) {
      buckets.add(
        _TimerBucket(
          id: _nextId(),
          taskId: taskId,
          adHocId: adHocId,
          date: date,
          relation: relation,
          milliseconds: milliseconds,
          startedAt: start,
          endedAt: end,
          sessionIds: [sessionId],
        ),
      );
      return buckets.length - 1;
    }
    buckets[index] = buckets[index].add(milliseconds, end, sessionId);
    return index;
  }

  bool _canStartTask(String taskId, {required bool allowCompleted}) {
    if (coordinator.blocked) return false;
    final data = coordinator.data;
    if (data == null) return false;
    final task = data.tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null || task.status == TaskStatus.archived) return false;
    if (task.status == TaskStatus.completed && !allowCompleted) return false;
    return strategy.strategyExecutionError(data, task, shanghaiToday(_now())) ==
        null;
  }

  bool _canActiveTime(_ActiveTimer active) {
    if (coordinator.blocked) return false;
    final data = coordinator.data;
    if (data == null) return false;
    final adHocId = active.adHocId;
    if (adHocId != null) {
      final learning = data.adHocLearnings
          .where((item) => item.id == adHocId)
          .firstOrNull;
      if (learning == null) return false;
      // A converted ad-hoc entity is archived but keeps working through its task.
      return !learning.archived || active.taskId != null;
    }
    final taskId = active.taskId;
    if (taskId == null) return false;
    final task = data.tasks.where((item) => item.id == taskId).firstOrNull;
    if (task == null || task.status == TaskStatus.archived) return false;
    if (task.status == TaskStatus.completed) {
      // A review interval keeps running; an arrangement interval pauses because
      // the item was completed elsewhere.
      return active.intent == TimeLogRelation.extra;
    }
    return strategy.strategyExecutionError(data, task, shanghaiToday(_now())) ==
        null;
  }

  void _planChanged() {
    if (_disposed) return;
    if (!ready && coordinator.data != null && coordinator.userId.isNotEmpty) {
      unawaited(initialize());
    }
    final active = _state.active;
    if (ready && active != null && !_canActiveTime(active)) {
      if (busy) {
        _checkActiveAfterWrite = true;
      } else {
        _pauseInvalidActive();
      }
    }
    if (ready &&
        !busy &&
        coordinator.data != null &&
        _plannerNeedsUpdate(coordinator.data!)) {
      _needsPlannerFlush = true;
      unawaited(checkpoint().catchError((Object _) {}));
    }
    _notify();
  }

  void _tick() {
    if (_disposed || !ready) return;
    _notify();
    if (busy) return;
    if (_pauseInvalidActive()) return;
    final projection = _project();
    final crossedMinute = projection.buckets.any((bucket) {
      final previous = _state.buckets
          .where((old) => old.id == bucket.id)
          .firstOrNull;
      return bucket.milliseconds ~/ 60000 >
          (previous?.milliseconds ?? 0) ~/ 60000;
    });
    if (crossedMinute || _needsPlannerFlush) {
      unawaited(checkpoint().catchError((Object _) {}));
    }
  }

  bool _pauseInvalidActive() {
    final active = _state.active;
    if (active == null || _canActiveTime(active)) return false;
    if (!_invalidPauseQueued) {
      _invalidPauseQueued = true;
      unawaited(
        pause().catchError((Object _) {}).whenComplete(() {
          _invalidPauseQueued = false;
        }),
      );
    }
    return true;
  }

  void _updateTicker() {
    if (_accountDeletionSuspended) {
      _ticker?.cancel();
      _ticker = null;
      return;
    }
    if (_disposed) return;
    if (ready && (_state.active != null || _needsPlannerFlush)) {
      final interval = tickInterval;
      if (_ticker == null && interval != null) {
        _ticker = Timer.periodic(interval, (_) => _tick());
      }
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _stopwatch.stop();
    coordinator.removeListener(_planChanged);
    coordinator.removeConflictResolutionHandler(_onConflictResolution);
    super.dispose();
  }
}

class _TimerLifecycleObserver extends WidgetsBindingObserver {
  _TimerLifecycleObserver(this.timer);
  final StudyTimer timer;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (timer.ready && !timer.busy) {
      unawaited(timer.checkpoint().catchError((Object _) {}));
    }
  }
}

int _relationRank(TimeLogRelation relation) => switch (relation) {
  TimeLogRelation.scheduled => 0,
  TimeLogRelation.extra => 1,
  TimeLogRelation.adHoc => 2,
  TimeLogRelation.legacyUnknown => 3,
};

int _compareBuckets(_TimerBucket a, _TimerBucket b) {
  final byRelation = _relationRank(
    a.relation,
  ).compareTo(_relationRank(b.relation));
  if (byRelation != 0) return byRelation;
  final byStart = a.startedAt.compareTo(b.startedAt);
  return byStart != 0 ? byStart : a.id.compareTo(b.id);
}

/// User-discard scope: one owner and Shanghai date.
class _DiscardScope {
  const _DiscardScope({this.taskId, this.adHocId, required this.date});
  final String? taskId;
  final String? adHocId;
  final String date;
}

class _TimerState {
  const _TimerState({
    this.revision = 0,
    this.buckets = const [],
    this.sessions = const [],
    this.discards = const [],
    this.active,
  });
  final int revision;
  final List<_TimerBucket> buckets;
  final List<_TimerSession> sessions;
  final List<_TimerDiscard> discards;
  final _ActiveTimer? active;

  /// Lifts user-discard markers, restoring the local records for [scopes].
  _TimerState withoutDiscards(List<_DiscardScope> scopes) {
    final filtered = discards
        .where(
          (record) => !scopes.any(
            (scope) =>
                scope.taskId == record.taskId &&
                scope.adHocId == record.adHocId &&
                scope.date == record.date,
          ),
        )
        .toList();
    if (filtered.length == discards.length) return this;
    return copyWith(active: active, discards: filtered);
  }

  /// Marks every local minute currently recorded for [scopes] as user-discarded.
  _TimerState withDiscards(List<_DiscardScope> scopes) {
    if (scopes.isEmpty) return this;
    final next = [...discards];
    var changed = false;
    for (final scope in scopes) {
      final total = buckets
          .where(
            (bucket) =>
                bucket.taskId == scope.taskId &&
                bucket.adHocId == scope.adHocId &&
                bucket.date == scope.date,
          )
          .fold<int>(0, (sum, bucket) => sum + bucket.milliseconds);
      if (total <= 0) continue;
      final index = next.indexWhere(
        (record) =>
            record.taskId == scope.taskId &&
            record.adHocId == scope.adHocId &&
            record.date == scope.date,
      );
      if (index >= 0 && next[index].milliseconds == total) continue;
      final record = _TimerDiscard(
        taskId: scope.taskId,
        adHocId: scope.adHocId,
        date: scope.date,
        milliseconds: total,
      );
      if (index >= 0) {
        next[index] = record;
      } else {
        next.add(record);
      }
      changed = true;
    }
    if (!changed) return this;
    return copyWith(active: active, discards: next);
  }

  _TimerState copyWith({
    required _ActiveTimer? active,
    List<_TimerBucket>? buckets,
    List<_TimerSession>? sessions,
    List<_TimerDiscard>? discards,
  }) => _TimerState(
    revision: revision,
    buckets: buckets ?? this.buckets,
    sessions: sessions ?? this.sessions,
    discards: discards ?? this.discards,
    active: active,
  );

  _TimerState withRevision(int revision) => _TimerState(
    revision: revision,
    buckets: buckets,
    sessions: sessions,
    discards: discards,
    active: active,
  );

  factory _TimerState.fromJson(JsonMap json) {
    final version = json['version'];
    if (version != 1 && version != 2 && version != 3) {
      throw const FormatException('计时记录版本无效');
    }
    final buckets = [
      for (final value in json['buckets'] as List)
        _TimerBucket.fromJson(JsonMap.from(value as Map)),
    ];
    final active = json['active'] == null
        ? null
        : _ActiveTimer.fromJson(JsonMap.from(json['active'] as Map));
    final discards = (version == 2 || version == 3) && json['discards'] is List
        ? [
            for (final value in json['discards'] as List)
              _TimerDiscard.fromJson(JsonMap.from(value as Map)),
          ]
        : <_TimerDiscard>[];
    final sessions = version == 1
        ? [
            for (final bucket in buckets)
              _TimerSession(
                id: 'legacy:${bucket.id}',
                taskId: bucket.taskId,
                adHocId: bucket.adHocId,
                relation: TimeLogRelation.legacyUnknown,
                startedAt: bucket.startedAt,
                endedAt: bucket.endedAt,
                slots: {
                  _TimerSession.slotKey(
                    bucket.date,
                    TimeLogRelation.legacyUnknown,
                  ): bucket.milliseconds,
                },
                isLegacy: true,
              ),
            if (active != null)
              _TimerSession(
                id: active.sessionId,
                taskId: active.taskId,
                adHocId: active.adHocId,
                relation: active.intent,
                startedAt: active.checkpoint,
                endedAt: active.checkpoint,
              ),
          ]
        : [
            for (final value in json['sessions'] as List)
              _TimerSession.fromJson(JsonMap.from(value as Map)),
          ];
    return _TimerState(
      revision: (json['revision'] as int?) ?? 0,
      buckets: buckets,
      sessions: sessions,
      discards: discards,
      active: active,
    );
  }

  JsonMap toJson() => {
    'version': 3,
    'revision': revision,
    'buckets': [for (final bucket in buckets) bucket.toJson()],
    'sessions': [for (final session in sessions) session.toJson()],
    'discards': [for (final discard in discards) discard.toJson()],
    'active': active?.toJson(),
  };
}

class _ActiveTimer {
  const _ActiveTimer({
    this.taskId,
    this.adHocId,
    required this.intent,
    required this.checkpoint,
    required this.sessionId,
  });
  final String? taskId;
  final String? adHocId;

  /// The relation explicitly chosen when the interval started:
  /// [TimeLogRelation.scheduled], [TimeLogRelation.extra] or
  /// [TimeLogRelation.adHoc]. A scheduled interval may still overflow to extra.
  final TimeLogRelation intent;
  final DateTime checkpoint;
  final String sessionId;

  factory _ActiveTimer.fromJson(JsonMap json) => _ActiveTimer(
    taskId: json['taskId'] as String?,
    adHocId: json['adHocId'] as String?,
    intent:
        TimeLogRelation.values
            .where((value) => value.name == json['intent'])
            .firstOrNull ??
        TimeLogRelation.scheduled,
    checkpoint: DateTime.parse(json['checkpoint'] as String).toUtc(),
    sessionId:
        json['sessionId'] as String? ??
        'legacy-active:${json['taskId']}:${json['checkpoint']}',
  );

  JsonMap toJson() => {
    if (taskId != null) 'taskId': taskId,
    if (adHocId != null) 'adHocId': adHocId,
    'intent': intent.name,
    'checkpoint': checkpoint.toIso8601String(),
    'sessionId': sessionId,
  };
}

class _TimerSession {
  const _TimerSession({
    required this.id,
    this.taskId,
    this.adHocId,
    this.relation,
    required this.startedAt,
    required this.endedAt,
    this.slots = const {},
    this.isLegacy = false,
    this.discarded = false,
  });

  final String id;
  final String? taskId;
  final String? adHocId;

  /// Relation chosen when this interval started (null for legacy aggregates).
  final TimeLogRelation? relation;
  final DateTime startedAt, endedAt;

  /// Milliseconds per `date|relation` slot, so undoing an interval removes exactly
  /// what that interval contributed even when several intervals share a bucket.
  final Map<String, int> slots;
  final bool isLegacy, discarded;

  static String slotKey(String date, TimeLogRelation relation) =>
      '$date|${relation.name}';

  int get milliseconds => slots.values.fold(0, (a, b) => a + b);

  Map<String, int> get millisecondsByDate {
    final result = <String, int>{};
    for (final entry in slots.entries) {
      final date = entry.key.split('|').first;
      result[date] = (result[date] ?? 0) + entry.value;
    }
    return result;
  }

  int millisecondsForDate(String date) {
    var total = 0;
    for (final entry in slots.entries) {
      if (entry.key.startsWith('$date|')) total += entry.value;
    }
    return total;
  }

  _TimerSession copyWith({bool? discarded, String? taskId, String? adHocId}) =>
      _TimerSession(
        id: id,
        taskId: taskId ?? this.taskId,
        adHocId: adHocId ?? this.adHocId,
        relation: relation,
        startedAt: startedAt,
        endedAt: endedAt,
        slots: slots,
        isLegacy: isLegacy,
        discarded: discarded ?? this.discarded,
      );

  _TimerSession add(
    String date,
    TimeLogRelation relation,
    int elapsedMilliseconds,
    DateTime end,
  ) {
    final key = slotKey(date, relation);
    return _TimerSession(
      id: id,
      taskId: taskId,
      adHocId: adHocId,
      relation: relation,
      startedAt: startedAt,
      endedAt: end,
      slots: {...slots, key: (slots[key] ?? 0) + elapsedMilliseconds},
      isLegacy: isLegacy,
      discarded: discarded,
    );
  }

  factory _TimerSession.fromJson(JsonMap json) {
    final slots = json['slots'];
    return _TimerSession(
      id: json['id'] as String,
      taskId: json['taskId'] as String?,
      adHocId: json['adHocId'] as String?,
      relation: TimeLogRelation.values
          .where((value) => value.name == json['relation'])
          .firstOrNull,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      endedAt: DateTime.parse(json['endedAt'] as String).toUtc(),
      slots: slots is Map
          ? Map<String, int>.from(slots)
          : {
              // Version-2 sessions stored only per-date milliseconds; legacy
              // aggregates keep the unknown relation.
              for (final entry in Map<String, int>.from(
                (json['millisecondsByDate'] as Map?) ?? const {},
              ).entries)
                slotKey(entry.key, TimeLogRelation.legacyUnknown): entry.value,
            },
      isLegacy: json['isLegacy'] == true,
      discarded: json['discarded'] == true,
    );
  }

  JsonMap toJson() => {
    'id': id,
    if (taskId != null) 'taskId': taskId,
    if (adHocId != null) 'adHocId': adHocId,
    if (relation != null) 'relation': relation!.name,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'slots': slots,
    'isLegacy': isLegacy,
    'discarded': discarded,
  };
}

/// Minutes the user explicitly abandoned for one owner/day when resolving a sync
/// conflict in favour of the cloud copy.
class _TimerDiscard {
  const _TimerDiscard({
    this.taskId,
    this.adHocId,
    required this.date,
    required this.milliseconds,
  });
  final String? taskId;
  final String? adHocId;
  final String date;
  final int milliseconds;

  _TimerDiscard copyWith({String? taskId}) => _TimerDiscard(
    taskId: taskId ?? this.taskId,
    adHocId: adHocId,
    date: date,
    milliseconds: milliseconds,
  );

  factory _TimerDiscard.fromJson(JsonMap json) {
    final milliseconds = json['milliseconds'] as int;
    if (milliseconds < 0) throw const FormatException('计时舍弃记录无效');
    return _TimerDiscard(
      taskId: json['taskId'] as String?,
      adHocId: json['adHocId'] as String?,
      date: json['date'] as String,
      milliseconds: milliseconds,
    );
  }

  JsonMap toJson() => {
    if (taskId != null) 'taskId': taskId,
    if (adHocId != null) 'adHocId': adHocId,
    'date': date,
    'milliseconds': milliseconds,
  };
}

class _TimerBucket {
  const _TimerBucket({
    required this.id,
    this.taskId,
    this.adHocId,
    required this.date,
    required this.relation,
    required this.milliseconds,
    required this.startedAt,
    required this.endedAt,
    this.quotaMinutes,
    this.sessionIds = const [],
  });
  final String id;
  final String? taskId;
  final String? adHocId;
  final String date;
  final TimeLogRelation relation;
  final int milliseconds;
  final DateTime startedAt, endedAt;

  /// For scheduled buckets: remaining scheduled minutes captured when the day's
  /// scheduled segment started (always null for extra/ad-hoc buckets).
  final int? quotaMinutes;

  /// Sessions that contributed to this bucket. A log keeps a stable session id
  /// only when it was produced by exactly one interval.
  final List<String> sessionIds;

  _TimerBucket add(int elapsedMilliseconds, DateTime end, String sessionId) =>
      _TimerBucket(
        id: id,
        taskId: taskId,
        adHocId: adHocId,
        date: date,
        relation: relation,
        milliseconds: milliseconds + elapsedMilliseconds,
        startedAt: startedAt,
        endedAt: end,
        quotaMinutes: quotaMinutes,
        sessionIds: sessionIds.contains(sessionId)
            ? sessionIds
            : [...sessionIds, sessionId],
      );

  _TimerBucket subtract(int milliseconds, {String? sessionId}) => _TimerBucket(
    id: id,
    taskId: taskId,
    adHocId: adHocId,
    date: date,
    relation: relation,
    milliseconds: math.max(0, this.milliseconds - milliseconds),
    startedAt: startedAt,
    endedAt: endedAt,
    quotaMinutes: quotaMinutes,
    sessionIds: sessionId == null
        ? sessionIds
        : [
            for (final id in sessionIds)
              if (id != sessionId) id,
          ],
  );

  _TimerBucket withTaskId(String taskId) => _TimerBucket(
    id: id,
    taskId: taskId,
    adHocId: adHocId,
    date: date,
    relation: relation,
    milliseconds: milliseconds,
    startedAt: startedAt,
    endedAt: endedAt,
    quotaMinutes: quotaMinutes,
    sessionIds: sessionIds,
  );

  factory _TimerBucket.fromJson(JsonMap json) {
    final elapsed = json['milliseconds'] as int;
    if (elapsed < 0) throw const FormatException('计时记录用时无效');
    final relation = TimeLogRelation.values
        .where((value) => value.name == json['relation'])
        .firstOrNull;
    return _TimerBucket(
      id: json['id'] as String,
      taskId: json['taskId'] as String?,
      adHocId: json['adHocId'] as String?,
      date: json['date'] as String,
      relation: relation ?? TimeLogRelation.legacyUnknown,
      milliseconds: elapsed,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      endedAt: DateTime.parse(json['endedAt'] as String).toUtc(),
      quotaMinutes: json['quotaMinutes'] as int?,
      sessionIds: json['sessionIds'] is List
          ? [
              for (final value in json['sessionIds'] as List)
                if (value is String) value,
            ]
          : const [],
    );
  }

  JsonMap toJson() => {
    'id': id,
    if (taskId != null) 'taskId': taskId,
    if (adHocId != null) 'adHocId': adHocId,
    'date': date,
    'relation': relation.name,
    'milliseconds': milliseconds,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    if (quotaMinutes != null) 'quotaMinutes': quotaMinutes,
    if (sessionIds.isNotEmpty) 'sessionIds': sessionIds,
  };
}
