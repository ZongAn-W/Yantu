import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_day_data.dart';
import '../domain/calendar_view.dart';
import '../domain/calendar_week_data.dart';

/// Item colors follow the item identity. Tags never affect chart grouping or
/// color, since a task can carry more than one tag.
Color _itemColor(CalendarDayItem item) => _stableItemColor(item.id);

Color _stableItemColor(String seed) {
  // String.hashCode is not a persistent contract on every Flutter target, so
  // keep the explicit 31-based hash the day views already use.
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

Color _layerColor(CalendarWeekLayer layer) => switch (layer.kind) {
  CalendarEffortKind.scheduled => PlannerColors.blue,
  CalendarEffortKind.extra => PlannerColors.orange,
  CalendarEffortKind.unscheduled => PlannerColors.green,
  CalendarEffortKind.legacyUnknown => PlannerColors.muted,
};

/// One read-only week graphic with compact legends and day details on demand.
///
/// Both [CalendarWeekView] values render this same widget with the same
/// [CalendarWeekData] instance; only the painter changes.
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  '周计划 ${duration(week.plannedMinutes)}',
                  key: const ValueKey('calendar-week-planned-total'),
                  style: tabularFigures.copyWith(color: PlannerColors.muted),
                ),
                Text(
                  '周实学 ${duration(week.actualMinutes)}',
                  key: const ValueKey('calendar-week-actual-total'),
                  style: tabularFigures.copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _WeekLegend(week: week, view: widget.view),
            if (week.isEmpty)
              const Padding(
                key: ValueKey('calendar-week-empty'),
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  '本周没有学习计划或学习记录',
                  style: TextStyle(fontSize: 12, color: PlannerColors.muted),
                ),
              ),
            const SizedBox(height: 8),
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
          width: 18,
          height: 10,
          child: CustomPaint(
            key: const ValueKey('calendar-week-kind-planned'),
            painter: _PlanLegendPainter(view),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        view == CalendarWeekView.mirror ? '计划 ↑' : '计划',
        style: const TextStyle(fontSize: 11, color: PlannerColors.muted),
      ),
    ],
  );
}

class _PlanLegendPainter extends CustomPainter {
  const _PlanLegendPainter(this.view);

  final CalendarWeekView view;

  @override
  void paint(Canvas canvas, Size size) {
    if (view == CalendarWeekView.mirror) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = PlannerColors.blue.withValues(alpha: .14),
      );
    } else {
      _drawDashedPolyline(
        canvas,
        [Offset(0, size.height / 2), Offset(size.width, size.height / 2)],
        Paint()
          ..color = PlannerColors.blue
          ..strokeWidth = 1.6,
        dash: 4,
        gap: 3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PlanLegendPainter oldDelegate) =>
      view != oldDelegate.view;
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
          width: 16,
          height: 10,
          child: CustomPaint(
            key: ValueKey('calendar-week-kind-${kind?.name ?? 'planned'}'),
            painter: _KindSwatchPainter(kind),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: PlannerColors.muted),
      ),
    ],
  );
}

