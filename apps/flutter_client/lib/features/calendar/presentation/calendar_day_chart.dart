import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_view.dart';

/// The visualizations consume one immutable daily snapshot and never mutate it.
class CalendarDayChart extends StatefulWidget {
  const CalendarDayChart({
    required this.day,
    required this.view,
    this.showTitle = false,
    super.key,
  });

  final CalendarDayData day;
  final CalendarView view;
  final bool showTitle;

  @override
  State<CalendarDayChart> createState() => _CalendarDayChartState();
}

class _CalendarDayChartState extends State<CalendarDayChart> {
  String? _selectedId;

  @override
  void didUpdateWidget(covariant CalendarDayChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.day.date != widget.day.date ||
        !widget.day.items.any((item) => item.id == _selectedId)) {
      _selectedId = null;
    }
  }

  void _select(CalendarDayItem item) {
    if (_selectedId != item.id) setState(() => _selectedId = item.id);
  }

  @override
  Widget build(BuildContext context) {
    final day = widget.day;
    return PlannerPanel(
      key: const ValueKey('calendar-day-chart'),
      title: widget.showTitle ? widget.view.label : null,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.showTitle) CalendarDayTotals(day: day),
          if (day.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Text(
                '当天没有学习计划或学习记录',
                textAlign: TextAlign.center,
                style: TextStyle(color: PlannerColors.muted),
              ),
            )
          else ...[
            if (!widget.showTitle) const SizedBox(height: 14),
            _EncodingKey(day: day),
            const SizedBox(height: 12),
            switch (widget.view) {
              CalendarView.growth => _GrowthChart(
                day: day,
                selectedId: _selectedId,
                onSelect: _select,
              ),
              CalendarView.rivers => _RiverChart(
                day: day,
                selectedId: _selectedId,
                onSelect: _select,
              ),
            },
          ],
        ],
      ),
    );
  }
}

/// Daily totals shared by the stacked day graphics.
class CalendarDayTotals extends StatelessWidget {
  const CalendarDayTotals({
    required this.day,
    this.capacityMinutes,
    super.key,
  });

  final CalendarDayData day;

  /// Resolved net capacity of the same day; null when the caller does not show it.
  final int? capacityMinutes;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 20,
    runSpacing: 4,
    children: [
      Text(
        '计划 ${duration(day.plannedMinutes)}',
        key: const ValueKey('calendar-planned-total'),
        style: tabularFigures.copyWith(color: PlannerColors.muted),
      ),
      Text(
        '实学 ${duration(day.actualMinutes)}',
        key: const ValueKey('calendar-actual-total'),
        style: tabularFigures.copyWith(fontWeight: FontWeight.w600),
      ),
      if (capacityMinutes != null)
        Text(
          '容量 ${duration(capacityMinutes!)}',
          key: const ValueKey('calendar-capacity-total'),
          style: tabularFigures.copyWith(color: PlannerColors.muted),
        ),
    ],
  );
}

class _EncodingKey extends StatelessWidget {
  const _EncodingKey({required this.day});

  final CalendarDayData day;

  @override
  Widget build(BuildContext context) {
    final kinds = day.items
        .expand((item) => item.efforts)
        .map((e) => e.kind)
        .toSet();
    return Wrap(
      spacing: 14,
      runSpacing: 7,
      children: [
        const _EncodingSwatch(label: '计划参照'),
        for (final kind in CalendarEffortKind.values)
          if (kinds.contains(kind))
            _EncodingSwatch(label: kind.label, kind: kind),
      ],
    );
  }
}

class _EncodingSwatch extends StatelessWidget {
  const _EncodingSwatch({required this.label, this.kind});

  final String label;
  final CalendarEffortKind? kind;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          width: 18,
          height: 12,
          child: CustomPaint(painter: _SwatchPainter(kind)),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: PlannerColors.muted),
      ),
    ],
  );
}

/// A compact, named entry for an item in the graphic itself.
///
/// This deliberately contains the item name only. The exact plan/actual
/// breakdown stays in the chart tooltip so the calendar does not grow a
/// second item list below the graphic.
class _ChartItemLabel extends StatefulWidget {
  const _ChartItemLabel({
    required this.item,
    required this.onSelect,
    this.compact = false,
    this.maxLines = 2,
    this.foreground,
    this.background,
  });

  final CalendarDayItem item;
  final VoidCallback onSelect;
  final bool compact;
  final int maxLines;
  final Color? foreground;
  final Color? background;

