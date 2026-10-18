import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../shared/models/planner_models.dart';
import '../../planner/application/study_timer.dart';

/// Today's actual elapsed time, including timer seconds not yet in minute logs.
class TaskTimePiePanel extends ConsumerStatefulWidget {
  const TaskTimePiePanel({required this.data, required this.date, super.key});

  final PlannerData data;
  final String date;

  @override
  ConsumerState<TaskTimePiePanel> createState() => _TaskTimePiePanelState();
}

class _TaskTimePiePanelState extends ConsumerState<TaskTimePiePanel> {
  final _chartTooltip = GlobalKey<TooltipState>();
  final _colorsByTaskId = <String, Color>{};
  String? _selectedTaskId;
  String? _hoveredTaskId;
  String? _focusedTaskId;

  void _select(String? taskId) {
    setState(() {
      _selectedTaskId = _selectedTaskId == taskId ? null : taskId;
    });
  }

  void _showChartTooltip() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _chartTooltip.currentState?.ensureTooltipVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    final timer = ref.watch(studyTimerProvider);
    final tasks = {for (final task in widget.data.tasks) task.id: task};
    final taskIds = <String>{
      ...tasks.keys,
      for (final log in widget.data.logs)
        if (log.date == widget.date && log.taskId != null) log.taskId!,
      ?timer.activeTaskId,
    };
    _assignTaskColors(taskIds, _colorsByTaskId);
    final slices = <_TaskTimeSlice>[];
    for (final taskId in taskIds) {
      final elapsed = timer.elapsedFor(taskId, widget.date);
      if (elapsed <= Duration.zero) continue;
      slices.add(
        _TaskTimeSlice(
          taskId: taskId,
          title: tasks[taskId]?.title ?? '已删除事项',
          elapsed: elapsed,
          color: _colorsByTaskId[taskId]!,
        ),
      );
    }
    slices.sort((a, b) {
      final elapsed = b.elapsed.compareTo(a.elapsed);
      return elapsed != 0 ? elapsed : a.taskId.compareTo(b.taskId);
    });
    final totalMilliseconds = slices.fold<int>(
      0,
      (total, slice) => total + slice.elapsed.inMilliseconds,
    );
    final total = Duration(milliseconds: totalMilliseconds);
    final activeTaskId = _hoveredTaskId ?? _focusedTaskId ?? _selectedTaskId;
    final active = slices
        .where((slice) => slice.taskId == activeTaskId)
        .firstOrNull;

