import 'package:flutter/material.dart';

import '../../../core/theme.dart';
import '../domain/calendar_day_data.dart';

/// Stable course colour for one calendar item.
///
/// An explicit `#rrggbb` tag colour wins; otherwise the first tag name (or the
/// item id for untagged owners) seeds [PlannerTokens.tagFallbackColors]. Dark
/// themes lighten the result through [PlannerTokens.dataTone] so the mosaic
/// blocks stay readable on the dark graphite canvas.
Color calendarMonthItemColor(CalendarDayItem item, PlannerTokens tokens) {
  final explicit = _parseHex(item.tagColor);
  if (explicit != null) return tokens.dataTone(explicit);
  final seed = item.tagNames.isNotEmpty ? item.tagNames.first : item.id;
  return calendarMonthSeedColor(seed, tokens);
}

/// Fallback colour for a course/tag name that has no explicit colour.
Color calendarMonthSeedColor(String seed, PlannerTokens tokens) {
  final palette = tokens.tagFallbackColors;
  if (palette.isEmpty) return tokens.accent;
  return tokens.dataTone(palette[seed.hashCode.abs() % palette.length]);
}

Color? _parseHex(String? hex) {
  if (hex == null || hex.length != 7 || !hex.startsWith('#')) return null;
  final value = int.tryParse(hex.substring(1), radix: 16);
  if (value == null) return null;
  return Color(0xff000000 | value);
}
