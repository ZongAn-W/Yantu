import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_view.dart';
import '../domain/calendar_week_data.dart';

/// Semantic colour of one week chart layer.
///
/// Planned reference is ink-blue, extra study is amber and the sample points
/// stay near-black. Item identity no longer drives a rainbow palette; the hatch
/// pattern (not only the colour) still separates the effort kinds.
Color _layerColor(PlannerTokens tokens, CalendarWeekLayer layer) =>
    switch (layer.kind) {
      CalendarEffortKind.scheduled => tokens.accent,
      CalendarEffortKind.extra => tokens.warning,
      CalendarEffortKind.unscheduled => tokens.warning,
      CalendarEffortKind.legacyUnknown => tokens.subtle,
    };

/// Accent of one owner row in the on-demand day detail.
Color _itemColor(PlannerTokens tokens, CalendarDayItem item) {
  if (item.plannedMinutes > 0 || item.scheduledMinutes > 0) {
    return tokens.accent;
  }
  if (item.actualMinutes > 0) return tokens.warning;
  return tokens.subtle;
}

/// The fill of a planned reference block.
Color _planFill(PlannerTokens tokens) =>
    tokens.isDark ? tokens.accent.withValues(alpha: 0.22) : tokens.accentSoft;

/// The hairline accent of a planned reference block.
Color _planStroke(PlannerTokens tokens) => tokens.accent.withValues(alpha: .38);

/// Shared placement of a single effort-kind mark inside a legend or row.
Color _kindColor(PlannerTokens tokens, CalendarEffortKind? kind) => kind == null
    ? tokens.accent
    : switch (kind) {
        CalendarEffortKind.scheduled => tokens.accent,
        CalendarEffortKind.extra => tokens.warning,
        CalendarEffortKind.unscheduled => tokens.warning,
        CalendarEffortKind.legacyUnknown => tokens.subtle,
      };

/// One read-only week graphic with compact legends and day details on demand.
///
/// Both [CalendarWeekView] values render this same widget with the same
/// [CalendarWeekData] instance; only the plotted graphic changes.
class CalendarWeekChart extends StatefulWidget {
  const CalendarWeekChart({
    required this.week,
    required this.view,
    required this.selectedDate,
    required this.onSelectDate,
    super.key,
  });

  final CalendarWeekData week;
  final CalendarWeekView view;
  final String selectedDate;
  final ValueChanged<String> onSelectDate;

  @override
  State<CalendarWeekChart> createState() => _CalendarWeekChartState();
}

class _CalendarWeekChartState extends State<CalendarWeekChart> {
  final _menu = MenuController();
  final _panel = GlobalKey();
  String? _hoveredDate;
  String? _inspectionDate;

  void _hover(String? date) {
    if (_menu.isOpen || _hoveredDate == date) return;
    setState(() => _hoveredDate = date);
  }

  void _select(String date) {
    Tooltip.dismissAllToolTips();
    setState(() {
      _hoveredDate = null;
      _inspectionDate = date;
    });
    widget.onSelectDate(date);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _panel.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final index = widget.week.days.indexWhere((day) => day.date == date);
      if (index < 0) return;
      _menu.open(
        position: Offset(
          12 +
              _WeekGeometry.axisWidth +
              (box.size.width - 24 - _WeekGeometry.axisWidth) /
                  7 *
                  (index + .5),
          box.size.height - 48,
        ),
      );
    });
  }

  @override
  void didUpdateWidget(covariant CalendarWeekChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.week.weekStart != widget.week.weekStart ||
        oldWidget.view != widget.view) {
      _menu.close();
      _hoveredDate = null;
      _inspectionDate = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final week = widget.week;
    final detail =
        week.dayFor(_inspectionDate ?? widget.selectedDate) ?? week.days.first;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final highlightDate = _hoveredDate ?? widget.selectedDate;
    final tokens = context.tokens;
    return MenuAnchor(
      key: const ValueKey('calendar-week-chart'),
      controller: _menu,
      consumeOutsideTap: false,
      menuChildren: _inspectionDate == null
          ? const []
          : [
              SizedBox(
                width: math.min(380, MediaQuery.sizeOf(context).width - 48),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * .6,
                  ),
                  child: SingleChildScrollView(
                    primary: false,
                    padding: const EdgeInsets.all(16),
                    child: _WeekDayDetail(
                      key: const ValueKey('calendar-week-detail'),
                      date: detail.date,
                      items: detail.day.items,
                      plannedMinutes: detail.plannedMinutes,
                      actualMinutes: detail.actualMinutes,
                    ),
                  ),
                ),
              ),
            ],
      child: PlannerPanel(
        key: _panel,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 22,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '周计划 ${duration(week.plannedMinutes)}',
                  key: const ValueKey('calendar-week-planned-total'),
                  style: tabularFigures.copyWith(
                    fontSize: 12.5,
                    color: tokens.muted,
                  ),
                ),
                Text(
                  '周实学 ${duration(week.actualMinutes)}',
                  key: const ValueKey('calendar-week-actual-total'),
                  style: tabularFigures.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _WeekLegend(week: week, view: widget.view),
            if (week.isEmpty)
              Padding(
                key: const ValueKey('calendar-week-empty'),
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '本周没有学习计划或学习记录',
                  style: TextStyle(fontSize: 12.5, color: tokens.muted),
                ),
              ),
            const SizedBox(height: 10),
            switch (widget.view) {
              CalendarWeekView.mirror => _MirrorChart(
                week: week,
                highlightDate: highlightDate,
                onHover: _hover,
                onSelect: _select,
              ),
              CalendarWeekView.mountain => _MountainChart(
                week: week,
                highlightDate: highlightDate,
                onHover: _hover,
                onSelect: _select,
              ),
            },
            const SizedBox(height: 4),
            _WeekDayAxis(
              week: week,
              selectedDate: widget.selectedDate,
              onSelect: _select,
              reduceMotion: reduceMotion,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekLegend extends StatelessWidget {
  const _WeekLegend({required this.week, required this.view});

  final CalendarWeekData week;
  final CalendarWeekView view;

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final kind in CalendarEffortKind.values)
        if ((week.minutesByKind[kind] ?? 0) > 0) kind,
    ];
    return Column(
      key: const ValueKey('calendar-week-legend'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _PlanLegendItem(view: view),
            _KindLegendItem(
              kind: CalendarEffortKind.scheduled,
              label: view == CalendarWeekView.mirror ? '实学 ↓' : '实学',
            ),
            if (kinds.any(
              (kind) =>
                  kind != CalendarEffortKind.scheduled &&
                  kind != CalendarEffortKind.legacyUnknown,
            ))
              const Tooltip(
                message: '计划外投入：已有事项加学、当天未排程的事项；具体分类可点选日期查看。',
                excludeFromSemantics: true,
                child: _KindLegendItem(
                  kind: CalendarEffortKind.extra,
                  label: '计划外',
                ),
              ),
            if (kinds.contains(CalendarEffortKind.legacyUnknown))
              const _KindLegendItem(
                kind: CalendarEffortKind.legacyUnknown,
                label: '历史',
              ),
          ],
        ),
      ],
    );
  }
}

