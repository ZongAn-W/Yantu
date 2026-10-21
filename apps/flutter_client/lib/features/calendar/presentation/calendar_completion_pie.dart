import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../planner/domain/planner_format.dart';
import '../domain/calendar_completion_data.dart';

/// Read-only donut of the recorded minutes per completed item in one period.
///
/// The calendar renders one of these at the top of the day, week and month
/// scopes. It reads the same [CalendarCompletionData] that the scope aggregates
/// from its [CalendarDayData] snapshots, so the centre total can never disagree
/// with the plan/actual totals further down the page. Nothing here is
/// interactive or writable: there is no timer, no completion action and no
/// hover state that changes the selected date.
class CalendarCompletionPie extends StatelessWidget {
  const CalendarCompletionPie({required this.data, super.key});

  /// The period composition to show; [CalendarCompletionData.empty] renders the
  /// quiet empty state instead of a blank circle.
  final CalendarCompletionData data;

  /// Inner width at which the legend moves beside the donut instead of below it.
  static const double _sideBySideWidth = 560;

  /// At most this many slices are drawn; the tail collapses into one row.
  static const int _maxVisibleSlices = 8;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PlannerPanel(
      key: const ValueKey('calendar-period-pie'),
      title: '本期完成事项',
      subtitle: '按实际学习用时',
      padding: const EdgeInsets.all(PlannerSpace.lg),
      child: data.isEmpty
          ? _EmptyPie(tokens: tokens)
          : LayoutBuilder(
              builder: (context, constraints) {
                final slices = _visibleSlices(tokens);
                final percents = _percentages(slices);
                final donut = _Donut(
                  slices: slices,
                  percents: percents,
                  totalMinutes: data.totalMinutes,
                  itemCount: data.itemCount,
                );
                final legend = _Legend(slices: slices, percents: percents);
                if (constraints.maxWidth >= _sideBySideWidth) {
                  // The reference cards are read left-to-right at a comfortable
                  // measure: do not stretch one short title all the way to the
                  // card edge on a wide desktop.
                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 900),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          donut,
                          const SizedBox(width: PlannerSpace.xl),
                          Expanded(child: legend),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: donut),
                    const SizedBox(height: PlannerSpace.lg),
                    legend,
                  ],
                );
              },
            ),
    );
  }

  /// The drawn slices. A long tail folds into one neutral "其他" row so the
  /// ring and the legend stay readable for months with many studied items; the
  /// centre still reports the true item count.
  ///
  /// Slices from the same tag share the tag colour, which would make several
  /// ring segments indistinguishable. Duplicates keep the same hue but are
  /// lifted by a small, stable amount so identity stays readable without
  /// inventing a second palette.
  List<_PieSlice> _visibleSlices(PlannerTokens tokens) {
    final slices = data.slices;
    final visible = <_PieSlice>[];
    for (final slice in slices.take(_maxVisibleSlices)) {
      visible.add(
        _PieSlice(
          id: slice.id,
          label: slice.title,
          tagNames: slice.tagNames,
          minutes: slice.minutes,
          color: _sliceColor(tokens, slice),
        ),
      );
    }
    if (slices.length > _maxVisibleSlices) {
      final hidden = slices.skip(_maxVisibleSlices).toList();
      var minutes = 0;
      for (final slice in hidden) {
        minutes += slice.minutes;
      }
      // Replace the last shown slice with it plus the folded tail so the ring
      // never advertises more colours than the legend explains.
      final kept = visible.removeLast();
      visible.add(
        _PieSlice(
          id: 'other',
          label: '其他 ${hidden.length + 1} 个事项',
          tagNames: const [],
          minutes: kept.minutes + minutes,
          color: tokens.subtle,
        ),
      );
      // The folded row must be last in the legend regardless of size.
      visible.sort((a, b) {
        if (a.id == 'other') return 1;
        if (b.id == 'other') return -1;
        return b.minutes.compareTo(a.minutes);
      });
    }
    final used = <Color>{};
    final distinguished = <_PieSlice>[];
    for (final slice in visible) {
      final color = _uniqueColor(tokens, slice.color, slice.id, used);
      used.add(color);
      distinguished.add(slice.withColor(color));
    }
    return distinguished;
  }

  /// Integer percentages that always add up to exactly 100, using the largest
  /// remainder method; a visible slice never rounds down to 0%.
  static List<int> _percentages(List<_PieSlice> slices) {
    if (slices.isEmpty) return const [];
    var total = 0;
    for (final slice in slices) {
      total += slice.minutes;
    }
    if (total <= 0) return List<int>.filled(slices.length, 0);
    final exact = [for (final slice in slices) slice.minutes * 100 / total];
    final result = [for (final value in exact) math.max(1, value.floor())];
    var diff = 100 - result.fold<int>(0, (sum, value) => sum + value);
    if (diff > 0) {
      final order = [for (var index = 0; index < exact.length; index++) index]
        ..sort(
          (a, b) => (exact[b] - exact[b].floor()).compareTo(
            exact[a] - exact[a].floor(),
          ),
        );
      var index = 0;
      while (diff > 0) {
        result[order[index % order.length]] += 1;
        diff -= 1;
        index += 1;
      }
    } else if (diff < 0) {
      final order = [for (var index = 0; index < result.length; index++) index]
        ..sort((a, b) => result[b].compareTo(result[a]));
      var index = 0;
      while (diff < 0) {
        final target = order[index % order.length];
        if (result[target] > 1) {
          result[target] -= 1;
          diff += 1;
        }
        index += 1;
      }
    }
    return result;
  }
}

/// One drawn slice; the folded tail is a normal slice with a neutral colour.
class _PieSlice {
  const _PieSlice({
    required this.id,
    required this.label,
    required this.tagNames,
    required this.minutes,
    required this.color,
  });