abstract final class _WeekGeometry {
  /// Left gutter that holds the minute ticks; the day axis rows reserve the
  /// same width so labels sit exactly under their chart columns.
  static const double axisWidth = 36;

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
    required this.painter,
    required this.semanticsLabel,
    required this.onHover,
    required this.onSelect,
  });

  final Key canvasKey;

  final CalendarWeekData week;
  final double height;
  final CustomPainter painter;
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
                  child: CustomPaint(painter: widget.painter),
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
          const Text(
            '分钟',
            style: TextStyle(fontSize: 11, color: PlannerColors.muted),
          ),
          const SizedBox(height: 2),
          _WeekGraphic(
            canvasKey: const ValueKey('calendar-week-mirror-canvas'),
            week: week,
            height: height,
            semanticsLabel: _mirrorSemantics(week),
            painter: _MirrorPainter(week: week, highlightDate: highlightDate),
            onHover: onHover,
            onSelect: onSelect,
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

class _MirrorPainter extends CustomPainter {
  const _MirrorPainter({required this.week, required this.highlightDate});

  final CalendarWeekData week;
  final String highlightDate;

  static const double _topPad = 8;
  static const double _bottomPad = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _WeekGeometry.axisWidth;
    final plotWidth = math.max(1.0, size.width - plotLeft);
    final plotHeight = math.max(1.0, size.height - _topPad - _bottomPad);
    final half = plotHeight / 2;
    final zeroY = _topPad + half;
    final unit = half / week.scaleMinutes;
    final columnWidth = plotWidth / 7;
    final barWidth = math.max(2.0, columnWidth - 3);

    final grid = Paint()..color = PlannerColors.border.withValues(alpha: .5);
    final faintGrid = Paint()
      ..color = PlannerColors.border.withValues(alpha: .28);
    for (final fraction in const [0.0, .5, 1.0]) {
      final dy = half * fraction;
      canvas.drawLine(
        Offset(plotLeft, zeroY - dy),
        Offset(size.width, zeroY - dy),
        fraction == 0 ? grid : faintGrid,
      );
      canvas.drawLine(
        Offset(plotLeft, zeroY + dy),
        Offset(size.width, zeroY + dy),
        fraction == 0 ? grid : faintGrid,
      );
    }
    for (var index = 0; index <= 7; index++) {
      final x = plotLeft + columnWidth * index;
      canvas.drawLine(
        Offset(x, _topPad),
        Offset(x, _topPad + plotHeight),
        faintGrid,
      );
    }

    // Highlight the selected/hovered day column without hiding the data.
    final highlightIndex = week.days.indexWhere(
      (day) => day.date == highlightDate,
    );
    if (highlightIndex >= 0) {
      final left = plotLeft + columnWidth * highlightIndex;
      canvas.drawRect(
        Rect.fromLTWH(left, _topPad, columnWidth, plotHeight),
        Paint()..color = const Color(0x0f275e91),
      );
    }

    _paintMirrorAxis(canvas, size, zeroY, half, plotLeft);

    for (var index = 0; index < week.days.length; index++) {
      final day = week.days[index];
      final left =
          plotLeft + columnWidth * index + (columnWidth - barWidth) / 2;
      // Planned reference: light segments stacked upward from the shared zero.
      var plannedTop = zeroY;
      for (final item in day.day.items) {
        if (item.plannedMinutes <= 0) continue;
        final height = item.plannedMinutes * unit;
        final rect = Rect.fromLTWH(left, plannedTop - height, barWidth, height);
        final color = _itemColor(item);
        canvas.drawRect(rect, Paint()..color = color.withValues(alpha: .14));
        plannedTop -= height;
      }
      // Actual study: positive minutes drawn downward, full over-plan amount.
      var actualTop = zeroY;
      for (var itemIndex = 0; itemIndex < day.day.items.length; itemIndex++) {
        final item = day.day.items[itemIndex];
        final color = _itemColor(item);
        var drewItem = false;
        for (final effort in item.efforts) {
          if (effort.minutes <= 0) continue;
          final height = effort.minutes * unit;
          _drawEffortSegment(
            canvas,
            Rect.fromLTWH(left, actualTop, barWidth, height),
            color,
            effort.kind,
            textureAlpha: .72,
          );
          actualTop += height;
          drewItem = true;
        }
        // A hairline rule separates adjacent task rows so the
        // object attribution stays visible even when their colours match.
        if (drewItem &&
            itemIndex != day.day.items.length - 1 &&
            actualTop > zeroY) {
          canvas.drawLine(
            Offset(left, actualTop),
            Offset(left + barWidth, actualTop),
            Paint()
              ..color = Colors.white.withValues(alpha: .65)
              ..strokeWidth = 1,
          );
        }
      }
    }

    // One strong zero baseline: the same shared axis for plan and actual.
    canvas.drawLine(
      Offset(0, zeroY),
      Offset(size.width, zeroY),
      Paint()
        ..color = PlannerColors.text.withValues(alpha: .55)
        ..strokeWidth = 1.4,
    );
    _paintLeftLabel(canvas, '0', zeroY, plotLeft, align: _LabelAlign.center);
  }

  void _paintMirrorAxis(
    Canvas canvas,
    Size size,
    double zeroY,
    double half,
    double plotLeft,
  ) {
    final narrow = size.width < 340;
    final planTop = zeroY - half;
    final actualBottom = zeroY + half;
    _paintLeftLabel(
      canvas,
      _minuteText(week.scaleMinutes),
      planTop,
      plotLeft,
      align: _LabelAlign.center,
    );
    _paintLeftLabel(
      canvas,
      _minuteText(week.scaleMinutes),
      actualBottom,
      plotLeft,
      align: _LabelAlign.center,
    );
    if (!narrow) {
      _paintLeftLabel(
        canvas,
        _minuteText(week.scaleMinutes / 2),
        planTop + half / 2,
        plotLeft,
        align: _LabelAlign.center,
      );
      _paintLeftLabel(
        canvas,
        _minuteText(week.scaleMinutes / 2),
        zeroY + half / 2,
        plotLeft,
        align: _LabelAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MirrorPainter oldDelegate) =>
      week != oldDelegate.week || highlightDate != oldDelegate.highlightDate;
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
        painter: _MountainPainter(week: week, highlightDate: highlightDate),
        onHover: onHover,
        onSelect: onSelect,
      );
    },
  );
}

