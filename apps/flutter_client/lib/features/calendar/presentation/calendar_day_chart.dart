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
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.showTitle) CalendarDayTotals(day: day),
          if (day.items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 44),
              child: Text(
                '当天没有学习计划或学习记录',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: PlannerColors.muted),
              ),
            )
          else ...[
            if (!widget.showTitle) const SizedBox(height: 14),
            _EncodingKey(day: day),
            const SizedBox(height: 14),
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
  const CalendarDayTotals({required this.day, this.capacityMinutes, super.key});

  final CalendarDayData day;

  /// Resolved net capacity of the same day; null when the caller does not show it.
  final int? capacityMinutes;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Wrap(
      spacing: 22,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          '计划 ${duration(day.plannedMinutes)}',
          key: const ValueKey('calendar-planned-total'),
          style: tabularFigures.copyWith(
            fontSize: 12.5,
            color: PlannerColors.muted,
          ),
        ),
        Text(
          '实学 ${duration(day.actualMinutes)}',
          key: const ValueKey('calendar-actual-total'),
          style: tabularFigures.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: PlannerColors.text,
          ),
        ),
        if (capacityMinutes != null)
          Text(
            '容量 ${duration(capacityMinutes!)}',
            key: const ValueKey('calendar-capacity-total'),
            style: tabularFigures.copyWith(
              fontSize: 12.5,
              color: PlannerColors.subtle,
            ),
          ),
      ],
    ),
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
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const _EncodingSwatch(label: '计划参照'),
        for (final kind in CalendarEffortKind.values)
          if (kinds.contains(kind))
            _EncodingSwatch(label: kind.label, kind: kind),
      ],
    );
  }
}

/// Small dot plus 11.5 px label: colour stays an accent, never a full bar.
class _EncodingSwatch extends StatelessWidget {
  const _EncodingSwatch({required this.label, this.kind});

  final String label;
  final CalendarEffortKind? kind;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: kind == null ? PlannerColors.blueSoft : _kindColor(kind!),
            border: kind == null
                ? Border.all(color: PlannerColors.blue.withValues(alpha: .55))
                : null,
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          height: 1.35,
          color: PlannerColors.muted,
        ),
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
    final accent = widget.foreground ?? _itemAccent(item);
    final background =
        widget.background ??
        Color.alphaBlend(accent.withValues(alpha: .07), PlannerColors.surface);
    void inspect() {
      widget.onSelect();
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _tooltip.currentState?.ensureTooltipVisible(),
      );
    }

    final child = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(compact ? 3 : 4),
        border: Border.all(color: accent.withValues(alpha: .24)),
      ),
      child: ClipRect(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 3 : 5,
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
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
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
                    color: accent,
                    fontSize: compact ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    height: 1.15,
                  ),
                ),
              ),
            ],
          ),
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
    '${item.title}${item.tagNames.isEmpty ? '' : '，标签 ${item.tagNames.join('、')}'}，计划 ${duration(item.plannedMinutes)}，实学 ${duration(item.actualMinutes)}。'
    '${item.efforts.isEmpty ? '尚无学习记录' : item.efforts.map((effort) => '${effort.kind.label} ${duration(effort.minutes)}').join('，')}';

/// Semantic accent of one owner: planned work is ink-blue, study recorded
/// without a plan is amber, and an owner with neither falls back to the muted
/// line colour. Item identity no longer creates a rainbow palette.
Color _itemAccent(CalendarDayItem item) {
  if (item.plannedMinutes > 0 || item.scheduledMinutes > 0) {
    return PlannerColors.blue;
  }
  if (item.actualMinutes > 0) return PlannerColors.orange;
  return PlannerColors.subtle;
}

/// Colour of one recorded-effort kind. The hatch pattern still separates
/// "已有事项加学" from "当天未排程的事项"; colour alone never carries meaning.
Color _kindColor(CalendarEffortKind kind) => switch (kind) {
  CalendarEffortKind.scheduled => PlannerColors.blue,
  CalendarEffortKind.extra => PlannerColors.orange,
  CalendarEffortKind.unscheduled => PlannerColors.orange,
  CalendarEffortKind.legacyUnknown => PlannerColors.subtle,
};

