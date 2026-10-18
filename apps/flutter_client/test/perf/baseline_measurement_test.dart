import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:sjtu_study_planner_client/core/storage/database_factory_io.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';

import 'perf_samples.dart';
import 'perf_support.dart';

/// 问题七：可重复性能基线（同步/本机存储部分）。
///
/// - 只用合成数据，不连真实服务端。
/// - 结构性计数（请求数、字节数、物理备份次数）为主要验收依据；
///   耗时只记录单次观测并注明环境，不用于跨机器比较。
/// - 通过 `PERF_LABEL` 环境变量区分阶段，产物写入
///   `.dsh-verify/optfix/perf/flutter-<label>.json`；
///   默认 `current`，避免误覆盖冻结的 `before`/`after` 产物。
void main() {
  final label = Platform.environment['PERF_LABEL'] ?? 'current';
  final artifact = <String, Object?>{
    ...perfReportHeader(label),
    'samples': <String, Object?>{},
    'scenarios': <String, Object?>{},
  };

  Map<String, Object?> samples() =>
      artifact['samples'] as Map<String, Object?>;
  Map<String, Object?> scenarios() =>
      artifact['scenarios'] as Map<String, Object?>;

  tearDownAll(() {
    artifact['finishedAt'] = DateTime.now().toUtc().toIso8601String();
    writePerfArtifact('flutter-$label.json', artifact);
  });

  test('records sample sizes and physical full-database export cost', () async {
    final normal = normalPerfPlan();
    final large = largePerfPlan();
    final normalSample = describeSample('normal', normal);
    final largeSample = describeSample('large', large);
    samples()['normal'] = normalSample;
    samples()['large'] = largeSample;
    expect(largeSample['blocks'], perfBlockCount);
    expect(largeSample['logs'], perfLogCount);

    final export = <String, Object?>{};
    for (final entry in [('normal', normal), ('large', large)]) {
      final directory = await Directory.systemTemp.createTemp(
        'planner-perf-export-',
      );
      final path = '${directory.path}/planner.db';
      final db = await openPlannerDatabase(path);
      await StoreRef<String, Object?>.main().record('planner-sample').put(db, {
        'version': 1,
        'data': entry.$2.toJson(),
        'metadata': <String, Object?>{},
      });
      // 预热一次，避免把文件系统首次写入抖动计入中位数。
      await backupPlannerDatabase(db);
      final durations = <int>[];
      for (var run = 0; run < 5; run++) {
        final watch = Stopwatch()..start();
        await backupPlannerDatabase(db);
        watch.stop();
        durations.add(watch.elapsedMicroseconds);
      }
      await db.close();
      export[entry.$1] = {
        'runs': durations.length,
        'medianMs': medianMilliseconds(durations),
        'databaseBytes': await fileBytes(path),
        'recoveryBytes': await fileBytes('$path.recovery.json'),
      };
    }
    artifact['physicalBackupExport'] = export;
  });

  test('records local write counts and physical backup frequency', () async {
    for (final entry in [
      ('normal', normalPerfPlan()),
      ('large', largePerfPlan()),
    ]) {
      final name = entry.$1;
      final plan = entry.$2;
      final harness = await PerfHarness.create(remote: plan);
      harness.resetCounters();
      final metadata = StorageMetadata(
        revision: harness.server.revision,
        base: plan,
        updatedAt: DateTime.utc(2026, 10, 16),
      );
      final watch = Stopwatch()..start();
      for (var index = 0; index < 60; index++) {
        await harness.storage.save(
          harness.key,
          plan.copyWith(
            profile: plan.profile.copyWith(targetSchool: 'perf-$index'),
          ),
          metadata.copyWith(updatedAt: DateTime.utc(2026, 10, 16, 0, index)),
        );
      }
      watch.stop();
      final sizes = await harness.storageSizes();
      scenarios()['localWrite-$name'] = {
        'saves': 60,
        ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
        ...sizes,
        'recoveryBytesWrittenTotal': (sizes['recoveryBytes'] as int) * 60,
      };
      await harness.dispose();
    }
  });

  test(
    'records sync counts: cold start, idle polling, upload and offline recovery',
    () async {
      for (final entry in [
        ('normal', normalPerfPlan()),
        ('large', largePerfPlan()),
      ]) {
        final name = entry.$1;
        final plan = entry.$2;
        final documentBytes = jsonBytes(plan.toJson());

        // 1) 冷启动：本机没有数据，首个同步把云端完整文档写入本机。
        var harness = await PerfHarness.create(
          remote: plan,
          seedLocal: false,
        );
        var watch = Stopwatch()..start();
        await harness.coordinator.initialize();
        watch.stop();
        expect(harness.coordinator.status, SyncStatus.connected);
        scenarios()['syncColdStart-$name'] = {
          'documentBytes': documentBytes,
          ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
        };
        await harness.dispose();

        // 2) 空闲轮询：本机与云端已一致，周期同步仍完整拉取文档。
        harness = await PerfHarness.create(remote: plan);
        await harness.coordinator.initialize();
        await settle();
        harness.resetCounters();
        watch = Stopwatch()..start();
        for (var poll = 0; poll < 4; poll++) {
          await harness.coordinator.sync();
        }
        watch.stop();
        expect(harness.coordinator.pending, isFalse);
        scenarios()['syncIdlePoll-$name'] = {
          'polls': 4,
          'documentBytesPerResponse': documentBytes,
          'serverMode': 'legacy-full-document',
          ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
        };
        await harness.dispose();

        // 2b) 空闲轮询（支持 unchanged 快速路径的服务端）：响应只剩 revision 标记。
        harness = await PerfHarness.create(
          remote: plan,
          supportsUnchanged: true,
        );
        await harness.coordinator.initialize();
        await settle();
        harness.resetCounters();
        watch = Stopwatch()..start();
        for (var poll = 0; poll < 4; poll++) {
          await harness.coordinator.sync();
        }
        watch.stop();
        expect(harness.coordinator.pending, isFalse);
        scenarios()['syncIdlePollFastPath-$name'] = {
          'polls': 4,
          'documentBytesPerResponse': documentBytes,
          'serverMode': 'unchanged-marker',
          ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
        };
        await harness.dispose();

        // 3) 一次本机编辑上传：pull 完整文档 + push(data/base 各一份完整文档)。
        harness = await PerfHarness.create(remote: plan);
        await harness.coordinator.initialize();
        await settle();
        harness.resetCounters();
        watch = Stopwatch()..start();
        await harness.coordinator.edit(
          (current) => current.copyWith(
            profile: current.profile.copyWith(targetSchool: '上传测量'),
          ),
        );
        // 测量时立即手动同步，避免 500ms 合并窗口影响单次上传的固定测量窗口。
        await harness.coordinator.sync();
        await waitUntilSyncIdle(harness.coordinator, label: 'upload-$name');
        watch.stop();
        expect(harness.coordinator.pending, isFalse);
        expect(harness.server.document!.profile.targetSchool, '上传测量');
        scenarios()['syncUploadOneEdit-$name'] = {
          'documentBytes': documentBytes,
          ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
        };
        await harness.dispose();

        // 4) 离线编辑后恢复同步：失败的 pull 不计响应字节，恢复后重新 pull+push。
        harness = await PerfHarness.create(remote: plan);
        await harness.coordinator.initialize();
        await settle();
        harness.resetCounters();
        harness.server.offline = true;
        await harness.coordinator.edit(
          (current) => current.copyWith(
            profile: current.profile.copyWith(targetProgram: '离线修改'),
          ),
        );
        // 立即手动同步以产生确定的离线失败（不受合并窗口影响）。
        await harness.coordinator.sync();
        expect(harness.coordinator.pending, isTrue);
        expect(harness.coordinator.status, SyncStatus.offline);
        harness.server.offline = false;
        watch = Stopwatch()..start();
        await harness.coordinator.sync();
        watch.stop();
        expect(harness.coordinator.status, SyncStatus.connected);
        expect(harness.coordinator.pending, isFalse);
        expect(harness.server.document!.profile.targetProgram, '离线修改');
        scenarios()['syncOfflineRecovery-$name'] = {
          'documentBytes': documentBytes,
          ...harness.counters(elapsedMilliseconds: watch.elapsedMilliseconds),
        };
        await harness.dispose();

        // 5) 连续编辑：旧行为等价（uploadDebounce=0，每次编辑立即上传）vs 合并上传。
        for (final mode in [
          ('syncBurstImmediate', Duration.zero),
          ('syncBurstCoalesced', const Duration(milliseconds: 500)),
        ]) {
          harness = await PerfHarness.create(
            remote: plan,
            supportsUnchanged: true,
            uploadDebounce: mode.$2,
            uploadMaxWait: const Duration(seconds: 1),
          );
          await harness.coordinator.initialize();
          await settle();
          harness.resetCounters();
          watch = Stopwatch()..start();
          for (var index = 0; index < 5; index++) {
            await harness.coordinator.edit(
              (current) => current.copyWith(
                profile: current.profile.copyWith(targetSchool: '连续-$index'),
              ),
            );
            if (mode.$2 <= Duration.zero) {
              // 立即上传模式：等本次上传完成，模拟两次编辑之间的用户停顿；
              // 合并模式下这段间隔仍在窗口内，编辑会被合并成一次上传。
              await harness.coordinator.sync();
            }
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          try {
            await harness.waitUntilUploaded(
              timeout: const Duration(seconds: 3),
            );
          } catch (error) {
            throw StateError('${mode.$1}-$name: $error');
          }
          watch.stop();
          expect(harness.server.document!.profile.targetSchool, '连续-4');
          scenarios()['${mode.$1}-$name'] = {
            'edits': 5,
            'documentBytes': documentBytes,
            ...harness.counters(
              elapsedMilliseconds: watch.elapsedMilliseconds,
            ),
          };
          await harness.dispose();
        }
      }
    },
  );
}
