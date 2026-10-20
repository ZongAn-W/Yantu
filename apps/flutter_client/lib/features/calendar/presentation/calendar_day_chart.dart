import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
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
    final tokens = context.tokens;
    return PlannerPanel(
      key: const ValueKey('calendar-day-chart'),
      title: widget.showTitle ? widget.view.label : null,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.showTitle) CalendarDayTotals(day: day),
          if (day.items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 44),
              child: Text(
                '当天没有学习计划或学习记录',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: tokens.muted),
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
            color: context.tokens.muted,
          ),
        ),
        Text(
          '实学 ${duration(day.actualMinutes)}',
          key: const ValueKey('calendar-actual-total'),
          style: tabularFigures.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.tokens.text,
          ),
        ),
        if (capacityMinutes != null)
          Text(
            '容量 ${duration(capacityMinutes!)}',
            key: const ValueKey('calendar-capacity-total'),
            style: tabularFigures.copyWith(
              fontSize: 12.5,
              color: context.tokens.subtle,
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
            color: kind == null
                ? context.tokens.accentSoft
                : _kindColor(context.tokens, kind!),
            border: kind == null
                ? Border.all(
                    color: context.tokens.accent.withValues(alpha: .55),
                  )
                : null,
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        label,
        style: TextStyle(
          fontSize: 11,
          height: 1.35,
          color: context.tokens.muted,
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
    final tokens = context.tokens;
    final compact = widget.compact;
    final accent = widget.foreground ?? _itemAccent(tokens, item);
    final background =
        widget.background ??
        Color.alphaBlend(accent.withValues(alpha: .07), tokens.surface);
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
Color _itemAccent(PlannerTokens tokens, CalendarDayItem item) {
  if (item.plannedMinutes > 0 || item.scheduledMinutes > 0) {
    return tokens.accent;
  }
  if (item.actualMinutes > 0) return tokens.warning;
  return tokens.subtle;
}

/// Colour of one recorded-effort kind. The hatch pattern still separates
/// "已有事项加学" from "当天未排程的事项"; colour alone never carries meaning.
Color _kindColor(PlannerTokens tokens, CalendarEffortKind kind) =>
    switch (kind) {
      CalendarEffortKind.scheduled => tokens.accent,
      CalendarEffortKind.extra => tokens.warning,
      CalendarEffortKind.unscheduled => tokens.warning,
      CalendarEffortKind.legacyUnknown => tokens.subtle,
    };

/// Fill under a planned reference block.
Color _planFill(PlannerTokens tokens) =>
    tokens.isDark ? tokens.accent.withValues(alpha: 0.22) : tokens.accentSoft;

/// Hairline-accent of an effort segment.
Color _effortColor(PlannerTokens tokens, CalendarEffortKind kind) =>
    _kindColor(tokens, kind);

String _chartTitle(String title) {
  return title.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Height of the shared minute axis; every tick is an 11 px tabular caption.
const double _minuteAxisHeight = 22;

/// Height of one growth lane. The planned reference band (26 px) and the
/// recorded effort run (14 px) both live inside it, so 28 owners still fit a
/// 320 px wide panel.
const double _growthRowHeight = 40;
const double _growthLabelWidth = 112;

/// Vertical insets of one growth lane: the 26 px plan reference band and the
/// 14 px recorded effort run are both centred on the lane.
const double _growthPlanInset = 7;
const double _growthEffortInset = 13;
const double _growthEffortRunHeight = 14;

/// Vertical geometry of the double river, in stack pixels. The label layout
/// below shares these numbers, so callout leaders still meet their segments.
const double _riverGraphicHeight = 226;
const double _riverPlannedTop = 46;
const double _riverPlannedBottom = 74;
const double _riverActualTop = 164;
const double _riverActualBottom = 192;
const double _riverHandleY = 118;

/// No title, no grid line, no border on the sides we do not use.
const SideTitles _hiddenSideTitles = SideTitles(showTitles: false);

/// One coordinate of a cubic Bezier whose control points are given separately.
double _cubic(
  double from,
  double fromHandle,
  double toHandle,
  double to,
  double t,
) {
  final u = 1 - t;
  return u * u * u * from +
      3 * u * u * t * fromHandle +
      3 * u * t * t * toHandle +
      t * t * t * to;
}

/// Tabular minute caption: decimals are trimmed and only the last tick spells
/// the unit out, exactly like the old hand-painted axis.
String _minuteTickLabel(double value, double scale) {
  var text = value.toStringAsFixed(2);
  while (text.contains('.') && text.endsWith('0')) {
    text = text.substring(0, text.length - 1);
  }
  if (text.endsWith('.')) {
    text = text.substring(0, text.length - 1);
  }
  return (value - scale).abs() < 1e-6 ? '$text 分钟' : text;
}

/// Shared minute tick: the old axis kept two labels below 220 px, three below
/// 420 px and five on wider plots.
Widget _minuteTitle(PlannerTokens tokens, double value, TitleMeta meta) {
  final scale = meta.max;
  return SideTitleWidget(
    meta: meta,
    space: 4,
    fitInside: SideTitleFitInsideData.fromTitleMeta(meta, distanceFromEdge: 0),
    child: Text(
      _minuteTickLabel(value, scale),
      style: tabularFigures.copyWith(fontSize: 11, color: tokens.subtle),
    ),
  );
}

SideTitles _minuteSideTitles(
  PlannerTokens tokens, {
  required double scale,
  required double width,
}) {
  final interval = width < 220
      ? scale
      : width < 420
      ? scale / 2
      : scale / 4;
  return SideTitles(
    showTitles: true,
    reservedSize: _minuteAxisHeight,
    interval: interval > 0 ? interval : scale,
    getTitlesWidget: (value, meta) => _minuteTitle(tokens, value, meta),
  );
}

/// One fl_chart segment whose stroke width is the band thickness: a 26 px plan
/// reference or a 14 px effort run stays a crisp rectangle without layers.
LineChartBarData _bandLine(List<FlSpot> spots, Color color, double thickness) =>
    LineChartBarData(
      spots: spots,
      color: color,
      barWidth: thickness,
      dotData: const FlDotData(show: false),
    );

LineChartBarData _strokeLine(
  List<FlSpot> spots,
  Color color,
  double strokeWidth,
) => LineChartBarData(
  spots: spots,
  color: color,
  barWidth: strokeWidth,
  dotData: const FlDotData(show: false),
);

/// Appends one horizontal segment; null spots keep fl_chart from joining two
/// unrelated blocks into a single run.
void _appendSegment(List<FlSpot> target, double start, double end, double y) {
  if (end <= start) {
    return;
  }
  if (target.isNotEmpty) {
    target.add(FlSpot.nullSpot);
  }
  target
    ..add(FlSpot(start, y))
    ..add(FlSpot(end, y));
}

void _appendPolyline(
  Map<bool, List<FlSpot>> target,
  bool selected,
  List<FlSpot> spots,
) {
  final group = target.putIfAbsent(selected, () => <FlSpot>[]);
  if (group.isNotEmpty) {
    group.add(FlSpot.nullSpot);
  }
  group.addAll(spots);
}

/// Re-applies the established effort-kind texture over the fl_chart bands.
///
/// fl_chart has no pattern fills, and the two amber kinds would otherwise be
/// told apart by hue alone; the same seven-pixel hatch the old painter used is
/// redrawn over the exact band rectangles, so classification never depends on
/// colour (DESIGN.md). The overlay is pointer-transparent and decorative only.
class _GrowthTexturePainter extends CustomPainter {
  const _GrowthTexturePainter({
    required this.tokens,
    required this.day,
    required this.width,
    required this.scale,
  });

  final PlannerTokens tokens;
  final CalendarDayData day;
  final double width;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = width > 0 ? width : size.width;
    final unit = scale > 0 ? plotWidth / scale : 0.0;
    if (unit <= 0) return;
    for (var index = 0; index < day.items.length; index++) {
      final top =
          _minuteAxisHeight + index * _growthRowHeight + _growthEffortInset;
      var left = 0.0;
      for (final effort in day.items[index].efforts) {
        final runWidth = effort.minutes * unit;
        if (effort.kind != CalendarEffortKind.scheduled && runWidth > 0) {
          _paintEffortTexture(
            canvas,
            Rect.fromLTWH(left, top, runWidth, _growthEffortRunHeight),
            effort.kind,
            tokens.surface,
          );
        }
        left += runWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GrowthTexturePainter oldDelegate) =>
      tokens != oldDelegate.tokens ||
      day != oldDelegate.day ||
      width != oldDelegate.width ||
      scale != oldDelegate.scale;
}

/// Re-applies the effort-kind texture on the actual river bank, using the same
/// pixel mapping as the LineChart below it.
class _RiverTexturePainter extends CustomPainter {
  const _RiverTexturePainter({
    required this.tokens,
    required this.day,
    required this.width,
    required this.scale,
    required this.topBand,
  });

  final PlannerTokens tokens;
  final CalendarDayData day;
  final double width;
  final double scale;
  final double topBand;

  @override
  void paint(Canvas canvas, Size size) {
    final plotWidth = width > 0 ? width : size.width;
    final unit = scale > 0 ? plotWidth / scale : 0.0;
    if (unit <= 0) return;
    final top = topBand + _riverActualTop;
    final height = _riverActualBottom - _riverActualTop;
    var left = 0.0;
    for (final item in day.items) {
      for (final effort in item.efforts) {
        final runWidth = effort.minutes * unit;
        if (effort.kind != CalendarEffortKind.scheduled && runWidth > 0) {
          _paintEffortTexture(
            canvas,
            Rect.fromLTWH(left, top, runWidth, height),
            effort.kind,
            tokens.surface,
          );
        }
        left += runWidth;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RiverTexturePainter oldDelegate) =>
      tokens != oldDelegate.tokens ||
      day != oldDelegate.day ||
      width != oldDelegate.width ||
      scale != oldDelegate.scale ||
      topBand != oldDelegate.topBand;
}

/// White diagonal / dot texture of one recorded-effort run, clipped to its
/// band: extra and unscheduled are mirrored hatches, legacy rows are dots.
void _paintEffortTexture(
  Canvas canvas,
  Rect rect,
  CalendarEffortKind kind,
  Color patternColor,
) {
  if (rect.isEmpty) return;
  final paint = Paint()
    ..color = patternColor.withValues(alpha: .68)
    ..strokeWidth = 1.15;
  canvas.save();
  canvas.clipRect(rect);
  if (kind == CalendarEffortKind.legacyUnknown) {
    for (var y = rect.top + 2; y < rect.bottom; y += 5) {
      for (var x = rect.left + 2; x < rect.right; x += 5) {
        canvas.drawCircle(Offset(x, y), .85, paint);
      }
    }
  } else {
    final reverse = kind == CalendarEffortKind.unscheduled;
    for (
      var x = rect.left - rect.height;
      x < rect.right + rect.height;
      x += 7
    ) {
      canvas.drawLine(
        Offset(x, reverse ? rect.top : rect.bottom),
        Offset(x + rect.height, reverse ? rect.bottom : rect.top),
        paint,
      );
    }
  }
  canvas.restore();
}

/// The first day graphic: one shared fl_chart LineChart draws every owner's
/// planned reference band and recorded effort run as a horizontal lane, while
/// the labels stay real widgets next to their row.
class _GrowthChart extends StatelessWidget {
  const _GrowthChart({
    required this.day,
    required this.selectedId,
    required this.onSelect,
  });

  final CalendarDayData day;
  final String? selectedId;
  final ValueChanged<CalendarDayItem> onSelect;

  CalendarDayItem? _hit(Offset point) {
    final dy = point.dy - _minuteAxisHeight;
    if (dy < 0) return null;
    final index = dy ~/ _growthRowHeight;
    if (index >= day.items.length) return null;
    return day.items[index];
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final items = day.items;
      final tokens = context.tokens;
      if (items.isEmpty) return const SizedBox.shrink();
      final rowsHeight = items.length * _growthRowHeight;
      final plotWidth = math.max(0.0, constraints.maxWidth - _growthLabelWidth);
      final selectedIndex = selectedId == null
          ? -1
          : items.indexWhere((item) => item.id == selectedId);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _growthLabelWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: _minuteAxisHeight),
                for (final item in items)
                  SizedBox(
                    height: _growthRowHeight,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _ChartItemLabel(
                        item: item,
                        compact: true,
                        onSelect: () => onSelect(item),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SizedBox(
              height: _minuteAxisHeight + rowsHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _InteractiveGraphic(
                      height: _minuteAxisHeight + rowsHeight,
                      hit: (point, size) => _hit(point),
                      onSelect: onSelect,
                      // W7: isolate the static chart canvas from hover overlays.
                      child: RepaintBoundary(
                        child: LineChart(
                          _growthChartData(
                            tokens: tokens,
                            day: day,
                            width: plotWidth,
                          ),
                          duration: Duration.zero,
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _GrowthTexturePainter(
                          tokens: tokens,
                          day: day,
                          width: plotWidth,
                          scale: day.scaleMinutes > 0 ? day.scaleMinutes : 1.0,
                        ),
                      ),
                    ),
                  ),
                  if (selectedIndex >= 0)
                    Positioned(
                      left: 0,
                      right: 0,
                      top:
                          _minuteAxisHeight +
                          selectedIndex * _growthRowHeight +
                          2,
                      height: _growthRowHeight - 4,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(color: tokens.accent, width: 2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}

LineChartData _growthChartData({
  required PlannerTokens tokens,
  required CalendarDayData day,
  required double width,
}) {
  final items = day.items;
  final rowsHeight = items.length * _growthRowHeight;
  final scale = day.scaleMinutes > 0 ? day.scaleMinutes : 1.0;
  final planBands = <FlSpot>[];
  final planEdges = <FlSpot>[];
  final effortBands = <Color, List<FlSpot>>{};
  final rowRules = <HorizontalLine>[];
  for (var index = 0; index < items.length; index++) {
    final item = items[index];
    final base = (items.length - 1 - index) * _growthRowHeight;
    rowRules.add(
      HorizontalLine(
        y: base,
        color: tokens.border.withValues(alpha: .7),
        strokeWidth: 1,
      ),
    );
    if (item.plannedMinutes > 0) {
      _appendSegment(
        planBands,
        0,
        item.plannedMinutes.toDouble(),
        base + _growthRowHeight / 2,
      );
      _appendSegment(
        planEdges,
        0,
        item.plannedMinutes.toDouble(),
        base + _growthRowHeight - _growthPlanInset,
      );
    }
    var left = 0.0;
    for (final effort in item.efforts) {
      final end = left + effort.minutes;
      if (effort.minutes > 0) {
        final band = effortBands.putIfAbsent(
          _effortColor(tokens, effort.kind),
          () => <FlSpot>[],
        );
        _appendSegment(band, left, end, base + _growthRowHeight / 2);
      }
      left = end;
    }
  }
  final lines = <LineChartBarData>[
    if (planBands.isNotEmpty)
      _bandLine(
        planBands,
        _planFill(tokens),
        _growthRowHeight - _growthPlanInset * 2,
      ),
    if (planEdges.isNotEmpty)
      _strokeLine(planEdges, tokens.accent.withValues(alpha: .45), 1),
    for (final entry in effortBands.entries)
      _bandLine(entry.value, entry.key, _growthEffortRunHeight),
  ];
  return LineChartData(
    minX: 0,
    maxX: scale,
    minY: 0,
    maxY: rowsHeight,
    lineBarsData: lines,
    titlesData: FlTitlesData(
      show: true,
      topTitles: AxisTitles(
        sideTitles: _minuteSideTitles(tokens, scale: scale, width: width),
      ),
      leftTitles: const AxisTitles(sideTitles: _hiddenSideTitles),
      rightTitles: const AxisTitles(sideTitles: _hiddenSideTitles),
      bottomTitles: const AxisTitles(sideTitles: _hiddenSideTitles),
    ),
    gridData: const FlGridData(show: false),
    borderData: FlBorderData(show: false),
    clipData: const FlClipData.none(),
    lineTouchData: const LineTouchData(enabled: false),
    extraLinesData: ExtraLinesData(
      horizontalLines: rowRules,
      extraLinesOnTop: false,
    ),
  );
}

/// The second day graphic: one fl_chart LineChart draws both river banks, the
/// scheduled ribbons between them and the callout leaders, while the real item
/// label widgets stay positioned by the shared river label layout.
class _RiverChart extends StatelessWidget {
  const _RiverChart({
    required this.day,
    required this.selectedId,
    required this.onSelect,
  });

  final CalendarDayData day;
  final String? selectedId;
  final ValueChanged<CalendarDayItem> onSelect;

  CalendarDayItem? _hit(Offset point, Size size, double topBand) {
    final graphicY = point.dy - topBand;
    if (graphicY < 0 || graphicY > _riverGraphicHeight) return null;
    final planned = graphicY < 120;
    final minutes = size.width <= 0
        ? 0.0
        : point.dx / size.width * day.riverScaleMinutes;
    var sum = 0.0;
    CalendarDayItem? nearest;
    var distance = double.infinity;
    for (final item in day.items) {
      final amount = (planned ? item.plannedMinutes : item.actualMinutes)
          .toDouble();
      if (amount <= 0) continue;
      if (minutes >= sum && minutes <= sum + amount) return item;
      final middle = sum + amount / 2;
      final delta = (minutes - middle).abs();
      if (delta < distance) {
        nearest = item;
        distance = delta;
      }
      sum += amount;
    }
    return nearest;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final tokens = context.tokens;
      final layout = _riverLabelLayout(day, width);
      final specs = _riverLabelSpecs(tokens, day, width, layout);
      final stackHeight =
          _riverGraphicHeight + layout.topBand + layout.bottomBand;
      final chartHeight = stackHeight + _minuteAxisHeight;
      return SizedBox(
        width: width,
        height: chartHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: _InteractiveGraphic(
                height: chartHeight,
                hit: (point, size) => _hit(point, size, layout.topBand),
                onSelect: onSelect,
                // W7: isolate the static chart canvas from hover overlays.
                child: RepaintBoundary(
                  child: LineChart(
                    _riverChartData(
                      tokens: tokens,
                      day: day,
                      specs: specs,
                      selectedId: selectedId,
                      width: width,
                      topBand: layout.topBand,
                      stackHeight: stackHeight,
                    ),
                    duration: Duration.zero,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _RiverTexturePainter(
                    tokens: tokens,
                    day: day,
                    width: width,
                    scale: day.riverScaleMinutes > 0
                        ? day.riverScaleMinutes
                        : 1.0,
                    topBand: layout.topBand,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: layout.topBand + 25,
              child: _riverCaption('计划', tokens),
            ),
            Positioned(
              left: 0,
              top: layout.topBand + 143,
              child: _riverCaption('实学', tokens),
            ),
            if (day.plannedMinutes == 0)
              Positioned(
                left: 0,
                top: layout.topBand + 52,
                child: _riverCaption('无当日计划', tokens, color: tokens.muted),
              ),
            if (day.actualMinutes == 0)
              Positioned(
                left: 0,
                top: layout.topBand + 170,
                child: _riverCaption('尚无学习记录', tokens, color: tokens.muted),
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
      );
    },
  );
}

Widget _riverCaption(String text, PlannerTokens tokens, {Color? color}) =>
    IgnorePointer(
      child: ExcludeSemantics(
        child: Text(
          text,
          style: tabularFigures.copyWith(
            fontSize: 11,
            color: color ?? tokens.subtle,
          ),
        ),
      ),
    );

LineChartData _riverChartData({
  required PlannerTokens tokens,
  required CalendarDayData day,
  required List<_RiverLabelSpec> specs,
  required String? selectedId,
  required double width,
  required double topBand,
  required double stackHeight,
}) {
  final scale = day.riverScaleMinutes > 0 ? day.riverScaleMinutes : 1.0;
  final gap = width <= 0 ? 0.0 : 0.6 * scale / width;
  double chartY(double canvasY) => stackHeight - canvasY;
  final plannedTop = chartY(topBand + _riverPlannedTop);
  final plannedBottom = chartY(topBand + _riverPlannedBottom);
  final plannedCenter = chartY(
    topBand + (_riverPlannedTop + _riverPlannedBottom) / 2,
  );
  final actualCenter = chartY(
    topBand + (_riverActualTop + _riverActualBottom) / 2,
  );
  final planLefts = <double>[];
  final actualLefts = <double>[];
  var planLeft = 0.0;
  var actualLeft = 0.0;
  for (final item in day.items) {
    planLefts.add(planLeft);
    actualLefts.add(actualLeft);
    planLeft += item.plannedMinutes;
    actualLeft += item.actualMinutes;
  }

  final lines = <LineChartBarData>[];
  final between = <BetweenBarsData>[];

  // Ribbons: the old painter connected the planned bank to the actual bank
  // with two cubics; sampling both sides and filling between them keeps the
  // bend of the original ribbon without a custom painter.
  final ribbonLeft = <bool, List<FlSpot>>{};
  final ribbonRight = <bool, List<FlSpot>>{};
  const ribbonSamples = 12;
  for (var index = 0; index < day.items.length; index++) {
    final item = day.items[index];
    final original = math.min(item.scheduledMinutes, item.plannedMinutes);
    if (original <= 0) continue;
    final selected = item.id == selectedId;
    final left = <FlSpot>[];
    final right = <FlSpot>[];
    for (var step = 0; step <= ribbonSamples; step++) {
      final t = step / ribbonSamples;
      final y = chartY(
        _cubic(
          topBand + _riverPlannedBottom,
          topBand + _riverHandleY,
          topBand + _riverHandleY,
          topBand + _riverActualTop,
          t,
        ),
      );
      left.add(
        FlSpot(
          _cubic(
            planLefts[index],
            planLefts[index],
            actualLefts[index],
            actualLefts[index],
            t,
          ),
          y,
        ),
      );
      right.add(
        FlSpot(
          _cubic(
            planLefts[index] + original,
            planLefts[index] + original,
            actualLefts[index] + original,
            actualLefts[index] + original,
            t,
          ),
          y,
        ),
      );
    }
    _appendPolyline(ribbonLeft, selected, left);
    _appendPolyline(ribbonRight, selected, right);
  }
  for (final selected in const [false, true]) {
    final left = ribbonLeft[selected];
    final right = ribbonRight[selected];
    if (left == null || right == null || left.isEmpty) continue;
    final fromIndex = lines.length;
    lines.add(LineChartBarData(spots: left, show: false));
    final toIndex = lines.length;
    lines.add(LineChartBarData(spots: right, show: false));
    between.add(
      BetweenBarsData(
        fromIndex: fromIndex,
        toIndex: toIndex,
        color: tokens.accent.withValues(alpha: selected ? .16 : .07),
      ),
    );
  }

  final planBands = <FlSpot>[];
  final planEdges = <FlSpot>[];
  for (var index = 0; index < day.items.length; index++) {
    final item = day.items[index];
    if (item.plannedMinutes <= 0) continue;
    final localGap = math.min(gap, item.plannedMinutes * .1);
    final start = planLefts[index] + localGap;
    final end = planLefts[index] + item.plannedMinutes - localGap;
    _appendSegment(planBands, start, end, plannedCenter);
    _appendSegment(planEdges, start, end, plannedTop);
  }
  if (planBands.isNotEmpty) {
    lines.add(
      _bandLine(
        planBands,
        _planFill(tokens),
        _riverPlannedBottom - _riverPlannedTop,
      ),
    );
    lines.add(_strokeLine(planEdges, tokens.accent.withValues(alpha: .45), 1));
  }

  final effortBands = <Color, List<FlSpot>>{};
  for (var index = 0; index < day.items.length; index++) {
    var offset = actualLefts[index];
    for (final effort in day.items[index].efforts) {
      final end = offset + effort.minutes;
      if (effort.minutes > 0) {
        final band = effortBands.putIfAbsent(
          _effortColor(tokens, effort.kind),
          () => <FlSpot>[],
        );
        final localGap = math.min(gap, effort.minutes * .1);
        _appendSegment(band, offset + localGap, end - localGap, actualCenter);
      }
      offset = end;
    }
  }
  for (final entry in effortBands.entries) {
    lines.add(
      _bandLine(entry.value, entry.key, _riverActualBottom - _riverActualTop),
    );
  }

  final selectedIndex = selectedId == null
      ? -1
      : day.items.indexWhere((item) => item.id == selectedId);
  if (selectedIndex >= 0) {
    final item = day.items[selectedIndex];
    final outline = <FlSpot>[];
    void addOutline(double left, double right, double top, double bottom) {
      if (outline.isNotEmpty) {
        outline.add(FlSpot.nullSpot);
      }
      outline
        ..add(FlSpot(left, top))
        ..add(FlSpot(right, top))
        ..add(FlSpot(right, bottom))
        ..add(FlSpot(left, bottom))
        ..add(FlSpot(left, top));
    }

    if (item.plannedMinutes > 0) {
      addOutline(
        planLefts[selectedIndex],
        planLefts[selectedIndex] + item.plannedMinutes,
        plannedTop,
        plannedBottom,
      );
    }
    if (item.actualMinutes > 0) {
      addOutline(
        actualLefts[selectedIndex],
        actualLefts[selectedIndex] + item.actualMinutes,
        chartY(topBand + _riverActualTop - 3),
        chartY(topBand + _riverActualBottom + 6),
      );
    }
    if (outline.isNotEmpty) {
      lines.add(_strokeLine(outline, tokens.accent, 2));
    }
  }

  final leaderGroups = <Color, List<FlSpot>>{};
  for (final spec in specs) {
    if (!spec.callout) continue;
    final color = _itemAccent(tokens, spec.item).withValues(alpha: .45);
    final labelX = spec.left + spec.width / 2;
    final labelY = spec.lane == _RiverLabelLane.planned
        ? spec.top + spec.height
        : spec.top;
    final segmentX = spec.segmentCenter;
    final segmentY =
        spec.segmentTop + (spec.lane == _RiverLabelLane.planned ? 0 : 28);
    final bend = segmentY + (spec.lane == _RiverLabelLane.planned ? -7 : 7);
    final group = leaderGroups.putIfAbsent(color, () => <FlSpot>[]);
    if (group.isNotEmpty) {
      group.add(FlSpot.nullSpot);
    }
    group
      ..add(FlSpot(labelX, chartY(labelY)))
      ..add(FlSpot(labelX, chartY(bend)))
      ..add(FlSpot(segmentX, chartY(bend)))
      ..add(FlSpot(segmentX, chartY(segmentY)));
  }
  for (final entry in leaderGroups.entries) {
    lines.add(_strokeLine(entry.value, entry.key, 1));
  }

  return LineChartData(
    minX: 0,
    maxX: scale,
    minY: 0,
    maxY: stackHeight > 0 ? stackHeight : 1,
    lineBarsData: lines,
    betweenBarsData: between,
    titlesData: FlTitlesData(
      show: true,
      bottomTitles: AxisTitles(
        sideTitles: _minuteSideTitles(tokens, scale: scale, width: width),
      ),
      topTitles: const AxisTitles(sideTitles: _hiddenSideTitles),
      leftTitles: const AxisTitles(sideTitles: _hiddenSideTitles),
      rightTitles: const AxisTitles(sideTitles: _hiddenSideTitles),
    ),
    gridData: const FlGridData(show: false),
    borderData: FlBorderData(show: false),
    clipData: const FlClipData.none(),
    lineTouchData: const LineTouchData(enabled: false),
    extraLinesData: ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: chartY(topBand + _riverPlannedTop),
          color: tokens.border.withValues(alpha: .8),
          strokeWidth: 1,
        ),
        HorizontalLine(
          y: chartY(topBand + _riverActualBottom),
          color: tokens.border.withValues(alpha: .8),
          strokeWidth: 1,
        ),
      ],
      extraLinesOnTop: false,
    ),
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
  PlannerTokens tokens,
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
          foreground: _itemAccent(tokens, item),
          background: null,
        ),
      );
    }
    plannedLeft += plannedWidth;
    actualLeft += actualWidth;
  }
  return specs;
}

typedef _GraphicHit = CalendarDayItem? Function(Offset point, Size size);

/// Shared hover/tap surface for both day graphics. The chart itself is now a
/// real fl_chart widget, but the hit mapping, the hover tooltip and the
/// callback stay exactly the same as when it was a CustomPainter.
class _InteractiveGraphic extends StatefulWidget {
  const _InteractiveGraphic({
    required this.height,
    required this.hit,
    required this.onSelect,
    required this.child,
  });

  final double height;
  final _GraphicHit hit;
  final ValueChanged<CalendarDayItem> onSelect;
  final Widget child;

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
      return ExcludeSemantics(
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
                child: widget.child,
              ),
            ),
          ),
        ),
      );
    },
  );
}