/// Fill under a planned reference block.
Color _planFill() => PlannerColors.blueSoft;

/// Hairline-accent of an effort segment.
Color _effortColor(CalendarEffortKind kind) => _kindColor(kind);

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

  static const double _rowHeight = 40;
  static const double _labelWidth = 112;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.only(left: _labelWidth, bottom: 2),
        child: _MinuteAxis(scale: day.scaleMinutes),
      ),
      for (var index = 0; index < day.items.length; index++)
        SizedBox(
          height: _rowHeight,
          child: Row(
            children: [
              SizedBox(
                width: _labelWidth,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _ChartItemLabel(
                    item: day.items[index],
                    compact: true,
                    onSelect: () => onSelect(day.items[index]),
                  ),
                ),
              ),
              Expanded(
                child: _InteractiveGraphic(
                  height: _rowHeight,
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
    final hairline = 1.0;
    // One hairline baseline only: vertical gridlines would compete with the
    // tracks and are intentionally gone.
    canvas.drawLine(
      Offset(0, size.height - hairline),
      Offset(size.width, size.height - hairline),
      Paint()..color = PlannerColors.border.withValues(alpha: .7),
    );
    if (item.plannedMinutes > 0) {
      final rect = Rect.fromLTWH(
        0,
        7,
        size.width * item.plannedMinutes / scale,
        26,
      );
      _fillRRect(canvas, rect, _planFill(), radius: 4);
      _strokeRRect(
        canvas,
        rect,
        PlannerColors.blue.withValues(alpha: .45),
        radius: 4,
        width: hairline,
      );
    }
    var left = 0.0;
    for (final effort in item.efforts) {
      final width = size.width * effort.minutes / scale;
      _drawEffort(
        canvas,
        Rect.fromLTWH(left, 13, width, 14),
        _effortColor(effort.kind),
        effort.kind,
        radius: 3,
      );
      left += width;
    }
    if (selected) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 2, size.width, size.height - 2),
          const Radius.circular(5),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..color = PlannerColors.blue
          ..strokeWidth = 2,
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
      // Inside labels keep a 2 px gutter from the neighbouring block so two
      // adjacent owners can never read as one run of text.
      final labelWidth = callout
          ? calloutWidth
          : math.max(24.0, segmentWidth - 2);
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
          foreground: _itemAccent(item),
          background: null,
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
        paint..color = _itemAccent(spec.item).withValues(alpha: .45),
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
    const radius = 5.0;
    // Two hairline section rules only: vertical gridlines are gone so the
    // banks read as ink on paper, not as a screenshot of a spreadsheet.
    final rule = Paint()..color = PlannerColors.border.withValues(alpha: .8);
    canvas.drawLine(const Offset(0, top), Offset(size.width, top), rule);
    canvas.drawLine(
      Offset(0, bottom + height),
      Offset(size.width, bottom + height),
      rule,
    );
    var plannedLeft = 0.0;
    var actualLeft = 0.0;
    // Identical item order on both banks makes the original-study ribbons
    // monotone. Other efforts never enter a ribbon or consume another plan.
    for (final item in day.items) {
      final original =
          math.min(item.scheduledMinutes, item.plannedMinutes) * unit;
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
            ..color = PlannerColors.blue.withValues(
              alpha: selectedId == item.id ? .16 : .07,
            ),
        );
      }
      plannedLeft += item.plannedMinutes * unit;
      actualLeft += item.actualMinutes * unit;
    }
    plannedLeft = 0;
    actualLeft = 0;
    for (final item in day.items) {
      final plannedWidth = item.plannedMinutes * unit;
      if (plannedWidth > 0) {
        final rect = Rect.fromLTWH(plannedLeft, top, plannedWidth, height);
        _fillRRect(canvas, rect, _planFill(), radius: radius);
        _strokeRRect(
          canvas,
          rect,
          PlannerColors.blue.withValues(
            alpha: selectedId == item.id ? .9 : .35,
          ),
          radius: radius,
          width: selectedId == item.id ? 2 : 1,
        );
      }
      var effortLeft = actualLeft;
      for (final effort in item.efforts) {
        final width = effort.minutes * unit;
        _drawEffort(
          canvas,
          Rect.fromLTWH(effortLeft, bottom, width, height),
          _effortColor(effort.kind),
          effort.kind,
          radius: radius,
        );
        effortLeft += width;
      }
      // A hairline gap keeps neighbouring owners readable even when they share
      // the same semantic colour.
      if (item.actualMinutes > 0 && actualLeft > 0) {
        canvas.drawLine(
          Offset(actualLeft, bottom + 1),
          Offset(actualLeft, bottom + height - 1),
          Paint()
            ..color = Colors.white.withValues(alpha: .8)
            ..strokeWidth = 1,
        );
      }
      if (selectedId == item.id && item.actualMinutes > 0) {
        _strokeRRect(
          canvas,
          Rect.fromLTWH(
            actualLeft,
            bottom - 3,
            item.actualMinutes * unit,
            height + 6,
          ),
          PlannerColors.blue,
          radius: radius + 2,
          width: 2,
        );
      }
      plannedLeft += plannedWidth;
      actualLeft += item.actualMinutes * unit;
    }
    _paintText(
      canvas,
      '计划',
      const Offset(0, 25),
      maxWidth: size.width,
      fontSize: 11,
      color: PlannerColors.subtle,
    );
    _paintText(
      canvas,
      '实学',
      const Offset(0, 143),
      maxWidth: size.width,
      fontSize: 11,
      color: PlannerColors.subtle,
    );
    if (day.plannedMinutes == 0) {
      _paintText(
        canvas,
        '无当日计划',
        const Offset(0, top + 6),
        maxWidth: size.width,
        color: PlannerColors.subtle,
      );
    }
    if (day.actualMinutes == 0) {
      _paintText(
        canvas,
        '尚无学习记录',
        const Offset(0, bottom + 6),
        maxWidth: size.width,
        color: PlannerColors.subtle,
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
      height: 22,
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
    // Narrow plots keep only the readable extremes; five labels collide below
    // ~420 px, which is exactly the 320–390 px mobile range.
    final fractions = size.width < 220
        ? const [0.0, 1.0]
        : size.width < 420
        ? const [0.0, .5, 1.0]
        : const [0.0, .25, .5, .75, 1.0];
    for (final fraction in fractions) {
      final value = (scale * fraction)
          .toStringAsFixed(2)
          .replaceFirst(RegExp(r'\.?0+$'), '');
      final text = fraction == 1 ? '$value 分钟' : value;
      final label = TextPainter(
        text: TextSpan(
          text: text,
          style: tabularFigures.copyWith(
            fontSize: 11,
            color: PlannerColors.subtle,
          ),
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
          5,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MinuteAxisPainter oldDelegate) =>
      scale != oldDelegate.scale;
}

void _fillRRect(Canvas canvas, Rect rect, Color color, {double radius = 4}) {
  if (rect.isEmpty) return;
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(radius)),
    Paint()..color = color,
  );
}

void _strokeRRect(
  Canvas canvas,
  Rect rect,
  Color color, {
  double radius = 4,
  double width = 1,
}) {
  if (rect.isEmpty) return;
  canvas.drawRRect(
    RRect.fromRectAndRadius(rect, Radius.circular(radius)),
    Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      ..strokeWidth = width,
  );
}

void _drawEffort(
  Canvas canvas,
  Rect rect,
  Color color,
  CalendarEffortKind kind, {
  double radius = 4,
}) {
  if (rect.isEmpty) return;
  _fillRRect(canvas, rect, color, radius: radius);
  if (kind != CalendarEffortKind.scheduled) {
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
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
    ..color = Colors.white.withValues(alpha: .68)
    ..strokeWidth = 1.15;
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