  @override
  State<_ChartItemLabel> createState() => _ChartItemLabelState();
}

class _ChartItemLabelState extends State<_ChartItemLabel> {
  final _tooltip = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final compact = widget.compact;
    final color = _itemColor(item);
    void inspect() {
      widget.onSelect();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tooltip.currentState?.ensureTooltipVisible(),
      );
    }

    final child = DecoratedBox(
      decoration: BoxDecoration(
        color: widget.background,
        borderRadius: BorderRadius.circular(compact ? 3 : 5),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 2 : 5,
          vertical: compact ? 1 : 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(top: compact ? 4 : 5, right: 4),
              child: DecoratedBox(
                key: ValueKey('calendar-chart-color-${item.id}'),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const SizedBox.square(dimension: 6),
              ),
            ),
            Flexible(
              child: Text(
                _chartTitle(item.title),
                key: ValueKey('calendar-chart-label-text-${item.id}'),
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                softWrap: true,
                style: TextStyle(
                  color: widget.foreground ?? color,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return Semantics(
      key: ValueKey('calendar-chart-label-${item.id}'),
      label: _itemDescription(item),
      button: false,
      onTap: inspect,
      excludeSemantics: true,
      child: Tooltip(
        key: _tooltip,
        message: _itemDescription(item),
        triggerMode: TooltipTriggerMode.manual,
        child: InkWell(
          key: ValueKey('calendar-chart-label-target-${item.id}'),
          onTap: inspect,
          onFocusChange: (focused) {
            if (focused) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _tooltip.currentState?.ensureTooltipVisible(),
              );
            }
          },
          onHover: (hovering) {
            if (hovering) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _tooltip.currentState?.ensureTooltipVisible(),
              );
            } else {
              Tooltip.dismissAllToolTips();
            }
          },
          borderRadius: BorderRadius.circular(compact ? 3 : 5),
          child: child,
        ),
      ),
    );
  }
}

String _itemDescription(CalendarDayItem item) =>
    '${item.title}，${item.subjectName}，计划 ${duration(item.plannedMinutes)}，实学 ${duration(item.actualMinutes)}。'
    '${item.efforts.isEmpty ? '尚无学习记录' : item.efforts.map((effort) => '${effort.kind.label} ${duration(effort.minutes)}').join('，')}';

Color _itemColor(CalendarDayItem item) {
  if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(item.declaredColor?.trim() ?? '') ||
      subjectColors.containsKey(item.subjectId)) {
    return subjectColor(item.subjectId, item.declaredColor);
  }
  // String.hashCode is not a persistent color contract on every Flutter target.
  final seed = item.subjectId == 'unknown' || item.subjectId.isEmpty
      ? item.id
      : item.subjectId;
  var hash = 0;
  for (final code in seed.codeUnits) {
    hash = (hash * 31 + code) & 0x7fffffff;
  }
  const palette = [
    Color(0xff537c87),
    Color(0xff7d629f),
    Color(0xffa06145),
    Color(0xff537e52),
    Color(0xff985c78),
    Color(0xff66739b),
  ];
  return palette[hash % palette.length];
}

String _chartTitle(String title) {
  return title.replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _GrowthChart extends StatelessWidget {
  const _GrowthChart({
    required this.day,
    required this.selectedId,
    required this.onSelect,
  });

  final CalendarDayData day;
  final String? selectedId;
  final ValueChanged<CalendarDayItem> onSelect;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 112),
        child: _MinuteAxis(scale: day.scaleMinutes),
      ),
      for (var index = 0; index < day.items.length; index++)
        Row(
          children: [
            SizedBox(
              width: 112,
              child: _ChartItemLabel(
                item: day.items[index],
                compact: true,
                onSelect: () => onSelect(day.items[index]),
              ),
            ),
            Expanded(
              child: _InteractiveGraphic(
                height: 44,
                hit: (_, _) => day.items[index],
                onSelect: onSelect,
                painter: _GrowthPainter(
                  item: day.items[index],
                  scale: day.scaleMinutes,
                  selected: selectedId == day.items[index].id,
                ),
              ),
            ),
          ],
        ),
    ],
  );
}

