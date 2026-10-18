import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import 'perf_samples.dart';
import 'perf_support.dart';

/// 问题七：单次计时 checkpoint 的端到端测量。
///
/// 在真实 `StudyTimer` 上推进固定时钟 1 分钟并调用 `checkpoint()`，测量：
/// - 网络请求数 / 请求字节 / 响应字节（真实 HttpSyncApi + Dio + 假 HTTP 服务端）
/// - 本机数据库写入次数 / 物理全库备份次数
/// - 端到端耗时（含计时快照写入、计划落盘、同步上传）
///
/// 同时测量两种服务端模式：老服务端（完整文档）与任务七条件读取服务端
/// （pending 存在但 revision 未变时，GET 只返回 unchanged 标记，直接上传）。
///
/// 产物：`.dsh-verify/optfix/perf/flutter-timer-<label>.json`。
void main() {
  final label = Platform.environment['PERF_LABEL'] ?? 'current';
  final artifact = <String, Object?>{
    ...perfReportHeader(label),
    'notes':
        'checkpoint 前先启动计时并完成一次上传；测量窗口只包含 checkpoint 本身及其触发的同步/落盘；'
        '测量时显式立即同步以固定窗口，避免 500ms 合并窗口影响耗时口径。',
    'scenarios': <String, Object?>{},
  };

  Map<String, Object?> scenarios() =>
      artifact['scenarios'] as Map<String, Object?>;

  tearDownAll(() {
    artifact['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    writePerfArtifact('flutter-timer-$label.json', artifact);
  });

  Future<Map<String, Object?>> measureCheckpoint(
    String name,
    PlannerData plan, {
    required bool supportsUnchanged,
  }) async {
    final harness = await PerfHarness.create(
      remote: plan,
      supportsUnchanged: supportsUnchanged,
    );
    await harness.coordinator.initialize();
    await settle();

    var now = DateTime.utc(2026, 10, 16, 4); // 上海时间 2026-10-16 12:00
    var monotonic = Duration.zero;
    var sequence = 0;
    final timer = StudyTimer(
      coordinator: harness.coordinator,
      store: LocalStudyTimerStore(harness.database),
      now: () => now,
      monotonicNow: () => monotonic,
      nextId: () => 'perf-timer-${sequence++}',
      tickInterval: null,
    );
    await timer.initialize();
    final taskId = plan.tasks.single.id;
    const date = '2026-10-16';
    final totals = <String, Object?>{
      'documentBytes': jsonBytes(plan.toJson()),
      'supportsUnchanged': supportsUnchanged,
      'runs': <Object?>[],
      'requests': 0,
      'getRequests': 0,
      'putRequests': 0,
      'failedRequests': 0,
      'requestBytes': 0,
      'responseBytes': 0,
      'localWrites': 0,
      'physicalBackups': 0,
      'elapsedMs': 0,
    };

    // 启动计时本身的成本单独记录，不属于 checkpoint 测量窗口。
    // fixture 里当天可能已有日志（normal 样本 35 分钟），先记录基线，
    // 这样 ownedMinutes 只反映计时器新增的分钟数。
    final fixtureMinutes = timer.elapsedFor(taskId, date).inMinutes;
    harness.resetCounters();
    var watch = Stopwatch()..start();
    await timer.start(taskId, date);
    await waitUntilSyncIdle(harness.coordinator, label: 'timer-start-$name');
    watch.stop();
    totals['start'] = {
      ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
      'documentBytes': jsonBytes(plan.toJson()),
    };
    harness.resetCounters();

    for (var run = 1; run <= 2; run++) {
      now = now.add(const Duration(minutes: 1));
      monotonic = monotonic + const Duration(minutes: 1);
      watch = Stopwatch()..start();
      await timer.checkpoint();
      // 测量时立即手动同步，避免 500ms 合并窗口影响固定测量窗口；
      // 发出的请求/写入与窗口到期自动上传相同。
      await harness.coordinator.sync();
      await waitUntilSyncIdle(
        harness.coordinator,
        label: 'timer-checkpoint-$name-$run',
      );
      watch.stop();
      final counters = harness.counters(
        elapsedMilliseconds: watch.elapsedMilliseconds,
      );
      final runs = totals['runs'] as List<Object?>;
      runs.add({...counters, 'run': run});
      for (final key in [
        'requests',
        'getRequests',
        'putRequests',
        'failedRequests',
        'requestBytes',
        'responseBytes',
        'localWrites',
        'physicalBackups',
        'elapsedMs',
      ]) {
        totals[key] = (totals[key] as int) + (counters[key] as int);
      }
      harness.resetCounters();
    }

    expect(harness.coordinator.pending, isFalse);
    expect(harness.coordinator.status, SyncStatus.connected);
    final ownedMinutes =
        timer.elapsedFor(taskId, date).inMinutes - fixtureMinutes;
    expect(ownedMinutes, greaterThanOrEqualTo(2));
    expect(harness.server.document, isNotNull);
    totals['fixtureMinutes'] = fixtureMinutes;
    totals['ownedMinutes'] = ownedMinutes;
    totals['storageBytes'] = await harness.storageSizes();

    timer.dispose();
    await harness.dispose();
    return totals;
  }

  test('records one-minute timer checkpoint end-to-end cost', () async {
    for (final entry in [
      ('normal', normalPerfPlan()),
      ('large', largePerfPlan()),
    ]) {
      final name = entry.$1;
      final plan = entry.$2;
      scenarios()['timerCheckpoint-$name'] = await measureCheckpoint(
        name,
        plan,
        supportsUnchanged: false,
      );
      // 生产条件读取服务端：pending 但 revision 未变时 GET 只回 unchanged 标记。
      scenarios()['timerCheckpointFastPath-$name'] = await measureCheckpoint(
        name,
        plan,
        supportsUnchanged: true,
      );
    }
  });
}