class _PlanLegendItem extends StatelessWidget {
  const _PlanLegendItem({required this.view});

  final CalendarWeekView view;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          width: 14,
          height: 10,
          child: CustomPaint(
            key: const ValueKey('calendar-week-kind-planned'),
            painter: _PlanLegendPainter(context.tokens, view),
          ),
        ),
      ),
      const SizedBox(width: 5),
      Text(
        view == CalendarWeekView.mirror ? '计划 ↑' : '计划',
        style: TextStyle(
          fontSize: 11,
          height: 1.35,
          color: context.tokens.muted,
        ),
      ),
    ],
  );
}

class _PlanLegendPainter extends CustomPainter {
  const _PlanLegendPainter(this.tokens, this.view);

  final PlannerTokens tokens;
  final CalendarWeekView view;

  @override
  void paint(Canvas canvas, Size size) {
    if (view == CalendarWeekView.mirror) {
      final rect = Rect.fromLTWH(0, 0, size.width, size.height - 2);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2.5));
      canvas.drawRRect(rrect, Paint()..color = _planFill(tokens));
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _planStroke(tokens),
      );
    } else {
      _drawDashedPolyline(
        canvas,
        [Offset(0, size.height / 2), Offset(size.width, size.height / 2)],
        Paint()
          ..color = tokens.accent
          ..strokeWidth = 1.5,
        dash: 4,
        gap: 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlanLegendPainter oldDelegate) =>
      tokens != oldDelegate.tokens || view != oldDelegate.view;
}

class _KindLegendItem extends StatelessWidget {
  const _KindLegendItem({required this.kind, required this.label});