String _mountainSemantics(CalendarWeekData week) =>
    '一周学习山脉图，横轴周一至周日，纵轴学习分钟。实学山形按投入类型分类'
    '固定顺序堆叠，高度为当天实际学习总量；虚线为当天计划总量，两者共用同一比例。'
    '本周计划 ${duration(week.plannedMinutes)}，本周实学 ${duration(week.actualMinutes)}。'
    '下方日期按钮可选择某天查看明细。';

class _MountainPainter extends CustomPainter {
  const _MountainPainter({required this.week, required this.highlightDate});

  final CalendarWeekData week;
  final String highlightDate;

  static const double _topPad = 6;
  static const double _bottomPad = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final plotLeft = _WeekGeometry.axisWidth;
    final plotWidth = math.max(1.0, size.width - plotLeft);
    final plotHeight = math.max(1.0, size.height - _topPad - _bottomPad);
    final baselineY = _topPad + plotHeight;
    final unit = plotHeight / week.scaleMinutes;
    final columnWidth = plotWidth / 7;

    final grid = Paint()..color = PlannerColors.border.withValues(alpha: .45);
    final faintGrid = Paint()
      ..color = PlannerColors.border.withValues(alpha: .25);
    for (final fraction in const [0.0, .25, .5, .75, 1.0]) {
      final y = baselineY - plotHeight * fraction;
      canvas.drawLine(
        Offset(plotLeft, y),
        Offset(size.width, y),
        fraction == 0 ? grid : faintGrid,
      );
    }
    for (var index = 0; index <= 7; index++) {
      final x = plotLeft + columnWidth * index;
      canvas.drawLine(Offset(x, _topPad), Offset(x, baselineY), faintGrid);
    }
    _paintMountainAxis(canvas, size, baselineY, plotHeight, plotLeft);

    final highlightIndex = week.days.indexWhere(
      (day) => day.date == highlightDate,
    );
    if (highlightIndex >= 0) {
      final left = plotLeft + columnWidth * highlightIndex;
      canvas.drawRect(
        Rect.fromLTWH(left, _topPad, columnWidth, plotHeight),
        Paint()..color = const Color(0x0f275e91),
      );
    }

    // Fixed-ordered stacked areas: straight segments through the seven real
    // daily samples, never a smooth curve that would invent unrecorded peaks.
    final cumulative = List<double>.filled(7, 0);
    for (final layer in week.layers) {
      final color = _layerColor(layer);
      final path = Path();
      for (var index = 0; index < 7; index++) {
        final x = plotLeft + columnWidth * (index + .5);
        final y =
            baselineY - (cumulative[index] + layer.minutesOn(index)) * unit;
        if (index == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      for (var index = 6; index >= 0; index--) {
        final x = plotLeft + columnWidth * (index + .5);
        final y = baselineY - cumulative[index] * unit;
        path.lineTo(x, y);
      }
      path.close();
      canvas.drawPath(path, Paint()..color = color.withValues(alpha: .88));
      if (layer.kind != CalendarEffortKind.scheduled) {
        canvas.save();
        canvas.clipPath(path);
        _drawKindPattern(
          canvas,
          path.getBounds(),
          color,
          layer.kind,
          alpha: .5,
        );
        canvas.restore();
      }
      for (var index = 0; index < 7; index++) {
        cumulative[index] += layer.minutesOn(index);
      }
    }

    // The plan is a separate dashed total contour with the same vertical scale;
    // no fill between plan and actual ever claims original-plan achievement.
    final planPoints = <Offset>[
      for (var index = 0; index < 7; index++)
        Offset(
          plotLeft + columnWidth * (index + .5),
          baselineY - week.days[index].plannedMinutes * unit,
        ),
    ];
    _drawDashedPolyline(
      canvas,
      planPoints,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = PlannerColors.blue,
    );

    // Real daily sample points of the actual mountain.
    for (var index = 0; index < 7; index++) {
      final x = plotLeft + columnWidth * (index + .5);
      final total = cumulative[index];
      final y = baselineY - total * unit;
      if (total > 0) {
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = PlannerColors.text);
        canvas.drawCircle(Offset(x, y), 1.2, Paint()..color = Colors.white);
      } else {
        canvas.drawCircle(
          Offset(x, baselineY),
          2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = PlannerColors.muted.withValues(alpha: .7),
        );
      }
    }

    canvas.drawLine(
      Offset(0, baselineY),
      Offset(size.width, baselineY),
      Paint()
        ..color = PlannerColors.text.withValues(alpha: .5)
        ..strokeWidth = 1.2,
    );
  }

