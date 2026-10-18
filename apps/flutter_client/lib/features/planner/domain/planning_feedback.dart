import '../../../shared/models/planner_models.dart';

class PaceCalibration {
  const PaceCalibration({
    required this.samples,
    required this.minutes,
    this.unit,
    this.expectedMinutesPerUnit,
    this.observedMinutesPerUnit,
  });
  final int samples;
  final int minutes;
  final String? unit;
  final double? expectedMinutesPerUnit;
  final double? observedMinutesPerUnit;

  bool get sufficient => samples >= 3 && observedMinutesPerUnit != null;
  bool get deviates =>
      sufficient &&
      expectedMinutesPerUnit != null &&
      (observedMinutesPerUnit! > expectedMinutesPerUnit! * 1.35 ||
          observedMinutesPerUnit! < expectedMinutesPerUnit! * .65);
}

/// Derive from surviving timer logs so undo immediately removes its evidence.
PaceCalibration calibratePace(Task task, Iterable<TimeLog> logs) {
  final feedback = task.planning?['feedback'];
  final sampleTime = feedback is Map
      ? DateTime.tryParse(feedback['sampled_at'] as String? ?? '')
      : null;
  final units = feedback is Map ? feedback['content_units'] : null;
  final samples = logs.where((log) {
    final start = DateTime.tryParse(log.startedAt);
    final end = DateTime.tryParse(log.endedAt);
    // Extra study and temporary learning are real minutes, but they are not
    // evidence of this item's content pace: only scheduled (or legacy
    // unclassified) timer intervals calibrate the content speed.
    final countsForContent =
        log.relation == TimeLogRelation.scheduled ||
        log.relation == TimeLogRelation.legacyUnknown;
    return log.taskId == task.id &&
        countsForContent &&
        log.source == LogSource.timer &&
        log.minutes > 0 &&
        start != null &&
        end != null &&
        end.isAfter(start) &&
        sampleTime != null &&
        !end.isAfter(sampleTime);
  }).toList();
  final minutes = samples.fold<int>(0, (sum, log) => sum + log.minutes);
  final workload = task.planning?['workload'];
  final raw = workload is Map ? workload['components'] : null;
  final components = raw is List
      ? raw.whereType<Map>().where((c) => c['selected'] != false).toList()
      : <Map>[];
  final unitNames = components
      .map((c) => c['unit'])
      .whereType<String>()
      .toSet();
  double? expected;
  // A single content counter cannot distinguish overlapping component units
  // (for example, answering and reviewing the same 21 papers).
  if (components.length == 1 &&
      unitNames.length == 1 &&
      components.every(
        (c) => c['quantity'] is num && c['minutes_per_unit'] is num,
      )) {
    final count = components.fold<double>(
      0,
      (sum, c) => sum + (c['quantity'] as num),
    );
    final budget = components.fold<double>(
      0,
      (sum, c) => sum + (c['quantity'] as num) * (c['minutes_per_unit'] as num),
    );
    if (count > 0 && budget > 0) expected = budget / count;
  }
  return PaceCalibration(
    samples: samples.length,
    minutes: minutes,
    unit: unitNames.length == 1 ? unitNames.single : null,
    expectedMinutesPerUnit: expected,
    observedMinutesPerUnit: samples.length >= 3 && units is num && units > 0
        ? minutes / units
        : null,
  );
}

PlannerData recordPlanningFeedback(
  PlannerData data,
  String taskId, {
  required double contentUnits,
  required bool contentCompleted,
  required String difficulty,
  required String sampledAt,
}) {
  if (!contentUnits.isFinite ||
      contentUnits < 0 ||
      !const ['easy', 'manageable', 'hard'].contains(difficulty)) {
    throw ArgumentError('内容进度或困难程度无效');
  }
  final updated = data.copyWith(
    tasks: [
      for (final task in data.tasks)
        if (task.id == taskId)
          task.copyWith(
            updatedAt: sampledAt,
            planning: {
              ...?task.planning,
              'feedback': {
                'content_units': contentUnits,
                'content_completed': contentCompleted,
                'difficulty': difficulty,
                'sampled_at': sampledAt,
              },
              'content_progress': {
                'completed_units': contentUnits,
                'confirmed': contentCompleted,
                'feedback': difficulty == 'hard'
                    ? '学习困难，需要重新评估'
                    : difficulty == 'easy'
                    ? '进展顺利'
                    : '按预期推进',
              },
            },
          )
        else
          task,
    ],
  );
  final task = updated.tasks.where((task) => task.id == taskId).firstOrNull;
  if (updated.planning != null &&
      task != null &&
      (difficulty == 'hard' || calibratePace(task, updated.logs).deviates)) {
    return updated.copyWith(
      planning: {
        ...updated.planning!,
        'needs_review': true,
        'quality': null,
        'forecast': null,
      },
    );
  }
  return updated;
}