  final CalendarEffortKind? kind;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      ExcludeSemantics(
        child: SizedBox(
          width: 10,
          height: 10,
          child: CustomPaint(
            key: ValueKey('calendar-week-kind-${kind?.name ?? 'planned'}'),
            painter: _KindSwatchPainter(context.tokens, kind),
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

abstract final class _WeekGeometry {
  /// Left gutter that holds the minute ticks; the day axis rows reserve the
  /// same width so labels sit exactly under their chart columns.
  static const double axisWidth = 36;

  /// Gap between neighbouring day columns: the plot draws no vertical
  /// gridlines, so a small gutter keeps adjacent bars readable.
  static const double columnGutter = 6;

  /// Vertical breathing room of the plot. The hidden top/bottom axis name areas
  /// reserve exactly these sizes (fl_chart turns them into chart margin) and the
  /// texture overlays reuse them, so patterns stay on their bars.
  static const double topPad = 10;
  static const double bottomPad = 10;

  static int? dayIndexAt(Size size, Offset point) {
    final plotWidth = size.width - axisWidth;
    if (plotWidth <= 0 || point.dx < axisWidth) return null;
    final fraction = (point.dx - axisWidth) / plotWidth;
    return (fraction * 7).floor().clamp(0, 6);
  }
}

class _WeekGraphic extends StatefulWidget {
  const _WeekGraphic({
    required this.canvasKey,
    required this.week,
    required this.height,
    required this.chart,
    required this.semanticsLabel,
    required this.onHover,
    required this.onSelect,
  });

  final Key canvasKey;

  final CalendarWeekData week;
  final double height;

  /// The whole-week plot for the current chart mode. It is laid out inside the
  /// seven-column coordinate box that owns [canvasKey].
  final Widget chart;
  final String semanticsLabel;
  final ValueChanged<String?> onHover;
  final ValueChanged<String> onSelect;

  @override
  State<_WeekGraphic> createState() => _WeekGraphicState();
}

class _WeekGraphicState extends State<_WeekGraphic> {
  final _tooltip = GlobalKey<TooltipState>();
  int? _hoverIndex;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, widget.height);
      String? dateAt(Offset point) {
        final index = _WeekGeometry.dayIndexAt(size, point);
        if (index == null) return null;
        return widget.week.days[index].date;
      }

      // The painted plot owns pointer hit-testing only inside its own box. The
      // accessible day controls live in the separate date axis below, so no
      // transparent widget covers the graphic for keyboard/screen-reader users.
      return Tooltip(
        key: _tooltip,
        message: _hoverIndex == null
            ? ''
            : _dayHoverDescription(widget.week.days[_hoverIndex!]),
        triggerMode: TooltipTriggerMode.manual,
        excludeFromSemantics: true,
        constraints: BoxConstraints(
          maxWidth: math.min(380, MediaQuery.sizeOf(context).width - 32),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (event) {
            final index = _WeekGeometry.dayIndexAt(size, event.localPosition);
            if (_hoverIndex != index) {
              setState(() => _hoverIndex = index);
              widget.onHover(dateAt(event.localPosition));
            }
            if (index != null) {
              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _tooltip.currentState?.ensureTooltipVisible(),
              );
            }
          },
          onExit: (_) {
            Tooltip.dismissAllToolTips();
            if (_hoverIndex != null) setState(() => _hoverIndex = null);
            widget.onHover(null);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) {
              final date = dateAt(details.localPosition);
              if (date != null) widget.onSelect(date);
            },
            child: Semantics(
              container: true,
              label: widget.semanticsLabel,
              child: ExcludeSemantics(
                child: SizedBox(
                  key: widget.canvasKey,
                  width: size.width,
                  height: size.height,
                  child: widget.chart,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _MirrorChart extends StatelessWidget {
  const _MirrorChart({
    required this.week,
    required this.highlightDate,
    required this.onHover,
    required this.onSelect,
  });

  final CalendarWeekData week;
  final String highlightDate;
  final ValueChanged<String?> onHover;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxWidth < 360 ? 228.0 : 264.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '分钟',
            style: TextStyle(
              fontSize: 11,
              height: 1.3,
              color: context.tokens.subtle,
            ),
          ),
          const SizedBox(height: 2),
          _WeekGraphic(
            canvasKey: const ValueKey('calendar-week-mirror-canvas'),
            week: week,
            height: height,
            semanticsLabel: _mirrorSemantics(week),
            onHover: onHover,
            onSelect: onSelect,
            chart: _MirrorPlot(week: week, highlightDate: highlightDate),
          ),
        ],
      );
    },
  );
}

String _mirrorSemantics(CalendarWeekData week) =>
    '一周学习镜像图，横轴周一至周日，纵轴学习分钟。零基线以上为当天计划，'
    '以下为当天实际学习；实际学习向下但为正值，两个方向使用同一比例。'
    '本周计划 ${duration(week.plannedMinutes)}，本周实学 ${duration(week.actualMinutes)}。'
    '下方日期按钮可选择某天查看明细。';

/// The mirrored week plot.
///
/// fl_chart owns the shared zero baseline, the minute grid, the stacked
/// planned/actual bars, the highlighted day column and the minute labels; only
/// the effort-kind texture is layered on top as a decorative overlay.
class _MirrorPlot extends StatelessWidget {
  const _MirrorPlot({required this.week, required this.highlightDate});

  final CalendarWeekData week;
  final String highlightDate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 340;
      final scale = week.scaleMinutes;
      final tokens = context.tokens;
      final columnWidth =
          math.max(1.0, constraints.maxWidth - _WeekGeometry.axisWidth) / 7;
      final barWidth = math.max(2.0, columnWidth - _WeekGeometry.columnGutter);
      return Stack(
        fit: StackFit.expand,
        children: [
          // W7: isolate the static chart canvas from hover overlays.
          RepaintBoundary(
            child: BarChart(
              BarChartData(
                // Centering the seven equally wide groups with the same gutter
                // as the bars keeps every column centred under its date button.
                alignment: BarChartAlignment.center,
                groupsSpace: _WeekGeometry.columnGutter,
                barGroups: _mirrorBarGroups(tokens, week, barWidth),
                minY: -scale,
                maxY: scale,
                barTouchData: const BarTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: [
                    for (var index = 0; index < week.days.length; index++)
                      if (week.days[index].date == highlightDate)
                        VerticalRangeAnnotation(
                          x1: index / week.days.length,
                          x2: (index + 1) / week.days.length,
                          color: tokens.accentSoft.withValues(alpha: .55),
                        ),
                  ],
                ),
                gridData: _weekGrid(tokens, scale / 2, faintAlpha: .45),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    for (final y in [-scale, scale])
                      HorizontalLine(
                        y: y,
                        color: tokens.border.withValues(alpha: .45),
                        strokeWidth: 1,
                      ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: _minuteAxisTitles(
                    tokens,
                    interval: narrow ? scale : scale / 2,
                    mirror: true,
                  ),
                  topTitles: _edgePaddingTitles,
                  rightTitles: _noTitles,
                  bottomTitles: _edgePaddingTitles,
                ),
              ),
              duration: Duration.zero,
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _MirrorTexturePainter(week: week, tokens: tokens),
            ),
          ),
        ],
      );
    },
  );
}