  void _paintMountainAxis(
    Canvas canvas,
    Size size,
    double baselineY,
    double plotHeight,
    double plotLeft,
  ) {
    _paintLeftLabel(
      canvas,
      _minuteText(week.scaleMinutes),
      baselineY - plotHeight,
      plotLeft,
      align: _LabelAlign.center,
    );
    _paintLeftLabel(
      canvas,
      '0',
      baselineY,
      plotLeft,
      align: _LabelAlign.center,
    );
    if (size.width >= 340) {
      _paintLeftLabel(
        canvas,
        _minuteText(week.scaleMinutes / 2),
        baselineY - plotHeight / 2,
        plotLeft,
        align: _LabelAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MountainPainter oldDelegate) =>
      week != oldDelegate.week || highlightDate != oldDelegate.highlightDate;
}

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
          borderRadius: BorderRadius.circular(6),
          splashFactory: reduceMotion ? NoSplash.splashFactory : null,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            constraints: const BoxConstraints(minHeight: 48),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 1),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? PlannerColors.blue : Colors.transparent,
                  width: 2,
                ),
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
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? PlannerColors.blue : PlannerColors.muted,
                  ),
                ),
                Text(
                  day.date.substring(8, 10),
                  maxLines: 1,
                  style: tabularFigures.copyWith(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? PlannerColors.blue : PlannerColors.text,
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
              style: const TextStyle(fontSize: 12, color: PlannerColors.muted),
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
              style: tabularFigures.copyWith(
                fontSize: 12,
                color: PlannerColors.muted,
              ),
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
                          width: 15,
                          height: 9,
                          child: CustomPaint(painter: _KindSwatchPainter(kind)),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${kind.label} ${duration(kinds[kind]!)}',
                        style: tabularFigures.copyWith(
                          fontSize: 11,
                          color: PlannerColors.muted,
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
    final color = _itemColor(item);
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
                      color: PlannerColors.muted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      if (item.efforts.isEmpty)
                        const Text(
                          '尚无学习记录',
                          style: TextStyle(
                            fontSize: 11,
                            color: PlannerColors.muted,
                          ),
                        ),
                      for (final effort in item.efforts)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ExcludeSemantics(
                              child: SizedBox(
                                width: 15,
                                height: 9,
                                child: CustomPaint(
                                  painter: _KindSwatchPainter(
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
                                color: PlannerColors.muted,
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
  const _KindSwatchPainter(this.kind, {this.color = PlannerColors.blue});

  final CalendarEffortKind? kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (kind == null) {
      canvas.drawRect(rect, Paint()..color = color.withValues(alpha: .14));
      canvas.drawRect(
        rect.deflate(.5),
        Paint()
          ..color = color.withValues(alpha: .45)
          ..style = PaintingStyle.stroke,
      );
      return;
    }
    canvas.drawRect(rect, Paint()..color = color);
    if (kind != CalendarEffortKind.scheduled) {
      canvas.save();
      canvas.clipRect(rect);
      _drawKindPattern(canvas, rect, color, kind!);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _KindSwatchPainter oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}

void _drawEffortSegment(
  Canvas canvas,
  Rect rect,
  Color color,
  CalendarEffortKind kind, {
  double textureAlpha = .7,
}) {
  if (rect.isEmpty) return;
  canvas.drawRect(rect, Paint()..color = color);
  if (kind != CalendarEffortKind.scheduled) {
    canvas.save();
    canvas.clipRect(rect);
    _drawKindPattern(canvas, rect, color, kind, alpha: textureAlpha);
    canvas.restore();
  }
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
  double alpha = .7,
}) {
  final paint = Paint()
    ..color = Colors.white.withValues(alpha: alpha)
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

enum _LabelAlign { left, center, right }

void _paintLeftLabel(
  Canvas canvas,
  String text,
  double centerY,
  double axisWidth, {
  _LabelAlign align = _LabelAlign.right,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: const TextStyle(fontSize: 9, color: PlannerColors.muted),
    ),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(maxWidth: axisWidth);
  final dx = switch (align) {
    _LabelAlign.left => 0.0,
    _LabelAlign.center => (axisWidth - painter.width) / 2,
    _LabelAlign.right => axisWidth - painter.width - 4,
  };
  painter.paint(canvas, Offset(dx, centerY - painter.height / 2));
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