    return PlannerPanel(
      key: const Key('task-time-pie-panel'),
      title: '今日事项用时',
      trailing: Text(
        '合计 ${_elapsedLabel(total)}',
        key: const Key('task-time-pie-total'),
        style: tabularFigures.copyWith(
          color: PlannerColors.muted,
          fontSize: 12,
        ),
      ),
      child: slices.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  Icon(
                    Icons.pie_chart_outline,
                    color: PlannerColors.border,
                    size: 48,
                  ),
                  SizedBox(height: 12),
                  Text(
                    '今天还没有学习用时',
                    key: Key('task-time-pie-empty'),
                    style: TextStyle(color: PlannerColors.muted),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final diameter = math.min(232.0, constraints.maxWidth);
                    final size = Size.square(diameter);
                    return Center(
                      child: Semantics(
                        image: true,
                        label:
                            '今日事项用时饼图，${slices.length}项，'
                            '合计${_elapsedLabel(total)}',
                        child: Tooltip(
                          key: _chartTooltip,
                          message: active?.details(totalMilliseconds) ?? '',
                          excludeFromSemantics: true,
                          triggerMode: TooltipTriggerMode.manual,
                          showDuration: const Duration(seconds: 4),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            onHover: (event) {
                              final hovered = _sliceAt(
                                event.localPosition,
                                size,
                                slices,
                                totalMilliseconds,
                              )?.taskId;
                              if (_hoveredTaskId == hovered) return;
                              setState(() => _hoveredTaskId = hovered);
                              if (hovered != null) _showChartTooltip();
                            },
                            onExit: (_) {
                              setState(() => _hoveredTaskId = null);
                              Tooltip.dismissAllToolTips();
                            },
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (details) {
                                final selected = _sliceAt(
                                  details.localPosition,
                                  size,
                                  slices,
                                  totalMilliseconds,
                                );
                                _select(selected?.taskId);
                                if (selected != null) _showChartTooltip();
                              },
                              child: CustomPaint(
                                key: const Key('task-time-pie-chart'),
                                size: size,
                                painter: _TaskTimePiePainter(
                                  slices: slices,
                                  totalMilliseconds: totalMilliseconds,
                                  selectedTaskId: active?.taskId,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                for (final slice in slices)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Semantics(
                      key: Key('task-time-pie-entry-${slice.taskId}'),
                      button: true,
                      selected: active?.taskId == slice.taskId,
                      label: slice.details(totalMilliseconds),
                      onTap: () => _select(slice.taskId),
                      child: Tooltip(
                        message: slice.details(totalMilliseconds),
                        excludeFromSemantics: true,
                        child: InkWell(
                          excludeFromSemantics: true,
                          borderRadius: BorderRadius.circular(4),
                          onTap: () => _select(slice.taskId),
                          onHover: (hovered) => setState(
                            () =>
                                _hoveredTaskId = hovered ? slice.taskId : null,
                          ),
                          onFocusChange: (focused) => setState(
                            () =>
                                _focusedTaskId = focused ? slice.taskId : null,
                          ),
                          child: ExcludeSemantics(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: active?.taskId == slice.taskId
                                    ? slice.color.withValues(alpha: 0.09)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Container(
                                      key: Key(
                                        'task-time-pie-swatch-${slice.taskId}',
                                      ),
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: slice.color,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          slice.title,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${_elapsedLabel(slice.elapsed)}'
                                          '  ·  '
                                          '${_percentage(slice.elapsed.inMilliseconds, totalMilliseconds)}',
                                          key: Key(
                                            'task-time-pie-value-${slice.taskId}',
                                          ),
                                          style: tabularFigures.copyWith(
                                            fontSize: 12,
                                            color: PlannerColors.muted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _TaskTimeSlice {
  const _TaskTimeSlice({
    required this.taskId,
    required this.title,
    required this.elapsed,
    required this.color,
  });

  final String taskId, title;
  final Duration elapsed;
  final Color color;

  String details(int totalMilliseconds) =>
      '$title，${_elapsedLabel(elapsed)}，'
      '${_percentage(elapsed.inMilliseconds, totalMilliseconds)}';
}

String _elapsedLabel(Duration value) {
  if (value == Duration.zero) return '0秒';
  if (value.inSeconds == 0) return '不足1秒';
  final seconds = value.inSeconds % 60;
  final minutes = value.inMinutes % 60;
  if (value.inHours > 0) {
    return '${value.inHours}小时'
        '${minutes > 0 ? '$minutes分' : ''}'
        '${seconds > 0 ? '$seconds秒' : ''}';
  }
  if (value.inMinutes > 0) return '$minutes分${seconds > 0 ? '$seconds秒' : ''}';
  return '${value.inSeconds}秒';
}

String _percentage(int milliseconds, int totalMilliseconds) {
  final percentage = milliseconds * 100 / totalMilliseconds;
  if (percentage < 0.1) return '不足0.1%';
  return '${percentage.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '')}%';
}

void _assignTaskColors(Set<String> taskIds, Map<String, Color> colors) {
  const palette = [
    PlannerColors.blue,
    PlannerColors.green,
    Color(0xffce952d),
    Color(0xff8660a0),
    Color(0xff298c96),
    Color(0xffc26a78),
    Color(0xff7e8f3b),
    Color(0xffc5743b),
  ];
  final sortedIds = taskIds.toList()..sort();
  final used = colors.values.toSet();
  for (final id in sortedIds) {
    if (colors.containsKey(id)) continue;
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    Color? color;
    for (var offset = 0; offset < palette.length; offset++) {
      final candidate = palette[(hash + offset) % palette.length];
      if (!used.contains(candidate)) {
        color = candidate;
        break;
      }
    }
    var hue = hash % 360.0;
    for (var attempt = 0; color == null && attempt < 360; attempt++) {
      final candidate = HSVColor.fromAHSV(1, hue, 0.58, 0.68).toColor();
      if (!used.contains(candidate)) color = candidate;
      hue = (hue + 19) % 360;
    }
    color ??= palette[hash % palette.length];
    colors[id] = color;
    used.add(color);
  }
}

_TaskTimeSlice? _sliceAt(
  Offset position,
  Size size,
  List<_TaskTimeSlice> slices,
  int totalMilliseconds,
) {
  final center = size.center(Offset.zero);
  final delta = position - center;
  if (delta.distance > size.shortestSide / 2 - 6) return null;
  final angle = (math.atan2(delta.dy, delta.dx) + math.pi / 2) % (math.pi * 2);
  var end = 0.0;
  for (final slice in slices) {
    end += slice.elapsed.inMilliseconds / totalMilliseconds * math.pi * 2;
    if (angle < end) return slice;
  }
  return slices.lastOrNull;
}

class _TaskTimePiePainter extends CustomPainter {
  const _TaskTimePiePainter({
    required this.slices,
    required this.totalMilliseconds,
    required this.selectedTaskId,
  });

  final List<_TaskTimeSlice> slices;
  final int totalMilliseconds;
  final String? selectedTaskId;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 6;
    final paint = Paint()..style = PaintingStyle.fill;
    if (slices.length == 1) {
      canvas.drawCircle(center, radius, paint..color = slices.first.color);
      return;
    }
    var start = -math.pi / 2;
    for (final slice in slices) {
      final sweep =
          slice.elapsed.inMilliseconds / totalMilliseconds * math.pi * 2;
      final selected = slice.taskId == selectedTaskId;
      final offset = selected
          ? Offset(math.cos(start + sweep / 2), math.sin(start + sweep / 2)) * 4
          : Offset.zero;
      paint.color = selectedTaskId == null || selected
          ? slice.color
          : slice.color.withValues(alpha: 0.35);
      canvas.drawArc(
        Rect.fromCircle(center: center + offset, radius: radius),
        start,
        sweep,
        true,
        paint,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _TaskTimePiePainter oldDelegate) {
    if (totalMilliseconds != oldDelegate.totalMilliseconds ||
        selectedTaskId != oldDelegate.selectedTaskId ||
        slices.length != oldDelegate.slices.length) {
      return true;
    }
    for (var index = 0; index < slices.length; index++) {
      final current = slices[index];
      final previous = oldDelegate.slices[index];
      if (current.taskId != previous.taskId ||
          current.elapsed != previous.elapsed ||
          current.color != previous.color) {
        return true;
      }
    }
    return false;
  }
}