List<BarChartGroupData> _mirrorBarGroups(
  PlannerTokens tokens,
  CalendarWeekData week,
  double barWidth,
) => [
  for (var index = 0; index < week.days.length; index++)
    BarChartGroupData(
      x: index,
      groupVertically: true,
      barRods: _mirrorRods(tokens, week.days[index], barWidth),
    ),
];

List<BarChartRodData> _mirrorRods(
  PlannerTokens tokens,
  CalendarWeekDay day,
  double barWidth,
) {
  const radius = BorderRadius.all(Radius.circular(2));
  // Planned reference: light segments stacked upward from the shared zero.
  final planned = <BarChartRodStackItem>[];
  var plannedTop = 0.0;
  for (final item in day.day.items) {
    if (item.plannedMinutes <= 0) continue;
    planned.add(
      BarChartRodStackItem(
        plannedTop,
        plannedTop + item.plannedMinutes,
        _planFill(tokens),
        borderSide: BorderSide(color: _planStroke(tokens), width: 1),
      ),
    );
    plannedTop += item.plannedMinutes;
  }
  // Actual study: positive minutes drawn downward, full over-plan amount.
  final actual = <BarChartRodStackItem>[];
  var actualBottom = 0.0;
  for (final item in day.day.items) {
    for (final effort in item.efforts) {
      if (effort.minutes <= 0) continue;
      actual.add(
        BarChartRodStackItem(
          -actualBottom,
          -(actualBottom + effort.minutes),
          _kindColor(tokens, effort.kind),
        ),
      );
      actualBottom += effort.minutes;
    }
  }
  // Every day keeps both rods, even at zero, because fl_chart derives the
  // seven column positions from the sum of the group widths.
  return [
    BarChartRodData(
      fromY: 0,
      toY: plannedTop,
      color: _planFill(tokens),
      width: barWidth,
      borderRadius: radius,
      borderSide: BorderSide(color: _planStroke(tokens), width: 1),
      rodStackItems: planned,
    ),
    BarChartRodData(
      fromY: 0,
      toY: -actualBottom,
      color: Colors.transparent,
      width: barWidth,
      borderRadius: radius,
      rodStackItems: actual,
    ),
  ];
}

/// Re-applies the established effort-kind texture language on top of the
/// fl_chart bars. fl_chart has no pattern fills, so the decorative hatch is
/// painted in exactly the same seven-column geometry as the chart below it.
class _MirrorTexturePainter extends CustomPainter {
  const _MirrorTexturePainter({required this.week, required this.tokens});

  final CalendarWeekData week;
  final PlannerTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _WeekGeometry.axisWidth;
    final plotWidth = math.max(1.0, size.width - plotLeft);
    final plotHeight = math.max(
      1.0,
      size.height - _WeekGeometry.topPad - _WeekGeometry.bottomPad,
    );
    final half = plotHeight / 2;
    final zeroY = _WeekGeometry.topPad + half;
    final unit = half / week.scaleMinutes;
    final columnWidth = plotWidth / 7;
    final barWidth = math.max(2.0, columnWidth - _WeekGeometry.columnGutter);
    for (var index = 0; index < week.days.length; index++) {
      final day = week.days[index];
      final left =
          plotLeft + columnWidth * index + (columnWidth - barWidth) / 2;
      var actualTop = zeroY;
      for (var itemIndex = 0; itemIndex < day.day.items.length; itemIndex++) {
        final item = day.day.items[itemIndex];
        var drewItem = false;
        for (final effort in item.efforts) {
          if (effort.minutes <= 0) continue;
          final height = effort.minutes * unit;
          if (effort.kind != CalendarEffortKind.scheduled) {
            final rect = Rect.fromLTWH(left, actualTop, barWidth, height);
            canvas.save();
            canvas.clipRect(rect);
            _drawKindPattern(
              canvas,
              rect,
              _kindColor(tokens, effort.kind),
              effort.kind,
              alpha: .42,
              patternColor: tokens.surface,
            );
            canvas.restore();
          }
          actualTop += height;
          drewItem = true;
        }
        // A hairline rule separates adjacent task rows so the object
        // attribution stays visible even when their colours match.
        if (drewItem &&
            itemIndex != day.day.items.length - 1 &&
            actualTop > zeroY) {
          canvas.drawLine(
            Offset(left, actualTop),
            Offset(left + barWidth, actualTop),
            Paint()
              ..color = tokens.surface.withValues(alpha: .75)
              ..strokeWidth = 1,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MirrorTexturePainter oldDelegate) =>
      week != oldDelegate.week || tokens != oldDelegate.tokens;
}

class _MountainChart extends StatelessWidget {
  const _MountainChart({
    required this.week,
    required this.highlightDate,
    required this.onHover,
    required this.onSelect,
  });

  final CalendarWeekData week;
  final String highlightDate;
  final ValueChanged<String?> onHover;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final height = constraints.maxWidth < 360 ? 228.0 : 264.0;
      return _WeekGraphic(
        canvasKey: const ValueKey('calendar-week-mountain-canvas'),
        week: week,
        height: height,
        semanticsLabel: _mountainSemantics(week),
        onHover: onHover,
        onSelect: onSelect,
        chart: _MountainPlot(week: week, highlightDate: highlightDate),
      );
    },
  );
}

String _mountainSemantics(CalendarWeekData week) =>
    '一周学习山脉图，横轴周一至周日，纵轴学习分钟。实学山形按投入类型分类'
    '固定顺序堆叠，高度为当天实际学习总量；虚线为当天计划总量，两者共用同一比例。'
    '本周计划 ${duration(week.plannedMinutes)}，本周实学 ${duration(week.actualMinutes)}。'
    '下方日期按钮可选择某天查看明细。';

/// The stacked "learning mountain" plot.
///
/// fl_chart owns the minute grid, the fixed-order stacked areas, the dashed
/// planned contour, the real daily sample points and the highlighted day
/// column; the texture overlay only adds the effort-kind pattern on top.
class _MountainPlot extends StatelessWidget {
  const _MountainPlot({required this.week, required this.highlightDate});

