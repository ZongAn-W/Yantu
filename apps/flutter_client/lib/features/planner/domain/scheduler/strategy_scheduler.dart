import 'dart:math' as math;

import '../../../../shared/models/planner_models.dart';
import '../capacity.dart' as capacity_core;
import 'planner_scheduler.dart' as base;

/// 灵活容量排程中一个自然周的持续练习计划。
class _FlexibleWeekPlan {
  _FlexibleWeekPlan({
    required this.task,
    required this.weekStart,
    required this.sessions,
    required this.oldSessions,
    required this.dates,
  });

  final Task task;
  final String weekStart;
  final int sessions;
  final int oldSessions;
  final List<String> dates;
  final List<_FlexibleSession> sessions_ = [];
  int placedNew = 0;

  List<_FlexibleSession> get pending =>
      sessions_.where((session) => !session.placed).toList();
}

class _FlexibleSession {
  _FlexibleSession({
    required this.index,
    required this.instance,
    required this.needed,
    required this.preferred,
    required this.preferredIndex,
  });

  final int index;
  final String instance;
  final int needed;
  final String preferred;
  final int preferredIndex;
  bool placed = false;
}

JsonMap? activityOf(Task task) {
  final value = task.planning?['activity'];
  return value is Map ? JsonMap.from(value) : null;
}

List<JsonMap> dependenciesOf(Task task) =>
    (task.planning?['dependencies'] as List? ?? const [])
        .whereType<Map>()
        .map(JsonMap.from)
        .toList();

/// A planned ordering is a forecast; starting dependent content still needs confirmation.
String? strategyExecutionError(PlannerData data, Task task, String date) {
  final activity = activityOf(task);
  if (activity?['state'] == 'paused' || activity?['state'] == 'ended') {
    return '该持续活动已暂停或结束，请先确认学习策略';
  }
  if ((activity?['starts_on'] != null &&
          date.compareTo(activity!['starts_on'] as String) < 0) ||
      (activity?['ends_on'] != null &&
          date.compareTo(activity!['ends_on'] as String) > 0)) {
    return '今天不在该活动的有效日期内，请先调整计划';
  }
  for (final dependency in dependenciesOf(task)) {
    final prior = data.tasks
        .where((item) => item.id == dependency['task_id'])
        .firstOrNull;
    if (prior == null ||
        prior.userId != task.userId ||
        prior.status == TaskStatus.archived) {
      return '前置内容${prior == null ? '' : '「${prior.title}」'}尚未确认完成，请先核对内容进度';
    }
    // Execution never accepts a forecast: only real content confirmation unlocks timing.
    if (!base.dependencySatisfied(
      prior: prior,
      dependency: dependency,
      priorBlocks: const [],
      date: date,
      remaining: 0,
      allowForecast: false,
    )) {
      return '前置内容「${prior.title}」尚未确认完成，请先核对内容进度';
    }
  }
  return null;
}

class StrategyIssue {
  const StrategyIssue(
    this.code,
    this.taskId,
    this.expected,
    this.actual,
    this.message, [
    this.date,
  ]);
  final String code, taskId, message;
  final String? date;
  final int expected, actual;
  JsonMap toJson() => {
    'code': code,
    'task_id': taskId,
    'expected': expected,
    'actual': actual,
    'message': message,
    if (date != null) 'date': date,
  };
}

class StrategyResult {
  const StrategyResult(
    this.blocks,
    this.added,
    this.scheduledMinutes,
    this.unscheduledMinutes,
    this.issues,
  );
  final List<ScheduleBlock> blocks;
  final int added, scheduledMinutes, unscheduledMinutes;
  final List<StrategyIssue> issues;
}

String _maxDate(Iterable<String> dates) =>
    dates.reduce((a, b) => a.compareTo(b) > 0 ? a : b);
String _minDate(Iterable<String> dates) =>
    dates.reduce((a, b) => a.compareTo(b) < 0 ? a : b);
int _days(String start, String end) =>
    DateTime.parse(
      '${end}T00:00:00Z',
    ).difference(DateTime.parse('${start}T00:00:00Z')).inDays +
    1;
String _monday(String date) =>
    base.addDays(date, -((base.weekdayIndex(date) + 6) % 7));

