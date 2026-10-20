import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../planner_fonts.dart';
import 'component_themes.dart';
import 'tokens.dart';

/// Builds the light "Mist Ink" theme from [PlannerTokens.light].
ThemeData plannerTheme() =>
    _buildPlannerTheme(PlannerTokens.light, Brightness.light);

/// Builds the "Dense Graphite" dark theme from [PlannerTokens.dark].
///
/// Same semantic roles as the light theme; only token values change, so every
/// migrated widget flips automatically. Not the default: the study app stays
/// light unless the user (or the OS) asks for dark.
ThemeData plannerDarkTheme() =>
    _buildPlannerTheme(PlannerTokens.dark, Brightness.dark);

ThemeData _buildPlannerTheme(PlannerTokens tokens, Brightness brightness) {
  final seeded = ColorScheme.fromSeed(
    seedColor: tokens.accent,
    brightness: brightness,
  );
  final scheme = seeded.copyWith(
    primary: tokens.accent,
    onPrimary: tokens.accentOn,
    primaryContainer: tokens.accentSoft,
    onPrimaryContainer: tokens.accent,
    secondary: tokens.success,
    onSecondary: tokens.accentOn,
    secondaryContainer: tokens.accentSoft,
    onSecondaryContainer: tokens.accent,
    surface: tokens.surface,
    onSurface: tokens.text,
    onSurfaceVariant: tokens.muted,
    surfaceContainerLowest: tokens.surface,
    surfaceContainerLow: tokens.canvas,
    surfaceContainer: tokens.surfaceMuted,
    surfaceContainerHigh: tokens.hover,
    surfaceContainerHighest: tokens.selected,
    outline: tokens.borderStrong,
    outlineVariant: tokens.border,
    error: tokens.danger,
    onError: tokens.isDark ? tokens.canvas : tokens.accentOn,
    shadow: tokens.shadow,
    scrim: tokens.scrim,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: tokens.canvas,
    canvasColor: tokens.canvas,
    dividerColor: tokens.border,
    disabledColor: tokens.subtle,
    fontFamily: kIsWeb ? 'NotoSansSC' : plannerFullFontFamily,
    fontFamilyFallback: const [
      plannerFullFontFamily,
      'Microsoft YaHei',
      'PingFang SC',
      'Noto Sans CJK SC',
    ],
    visualDensity: VisualDensity.adaptivePlatformDensity,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    splashFactory: InkSparkle.splashFactory,
    extensions: <ThemeExtension<dynamic>>[tokens],
  );

  final textTheme = buildPlannerTextTheme(base.textTheme, tokens);

  return PlannerComponentThemes.apply(
    base.copyWith(textTheme: textTheme, primaryTextTheme: textTheme),
    tokens: tokens,
    textTheme: textTheme,
  );
}

/// Type ladder shared with DESIGN.md: page 22/28, panel 15/22, row 13.5/20,
/// body 13-14/20-22, secondary 12/18, label 11/15 (Chinese never below 12.5 px
/// for body copy; labels stay >= 11 px).
TextTheme buildPlannerTextTheme(TextTheme base, PlannerTokens tokens) {
  TextStyle style(
    double size,
    double height,
    FontWeight weight, {
    Color? color,
    double letterSpacing = 0,
    List<FontFeature>? features,
  }) => TextStyle(
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    color: color ?? tokens.text,
    letterSpacing: letterSpacing,
    fontFeatures: features,
  );

  return base
      .apply(bodyColor: tokens.text, displayColor: tokens.text)
      .copyWith(
        headlineSmall: style(22, 28, FontWeight.w600, letterSpacing: -0.2),
        titleLarge: style(18, 24, FontWeight.w600),
        titleMedium: style(15, 22, FontWeight.w600),
        titleSmall: style(13.5, 20, FontWeight.w600),
        bodyLarge: style(14, 22, FontWeight.w400),
        bodyMedium: style(13, 20, FontWeight.w400),
        bodySmall: style(12.5, 19, FontWeight.w400, color: tokens.muted),
        labelLarge: style(13, 18, FontWeight.w500),
        labelMedium: style(12, 16, FontWeight.w500, color: tokens.muted),
        labelSmall: style(11, 15, FontWeight.w500, color: tokens.subtle),
      );
}