  final CalendarWeekData week;
  final String highlightDate;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final narrow = constraints.maxWidth < 340;
      final scale = week.scaleMinutes;
      final tokens = context.tokens;
      return Stack(
        fit: StackFit.expand,
        children: [
          // W7: isolate the static chart canvas from hover overlays.
          RepaintBoundary(
            child: LineChart(
              LineChartData(
                minX: -0.5,
                maxX: week.days.length - 0.5,
                minY: 0,
                maxY: scale,
                lineBarsData: _mountainLines(tokens, week),
                lineTouchData: const LineTouchData(enabled: false),
                borderData: FlBorderData(show: false),
                rangeAnnotations: RangeAnnotations(
                  verticalRangeAnnotations: [
                    for (var index = 0; index < week.days.length; index++)
                      if (week.days[index].date == highlightDate)
                        VerticalRangeAnnotation(
                          x1: index - 0.5,
                          x2: index + 0.5,
                          color: tokens.accentSoft.withValues(alpha: .45),
                        ),
                  ],
                ),
                gridData: _weekGrid(tokens, scale / 4, faintAlpha: .4),
                extraLinesData: ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: tokens.borderStrong,
                      strokeWidth: 1,
                    ),
                    HorizontalLine(
                      y: scale,
                      color: tokens.border.withValues(alpha: .4),
                      strokeWidth: 1,
                    ),
                  ],
                ),
                titlesData: FlTitlesData(
                  leftTitles: _minuteAxisTitles(
                    tokens,
                    interval: narrow ? scale : scale / 2,
                  ),
                  topTitles: _edgePaddingTitles,
                  rightTitles: _noTitles,
                  bottomTitles: _edgePaddingTitles,
                ),
              ),
              duration: Duration.zero,
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _MountainTexturePainter(week: week, tokens: tokens),
            ),
          ),
        ],
      );
    },
  );
}

/// One fixed-order stacked actual-learning band of the mountain plot.
class _WeekBand {
  const _WeekBand({
    required this.layer,
    required this.bottom,
    required this.top,
  });

  final CalendarWeekLayer layer;

  /// Cumulative minutes of every lower layer, per day.
  final List<double> bottom;

  /// [bottom] plus this layer's minutes, per day.
  final List<double> top;
}

List<_WeekBand> _weekBands(CalendarWeekData week) {
  final count = week.days.length;
  final cumulative = List<double>.filled(count, 0);
  final bands = <_WeekBand>[];
  for (final layer in week.layers) {
    final top = <double>[
      for (var index = 0; index < count; index++)
        cumulative[index] + layer.minutesOn(index),
    ];
    bands.add(
      _WeekBand(
        layer: layer,
        bottom: List<double>.unmodifiable(cumulative),
        top: List<double>.unmodifiable(top),
      ),
    );
    for (var index = 0; index < count; index++) {
      cumulative[index] = top[index];
    }
  }
  return bands;
}

List<LineChartBarData> _mountainLines(
  PlannerTokens tokens,
  CalendarWeekData week,
) {
  final bands = _weekBands(week);
  return [
    // Paint the topmost stacked boundary first: every lower band then covers
    // the shared baseline area underneath it, leaving exactly its own thickness.
    for (var index = bands.length - 1; index >= 0; index--)
      _bandLine(tokens, bands[index], week.days.length),
    // The plan is a separate dashed total contour on the same vertical scale;
    // it is never filled, so no area claims original-plan achievement.
    _planLine(tokens, week),
    // Real daily samples: solid dots on studied days, hollow zero dots otherwise.
    _sampleDotsLine(tokens, week),
    _sampleDotCentersLine(tokens, week),
  ];
}

LineChartBarData _bandLine(
  PlannerTokens tokens,
  _WeekBand band,
  int dayCount,
) => LineChartBarData(
  spots: [
    for (var index = 0; index < dayCount; index++)
      FlSpot(index.toDouble(), band.top[index]),
  ],
  color: Colors.transparent,
  barWidth: 0,
  belowBarData: BarAreaData(
    show: true,
    color: _layerColor(tokens, band.layer).withValues(alpha: .88),
  ),
  dotData: const FlDotData(show: false),
);

