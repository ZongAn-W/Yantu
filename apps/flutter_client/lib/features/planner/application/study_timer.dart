import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../core/storage/study_timer_store.dart';
import '../../../core/sync/planner_coordinator.dart';
import '../../../shared/models/planner_models.dart';
import '../domain/planner_format.dart';
import '../domain/scheduler/planner_scheduler.dart' as scheduler;
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
  final observer = _TimerLifecycleObserver(timer);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() => WidgetsBinding.instance.removeObserver(observer));
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
  });

  final String id;
  final DateTime startedAt, endedAt;
  final Duration elapsed;
  final bool isLegacy;
}

/// One running timer per signed-in account and API endpoint. Its stable log IDs
/// make the local checkpoint and planner write safe to retry independently.
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
  bool _needsPlannerFlush = false;
  bool _checkActiveAfterWrite = false;
  bool _invalidPauseQueued = false;

  bool ready = false;
  bool busy = false;
  String? error;

  String get storageKey => '${coordinator.key}:study-timer-v1';
  String? get activeTaskId => _state.active?.taskId;

  bool isRunning(String taskId, String date) =>
      activeTaskId == taskId && date == shanghaiToday(_logicalNow());

  StudyTimerSession? lastSessionFor(String taskId, String date) {
    final session = _state.sessions
        .where(
          (session) =>
              session.taskId == taskId &&
              !session.discarded &&
              session.id != _state.active?.sessionId &&
              (session.millisecondsByDate[date] ?? 0) > 0,
        )
        .lastOrNull;
    if (session == null) return null;
    return StudyTimerSession(
      id: session.id,
      startedAt: session.startedAt,
      endedAt: session.endedAt,
      elapsed: Duration(milliseconds: session.milliseconds),
      isLegacy: session.isLegacy,
    );
  }

  Duration elapsedFor(String taskId, String date) {
    final data = coordinator.data;
    if (data == null) return Duration.zero;
    final buckets = _project().buckets;
    final owned = buckets.map((bucket) => bucket.id).toSet();
    final existing = data.logs
        .where((log) => log.taskId == taskId && log.date == date)
        .toList();
    var milliseconds = existing
        .where((log) => !owned.contains(log.id))
        .fold<int>(0, (sum, log) => sum + log.minutes * 60000);
    for (final bucket in buckets) {
      if (bucket.taskId != taskId || bucket.date != date) continue;
      milliseconds += bucket.milliseconds;
    }
    return Duration(milliseconds: milliseconds);
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
      var anchor = _monotonicNow();
      final active = next.active;
      if (active != null) {
        final now = _now().toUtc();
        anchor = _monotonicNow();
        final end = now.isBefore(active.checkpoint) ? active.checkpoint : now;
        next = _accrue(next, end);
        if (!_canTime(active.taskId)) next = next.copyWith(active: null);
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

  Future<void> start(String taskId, String date) => _serial(() async {
    if (!ready) {
      await initialize();
      if (!ready) throw StateError(error ?? '计时记录尚未读取完成');
    }
    if (date != shanghaiToday(_now())) {
      throw StateError('只能为今天的学习开始计时');
    }
    if (!_canTime(taskId)) throw StateError('当前事项不可计时');
    if (activeTaskId == taskId) return;
    final now = _logicalNow();
    final projected = _accrue(_state, now);
    final sessionId = _nextId();
    final next = projected.copyWith(
      active: _ActiveTimer(taskId, now, sessionId),
      sessions: [
        ...projected.sessions,
        _TimerSession(
          id: sessionId,
          taskId: taskId,
          startedAt: now,
          endedAt: now,
        ),
      ],
    );
    await _commit(next);
  });

  Future<void> pause() => _serial(() async {
    if (!ready || _state.active == null) return;
    await _commit(_project().copyWith(active: null));
  });

  Future<void> discardLastSession(
    String taskId,
    String date, {
    required String expectedSessionId,
  }) => _serial(() async {
    if (!ready) throw StateError('计时记录尚未读取完成');
    if (activeTaskId == taskId) throw StateError('请先暂停计时，再删除上一段记录');
    final index = _state.sessions.indexWhere(
      (session) => session.id == expectedSessionId,
    );
    if (index >= 0 && _state.sessions[index].discarded) {
      await _flushPlanner();
      return;
    }
    if (lastSessionFor(taskId, date)?.id != expectedSessionId || index < 0) {
      throw StateError('计时记录已变化，请重新确认要删除的记录');
    }
    final session = _state.sessions[index];
    final projected = _project();
    final buckets = [
      for (final bucket in projected.buckets)
        if (bucket.taskId == taskId)
          bucket.subtract(session.millisecondsByDate[bucket.date] ?? 0)
        else
          bucket,
    ];
    final sessions = [...projected.sessions];
    sessions[index] = session.copyWith(discarded: true);
    await _commit(
      projected.copyWith(
        active: projected.active,
        buckets: buckets,
        sessions: sessions,
      ),
    );
  });

  /// Used on lifecycle changes and whole-minute boundaries, never by a time input.
  Future<void> checkpoint() => _serial(() async {
    if (!ready) return;
    await _commit(_project());
  });

  Future<void> _serial(Future<void> Function() action) {
    final result = _writes.then((_) async {
      if (_disposed) return;
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
          final task = current.tasks
              .where((task) => task.id == bucket.taskId)
              .firstOrNull;
          if (task == null) continue;
          final index = logs.indexWhere((log) => log.id == bucket.id);
          final minutes = bucket.milliseconds ~/ 60000;
          if ((index < 0 ? 0 : logs[index].minutes) == minutes) continue;
          affected.add('${bucket.taskId}:${bucket.date}');
          if (minutes == 0) {
            logs.removeAt(index);
            continue;
          }
          final log = TimeLog(
            id: bucket.id,
            userId: task.userId,
            taskId: task.id,
            blockId: null,
            date: bucket.date,
            minutes: minutes,
            startedAt: bucket.startedAt.toIso8601String(),
            endedAt: bucket.endedAt.toIso8601String(),
            source: LogSource.timer,
          );
          if (index >= 0) {
            logs[index] = log;
          } else {
            logs.add(log);
          }
        }
        final next = current.copyWith(logs: logs);
        final remainingByDay = <String, int>{};
        final stamp = _logicalNow().toIso8601String();
        final sorted = [...next.blocks]
          ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
        final replacements = <String, ScheduleBlock>{};
        for (final block in sorted) {
          final key = '${block.taskId}:${block.date}';
          if (!affected.contains(key)) continue;
          final remaining = remainingByDay.putIfAbsent(
            key,
            () => day_ops.taskDayMinutes(next, block.taskId, block.date),
          );
          final actual = math.min(remaining, block.durationMinutes);
          remainingByDay[key] = remaining - actual;
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
        return day_ops.refreshTaskProgress(
          next.copyWith(
            blocks: [
              for (final block in next.blocks) replacements[block.id] ?? block,
            ],
          ),
          updatedAt: stamp,
        );
      });
    }
    _needsPlannerFlush = false;
  }

  bool _plannerNeedsUpdate(PlannerData data) => _state.buckets.any((bucket) {
    if (!data.tasks.any((task) => task.id == bucket.taskId)) return false;
    final existing = data.logs.where((log) => log.id == bucket.id).firstOrNull;
    return (existing?.minutes ?? 0) != bucket.milliseconds ~/ 60000;
  });

  DateTime _logicalNow() {
    final active = _state.active;
    if (active == null) return _now().toUtc();
    final delta = _monotonicNow() - _anchorMonotonic;
    return active.checkpoint.add(delta.isNegative ? Duration.zero : delta);
  }

  _TimerState _project() => _accrue(_state, _logicalNow());

  _TimerState _accrue(_TimerState state, DateTime end) {
    final active = state.active;
    if (active == null || !end.isAfter(active.checkpoint)) return state;
    var cursor = active.checkpoint;
    final buckets = [...state.buckets];
    final sessions = [...state.sessions];
    final sessionIndex = sessions.indexWhere(
      (session) => session.id == active.sessionId,
    );
    var session = sessions[sessionIndex];
    while (cursor.isBefore(end)) {
      final date = shanghaiToday(cursor);
      final midnight = DateTime.parse(
        '${addDate(date, 1)}T00:00:00Z',
      ).subtract(const Duration(hours: 8));
      final until = end.isBefore(midnight) ? end : midnight;
      final index = buckets.indexWhere(
        (bucket) => bucket.taskId == active.taskId && bucket.date == date,
      );
      final previous = index < 0
          ? _TimerBucket(
              id: _nextId(),
              taskId: active.taskId,
              date: date,
              milliseconds: 0,
              startedAt: cursor,
              endedAt: cursor,
            )
          : buckets[index];
      final next = previous.add(until.difference(cursor), until);
      session = session.add(date, until.difference(cursor), until);
      if (index < 0) {
        buckets.add(next);
      } else {
        buckets[index] = next;
      }
      cursor = until;
    }
    sessions[sessionIndex] = session;
    return _TimerState(
      revision: state.revision,
      buckets: buckets,
      sessions: sessions,
      active: _ActiveTimer(active.taskId, end, active.sessionId),
    );
  }

  bool _canTime(String taskId) =>
      !coordinator.blocked &&
      (coordinator.data?.tasks.any(
            (task) =>
                task.id == taskId &&
                task.status != TaskStatus.archived &&
                task.status != TaskStatus.completed,
          ) ??
          false);

  void _planChanged() {
    if (_disposed) return;
    if (!ready && coordinator.data != null && coordinator.userId.isNotEmpty) {
      unawaited(initialize());
    }
    final active = activeTaskId;
    if (ready && active != null && !_canTime(active)) {
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
    final active = activeTaskId;
    if (active == null || _canTime(active)) return false;
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

class _TimerState {
  const _TimerState({
    this.revision = 0,
    this.buckets = const [],
    this.sessions = const [],
    this.active,
  });
  final int revision;
  final List<_TimerBucket> buckets;
  final List<_TimerSession> sessions;
  final _ActiveTimer? active;

  _TimerState copyWith({
    required _ActiveTimer? active,
    List<_TimerBucket>? buckets,
    List<_TimerSession>? sessions,
  }) => _TimerState(
    revision: revision,
    buckets: buckets ?? this.buckets,
    sessions: sessions ?? this.sessions,
    active: active,
  );

  _TimerState withRevision(int revision) => _TimerState(
    revision: revision,
    buckets: buckets,
    sessions: sessions,
    active: active,
  );

  factory _TimerState.fromJson(JsonMap json) {
    final version = json['version'];
    if (version != 1 && version != 2) {
      throw const FormatException('计时记录版本无效');
    }
    final buckets = [
      for (final value in json['buckets'] as List)
        _TimerBucket.fromJson(JsonMap.from(value as Map)),
    ];
    final active = json['active'] == null
        ? null
        : _ActiveTimer.fromJson(JsonMap.from(json['active'] as Map));
    final sessions = version == 1
        ? [
            for (final bucket in buckets)
              _TimerSession(
                id: 'legacy:${bucket.id}',
                taskId: bucket.taskId,
                startedAt: bucket.startedAt,
                endedAt: bucket.endedAt,
                millisecondsByDate: {bucket.date: bucket.milliseconds},
                isLegacy: true,
              ),
            if (active != null)
              _TimerSession(
                id: active.sessionId,
                taskId: active.taskId,
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
      active: active,
    );
  }

  JsonMap toJson() => {
    'version': 2,
    'revision': revision,
    'buckets': [for (final bucket in buckets) bucket.toJson()],
    'sessions': [for (final session in sessions) session.toJson()],
    'active': active?.toJson(),
  };
}

class _ActiveTimer {
  const _ActiveTimer(this.taskId, this.checkpoint, this.sessionId);
  final String taskId, sessionId;
  final DateTime checkpoint;

  factory _ActiveTimer.fromJson(JsonMap json) => _ActiveTimer(
    json['taskId'] as String,
    DateTime.parse(json['checkpoint'] as String).toUtc(),
    json['sessionId'] as String? ??
        'legacy-active:${json['taskId']}:${json['checkpoint']}',
  );

  JsonMap toJson() => {
    'taskId': taskId,
    'checkpoint': checkpoint.toIso8601String(),
    'sessionId': sessionId,
  };
}

class _TimerSession {
  const _TimerSession({
    required this.id,
    required this.taskId,
    required this.startedAt,
    required this.endedAt,
    this.millisecondsByDate = const {},
    this.isLegacy = false,
    this.discarded = false,
  });

  final String id, taskId;
  final DateTime startedAt, endedAt;
  final Map<String, int> millisecondsByDate;
  final bool isLegacy, discarded;

  int get milliseconds => millisecondsByDate.values.fold(0, (a, b) => a + b);

  _TimerSession copyWith({bool? discarded}) => _TimerSession(
    id: id,
    taskId: taskId,
    startedAt: startedAt,
    endedAt: endedAt,
    millisecondsByDate: millisecondsByDate,
    isLegacy: isLegacy,
    discarded: discarded ?? this.discarded,
  );

  _TimerSession add(String date, Duration elapsed, DateTime end) =>
      _TimerSession(
        id: id,
        taskId: taskId,
        startedAt: startedAt,
        endedAt: end,
        millisecondsByDate: {
          ...millisecondsByDate,
          date: (millisecondsByDate[date] ?? 0) + elapsed.inMilliseconds,
        },
        isLegacy: isLegacy,
        discarded: discarded,
      );

  factory _TimerSession.fromJson(JsonMap json) => _TimerSession(
    id: json['id'] as String,
    taskId: json['taskId'] as String,
    startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
    endedAt: DateTime.parse(json['endedAt'] as String).toUtc(),
    millisecondsByDate: Map<String, int>.from(
      json['millisecondsByDate'] as Map,
    ),
    isLegacy: json['isLegacy'] == true,
    discarded: json['discarded'] == true,
  );

  JsonMap toJson() => {
    'id': id,
    'taskId': taskId,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
    'millisecondsByDate': millisecondsByDate,
    'isLegacy': isLegacy,
    'discarded': discarded,
  };
}

class _TimerBucket {
  const _TimerBucket({
    required this.id,
    required this.taskId,
    required this.date,
    required this.milliseconds,
    required this.startedAt,
    required this.endedAt,
  });
  final String id, taskId, date;
  final int milliseconds;
  final DateTime startedAt, endedAt;

  _TimerBucket add(Duration elapsed, DateTime end) => _TimerBucket(
    id: id,
    taskId: taskId,
    date: date,
    milliseconds: milliseconds + elapsed.inMilliseconds,
    startedAt: startedAt,
    endedAt: end,
  );

  _TimerBucket subtract(int milliseconds) => _TimerBucket(
    id: id,
    taskId: taskId,
    date: date,
    milliseconds: math.max(0, this.milliseconds - milliseconds),
    startedAt: startedAt,
    endedAt: endedAt,
  );

  factory _TimerBucket.fromJson(JsonMap json) {
    final elapsed = json['milliseconds'] as int;
    if (elapsed < 0) throw const FormatException('计时记录用时无效');
    return _TimerBucket(
      id: json['id'] as String,
      taskId: json['taskId'] as String,
      date: json['date'] as String,
      milliseconds: elapsed,
      startedAt: DateTime.parse(json['startedAt'] as String).toUtc(),
      endedAt: DateTime.parse(json['endedAt'] as String).toUtc(),
    );
  }

  JsonMap toJson() => {
    'id': id,
    'taskId': taskId,
    'date': date,
    'milliseconds': milliseconds,
    'startedAt': startedAt.toIso8601String(),
    'endedAt': endedAt.toIso8601String(),
  };
}