class _GrowthPainter extends CustomPainter {
  const _GrowthPainter({
    required this.item,
    required this.scale,
    required this.selected,
  });
  final CalendarDayItem item;
  final double scale;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    for (final fraction in const [0.0, .25, .5, .75, 1.0]) {
      canvas.drawLine(
        Offset(size.width * fraction, 0),
        Offset(size.width * fraction, size.height),
        Paint()..color = PlannerColors.border.withValues(alpha: .45),
      );
    }
    final color = _itemColor(item);
    if (item.plannedMinutes > 0) {
      final rect = Rect.fromLTWH(
        0,
        9,
        size.width * item.plannedMinutes / scale,
        26,
      );
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: .13));
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color.withValues(alpha: .42),
      );
    }
    var left = 0.0;
    for (final effort in item.efforts) {
      final width = size.width * effort.minutes / scale;
      _drawEffort(
        canvas,
        Rect.fromLTWH(left, 14, width, 16),
        color,
        effort.kind,
      );
      left += width;
    }
    if (selected) {
      canvas.drawRect(
        Rect.fromLTWH(0, 5, size.width, 34),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = color
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GrowthPainter oldDelegate) =>
      item != oldDelegate.item ||
      scale != oldDelegate.scale ||
      selected != oldDelegate.selected;
}

class _RiverChart extends StatelessWidget {
  const _RiverChart({
    required this.day,
    required this.selectedId,
    required this.onSelect,
  });
  final CalendarDayData day;
  final String? selectedId;
  final ValueChanged<CalendarDayItem> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final layout = _riverLabelLayout(day, width);
      final specs = _riverLabelSpecs(day, width, layout);
      final graphicTop = layout.topBand;
      const graphicHeight = 226.0;
      final stackHeight = graphicHeight + layout.topBand + layout.bottomBand;
      return Column(
        children: [
          SizedBox(
            width: width,
            height: stackHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: graphicTop,
                  left: 0,
                  right: 0,
                  child: _InteractiveGraphic(
                    height: graphicHeight,
                    hit: (point, size) {
                      final planned = point.dy < 120;
                      final minutes =
                          point.dx / size.width * day.riverScaleMinutes;
                      var sum = 0;
                      CalendarDayItem? nearest;
                      var distance = double.infinity;
                      for (final item in day.items) {
                        final amount = planned
                            ? item.plannedMinutes
                            : item.actualMinutes;
                        if (amount <= 0) continue;
                        final middle = sum + amount / 2;
                        if (minutes >= sum && minutes <= sum + amount) {
                          return item;
                        }
                        if ((minutes - middle).abs() < distance) {
                          nearest = item;
                          distance = (minutes - middle).abs();
                        }
                        sum += amount;
                      }
                      return nearest;
                    },
                    onSelect: onSelect,
                    painter: _RiverPainter(day: day, selectedId: selectedId),
                  ),
                ),
                IgnorePointer(
                  child: CustomPaint(
                    size: Size(width, stackHeight),
                    painter: _RiverLabelLeaderPainter(specs: specs, day: day),
                  ),
                ),
                for (final spec in specs)
                  Positioned(
                    left: spec.left,
                    top: spec.top,
                    width: spec.width,
                    height: spec.height,
                    child: _ChartItemLabel(
                      item: spec.item,
                      maxLines: spec.callout ? 2 : 1,
                      compact: !spec.callout,
                      foreground: spec.foreground,
                      background: spec.background,
                      onSelect: () => onSelect(spec.item),
                    ),
                  ),
              ],
            ),
          ),
          _MinuteAxis(scale: day.riverScaleMinutes),
        ],
      );
    },
  );
}

enum _RiverLabelLane { planned, actual }

class _RiverLabelLayout {
  const _RiverLabelLayout({
    required this.plannedRows,
    required this.actualRows,
  });

  final int plannedRows;
  final int actualRows;

  double get topBand => plannedRows * _riverCalloutRowHeight + 8;
  double get bottomBand => actualRows * _riverCalloutRowHeight + 8;
}

const _riverCalloutRowHeight = 42.0;

class _RiverLabelSpec {
  const _RiverLabelSpec({
    required this.item,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.segmentCenter,
    required this.segmentTop,
    required this.lane,
    required this.callout,
    required this.foreground,
    required this.background,
  });

  final CalendarDayItem item;
  final double left;
  final double top;
  final double width;
  final double height;
  final double segmentCenter;
  final double segmentTop;
  final _RiverLabelLane lane;
  final bool callout;
  final Color foreground;
  final Color? background;
}

