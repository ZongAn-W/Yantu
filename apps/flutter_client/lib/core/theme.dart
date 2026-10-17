import 'package:flutter/material.dart';

/// Design tokens shared with `apps/web/src/styles.css` (`DESIGN.md`).
abstract final class PlannerColors {
  static const background = Color(0xfff5f7fa);
  static const text = Color(0xff20334a);
  static const blue = Color(0xff275e91);
  static const green = Color(0xff237354);
  static const orange = Color(0xffa85c14);
  static const border = Color(0xffdce3eb);
  static const muted = Color(0xff5b6b7d);
  static const danger = Color(0xffb3261e);
  static const surface = Colors.white;
}

/// Subject accent colours of the built-in courses, mirroring the Web CSS classes.
const subjectColors = <String, Color>{
  'calculus': Color(0xff4565c7),
  'linear-algebra': Color(0xff5b7fd4),
  'probability': Color(0xff7a6bd0),
  'english': Color(0xff1f7a5a),
  'data-structure': Color(0xffc2761f),
  'operating-system': Color(0xffa8522b),
  'computer-network': Color(0xff2b7f9e),
  'computer-organization': Color(0xff8a5a2b),
  'politics': Color(0xff9b3b57),
};

Color subjectColor(String subjectId, String? declared) {
  final parsed = declared == null ? null : _tryParseHex(declared);
  return parsed ??
      subjectColors[subjectId] ??
      PlannerColors.blue;
}

Color? _tryParseHex(String value) {
  final match = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(value.trim());
  if (match == null) return null;
  return Color(0xff000000 | int.parse(match.group(1)!, radix: 16));
}

ThemeData plannerTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: PlannerColors.blue,
    brightness: Brightness.light,
  ).copyWith(
    primary: PlannerColors.blue,
    secondary: PlannerColors.green,
    surface: PlannerColors.surface,
    error: PlannerColors.danger,
  );
  final base = ThemeData(
    fontFamily: 'NotoSansSC',
    colorScheme: scheme,
    scaffoldBackgroundColor: PlannerColors.background,
    useMaterial3: true,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: PlannerColors.text,
      displayColor: PlannerColors.text,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      isDense: true,
      border: OutlineInputBorder(),
      filled: true,
      fillColor: PlannerColors.surface,
    ),
    dividerTheme: const DividerThemeData(color: PlannerColors.border),
    cardTheme: const CardThemeData(
      color: PlannerColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: PlannerColors.border),
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: PlannerColors.surface,
      indicatorColor: Color(0x1a275e91),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: PlannerColors.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: PlannerColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Digits in time and quantity columns line up, matching `tabular-nums` on the Web.
const tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
