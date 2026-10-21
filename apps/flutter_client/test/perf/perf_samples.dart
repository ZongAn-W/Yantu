import 'dart:convert';

import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// 合成样本规模：历史计划固定 1,000 条日程块 + 1,000 条日志。
const int perfBlockCount = 1000;
const int perfLogCount = 1000;

/// 普通新计划：使用仓库现有 fixture（1 事项 / 1 日程块 / 1 日志）。
PlannerData normalPerfPlan() => plannerFixture();

/// 历史计划：同一事项在 1,000 个自然日各排一个 30 分钟块，并各有一条 20 分钟日志。
///
/// 所有数据均为合成数据，日期从 2024-01-01 起递增，不引用任何真实账号。
PlannerData largePerfPlan({
  int blocks = perfBlockCount,
  int logs = perfLogCount,
}) {
  final base = plannerFixture();
  final task = base.tasks.single;
  final owner = base.profile.userId;
  // 时间口径下 1,000 段 × 20 分钟会超过 fixture 的默认预算并自动完成事项，
  // 计时性能样本需要保持事项未完成，因此显式放大预算（不影响测量的数据规模）。
  final taskRow = task.copyWith(estimatedMinutes: 1000000);
  final firstDay = DateTime.utc(2024, 1, 1);
  final schedules = <ScheduleBlock>[];
  final timeLogs = <TimeLog>[];
  for (var index = 0; index < blocks; index++) {
    final date = dateOnlyOf(firstDay.add(Duration(days: index)));
    schedules.add(
      ScheduleBlock(
        id: 'perf-block-$index',
        userId: owner,
        taskId: task.id,
        date: date,
        startMinute: 480,
        durationMinutes: 30,
        actualMinutes: 20,
        isFixed: false,
        status: BlockStatus.planned,
        createdAt: '2024-01-01T00:00:00.000Z',
        updatedAt: '2024-01-01T00:00:00.000Z',
      ),
    );
  }
  for (var index = 0; index < logs; index++) {
    final date = dateOnlyOf(firstDay.add(Duration(days: index)));
    timeLogs.add(
      TimeLog(
        id: 'perf-log-$index',
        userId: owner,
        taskId: task.id,
        blockId: 'perf-block-$index',
        date: date,
        minutes: 20,
        startedAt: '${date}T04:00:00.000Z',
        endedAt: '${date}T04:20:00.000Z',
        source: LogSource.timer,
      ),
    );
  }
  return base.copyWith(tasks: [taskRow], blocks: schedules, logs: timeLogs);
}

/// JSON 线上字节数（UTF-8），用于“响应字节数/请求字节数”口径。
int jsonBytes(Object? value) => utf8.encode(jsonEncode(value)).length;

Map<String, Object?> describeSample(String name, PlannerData data) => {
  'name': name,
  'tags': data.tags.length,
  'tasks': data.tasks.length,
  'blocks': data.blocks.length,
  'logs': data.logs.length,
  'fixedEvents': data.fixedEvents.length,
  'replanRuns': data.replanRuns.length,
  'documentBytes': jsonBytes(data.toJson()),
};