_RiverLabelLayout _riverLabelLayout(CalendarDayData day, double width) {
  if (width <= 0 || day.items.isEmpty) {
    return const _RiverLabelLayout(plannedRows: 0, actualRows: 0);
  }
  final unit = width / day.riverScaleMinutes;
  var plannedRows = 0;
  var actualRows = 0;
  for (final item in day.items) {
    final plannedWidth = item.plannedMinutes * unit;
    final actualWidth = item.actualMinutes * unit;
    final lane = plannedWidth >= actualWidth && plannedWidth > 0
        ? _RiverLabelLane.planned
        : _RiverLabelLane.actual;
    final segmentWidth = lane == _RiverLabelLane.planned
        ? plannedWidth
        : actualWidth;
    if (segmentWidth > 0 && segmentWidth < 72) {
      if (lane == _RiverLabelLane.planned) {
        plannedRows++;
      } else {
        actualRows++;
      }
    }
  }
  return _RiverLabelLayout(plannedRows: plannedRows, actualRows: actualRows);
}

List<_RiverLabelSpec> _riverLabelSpecs(
  CalendarDayData day,
  double width,
  _RiverLabelLayout layout,
) {
  if (width <= 0 || day.items.isEmpty) return const [];
  final unit = width / day.riverScaleMinutes;
  const minInsideWidth = 72.0;
  const calloutWidth = 108.0;
  const labelHeight = 38.0;
  var plannedLeft = 0.0;
  var actualLeft = 0.0;
  var plannedRow = 0;
  var actualRow = 0;
  final specs = <_RiverLabelSpec>[];
  for (final item in day.items) {
    final plannedWidth = item.plannedMinutes * unit;
    final actualWidth = item.actualMinutes * unit;
    final lane = plannedWidth >= actualWidth && plannedWidth > 0
        ? _RiverLabelLane.planned
        : _RiverLabelLane.actual;
    final segmentWidth = lane == _RiverLabelLane.planned
        ? plannedWidth
        : actualWidth;
    final segmentLeft = lane == _RiverLabelLane.planned
        ? plannedLeft
        : actualLeft;
    if (segmentWidth > 0) {
      final segmentCenter = segmentLeft + segmentWidth / 2;
      final callout = segmentWidth < minInsideWidth;
      final labelWidth = callout ? calloutWidth : math.max(24.0, segmentWidth);
      final left = callout
          ? (segmentCenter - labelWidth / 2).clamp(0.0, width - labelWidth)
          : segmentLeft;
      final top = lane == _RiverLabelLane.planned
          ? (callout
                ? layout.topBand - (++plannedRow) * _riverCalloutRowHeight
                : layout.topBand + 46)
          : (callout
                ? layout.topBand + 202 + actualRow++ * _riverCalloutRowHeight
                : layout.topBand + 164);
      specs.add(
        _RiverLabelSpec(
          item: item,
          left: left,
          top: top,
          width: labelWidth,
          height: callout ? labelHeight : 28,
          segmentCenter: segmentCenter,
          segmentTop:
              layout.topBand + (lane == _RiverLabelLane.planned ? 46 : 164),
          lane: lane,
          callout: callout,
          foreground: callout
              ? _itemColor(item)
              : (lane == _RiverLabelLane.planned
                    ? _itemColor(item)
                    : Colors.white),
          background: callout ? _itemColor(item).withValues(alpha: .10) : null,
        ),
      );
    }
    plannedLeft += plannedWidth;
    actualLeft += actualWidth;
  }
  return specs;
}

class _RiverLabelLeaderPainter extends CustomPainter {
  const _RiverLabelLeaderPainter({required this.specs, required this.day});

