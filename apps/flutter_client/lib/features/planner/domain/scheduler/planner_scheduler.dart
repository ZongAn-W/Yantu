import 'dart:convert';
import 'dart:math' as math;

import '../../../../shared/models/planner_models.dart';
import '../capacity.dart' as capacity_core;
import 'strategy_scheduler.dart' as strategy;

typedef IdGenerator = String Function();

class SchedulerRuntime {
  const SchedulerRuntime({this.now, this.nextId});

  final DateTime? now;
  final IdGenerator? nextId;

  String timestamp() => DateTime.fromMillisecondsSinceEpoch(
    (now ?? DateTime.now()).millisecondsSinceEpoch,
    isUtc: true,
  ).toIso8601String();

  IdGenerator get ids => nextId ?? _randomId;
}

String _randomId() {
  final random = math.Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Public UUID v4 generator, so page code never reaches into private helpers.
String newUuid() => _randomId();

/// JS Array.sort is stable; Dart List.sort does not promise stable equal keys.
List<T> _stableSorted<T>(Iterable<T> values, int Function(T, T) compare) {
  final indexed = values.indexed.toList()
    ..sort((a, b) {
      final order = compare(a.$2, b.$2);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
  return indexed.map((row) => row.$2).toList();
}

String addDays(String date, int days) {
  final parsed = _parseDate(date);
  if (parsed == null) {
    throw const FormatException('日期格式无效');
  }
  return _dateOnly(parsed.add(Duration(days: days)));
}

DateTime? _parseDate(String date) {
  // Date.parse permits February overflow through day 31, but rejects month 0/13
  // and day 0/32. Dart's parser otherwise normalizes all of those values.
  if (!RegExp(
    r'^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$',
  ).hasMatch(date)) {
    return null;
  }
  return DateTime.tryParse('${date}T00:00:00Z');
}

String dateToday([DateTime? now]) {
  final value = now ?? DateTime.now();
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

String _dateOnly(DateTime value) =>
    '${value.toUtc().year.toString().padLeft(4, '0')}-${value.toUtc().month.toString().padLeft(2, '0')}-${value.toUtc().day.toString().padLeft(2, '0')}';

/// Compatibility helper for imported plans. Fixed events no longer recur or reserve time.
bool eventOccursOn(FixedEvent event, String date) => false;

int _finite(int value) => value < 0 ? 0 : value;

int taskCompletedMinutes(Task task, List<TimeLog> logs) {
  final logged = logs
      .where((log) => log.taskId == task.id)
      .fold<int>(0, (sum, log) => sum + _finite(log.minutes));
  return math.min(
    _finite(task.estimatedMinutes),
    math.max(_finite(task.completedMinutes), logged),
  );
}

int remainingTaskMinutes(Task task, List<TimeLog> logs) => math.max(
  0,
  _finite(task.estimatedMinutes) - taskCompletedMinutes(task, logs),
);

int _blockActual(ScheduleBlock block, List<TimeLog> logs) => math.max(
  _finite(block.actualMinutes),
  logs
      .where((log) => log.blockId == block.id)
      .fold<int>(0, (sum, log) => sum + _finite(log.minutes)),
);

int _blockPending(ScheduleBlock block, List<TimeLog> logs) =>
    block.status == BlockStatus.completed
    ? 0
    : math.max(0, block.durationMinutes - _blockActual(block, logs));

// ---------------------------------------------------------------------------
// Shared scheduling semantics.
//
// The automatic strategy scheduler (strategy_scheduler.dart) and the manual
// placement validator below must agree on prerequisites and capacity. These
// helpers are the single implementation of both rules in this language.
// ---------------------------------------------------------------------------

/// Real content confirmation: completed status or an explicit planning confirmation.
bool contentConfirmed(Task task) {
  if (task.status == TaskStatus.completed) return true;
  final content = task.planning?['content_progress'];
  return content is Map && content['confirmed'] == true;
}

/// Minutes a block reserves for capacity: recorded work when known, otherwise the
/// planned duration. A completed block without actual history still holds its slot.
int _blockOccupiedMinutes(ScheduleBlock block, List<TimeLog> logs) {
  final actual = _blockActual(block, logs);
  return block.status == BlockStatus.completed && actual > 0
      ? actual
      : math.max(block.durationMinutes, actual);
}

/// Half-open interval a block occupies; an actual overrun extends the interval.
(int, int) blockOccupiedInterval(ScheduleBlock block, List<TimeLog> logs) => (
  block.startMinute,
  block.startMinute +
      math.max(block.durationMinutes, _blockActual(block, logs)),
);

/// Length of the union of half-open intervals clipped to [from, to].
int _occupiedUnionMinutes(
  Iterable<(int, int)> intervals, {
  int from = 0,
  int to = 1440,
}) {
  var total = 0;
  var last = from;
  final sorted = intervals.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  for (final interval in sorted) {
    final start = math.max(from, interval.$1);
    final end = math.min(to, interval.$2);
    if (end <= start) continue;
    total += math.max(0, end - math.max(start, last));
    last = math.max(last, end);
  }
  return total;
}

/// Compatibility helper for imported plans; legacy events never occupy time.
List<(int, int)> fixedEventOccupiedIntervals(
  List<FixedEvent> events,
  String date,
) => const [];

/// Capacity occupied by study blocks on one day, shared by automatic scheduling
/// and manual placement. Timed plans clip block intervals to the study window;
/// daily plans add each block's occupied load. Legacy event data is ignored.
int occupiedDayMinutes({
  required Profile profile,
  required List<FixedEvent> fixedEvents,
  required List<ScheduleBlock> dayBlocks,
  required List<TimeLog> logs,
  required String date,
}) {
  if (profile.planningMode != PlanningMode.timed) {
    return dayBlocks.fold<int>(
      0,
      (sum, block) => sum + _blockOccupiedMinutes(block, logs),
    );
  }
  return _occupiedUnionMinutes(
    [for (final block in dayBlocks) blockOccupiedInterval(block, logs)],
    from: profile.studyStartMinute,
    to: profile.studyEndMinute,
  );
}

/// Minutes of [task] not covered by confirmed time or blocks scheduled on/after [from].
///
/// The automatic scheduler scopes this to its window because protected history is kept
/// outside it; manual placement validates one date and considers every placed block.
int forecastRemainingMinutes(
  Task task,
  List<TimeLog> logs,
  List<ScheduleBlock> blocks, {
  String? from,
}) {
  final completed = taskCompletedMinutes(task, logs);
  final pending = blocks
      .where(
        (block) =>
            block.taskId == task.id &&
            block.status != BlockStatus.completed &&
            (from == null || block.date.compareTo(from) >= 0),
      )
      .fold<int>(
        0,
        (sum, block) =>
            sum +
            math.max(0, block.durationMinutes - _blockActual(block, logs)),
      );
  return math.max(0, _finite(task.estimatedMinutes) - completed - pending);
}

/// Three-state prerequisite rule reused by automatic scheduling, manual placement and
/// execution (see [strategyExecutionError] which passes [allowForecast] false):
///
/// 1. completed status or explicit content confirmation satisfies any dependency;
/// 2. a "planned" dependency may also be met by a forecast: the predecessor's remaining
///    minutes are zero and every one of its blocks is before the target date;
/// 3. merely exhausting the estimated time never confirms content.
bool dependencySatisfied({
  required Task prior,
  required JsonMap dependency,
  required List<ScheduleBlock> priorBlocks,
  required String date,
  required int remaining,
  bool allowForecast = true,
}) {
  if (contentConfirmed(prior)) return true;
  if (dependency['mode'] == 'confirmed' || !allowForecast) return false;
  return remaining == 0 &&
      priorBlocks.isNotEmpty &&
      priorBlocks.every((block) => block.date.compareTo(date) < 0);
}

class _Limits {
  const _Limits({
    required this.quantum,
    required this.start,
    required this.end,
  });

  final int quantum;
  final int start;
  final int end;
}

/// 周几索引，与服务端 `getUTCDay` 一致：0 为周日，6 为周六。
int weekdayIndex(String date) {
  final parsed = _parseDate(date);
  if (parsed == null) return 0;
  return parsed.weekday % 7;
}

/// 某一自然日的可用学习预算（应用净/总口径后）。
///
/// 单一入口由 [capacity_core.resolveDayCapacity] 提供：具体日期覆盖、特定周、
/// 默认模板/周基线共用同一套规则，页面与调度器因此不会各算一份。
int dailyStudyBudget(Profile profile, String date) =>
    capacity_core.resolveDayCapacity(profile, date).minutes;

_Limits _limits(Profile profile) => _Limits(
  quantum: math.max(30, _finite(profile.granularityMinutes)),
  start: math.max(0, _finite(profile.studyStartMinute)),
  end: math.min(1440, _finite(profile.studyEndMinute)),
);

bool _overlap(int start, int duration, int otherStart, int otherDuration) =>
    start < otherStart + otherDuration && otherStart < start + duration;

/// Compatibility helper for imported plans; fixed events no longer reduce capacity.
int fixedEventMinutesForDate(
  List<FixedEvent> events,
  String date, {
  bool includeRest = true,
}) => 0;

int availableDailyMinutes(
  Profile profile,
  List<FixedEvent> events,
  String date,
) => dailyStudyBudget(profile, date);

String? _placementError(
  ReplanInput input,
  List<ScheduleBlock> blocks,
  ScheduleBlock candidate, {
  bool enforceTask = true,
}) {
  final task = input.tasks
      .where((item) => item.id == candidate.taskId)
      .firstOrNull;
  if (task == null) return '找不到对应任务';
  if (task.status == TaskStatus.archived) return '已归档事项不可安排';
  if (_parseDate(candidate.date) == null) {
    return '日期格式无效';
  }
  final capacity = _limits(input.profile);
  final timed = input.profile.planningMode == PlanningMode.timed;
  if (candidate.durationMinutes <= 0) return '时间块时长必须大于零';
  if (timed &&
      (candidate.startMinute < capacity.start ||
          candidate.startMinute + candidate.durationMinutes > capacity.end)) {
    return '时间块超出每日学习时间范围';
  }
  if (timed && candidate.startMinute % capacity.quantum != 0) {
    return '开始时间需要对齐计划时间粒度';
  }
  if (enforceTask &&
      (task.status == TaskStatus.completed ||
          remainingTaskMinutes(task, input.logs) == 0)) {
    return '已完成任务无需再次安排';
  }
  if (candidate.date.compareTo(task.earliestDate ?? '0000-01-01') < 0) {
    return '任务尚未到开始日期';
  }
  if (candidate.date.compareTo(task.deadline) > 0) {
    return '时间块不能晚于任务截止日期';
  }
  if ((input.profile.planStartDate.isNotEmpty &&
          candidate.date.compareTo(input.profile.planStartDate) < 0) ||
      (input.profile.planEndDate.isNotEmpty &&
          candidate.date.compareTo(input.profile.planEndDate) > 0)) {
    return '时间块不能超出本期规划区间';
  }
  final activity = strategy.activityOf(task);
  if (activity?['state'] == 'paused' || activity?['state'] == 'ended') {
    return '活动已暂停或结束';
  }
  if ((activity?['starts_on'] != null &&
          candidate.date.compareTo(activity!['starts_on'] as String) < 0) ||
      (activity?['ends_on'] != null &&
          candidate.date.compareTo(activity!['ends_on'] as String) > 0)) {
    return '时间块超出活动有效日期';
  }
  for (final dependency in strategy.dependenciesOf(task)) {
    final prior = input.tasks
        .where((item) => item.id == dependency['task_id'])
        .firstOrNull;
    if (prior == null ||
        prior.userId != task.userId ||
        prior.status == TaskStatus.archived) {
      return '前置内容尚未确认完成';
    }
    final priorBlocks = input.blocks
        .where((block) => block.taskId == prior.id)
        .toList();
    if (!dependencySatisfied(
      prior: prior,
      dependency: dependency,
      priorBlocks: priorBlocks,
      date: candidate.date,
      remaining: forecastRemainingMinutes(prior, input.logs, priorBlocks),
    )) {
      return '前置内容尚未确认完成';
    }
  }
  final dayBlocks = blocks
      .where((block) => block.date == candidate.date)
      .toList();
  if (timed &&
      dayBlocks.any(
        (block) => _overlap(
          candidate.startMinute,
          candidate.durationMinutes,
          block.startMinute,
          math.max(block.durationMinutes, _blockActual(block, input.logs)),
        ),
      )) {
    return '与已有时间块冲突';
  }
  final orphanLogs = input.logs.where(
    (log) =>
        log.date == candidate.date &&
        (log.blockId == null ||
            !dayBlocks.any((block) => block.id == log.blockId)),
  );
  // The same occupancy accounting is shared with the automatic strategy scheduler:
  // timed plans clip to the study window, and a completed block without actual
  // history still reserves its planned slot.
  final dailyOccupied = occupiedDayMinutes(
    profile: input.profile,
    fixedEvents: input.fixedEvents,
    dayBlocks: dayBlocks,
    logs: input.logs,
    date: candidate.date,
  );
  if (dailyOccupied +
          orphanLogs.fold<int>(0, (sum, log) => sum + _finite(log.minutes)) +
          candidate.durationMinutes >
      dailyStudyBudget(input.profile, candidate.date)) {
    return capacity_core.supportsLightweightScheduling(input.profile)
        ? '超出当天可用的净学习时间，请调整当天安排或设置该日期的容量'
        : '超出当天可用的学习时间（每日上限），须保留至少30分钟机动时间';
  }
  return null;
}

String? validateBlockPlacement(
  PlannerData data,
  ScheduleBlock block, {
  String? ignoreId,
}) {
  final old = ignoreId == null
      ? null
      : data.blocks.where((item) => item.id == ignoreId).firstOrNull;
  final oldTask = old == null
      ? null
      : data.tasks.where((task) => task.id == old.taskId).firstOrNull;
  if (old != null &&
      (old.isFixed ||
          old.status == BlockStatus.completed ||
          oldTask?.isFixed == true) &&
      (old.date != block.date ||
          (data.profile.planningMode == PlanningMode.timed &&
              old.startMinute != block.startMinute) ||
          old.durationMinutes != block.durationMinutes)) {
    return '固定或已完成的时间块不可移动';
  }
  return _placementError(
    ReplanInput(
      tasks: data.tasks,
      blocks: data.blocks,
      logs: data.logs,
      fixedEvents: data.fixedEvents,
      profile: data.profile,
      today: dateToday(),
      mode: ReplanMode.unfinished,
    ),
    data.blocks.where((item) => item.id != ignoreId).toList(),
    block,
  );
}

int _compareTask(Task a, Task b) => a.deadline.compareTo(b.deadline) != 0
    ? a.deadline.compareTo(b.deadline)
    : b.priority.compareTo(a.priority) != 0
    ? b.priority.compareTo(a.priority)
    : a.createdAt.compareTo(b.createdAt) != 0
    ? a.createdAt.compareTo(b.createdAt)
    : a.id.compareTo(b.id);

ScheduleBlock? _findSlot(
  ReplanInput input,
  List<ScheduleBlock> blocks,
  Task task,
  int duration,
  String firstDate,
  String lastDate,
  String timestamp,
  IdGenerator id,
) {
  final capacity = _limits(input.profile);
  final first = firstDate.compareTo(task.earliestDate ?? '') < 0
      ? task.earliestDate!
      : firstDate;
  final last = lastDate.compareTo(task.deadline) < 0 ? lastDate : task.deadline;
  for (var date = first; ; date = addDays(date, 1)) {
    if (date.compareTo(last) > 0) break;
    if (input.profile.planningMode != PlanningMode.timed) {
      final block = ScheduleBlock(
        id: id(),
        userId: input.profile.userId,
        taskId: task.id,
        date: date,
        startMinute: 0,
        durationMinutes: duration,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      if (_placementError(input, blocks, block) == null) return block;
      continue;
    }
    for (
      var start =
          ((capacity.start + capacity.quantum - 1) ~/ capacity.quantum) *
          capacity.quantum;
      start + duration <= capacity.end;
      start += capacity.quantum
    ) {
      final block = ScheduleBlock(
        id: id(),
        userId: input.profile.userId,
        taskId: task.id,
        date: date,
        startMinute: start,
        durationMinutes: duration,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      if (_placementError(input, blocks, block) == null) return block;
    }
  }
  return null;
}

String _snapshotKey(List<ScheduleBlock> blocks) {
  final rows =
      blocks
          .map(
            (block) => [
              block.id,
              block.userId,
              block.taskId,
              block.date,
              block.startMinute,
              block.durationMinutes,
              block.actualMinutes,
              block.isFixed,
              block.status.name,
              block.createdAt,
              block.updatedAt,
            ],
          )
          .toList()
        ..sort((a, b) => (a[0] as String).compareTo(b[0] as String));
  return jsonEncode(rows);
}

ScheduleBlock _copyBlock(ScheduleBlock block) => block.copyWith();

ReplanPreview _makePreview(
  ReplanInput input,
  List<ScheduleBlock> after,
  List<Conflict> conflicts,
  String timestamp,
  IdGenerator id,
) {
  final before = input.blocks.map(_copyBlock).toList();
  final runId = id();
  final oldMap = {for (final block in before) block.id: block};
  final nextMap = {for (final block in after) block.id: block};
  final changes = <ReplanChange>[];
  for (final block in before) {
    final next = nextMap[block.id];
    if (next == null || _snapshotKey([block]) != _snapshotKey([next])) {
      changes.add(
        ReplanChange(
          id: id(),
          userId: input.profile.userId,
          runId: runId,
          type: next == null ? ChangeType.deleted : ChangeType.moved,
          blockId: block.id,
          before: block,
          after: next,
        ),
      );
    }
  }
  for (final block in after) {
    if (!oldMap.containsKey(block.id)) {
      changes.add(
        ReplanChange(
          id: id(),
          userId: input.profile.userId,
          runId: runId,
          type: ChangeType.added,
          blockId: block.id,
          before: null,
          after: _copyBlock(block),
        ),
      );
    }
  }
  final postponed = <String>{};
  final advanced = <String>{};
  for (final change in changes) {
    final beforeBlock = change.before;
    final afterBlock = change.after;
    if (beforeBlock != null &&
        afterBlock != null &&
        afterBlock.date.compareTo(beforeBlock.date) > 0) {
      postponed.add(afterBlock.taskId);
    }
    if (beforeBlock != null &&
        afterBlock != null &&
        afterBlock.date.compareTo(beforeBlock.date) < 0) {
      advanced.add(afterBlock.taskId);
    }
  }
  for (final change in changes.where((item) => item.type == ChangeType.added)) {
    final moved = change.after!;
    if (before.any(
          (block) =>
              block.taskId == moved.taskId &&
              block.date == input.today &&
              block.status != BlockStatus.completed,
        ) &&
        moved.date.compareTo(input.today) > 0) {
      postponed.add(moved.taskId);
    }
  }
  final dates = {
    ...before.map((block) => block.date),
    ...after.map((block) => block.date),
  }.toList()..sort();
  final dailyChanges = dates
      .map((date) {
        final beforeMinutes = before
            .where((block) => block.date == date)
            .fold<int>(0, (sum, block) => sum + block.durationMinutes);
        final afterMinutes = after
            .where((block) => block.date == date)
            .fold<int>(0, (sum, block) => sum + block.durationMinutes);
        return DayChange(
          date: date,
          beforeMinutes: beforeMinutes,
          afterMinutes: afterMinutes,
        );
      })
      .where((day) => day.beforeMinutes != day.afterMinutes)
      .toList();
  return ReplanPreview(
    id: runId,
    userId: input.profile.userId,
    createdAt: timestamp,
    before: before,
    after: after.map(_copyBlock).toList(),
    changes: changes,
    postponed: postponed.toList(),
    advanced: advanced.toList(),
    conflicts: conflicts,
    dailyChanges: dailyChanges,
  );
}

ReplanPreview generateReplanPreview(
  ReplanInput input, {
  SchedulerRuntime runtime = const SchedulerRuntime(),
}) {
  final timestamp = runtime.timestamp();
  final id = runtime.ids;
  final horizon = addDays(
    input.today,
    input.mode == ReplanMode.overcompleted ? 7 : 14,
  );
  final tasks = {for (final task in input.tasks) task.id: task};
  bool immutable(ScheduleBlock block) =>
      block.isFixed ||
      block.status == BlockStatus.completed ||
      (input.mode == ReplanMode.overcompleted &&
          tasks[block.taskId] != null &&
          strategy.activityOf(tasks[block.taskId]!)?['kind'] == 'recurring') ||
      _blockActual(block, input.logs) > 0 ||
      input.logs.any(
        (log) =>
            log.blockId == block.id ||
            log.blockId == null &&
                log.taskId == block.taskId &&
                log.date == block.date,
      ) ||
      (tasks[block.taskId]?.status == TaskStatus.archived &&
          _blockActual(block, input.logs) > 0) ||
      tasks[block.taskId]?.isFixed == true ||
      block.date.compareTo(input.today) < 0 ||
      block.date.compareTo(horizon) > 0;
  if (input.mode == ReplanMode.unfinished &&
      input.tasks.any(
        (task) =>
            strategy.activityOf(task) != null ||
            strategy.dependenciesOf(task).isNotEmpty,
      )) {
    final end =
        input.profile.planEndDate.isNotEmpty &&
            input.profile.planEndDate.compareTo(horizon) < 0
        ? input.profile.planEndDate
        : horizon;
    final from = addDays(input.today, 1);
    final kept = input.blocks.where(immutable).toList();
    final result = from.compareTo(end) <= 0
        ? strategy.scheduleStrategy(
            PlannerData(
              version: 1,
              profile: input.profile,
              tags: const [],
              tasks: input.tasks,
              blocks: kept,
              logs: input.logs,
              fixedEvents: input.fixedEvents,
              replanRuns: const [],
              phases: const [],
            ),
            from,
            end,
            runtime: runtime,
          )
        : strategy.StrategyResult(kept, 0, 0, 0, const []);
    final after = result.blocks.map((block) {
      if (block.activityInstanceId == null) return block;
      final previous = input.blocks
          .where((old) => old.activityInstanceId == block.activityInstanceId)
          .firstOrNull;
      return previous != null && !kept.any((old) => old.id == previous.id)
          ? block.copyWith(id: previous.id, createdAt: previous.createdAt)
          : block;
    }).toList();
    return _makePreview(
      input,
      after,
      result.issues
          .map(
            (issue) => Conflict(
              taskId: issue.taskId,
              title: tasks[issue.taskId]?.title ?? '',
              minutes: issue.code == 'RECURRENCE_SHORTFALL'
                  ? (strategy.activityOf(
                              tasks[issue.taskId]!,
                            )?['session_minutes']
                            as int? ??
                        30)
                  : math.max(0, issue.expected - issue.actual),
              reason: issue.message,
            ),
          )
          .toList(),
      timestamp,
      id,
    );
  }
  if (input.mode == ReplanMode.overcompleted) {
    final after = input.blocks
        .where((block) {
          final task = tasks[block.taskId];
          return immutable(block) ||
              task == null ||
              (task.status != TaskStatus.archived &&
                  (block.date == input.today ||
                      (task.status != TaskStatus.completed &&
                          remainingTaskMinutes(task, input.logs) > 0)));
        })
        .map(_copyBlock)
        .toList();
    var available = _finite(input.excessMinutes ?? 0);
    final eligible = _stableSorted(
      input.blocks.where(
        (block) =>
            block.date.compareTo(input.today) > 0 &&
            block.date.compareTo(horizon) <= 0 &&
            !immutable(block) &&
            _blockActual(block, input.logs) == 0,
      ),
      (a, b) {
        final ta = tasks[a.taskId], tb = tasks[b.taskId];
        if (ta == null || tb == null) return 0;
        final priority = tb.priority.compareTo(ta.priority);
        if (priority != 0) return priority;
        final deadline = ta.deadline.compareTo(tb.deadline);
        if (deadline != 0) return deadline;
        final date = a.date.compareTo(b.date);
        return date != 0 ? date : a.startMinute.compareTo(b.startMinute);
      },
    );
    final spent = <String, int>{};
    for (final source in eligible) {
      final task = tasks[source.taskId];
      if (task == null ||
          task.status == TaskStatus.archived ||
          task.status == TaskStatus.completed ||
          remainingTaskMinutes(task, input.logs) == 0) {
        continue;
      }
      final remaining =
          remainingTaskMinutes(task, input.logs) - (spent[task.id] ?? 0);
      final pending = math.min(
        math.min(source.durationMinutes, remaining),
        available,
      );
      var moved = 0;
      String? firstMovedId;
      while (moved < pending) {
        final duration = math.min(
          _limits(input.profile).quantum,
          pending - moved,
        );
        if (duration < _limits(input.profile).quantum &&
            remaining - moved > duration &&
            source.durationMinutes - moved > duration) {
          break;
        }
        final slot = _findSlot(
          input,
          after,
          task,
          duration,
          input.today,
          input.today,
          timestamp,
          id,
        );
        if (slot == null) break;
        after.add(slot);
        firstMovedId ??= slot.id;
        moved += duration;
        available -= duration;
      }
      if (moved > 0) {
        final index = after.indexWhere((block) => block.id == source.id);
        final pulledIndex = after.indexWhere(
          (block) => block.id == firstMovedId,
        );
        if (pulledIndex >= 0) {
          after[pulledIndex] = after[pulledIndex].copyWith(
            id: source.id,
            createdAt: source.createdAt,
          );
        }
        if (moved == source.durationMinutes) {
          if (index >= 0) after.removeAt(index);
        } else if (index >= 0) {
          after[index] = source.copyWith(
            id: id(),
            durationMinutes: source.durationMinutes - moved,
            updatedAt: timestamp,
          );
        }
        spent[task.id] = (spent[task.id] ?? 0) + moved;
      }
      if (available <= 0) break;
    }
    return _makePreview(input, after, const [], timestamp, id);
  }
  final after = <ScheduleBlock>[];
  final candidates = <String, List<ScheduleBlock>>{};
  final immutableReserved = <String, int>{};
  for (final block in input.blocks) {
    if (immutable(block)) {
      after.add(_copyBlock(block));
      if (block.date.compareTo(input.today) >= 0 &&
          block.status != BlockStatus.completed) {
        immutableReserved[block.taskId] =
            (immutableReserved[block.taskId] ?? 0) +
            _blockPending(block, input.logs);
      }
      continue;
    }
    final task = tasks[block.taskId];
    if (task == null) {
      after.add(_copyBlock(block));
      continue;
    }
    if (_blockActual(block, input.logs) > 0) {
      after.add(
        block.copyWith(
          status: BlockStatus.completed,
          actualMinutes: _blockActual(block, input.logs),
          updatedAt: timestamp,
        ),
      );
    }
    if (task.status != TaskStatus.archived &&
        task.status != TaskStatus.completed &&
        remainingTaskMinutes(task, input.logs) > 0 &&
        _blockPending(block, input.logs) > 0) {
      (candidates[task.id] ??= []).add(block);
    }
  }
  final conflicts = <Conflict>[];
  final queuedTasks =
      input.tasks.where((task) => candidates.containsKey(task.id)).toList()
        ..sort(_compareTask);
  for (final task in queuedTasks) {
    var budget = math.max(
      0,
      remainingTaskMinutes(task, input.logs) -
          (immutableReserved[task.id] ?? 0),
    );
    var missed = 0;
    final sources = _stableSorted(
      candidates[task.id]!,
      (a, b) => a.date.compareTo(b.date) != 0
          ? a.date.compareTo(b.date)
          : a.startMinute.compareTo(b.startMinute),
    );
    for (final source in sources) {
      var pending = math.min(_blockPending(source, input.logs), budget);
      budget -= pending;
      var first = true;
      var offset = 0;
      while (pending > 0) {
        final duration = math.min(_limits(input.profile).quantum, pending);
        ScheduleBlock? next;
        final preferred = source.copyWith(
          id: first && _blockActual(source, input.logs) == 0 ? source.id : id(),
          startMinute: input.profile.planningMode == PlanningMode.timed
              ? source.startMinute + offset
              : source.startMinute,
          durationMinutes: duration,
          actualMinutes: 0,
          status: BlockStatus.planned,
        );
        if (source.date.compareTo(input.today) > 0 &&
            _placementError(input, after, preferred) == null) {
          next = preferred;
        }
        if (next == null) {
          final slot = _findSlot(
            input,
            after,
            task,
            duration,
            addDays(input.today, 1),
            horizon,
            timestamp,
            id,
          );
          if (slot != null) {
            next = slot.copyWith(
              id: first && _blockActual(source, input.logs) == 0
                  ? source.id
                  : slot.id,
              createdAt: first && _blockActual(source, input.logs) == 0
                  ? source.createdAt
                  : timestamp,
            );
          }
        }
        if (next != null) {
          if (_snapshotKey([source]) != _snapshotKey([next])) {
            next = next.copyWith(updatedAt: timestamp);
          }
          after.add(next);
        } else {
          missed += duration;
        }
        pending -= duration;
        offset += duration;
        first = false;
      }
    }
    if (missed > 0) {
      conflicts.add(
        Conflict(
          taskId: task.id,
          title: task.title,
          minutes: missed,
          reason: task.deadline.compareTo(input.today) <= 0
              ? '截止日期已到，未来没有可安排的日期'
              : '截止日期前或未来14天内容量不足；未突破每日容量',
        ),
      );
    }
  }
  return _makePreview(input, after, conflicts, timestamp, id);
}

PlannerData confirmReplan(PlannerData data, ReplanPreview preview) {
  if (preview.userId != data.profile.userId) throw StateError('不能确认其他用户的计划');
  if (data.replanRuns.any((run) => run.id == preview.id)) {
    throw StateError('这次调整已经确认');
  }
  if (_snapshotKey(data.blocks) != _snapshotKey(preview.before)) {
    throw StateError('计划已发生变化，请重新生成预览');
  }
  final before = data.tasks
      .map((task) => TaskStatusSnapshot(id: task.id, status: task.status))
      .toList();
  final tasks = data.tasks.map((task) {
    final complete = task.status == TaskStatus.completed;
    final status = task.status == TaskStatus.archived
        ? TaskStatus.archived
        : complete
        ? TaskStatus.completed
        : preview.conflicts.any((conflict) => conflict.taskId == task.id)
        ? TaskStatus.conflict
        : preview.postponed.contains(task.id)
        ? TaskStatus.delayed
        : task.status;
    final touched =
        preview.changes.any(
          (change) => (change.after ?? change.before)?.taskId == task.id,
        ) ||
        preview.conflicts.any((conflict) => conflict.taskId == task.id);
    return task.copyWith(
      status: status,
      updatedAt: touched ? preview.createdAt : task.updatedAt,
    );
  }).toList();
  final run = ReplanRun(
    id: preview.id,
    userId: preview.userId,
    createdAt: preview.createdAt,
    before: preview.before.map(_copyBlock).toList(),
    after: preview.after.map(_copyBlock).toList(),
    changes: preview.changes,
    postponed: preview.postponed,
    advanced: preview.advanced,
    conflicts: preview.conflicts,
    dailyChanges: preview.dailyChanges,
    status: ReplanStatus.confirmed,
    taskStatusBefore: before,
    taskStatusAfter: tasks
        .map((task) => TaskStatusSnapshot(id: task.id, status: task.status))
        .toList(),
  );
  return data.copyWith(
    blocks: preview.after.map(_copyBlock).toList(),
    tasks: tasks,
    replanRuns: [...data.replanRuns, run],
  );
}

PlannerData undoLastReplan(PlannerData data) {
  final index = data.replanRuns.lastIndexWhere(
    (run) => run.status == ReplanStatus.confirmed,
  );
  if (index < 0) throw StateError('没有可撤销的调整');
  final run = data.replanRuns[index];
  if (_snapshotKey(data.blocks) != _snapshotKey(run.after)) {
    throw StateError('调整后计划已被修改，请先恢复该版本再撤销');
  }
  final tasks = data.tasks.map((task) {
    final previous = run.taskStatusBefore
        ?.where((item) => item.id == task.id)
        .firstOrNull;
    return previous == null ? task : task.copyWith(status: previous.status);
  }).toList();
  final runs = [...data.replanRuns];
  runs[index] = run.copyWith(status: ReplanStatus.undone);
  return data.copyWith(
    blocks: run.before.map(_copyBlock).toList(),
    tasks: tasks,
    replanRuns: runs,
  );
}

PlannerData recordTaskDayMinutes(
  PlannerData data,
  String taskId,
  String date,
  int minutes, {
  SchedulerRuntime runtime = const SchedulerRuntime(),
}) {
  if (minutes < 0 || minutes > 1440) {
    throw const FormatException('实际用时需要是 0–1440 之间的整数分钟');
  }
  final task = data.tasks.where((item) => item.id == taskId).firstOrNull;
  if (task == null) throw StateError('请先创建并选择事项');
  final stamp = runtime.timestamp();
  // 只重建“当天合计分钟数”这一条 manual 语义的记录，其余真实记录必须保留：
  // - 计时器写入的日志（任何 relation）是真实时间事实，保留，避免下次 checkpoint
  //   重新补写时与新记录重复计数；
  // - 已有事项加学/临时学习关系（extra/ad_hoc）保留，不能被“记录今天时长”删除；
  // - 旧数据缺 relation 且来源是 manual 的日志，视为可重建的当天合计记录
  //   （与历史行为一致，旧 golden 不变）。
  final logs = <TimeLog>[];
  for (final log in data.logs) {
    final sameTaskDay = log.taskId == taskId && log.date == date;
    if (!sameTaskDay) {
      logs.add(log);
      continue;
    }
    final timerOwned = log.source == LogSource.timer;
    final extraRelation =
        log.relation == TimeLogRelation.extra ||
        log.relation == TimeLogRelation.adHoc;
    if (timerOwned || extraRelation) logs.add(log);
  }
  final blocks = data.blocks
      .where((block) => block.taskId == taskId && block.date == date)
      .toList();
  var remaining = minutes;
  for (final block in blocks) {
    final amount = math.min(remaining, block.durationMinutes);
    if (amount > 0) {
      logs.add(
        TimeLog(
          id: runtime.ids(),
          userId: task.userId,
          taskId: taskId,
          blockId: block.id,
          date: date,
          minutes: amount,
          startedAt: stamp,
          endedAt: stamp,
          source: LogSource.manual,
        ),
      );
    }
    remaining -= amount;
  }
  if (remaining > 0) {
    logs.add(
      TimeLog(
        id: runtime.ids(),
        userId: task.userId,
        taskId: taskId,
        blockId: blocks.lastOrNull?.id,
        date: date,
        minutes: remaining,
        startedAt: stamp,
        endedAt: stamp,
        source: LogSource.manual,
      ),
    );
  }
  bool scheduledCoverage(TimeLog log) =>
      log.relation == TimeLogRelation.scheduled ||
      log.relation == TimeLogRelation.legacyUnknown;
  final total = logs
      .where((log) => log.taskId == taskId)
      .fold<int>(0, (sum, log) => sum + log.minutes);
  return data.copyWith(
    logs: logs,
    tasks: data.tasks
        .map(
          (item) => item.id == taskId
              ? item.copyWith(
                  completedMinutes: math.min(item.estimatedMinutes, total),
                  status:
                      item.status == TaskStatus.archived ||
                          item.status == TaskStatus.completed
                      ? item.status
                      : total > 0
                      ? TaskStatus.inProgress
                      : TaskStatus.notStarted,
                  updatedAt: stamp,
                )
              : item,
        )
        .toList(),
    blocks: data.blocks
        .map(
          (block) => block.taskId == taskId && block.date == date
              ? block.copyWith(
                  // 原定达成只由 scheduled/legacy 推断覆盖，加学记录不冒充原定执行。
                  actualMinutes: logs
                      .where(
                        (log) =>
                            log.blockId == block.id && scheduledCoverage(log),
                      )
                      .fold<int>(0, (sum, log) => sum + log.minutes),
                  updatedAt: stamp,
                )
              : block,
        )
        .toList(),
  );
}

List<TimeLog> mergeTaskDayLogs(
  List<TimeLog> base,
  List<TimeLog> local,
  List<TimeLog> remote,
) {
  String key(TimeLog log) => '${log.date}:${log.taskId}';
  String signature(List<TimeLog> logs) => jsonEncode(
    logs.map((log) => log.toJson()).toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String)),
  );
  var merged = [...remote];
  final keys = {...base.map(key), ...local.map(key)};
  for (final groupKey in keys) {
    final before = base.where((log) => key(log) == groupKey).toList();
    final after = local.where((log) => key(log) == groupKey).toList();
    if (signature(before) == signature(after)) continue;
    merged = [...merged.where((log) => key(log) != groupKey), ...after];
  }
  return merged;
}