LineChartBarData _planLine(PlannerTokens tokens, CalendarWeekData week) =>
    LineChartBarData(
      spots: [
        for (var index = 0; index < week.days.length; index++)
          FlSpot(index.toDouble(), week.days[index].plannedMinutes.toDouble()),
      ],
      color: tokens.accent,
      barWidth: 1.6,
      dashArray: const [6, 4],
      dotData: const FlDotData(show: false),
    );

LineChartBarData _sampleDotsLine(PlannerTokens tokens, CalendarWeekData week) =>
    LineChartBarData(
      spots: [
        for (var index = 0; index < week.days.length; index++)
          FlSpot(index.toDouble(), week.days[index].actualMinutes.toDouble()),
      ],
      color: Colors.transparent,
      barWidth: 0,
      dotData: FlDotData(
        getDotPainter: (spot, percent, bar, index) => spot.y > 0
            ? FlDotCirclePainter(color: tokens.accent, radius: 3)
            : FlDotCirclePainter(
                color: Colors.transparent,
                radius: 2,
                strokeWidth: 1,
                strokeColor: tokens.subtle.withValues(alpha: .8),
              ),
      ),
    );

LineChartBarData _sampleDotCentersLine(
  PlannerTokens tokens,
  CalendarWeekData week,
) => LineChartBarData(
  spots: [
    for (var index = 0; index < week.days.length; index++)
      FlSpot(index.toDouble(), week.days[index].actualMinutes.toDouble()),
  ],
  color: Colors.transparent,
  barWidth: 0,
  dotData: FlDotData(
    checkToShowDot: (spot, bar) => spot.y > 0,
    getDotPainter: (spot, percent, bar, index) =>
        FlDotCirclePainter(color: tokens.accentOn, radius: 1.2),
  ),
);

/// Re-applies the effort-kind texture on the stacked bands. The band polygons
/// are the same seven-sample polylines the LineChart fills, so the pattern can
/// never drift away from the area it belongs to.
class _MountainTexturePainter extends CustomPainter {
  const _MountainTexturePainter({required this.week, required this.tokens});

  final CalendarWeekData week;
  final PlannerTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _WeekGeometry.axisWidth;
    final plotWidth = math.max(1.0, size.width - plotLeft);
    final plotHeight = math.max(
      1.0,
      size.height - _WeekGeometry.topPad - _WeekGeometry.bottomPad,
    );
    final baselineY = _WeekGeometry.topPad + plotHeight;
    final unit = plotHeight / week.scaleMinutes;
    final columnWidth = plotWidth / 7;
    for (final band in _weekBands(week)) {
      if (band.layer.kind == CalendarEffortKind.scheduled) continue;
      final path = Path();
      for (var index = 0; index < week.days.length; index++) {
        final x = plotLeft + columnWidth * (index + 0.5);
        final y = baselineY - band.top[index] * unit;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      for (var index = week.days.length - 1; index >= 0; index--) {
        path.lineTo(
          plotLeft + columnWidth * (index + 0.5),
          baselineY - band.bottom[index] * unit,
        );
      }
      path.close();
      canvas.save();
      canvas.clipPath(path);
      _drawKindPattern(
        canvas,
        path.getBounds(),
        _layerColor(tokens, band.layer),
        band.layer.kind,
        alpha: .5,
        patternColor: tokens.surface,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _MountainTexturePainter oldDelegate) =>
      week != oldDelegate.week || tokens != oldDelegate.tokens;
}

/// Hidden axis titles used to turn the fl_chart title margins into plot
/// padding: the top/bottom sides reserve the plot's vertical breathing room
/// through an empty axis name, the other sides reserve nothing. The visible
/// minute labels then stay centred on their gridline instead of being clipped
/// at the canvas edge.
const _edgePaddingTitles = AxisTitles(
  axisNameWidget: SizedBox.shrink(),
  axisNameSize: _WeekGeometry.topPad,
  sideTitles: SideTitles(showTitles: false, reservedSize: 0),
);
const _noTitles = AxisTitles(
  sideTitles: SideTitles(showTitles: false, reservedSize: 0),
);

/// Minute ticks in the left gutter: 11 px tabular digits in the subtle ink.
AxisTitles _minuteAxisTitles(
  PlannerTokens tokens, {
  required double interval,
  bool mirror = false,
}) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: _WeekGeometry.axisWidth,
    interval: interval,
    getTitlesWidget: (value, meta) =>
        _minuteLabel(tokens, mirror ? value.abs() : value),
  ),
);

Widget _minuteLabel(PlannerTokens tokens, double minutes) => Align(
  alignment: Alignment.center,
  child: Text(
    _minuteText(minutes),
    style: tabularFigures.copyWith(fontSize: 11, color: tokens.subtle),
  ),
);

/// Horizontal hairlines only: a calendar plot with vertical rules reads like a
/// spreadsheet, so the seven columns stay implied by the bars and the date axis.
FlGridData _weekGrid(
  PlannerTokens tokens,
  double interval, {
  required double faintAlpha,
}) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (value) => FlLine(
    color: value.abs() < .001
        ? tokens.borderStrong
        : tokens.border.withValues(alpha: faintAlpha),
    strokeWidth: 1,
  ),
);