  final List<_RiverLabelSpec> specs;
  final CalendarDayData day;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = PlannerColors.muted.withValues(alpha: .65);
    for (final spec in specs) {
      if (!spec.callout) continue;
      final labelAnchor = Offset(
        spec.left + spec.width / 2,
        spec.lane == _RiverLabelLane.planned
            ? spec.top + spec.height
            : spec.top,
      );
      final segmentAnchor = Offset(
        spec.segmentCenter,
        spec.segmentTop + (spec.lane == _RiverLabelLane.planned ? 0 : 28),
      );
      final bend = spec.lane == _RiverLabelLane.planned
          ? segmentAnchor.dy - 7
          : segmentAnchor.dy + 7;
      final path = Path()
        ..moveTo(labelAnchor.dx, labelAnchor.dy)
        ..lineTo(labelAnchor.dx, bend)
        ..lineTo(segmentAnchor.dx, bend)
        ..lineTo(segmentAnchor.dx, segmentAnchor.dy);
      canvas.drawPath(
        path,
        paint..color = _itemColor(spec.item).withValues(alpha: .5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RiverLabelLeaderPainter oldDelegate) =>
      specs != oldDelegate.specs || day != oldDelegate.day;
}

class _RiverPainter extends CustomPainter {
  const _RiverPainter({required this.day, required this.selectedId});
  final CalendarDayData day;
  final String? selectedId;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / day.riverScaleMinutes;
    const top = 46.0;
    const bottom = 164.0;
    const height = 28.0;
    for (final fraction in const [0.0, .25, .5, .75, 1.0]) {
      canvas.drawLine(
        Offset(size.width * fraction, top - 8),
        Offset(size.width * fraction, bottom + height + 8),
        Paint()..color = PlannerColors.border.withValues(alpha: .45),
      );
    }
    var plannedLeft = 0.0;
    var actualLeft = 0.0;
    // Identical item order on both banks makes the original-study ribbons
    // monotone. Other efforts never enter a ribbon or consume another plan.
    for (final item in day.items) {
      final original =
          math.min(item.scheduledMinutes, item.plannedMinutes) * unit;
      final color = _itemColor(item);
      if (original > 0) {
        final path = Path()
          ..moveTo(plannedLeft, top + height)
          ..cubicTo(plannedLeft, 118, actualLeft, 118, actualLeft, bottom)
          ..lineTo(actualLeft + original, bottom)
          ..cubicTo(
            actualLeft + original,
            118,
            plannedLeft + original,
            118,
            plannedLeft + original,
            top + height,
          )
          ..close();
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: selectedId == item.id ? .3 : .14),
        );
      }
      plannedLeft += item.plannedMinutes * unit;
      actualLeft += item.actualMinutes * unit;
    }
    plannedLeft = 0;
    actualLeft = 0;
    for (var index = 0; index < day.items.length; index++) {
      final item = day.items[index];
      final color = _itemColor(item);
      final plannedWidth = item.plannedMinutes * unit;
      if (plannedWidth > 0) {
        final rect = Rect.fromLTWH(plannedLeft, top, plannedWidth, height);
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: .16));
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = color.withValues(alpha: .45)
            ..strokeWidth = selectedId == item.id ? 2 : 1,
        );
      }
      var effortLeft = actualLeft;
      for (final effort in item.efforts) {
        final width = effort.minutes * unit;
        _drawEffort(
          canvas,
          Rect.fromLTWH(effortLeft, bottom, width, height),
          color,
          effort.kind,
        );
        effortLeft += width;
      }
      if (selectedId == item.id && item.actualMinutes > 0) {
        canvas.drawRect(
          Rect.fromLTWH(
            actualLeft,
            bottom - 3,
            item.actualMinutes * unit,
            height + 6,
          ),
          Paint()
            ..style = PaintingStyle.stroke
            ..color = color
            ..strokeWidth = 1.5,
        );
      }
      plannedLeft += plannedWidth;
      actualLeft += item.actualMinutes * unit;
    }
    _paintText(
      canvas,
      '计划',
      const Offset(0, 24),
      maxWidth: size.width,
      fontSize: 12,
    );
    _paintText(
      canvas,
      '实学',
      const Offset(0, 142),
      maxWidth: size.width,
      fontSize: 12,
    );
    if (day.plannedMinutes == 0) {
      _paintText(
        canvas,
        '无当日计划',
        const Offset(0, top + 6),
        maxWidth: size.width,
      );
    }
    if (day.actualMinutes == 0) {
      _paintText(
        canvas,
        '尚无学习记录',
        const Offset(0, bottom + 6),
        maxWidth: size.width,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RiverPainter oldDelegate) =>
      day != oldDelegate.day || selectedId != oldDelegate.selectedId;
}

typedef _GraphicHit = CalendarDayItem? Function(Offset point, Size size);

class _InteractiveGraphic extends StatefulWidget {
  const _InteractiveGraphic({
    required this.height,
    required this.painter,
    required this.hit,
    required this.onSelect,
  });
  final double height;
  final CustomPainter painter;
  final _GraphicHit hit;
  final ValueChanged<CalendarDayItem> onSelect;

