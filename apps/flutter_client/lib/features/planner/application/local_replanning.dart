import 'dart:convert';

import '../../../shared/models/planner_models.dart';
import '../../../shared/models/task_lifecycle.dart';
import '../domain/scheduler/planner_scheduler.dart' as scheduler;

/// A local proposal is deliberately separate from server plan generation/settlement.
class LocalReplanProposal {
  const LocalReplanProposal._(this.preview, this._baseline);
  final ReplanPreview preview;
  final String _baseline;
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _stateKey(Object? value) => jsonEncode(_canonical(value));

/// Guard every scheduling input and optional block field; never discard timestamps
/// or reorder arrays. Keep history separately to avoid recursively nested snapshots.
JsonMap _undoState(PlannerData data) =>
    {...data.toJson()}..remove('replan_runs');

class LocalReplanning {
  const LocalReplanning({this.runtime = const scheduler.SchedulerRuntime()});
  final scheduler.SchedulerRuntime runtime;

  LocalReplanProposal preview(
    PlannerData data, {
    required String today,
    ReplanMode mode = ReplanMode.unfinished,
    int? excessMinutes,
  }) => LocalReplanProposal._(
    scheduler.generateReplanPreview(
      ReplanInput(
        tasks: data.tasks,
        blocks: data.blocks,
        logs: data.logs,
        fixedEvents: data.fixedEvents,
        profile: data.profile,
        today: today,
        mode: mode,
        excessMinutes: excessMinutes,
      ),
      runtime: runtime,
    ),
    _stateKey(data.toJson()),
  );

  PlannerData confirm(PlannerData data, LocalReplanProposal proposal) {
    if (_stateKey(data.toJson()) != proposal._baseline) {
      throw StateError('计划已发生变化，请重新生成预览');
    }
    // 撤销守卫必须按持久化后的时间口径数据计算，否则 coordinator 在落盘时
    // 派生 completed_at/status 会让守卫与当前数据永久不一致。
    final confirmed = normalizeTaskLifecycle(
      scheduler
          .confirmReplan(data, proposal.preview)
          .copyWith(
            planning: data.planning == null
                ? null
                : {...data.planning!, 'needs_review': true, 'quality': null},
          ),
    );
    final runs = [...confirmed.replanRuns];
    runs[runs.length - 1] = runs.last.copyWith(
      localUndoGuard: _undoState(confirmed),
    );
    return confirmed.copyWith(replanRuns: runs);
  }

  PlannerData undo(PlannerData data) {
    final run = data.replanRuns
        .where((run) => run.status == ReplanStatus.confirmed)
        .lastOrNull;
    if (run?.localUndoGuard != null &&
        _stateKey(_undoState(data)) != _stateKey(run!.localUndoGuard)) {
      throw StateError('调整后数据已被修改，请先恢复该版本再撤销');
    }
    return scheduler.undoLastReplan(data);
  }
}