class _WeekDayAxis extends StatelessWidget {
  const _WeekDayAxis({
    required this.week,
    required this.selectedDate,
    required this.onSelect,
    required this.reduceMotion,
  });

  final CalendarWeekData week;
  final String selectedDate;
  final ValueChanged<String> onSelect;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) => Row(
    key: const ValueKey('calendar-week-axis'),
    children: [
      const SizedBox(width: _WeekGeometry.axisWidth),
      for (final day in week.days)
        Expanded(
          child: _WeekDayButton(
            day: day,
            selected: day.date == selectedDate,
            onSelect: () => onSelect(day.date),
            reduceMotion: reduceMotion,
          ),
        ),
    ],
  );
}

class _WeekDayButton extends StatelessWidget {
  const _WeekDayButton({
    required this.day,
    required this.selected,
    required this.onSelect,
    required this.reduceMotion,
  });

  final CalendarWeekDay day;
  final bool selected;
  final VoidCallback onSelect;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final description = _dayDescription(day);
    final isToday = day.date == shanghaiToday();
    final tokens = context.tokens;
    return Semantics(
      key: ValueKey('calendar-week-day-${day.date}'),
      button: true,
      selected: selected,
      label: description,
      hint: '查看当天明细',
      excludeSemantics: true,
      onTap: onSelect,
      child: Tooltip(
        message: _dayHoverDescription(day),
        constraints: BoxConstraints(
          maxWidth: math.min(380, MediaQuery.sizeOf(context).width - 32),
        ),
        excludeFromSemantics: true,
        child: InkWell(
          onTap: onSelect,
          borderRadius: BorderRadius.circular(8),
          splashFactory: reduceMotion ? NoSplash.splashFactory : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 1),
            decoration: BoxDecoration(
              color: selected ? tokens.accentSoft : null,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected ? tokens.accent : Colors.transparent,
                width: 2,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weekdayLabel(day.date),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? tokens.accent : tokens.subtle,
                  ),
                ),
                const SizedBox(height: 1),
                if (isToday)
                  Container(
                    width: 24,
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      day.date.substring(8, 10),
                      maxLines: 1,
                      style: tabularFigures.copyWith(
                        fontSize: 11.5,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: tokens.accentOn,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 24,
                    child: Center(
                      child: Text(
                        day.date.substring(8, 10),
                        maxLines: 1,
                        style: tabularFigures.copyWith(
                          fontSize: 12.5,
                          height: 1.3,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected ? tokens.accent : tokens.text,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _dayDescription(CalendarWeekDay day) {
  final kinds = <String>[
    for (final item in day.day.items)
      for (final effort in item.efforts)
        '${effort.kind.label} ${duration(effort.minutes)}',
  ];
  return '${fullDateLabel(day.date)}，计划 ${duration(day.plannedMinutes)}，'
      '实学 ${duration(day.actualMinutes)}'
      '${kinds.isEmpty ? '，尚无学习记录' : '，${kinds.join('，')}'}';
}

String _dayHoverDescription(CalendarWeekDay day) {
  final items = day.day.items;
  return [
    '${fullDateLabel(day.date)} · 计划 ${duration(day.plannedMinutes)} · 实学 ${duration(day.actualMinutes)}',
    for (final item in items.take(3)) _itemDescription(item),
    if (items.length > 3) '另有 ${items.length - 3} 项，点击日期查看全部',
    if (items.isEmpty) '当天没有学习计划或学习记录',
  ].join('\n');
}

class _WeekDayDetail extends StatelessWidget {
  const _WeekDayDetail({
    required this.date,
    required this.items,
    required this.plannedMinutes,
    required this.actualMinutes,
    super.key,
  });

  final String date;
  final List<CalendarDayItem> items;
  final int plannedMinutes;
  final int actualMinutes;

  @override
  Widget build(BuildContext context) {
    final kinds = <CalendarEffortKind, int>{};
    final tokens = context.tokens;
    for (final item in items) {
      for (final effort in item.efforts) {
        kinds[effort.kind] = (kinds[effort.kind] ?? 0) + effort.minutes;
      }
    }
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              fullDateLabel(date),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              '当天没有学习计划或学习记录',
              key: const ValueKey('calendar-week-detail-empty'),
              style: TextStyle(fontSize: 12, color: tokens.muted),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: [
            Text(
              fullDateLabel(date),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
            Text(
              '计划 ${duration(plannedMinutes)} · 实学 ${duration(actualMinutes)}',
              key: const ValueKey('calendar-week-detail-totals'),
              style: tabularFigures.copyWith(fontSize: 12, color: tokens.muted),
            ),
          ],
        ),
        if (kinds.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final kind in CalendarEffortKind.values)
                if ((kinds[kind] ?? 0) > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: SizedBox(
                          width: 10,
                          height: 10,
                          child: CustomPaint(
                            painter: _KindSwatchPainter(tokens, kind),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${kind.label} ${duration(kinds[kind]!)}',
                        style: tabularFigures.copyWith(
                          fontSize: 11,
                          color: tokens.muted,
                        ),
                      ),
                    ],
                  ),
            ],
          ),
        ],
        const SizedBox(height: 2),
        for (var index = 0; index < items.length; index++)
          _WeekItemRow(item: items[index], number: index + 1),
      ],
    );
  }
}

class _WeekItemRow extends StatelessWidget {
  const _WeekItemRow({required this.item, required this.number});

  final CalendarDayItem item;
  final int number;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = _itemColor(tokens, item);
    return Semantics(
      label: _itemDescription(item),
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(
                '$number',
                textAlign: TextAlign.center,
                style: tabularFigures.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5, right: 6),
                        child: DecoratedBox(
                          key: ValueKey('calendar-week-item-color-${item.id}'),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                          child: const SizedBox.square(dimension: 7),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${item.tagNames.isEmpty ? '未标记' : item.tagNames.join(' · ')} · '
                    '计划 ${duration(item.plannedMinutes)} · '
                    '实学 ${duration(item.actualMinutes)}',
                    style: tabularFigures.copyWith(
                      fontSize: 11,
                      color: tokens.muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (item.efforts.isEmpty)
                        Text(
                          '尚无学习记录',
                          style: TextStyle(fontSize: 11, color: tokens.muted),
                        ),
                      for (final effort in item.efforts)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: SizedBox(
                                width: 10,
                                height: 10,
                                child: CustomPaint(
                                  painter: _KindSwatchPainter(
                                    tokens,
                                    effort.kind,
                                    color: color,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${effort.kind.label} ${duration(effort.minutes)}',
                              style: tabularFigures.copyWith(
                                fontSize: 11,
                                color: tokens.muted,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _itemDescription(CalendarDayItem item) =>
    '${item.title}${item.tagNames.isEmpty ? '' : '，标签 ${item.tagNames.join('、')}'}，计划 ${duration(item.plannedMinutes)}，'
    '实学 ${duration(item.actualMinutes)}。'
    '${item.efforts.isEmpty ? '尚无学习记录' : item.efforts.map((effort) => '${effort.kind.label} ${duration(effort.minutes)}').join('，')}';

class _KindSwatchPainter extends CustomPainter {
  const _KindSwatchPainter(this.tokens, this.kind, {this.color});

  final PlannerTokens tokens;
  final CalendarEffortKind? kind;
  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final fill = _kindColor(tokens, kind);
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
    if (kind == null) {
      canvas.drawRRect(rrect, Paint()..color = _planFill(tokens));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = _planStroke(tokens)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
      return;
    }
    canvas.drawRRect(rrect, Paint()..color = fill);
    if (kind != CalendarEffortKind.scheduled) {
      canvas.save();
      canvas.clipRRect(rrect);
      _drawKindPattern(canvas, rect, fill, kind!, patternColor: tokens.surface);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KindSwatchPainter oldDelegate) =>
      tokens != oldDelegate.tokens ||
      kind != oldDelegate.kind ||
      color != oldDelegate.color;
}

/// Shared texture language for non-original-plan effort kinds.
///
/// The same patterns are used by the legends, the mirror segments and the
/// mountain areas, so classification never depends on colour alone.
void _drawKindPattern(
  Canvas canvas,
  Rect rect,
  Color color,
  CalendarEffortKind kind, {
  required Color patternColor,
  double alpha = .42,
}) {
  final paint = Paint()
    ..color = patternColor.withValues(alpha: alpha)
    ..strokeWidth = 1.2;
  if (kind == CalendarEffortKind.legacyUnknown) {
    for (var y = rect.top + 2; y < rect.bottom; y += 5) {
      for (var x = rect.left + 2; x < rect.right; x += 5) {
        canvas.drawCircle(Offset(x, y), .8, paint);
      }
    }
    return;
  }
  final reverse = kind == CalendarEffortKind.unscheduled;
  for (var x = rect.left - rect.height; x < rect.right + rect.height; x += 7) {
    canvas.drawLine(
      Offset(x, reverse ? rect.top : rect.bottom),
      Offset(x + rect.height, reverse ? rect.bottom : rect.top),
      paint,
    );
  }
}

String _minuteText(double minutes) => minutes.round().toStringAsFixed(0);

void _drawDashedPolyline(
  Canvas canvas,
  List<Offset> points,
  Paint paint, {
  double dash = 6,
  double gap = 4,
}) {
  if (points.length < 2) return;
  var drawing = true;
  var remaining = dash;
  for (var index = 0; index < points.length - 1; index++) {
    final start = points[index];
    final end = points[index + 1];
    final length = (end - start).distance;
    if (length <= 0) continue;
    var travelled = 0.0;
    while (travelled < length - 1e-6) {
      final step = math.min(remaining, length - travelled);
      if (step <= 1e-6) {
        // Floating point residue at a segment boundary: move to the next dash
        // phase instead of spinning on a zero-length step.
        drawing = !drawing;
        remaining = drawing ? dash : gap;
        continue;
      }
      if (drawing) {
        canvas.drawLine(
          start + (end - start) * (travelled / length),
          start + (end - start) * ((travelled + step) / length),
          paint,
        );
      }
      travelled += step;
      remaining -= step;
      if (remaining <= 1e-6) {
        drawing = !drawing;
        remaining = drawing ? dash : gap;
      }
    }
  }
}