  @override
  State<_InteractiveGraphic> createState() => _InteractiveGraphicState();
}

class _InteractiveGraphicState extends State<_InteractiveGraphic> {
  final _tooltip = GlobalKey<TooltipState>();
  CalendarDayItem? _hovered;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, widget.height);
      void inspect(Offset point, {bool tap = false}) {
        final item = widget.hit(point, size);
        if (item == null) return;
        if (_hovered?.id != item.id) setState(() => _hovered = item);
        if (tap) {
          widget.onSelect(item);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _tooltip.currentState?.ensureTooltipVisible(),
          );
        }
      }

      // Named item keys below expose the same inspection to keyboard and
      // screen-reader users; the painted hit surface must not add unnamed taps.
      final graphic = ExcludeSemantics(
        child: Tooltip(
          key: _tooltip,
          message: _hovered == null ? '' : _itemDescription(_hovered!),
          excludeFromSemantics: true,
          triggerMode: TooltipTriggerMode.manual,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onHover: (event) {
              inspect(event.localPosition);
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _tooltip.currentState?.ensureTooltipVisible(),
              );
            },
            onExit: (_) => Tooltip.dismissAllToolTips(),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (details) => inspect(details.localPosition, tap: true),
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: CustomPaint(painter: widget.painter),
              ),
            ),
          ),
        ),
      );
      return graphic;
    },
  );
}

class _MinuteAxis extends StatelessWidget {
  const _MinuteAxis({required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 27,
      width: double.infinity,
      child: CustomPaint(painter: _MinuteAxisPainter(scale)),
    ),
  );
}

class _MinuteAxisPainter extends CustomPainter {
  const _MinuteAxisPainter(this.scale);
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final fraction in const [0.0, .25, .5, .75, 1.0]) {
      final value = (scale * fraction)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'\.?0+$'), '');
      final text = fraction == 1 ? '$value 分钟' : value;
      final label = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(fontSize: 11, color: PlannerColors.muted),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 70);
      label.paint(
        canvas,
        Offset(
          (fraction * size.width - label.width / 2).clamp(
            0.0,
            math.max(0, size.width - label.width),
          ),
          6,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinuteAxisPainter oldDelegate) =>
      scale != oldDelegate.scale;
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter(this.kind);
  final CalendarEffortKind? kind;
  final Color color = PlannerColors.blue;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (kind == null) {
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: .13));
      canvas.drawRect(
        rect.deflate(.5),
        Paint()
          ..color = color.withValues(alpha: .5)
          ..style = PaintingStyle.stroke,
      );
    } else {
      _drawEffort(canvas, rect, color, kind!);
    }
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}

void _drawEffort(
  Canvas canvas,
  Rect rect,
  Color color,
  CalendarEffortKind kind,
) {
  if (rect.isEmpty) return;
  canvas.drawRect(rect, Paint()..color = color);
  if (kind != CalendarEffortKind.scheduled) {
    canvas.save();
    canvas.clipRect(rect);
    _drawPattern(canvas, rect, color, kind);
    canvas.restore();
  }
}

void _drawPattern(
  Canvas canvas,
  Rect rect,
  Color color,
  CalendarEffortKind kind,
) {
  final paint = Paint()
    ..color = Colors.white.withValues(alpha: .7)
    ..strokeWidth = 1.3;
  final reverse = kind == CalendarEffortKind.unscheduled;
  if (kind == CalendarEffortKind.legacyUnknown) {
    for (var y = rect.top + 2; y < rect.bottom; y += 5) {
      for (var x = rect.left + 2; x < rect.right; x += 5) {
        canvas.drawCircle(Offset(x, y), .85, paint);
      }
    }
    return;
  }
  for (var x = rect.left - rect.height; x < rect.right + rect.height; x += 7) {
    canvas.drawLine(
      Offset(x, reverse ? rect.top : rect.bottom),
      Offset(x + rect.height, reverse ? rect.bottom : rect.top),
      paint,
    );
  }
}

void _paintText(
  Canvas canvas,
  String text,
  Offset offset, {
  Color color = PlannerColors.muted,
  double fontSize = 11,
  double maxWidth = 200,
  Color? background,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: tabularFigures.copyWith(
        fontSize: fontSize,
        color: color,
        backgroundColor: background,
      ),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: math.max(0, maxWidth));
  painter.paint(canvas, offset);
}