  final String id;
  final String label;
  final List<String> tagNames;
  final int minutes;
  final Color color;

  String get tooltip =>
      tagNames.isEmpty ? label : '$label · ${tagNames.join(' / ')}';

  _PieSlice withColor(Color color) => _PieSlice(
    id: id,
    label: label,
    tagNames: tagNames,
    minutes: minutes,
    color: color,
  );
}

/// Item colour: the task's own tag colour wins, otherwise a stable fallback.
///
/// The fallback is hashed from the owner id so the same item keeps its colour
/// across periods and reloads, and so two unrelated items rarely collide.
Color _sliceColor(PlannerTokens tokens, CalendarCompletionSlice slice) {
  final hex = slice.tagColor;
  if (hex != null && hex.length >= 7) {
    final value = int.tryParse(hex.substring(1), radix: 16);
    if (value != null) return tokens.dataTone(Color(0xff000000 | value));
  }
  final palette = tokens.tagFallbackColors;
  return palette[_stableHash(slice.id) % palette.length];
}

/// Keeps same-tag slices distinguishable without leaving the tag's hue.
///
/// The first slice of a colour keeps the exact tag colour; later duplicates are
/// lifted a small stable amount towards the surface (light) or the ink (dark).
/// If the whole hue family is exhausted, the stable fallback palette is used.
Color _uniqueColor(
  PlannerTokens tokens,
  Color base,
  String id,
  Set<Color> used,
) {
  if (!used.contains(base)) return base;
  final lift = tokens.isDark ? tokens.text : tokens.surface;
  for (var step = 1; step <= 3; step++) {
    final candidate = Color.lerp(base, lift, 0.18 * step)!;
    if (!used.contains(candidate)) return candidate;
  }
  final palette = tokens.tagFallbackColors;
  final start = _stableHash(id) % palette.length;
  for (var step = 0; step < palette.length; step++) {
    final candidate = palette[(start + step) % palette.length];
    if (!used.contains(candidate)) return candidate;
  }
  return base;
}

/// FNV-1a is used only as a deterministic palette index, never for identity.
int _stableHash(String value) {
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

class _EmptyPie extends StatelessWidget {
  const _EmptyPie({required this.tokens});

  final PlannerTokens tokens;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: PlannerSpace.sm),
    child: Column(
      children: [
        Text(
          '本期还没有学习记录',
          key: const ValueKey('calendar-period-pie-empty'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: tokens.muted),
        ),
        const SizedBox(height: PlannerSpace.xs),
        Text(
          '完成一次计时后，这里会显示各事项的实际用时占比。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, height: 1.5, color: tokens.subtle),
        ),
      ],
    ),
  );
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.slices,
    required this.percents,
    required this.totalMinutes,
    required this.itemCount,
  });

  static const double _size = 168;

  final List<_PieSlice> slices;
  final List<int> percents;
  final int totalMinutes;
  final int itemCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Semantics(
      container: true,
      label: '本期实学 ${duration(totalMinutes)}，共 $itemCount 个事项',
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: _size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: const Size.square(_size),
              painter: _DonutPainter(slices: slices, percents: percents),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  duration(totalMinutes),
                  key: const ValueKey('calendar-period-pie-total'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tabularFigures.copyWith(
                    fontSize: 16,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                    color: tokens.text,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '共 $itemCount 个事项',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: tokens.muted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints the ring from 12 o'clock clockwise with a hairline surface gap
/// between slices; there is no gradient, shadow or decorative texture.
class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.slices, required this.percents});

  static const double _strokeWidth = 22;

  /// Gap between two slices, in radians (~1.4 degrees at the ring).
  static const double _gap = 0.025;

  final List<_PieSlice> slices;
  final List<int> percents;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (math.min(size.width, size.height) - _strokeWidth) / 2;
    if (radius <= 0) return;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth
      ..strokeCap = StrokeCap.butt;
    if (slices.length <= 1) {
      canvas.drawCircle(center, radius, paint..color = slices.first.color);
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: radius);
    var total = 0;
    for (final slice in slices) {
      total += slice.minutes;
    }
    if (total <= 0) return;
    var start = -math.pi / 2;
    for (var index = 0; index < slices.length; index++) {
      final sweep = slices[index].minutes / total * math.pi * 2;
      final drawn = math.max(0.0, sweep - _gap);
      if (drawn > 0) {
        paint.color = slices[index].color;
        canvas.drawArc(rect, start + _gap / 2, drawn, false, paint);
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.slices != slices || oldDelegate.percents != percents;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.slices, required this.percents});

  final List<_PieSlice> slices;
  final List<int> percents;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < slices.length; index++) ...[
          if (index > 0) const SizedBox(height: PlannerSpace.sm),
          _LegendRow(
            key: ValueKey('calendar-period-pie-slice-${slices[index].id}'),
            slice: slices[index],
            percent: percents[index],
          ),
        ],
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.slice, required this.percent, super.key});

  final _PieSlice slice;
  final int percent;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        ExcludeSemantics(
          child: Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: slice.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: PlannerSpace.sm),
        Expanded(
          child: Tooltip(
            message: slice.tooltip,
            child: Text(
              slice.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, height: 1.4, color: tokens.text),
            ),
          ),
        ),
        const SizedBox(width: PlannerSpace.sm),
        ExcludeSemantics(
          child: Text(
            '${duration(slice.minutes)} · $percent%',
            maxLines: 1,
            style: tabularFigures.copyWith(
              fontSize: 12,
              height: 1.4,
              color: tokens.muted,
            ),
          ),
        ),
      ],
    );
  }
}