/// Monday weeks and ceil(frequency * active calendar days / 7) for partial weeks.
List<JsonMap> recurringDemand(Task task, String from, String to) {
  final activity = activityOf(task);
  if (activity?['kind'] != 'recurring' ||
      activity?['state'] == 'paused' ||
      activity?['state'] == 'ended') {
    return [];
  }
  final start = _maxDate([
    from,
    activity?['starts_on'] as String? ?? from,
    task.earliestDate ?? from,
  ]);
  final end = _minDate([
    to,
    activity?['ends_on'] as String? ?? to,
    task.deadline,
  ]);
  final result = <JsonMap>[];
  for (
    var week = _monday(start);
    week.compareTo(end) <= 0;
    week = base.addDays(week, 7)
  ) {
    final first = _maxDate([start, week]),
        last = _minDate([end, base.addDays(week, 6)]);
    if (last.compareTo(first) < 0) continue;
    final sessions =
        ((activity?['sessions_per_week'] as num? ?? 1) * _days(first, last) / 7)
            .ceil();
    result.add({
      'week': week,
      'start': first,
      'end': last,
      'sessions': sessions,
      'minutes': sessions * (activity?['session_minutes'] as int? ?? 30),
    });
  }
  return result;
}

/// The same pure strategy used by API scheduling. Supplied records are immutable.
StrategyResult scheduleStrategy(
  PlannerData data,
  String from,
  String to, {
  base.SchedulerRuntime runtime = const base.SchedulerRuntime(),
}) {
  if (from.compareTo(to) > 0) throw StateError('规划结束日期不能早于开始日期');
  from = _maxDate([
    from,
    data.profile.planStartDate.isEmpty ? from : data.profile.planStartDate,
  ]);
  to = _minDate([
    to,
    data.profile.planEndDate.isEmpty ? to : data.profile.planEndDate,
  ]);
  final blocks = [...data.blocks], issues = <StrategyIssue>[];
  final stamp = runtime.timestamp(),
      byId = {for (final task in data.tasks) task.id: task};
  var added = 0, scheduled = 0, unscheduled = 0;
  int remaining(Task task) =>
      base.forecastRemainingMinutes(task, data.logs, blocks, from: from);
  int room(Task task, String date) {
    final day = blocks.where((block) => block.date == date).toList();
    final orphanLogs = data.logs.where(
      (log) =>
          log.date == date &&
          (log.blockId == null || !day.any((block) => block.id == log.blockId)),
    );
    // The same occupancy accounting is used by manual placement: overlapping timed
    // records count once and are clipped to the study window.
    final dailyOccupied = base.occupiedDayMinutes(
      profile: data.profile,
      fixedEvents: data.fixedEvents,
      dayBlocks: day,
      logs: data.logs,
      date: date,
    );
    final daily =
        base.dailyStudyBudget(data.profile, date) -
        dailyOccupied -
        orphanLogs.fold<int>(0, (sum, log) => sum + math.max(0, log.minutes));
    return math.max(0, daily);
  }

  bool add(Task task, String date, int duration, [String? instance]) {
    if (room(task, date) < duration) return false;
    var start = 0;
    if (data.profile.planningMode == PlanningMode.timed) {
      final intervals = <(int, int)>[
        for (final block in blocks.where((block) => block.date == date))
          base.blockOccupiedInterval(block, data.logs),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      final quantum = capacity_core.schedulingQuantum(data.profile);
      start = (data.profile.studyStartMinute / quantum).ceil() * quantum;
      for (final interval in intervals) {
        if (start + duration <= interval.$1) break;
        if (interval.$2 > start) {
          start = (interval.$2 / quantum).ceil() * quantum;
        }
      }
      if (start + duration > data.profile.studyEndMinute) return false;
    }
    blocks.add(
      ScheduleBlock(
        id: runtime.ids(),
        userId: data.profile.userId,
        taskId: task.id,
        date: date,
        startMinute: start,
        durationMinutes: duration,
        actualMinutes: 0,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: stamp,
        updatedAt: stamp,
        activityInstanceId: instance,
      ),
    );
    added++;
    scheduled += duration;
    return true;
  }

  final visiting = <String>{}, visited = <String>{}, invalid = <String>{};
  final ordered = <Task>[];
  void visit(Task task) {
    if (visited.contains(task.id)) return;
    if (visiting.contains(task.id)) {
      invalid.add(task.id);
      return;
    }
    visiting.add(task.id);
    for (final dependency in dependenciesOf(task)) {
      final prior = byId[dependency['task_id']];
      if (prior == null ||
          prior.userId != task.userId ||
          prior.status == TaskStatus.archived) {
        invalid.add(task.id);
      } else {
        visit(prior);
        if (invalid.contains(prior.id)) invalid.add(task.id);
      }
    }
    visiting.remove(task.id);
    visited.add(task.id);
    ordered.add(task);
  }

  final sorted = [...data.tasks]
    ..sort((a, b) {
      final deadline = a.deadline.compareTo(b.deadline);
      if (deadline != 0) return deadline;
      final priority = b.priority.compareTo(a.priority);
      if (priority != 0) return priority;
      final title = a.title.compareTo(b.title);
      return title != 0 ? title : a.id.compareTo(b.id);
    });
  for (final task in sorted) {
    visit(task);
  }
  bool unlocked(Task task, String date) {
    if (invalid.contains(task.id)) return false;
    return dependenciesOf(task).every((dependency) {
      final prior = byId[dependency['task_id']]!;
      return base.dependencySatisfied(
        prior: prior,
        dependency: dependency,
        priorBlocks: blocks.where((block) => block.taskId == prior.id).toList(),
        date: date,
        remaining: remaining(prior),
      );
    });
  }

  final active = ordered
      .where(
        (task) =>
            task.userId == data.profile.userId &&
            task.status != TaskStatus.completed &&
            task.status != TaskStatus.archived &&
            !base.contentConfirmed(task) &&
            activityOf(task)?['state'] != 'paused' &&
            activityOf(task)?['state'] != 'ended',
      )
      .toList();
  void fillFinite(Task task, String date) {
    if (date.compareTo(
              _maxDate([
                task.earliestDate ?? from,
                activityOf(task)?['starts_on'] as String? ?? from,
              ]),
            ) <
            0 ||
        date.compareTo(
              _minDate([
                task.deadline,
                activityOf(task)?['ends_on'] as String? ?? to,
              ]),
            ) >
            0 ||
        !unlocked(task, date)) {
      return;
    }
    final quantum = capacity_core.schedulingQuantum(data.profile);
    final lightweight = capacity_core.supportsLightweightScheduling(
      data.profile,
    );
    while (remaining(task) > 0 && room(task, date) > 0) {
      final amount = math.min(
        quantum,
        math.min(remaining(task), room(task, date)),
      );
      if (lightweight) {
        // 净容量允许最终分块短于常规粒度，但不少于 10 分钟。
        if (amount < capacity_core.lightweightMinimumMinutes) break;
      } else if (amount < quantum && remaining(task) > amount) {
        break;
      }
      if (!add(task, date, amount)) break;
    }
  }

  final prepared = <String>{};
  void preparePredecessors(Task task) {
    if (prepared.contains(task.id) || invalid.contains(task.id)) return;
    prepared.add(task.id);
    for (final dependency in dependenciesOf(task)) {
      if (dependency['mode'] != 'planned') continue;
      final prior = byId[dependency['task_id']]!;
      preparePredecessors(prior);
      if (active.contains(prior) && activityOf(prior)?['kind'] != 'recurring') {
        for (
          var date = from;
          date.compareTo(to) <= 0;
          date = base.addDays(date, 1)
        ) {
          fillFinite(prior, date);
        }
      }
    }
  }

  final finite = active
      .where((task) => activityOf(task)?['kind'] != 'recurring')
      .toList();
  final flexibleCapacity = capacity_core.usesFlexibleCapacity(data.profile);

  /// 新容量语义：按依赖/优先级顺序把“有限工作”和“持续练习会话”放进同一个
  /// 每日循环竞争容量，不再预先为低优先级持续练习保留整周容量。
  ///
  /// 未能在首选日期安排的练习会话，会在同一自然周的其余日期按“离首选最近优先”
  /// 重试一次；仍无法安排时如实报告缺口。旧 gross 数据不进入该分支。
  void scheduleFlexible() {
    final recurringTasks = active
        .where((task) => activityOf(task)?['kind'] == 'recurring')
        .toList();
    final plans = <_FlexibleWeekPlan>[];
    for (final task in recurringTasks) {
      preparePredecessors(task);
      final size = activityOf(task)?['session_minutes'] as int? ?? 30;
      for (final week in recurringDemand(
        task,
        data.profile.planStartDate.isEmpty ? from : data.profile.planStartDate,
        data.profile.planEndDate.isEmpty ? to : data.profile.planEndDate,
      )) {
        final first = week['start'] as String, last = week['end'] as String;
        if (last.compareTo(from) < 0 || first.compareTo(to) > 0) continue;
        final weekStart = week['week'] as String,
            sessions = week['sessions'] as int;
        final orphanWork = data.logs
            .where(
              (log) =>
                  log.taskId == task.id &&
                  log.date.compareTo(first) >= 0 &&
                  log.date.compareTo(last) <= 0 &&
                  !blocks.any(
                    (block) =>
                        block.taskId == task.id && block.date == log.date,
                  ),
            )
            .fold<int>(0, (sum, log) => sum + math.max(0, log.minutes));
        final oldSessions =
            blocks
                .where(
                  (block) =>
                      block.taskId == task.id &&
                      block.date.compareTo(first) >= 0 &&
                      block.date.compareTo(last) <= 0 &&
                      block.activityInstanceId == null,
                )
                .map((block) => block.date)
                .toSet()
                .length +
            orphanWork ~/ size;
        final credit = orphanWork % size;
        final dates = List.generate(
          _days(first, last),
          (i) => base.addDays(first, i),
        );
        final plan = _FlexibleWeekPlan(
          task: task,
          weekStart: weekStart,
          sessions: sessions,
          oldSessions: oldSessions,
          dates: dates,
        );
        for (var i = 0; i < sessions; i++) {
          final instance = '${task.id}:$weekStart:$i';
          if (i < oldSessions ||
              blocks.any((block) => block.activityInstanceId == instance)) {
            continue;
          }
          final preferredIndex = ((i + .5) * dates.length / sessions).floor();
          final preferred = dates[preferredIndex];
          if (preferred.compareTo(to) > 0) continue;
          plan.sessions_.add(
            _FlexibleSession(
              index: i,
              instance: instance,
              needed: size - (i == oldSessions ? credit : 0),
              preferred: preferred,
              preferredIndex: preferredIndex,
            ),
          );
        }
        plans.add(plan);
      }
    }

    bool place(_FlexibleWeekPlan plan, _FlexibleSession session, String date) {
      if (session.placed) return false;
      if (date.compareTo(from) < 0 || date.compareTo(to) > 0) return false;
      if (blocks.any(
        (block) => block.taskId == plan.task.id && block.date == date,
      )) {
        return false;
      }
      if (!unlocked(plan.task, date)) return false;
      if (!add(plan.task, date, session.needed, session.instance)) return false;
      session.placed = true;
      plan.placedNew++;
      return true;
    }

    final activeOrdered = ordered.where(active.contains).toList();
    for (
      var date = from;
      date.compareTo(to) <= 0;
      date = base.addDays(date, 1)
    ) {
      for (final task in activeOrdered) {
        if (activityOf(task)?['kind'] == 'recurring') {
          for (final plan in plans.where((plan) => plan.task.id == task.id)) {
            for (final session in plan.sessions_) {
              if (session.preferred == date) place(plan, session, date);
            }
          }
        } else {
          fillFinite(task, date);
        }
      }
    }
    for (final plan in plans) {
      final unplaced = plan.pending;
      if (unplaced.isEmpty) continue;
      for (final session in unplaced) {
        final candidates = [...plan.dates]
          ..sort((a, b) {
            final left = (plan.dates.indexOf(a) - session.preferredIndex).abs();
            final right = (plan.dates.indexOf(b) - session.preferredIndex)
                .abs();
            return left != right ? left.compareTo(right) : a.compareTo(b);
          });
        for (final date in candidates) {
          if (place(plan, session, date)) break;
        }
      }
      final stillUnplaced = plan.pending;
      if (stillUnplaced.isEmpty) continue;
      unscheduled += stillUnplaced.fold<int>(
        0,
        (sum, session) => sum + session.needed,
      );
      issues.add(
        StrategyIssue(
          invalid.contains(plan.task.id)
              ? 'DEPENDENCY_INVALID'
              : 'RECURRENCE_SHORTFALL',
          plan.task.id,
          plan.sessions,
          plan.oldSessions + plan.placedNew,
          '每周练习尚缺一次（${activityOf(plan.task)?['session_minutes'] as int? ?? 30}分钟）；'
          '请核对可用时间、有效日期和前置条件',
          plan.weekStart,
        ),
      );
    }
  }

  if (flexibleCapacity) {
    scheduleFlexible();
  } else {
    for (final task in active.where(
      (task) => activityOf(task)?['kind'] == 'recurring',
    )) {
      preparePredecessors(task);
      final size = activityOf(task)?['session_minutes'] as int? ?? 30;
      for (final week in recurringDemand(
        task,
        data.profile.planStartDate.isEmpty ? from : data.profile.planStartDate,
        data.profile.planEndDate.isEmpty ? to : data.profile.planEndDate,
      )) {
        final first = week['start'] as String, last = week['end'] as String;
        if (last.compareTo(from) < 0 || first.compareTo(to) > 0) continue;
        final weekStart = week['week'] as String,
            sessions = week['sessions'] as int;
        final orphanWork = data.logs
            .where(
              (log) =>
                  log.taskId == task.id &&
                  log.date.compareTo(first) >= 0 &&
                  log.date.compareTo(last) <= 0 &&
                  !blocks.any(
                    (block) =>
                        block.taskId == task.id && block.date == log.date,
                  ),
            )
            .fold<int>(0, (sum, log) => sum + math.max(0, log.minutes));
        final oldSessions =
            blocks
                .where(
                  (block) =>
                      block.taskId == task.id &&
                      block.date.compareTo(first) >= 0 &&
                      block.date.compareTo(last) <= 0 &&
                      block.activityInstanceId == null,
                )
                .map((block) => block.date)
                .toSet()
                .length +
            orphanWork ~/ size;
        final credit = orphanWork % size;
        final dates = List.generate(
          _days(first, last),
          (i) => base.addDays(first, i),
        );
        for (var i = 0; i < sessions; i++) {
          final instance = '${task.id}:$weekStart:$i';
          if (i < oldSessions ||
              blocks.any((block) => block.activityInstanceId == instance)) {
            continue;
          }
          final preferred = ((i + .5) * dates.length / sessions).floor();
          if (dates[preferred].compareTo(to) > 0) continue;
          final needed = size - (i == oldSessions ? credit : 0);
          final candidates =
              dates
                  .where(
                    (date) =>
                        date.compareTo(from) >= 0 && date.compareTo(to) <= 0,
                  )
                  .toList()
                ..sort((a, b) {
                  final distance = (dates.indexOf(a) - preferred)
                      .abs()
                      .compareTo((dates.indexOf(b) - preferred).abs());
                  return distance != 0 ? distance : a.compareTo(b);
                });
          final placed = candidates.any(
            (date) =>
                !blocks.any(
                  (block) => block.taskId == task.id && block.date == date,
                ) &&
                unlocked(task, date) &&
                add(task, date, needed, instance),
          );
          if (!placed) {
            unscheduled += needed;
            issues.add(
              StrategyIssue(
                invalid.contains(task.id)
                    ? 'DEPENDENCY_INVALID'
                    : 'RECURRENCE_SHORTFALL',
                task.id,
                sessions,
                oldSessions +
                    blocks
                        .where(
                          (block) =>
                              block.taskId == task.id &&
                              (block.activityInstanceId?.startsWith(
                                    '${task.id}:$weekStart:',
                                  ) ??
                                  false),
                        )
                        .length,
                '每周练习尚缺一次（$size分钟）；请核对可用时间、有效日期和前置条件',
                weekStart,
              ),
            );
          }
        }
      }
    }
    for (
      var date = from;
      date.compareTo(to) <= 0;
      date = base.addDays(date, 1)
    ) {
      for (final task in finite) {
        fillFinite(task, date);
      }
    }
  }
  for (final task in finite) {
    final left = remaining(task);
    unscheduled += left;
    if (left > 0) {
      issues.add(
        StrategyIssue(
          invalid.contains(task.id)
              ? 'DEPENDENCY_INVALID'
              : dependenciesOf(task).any(
                  (d) =>
                      d['mode'] == 'confirmed' &&
                      byId[d['task_id']]?.status != TaskStatus.completed,
                )
              ? 'DEPENDENCY_UNCONFIRMED'
              : 'WORK_UNSCHEDULED',
          task.id,
          task.estimatedMinutes,
          task.estimatedMinutes - left,
          '还有$left分钟未安排；请核对容量、事项日期和前置内容进度',
        ),
      );
    }
  }
  return StrategyResult(blocks, added, scheduled, unscheduled, issues);
}
