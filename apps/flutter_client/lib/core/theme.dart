import 'package:flutter/material.dart';

import 'theme/tokens.dart';

export 'theme/component_themes.dart' show PlannerComponentThemes;
export 'theme/theme_mode.dart' show PlannerThemeMode;
export 'theme/planner_theme.dart'
    show buildPlannerTextTheme, plannerDarkTheme, plannerTheme;
export 'theme/tokens.dart'
    show
        PlannerDarkPalette,
        PlannerDurations,
        PlannerPalette,
        PlannerRadius,
        PlannerSpace,
        PlannerTokens,
        PlannerTokensBuildContext,
        plannerPageMaxWidth;

/// Legacy colour aliases kept byte-compatible with the W1/W2 widgets.
///
/// New and migrated feature code should read the semantic extension instead
/// (BuildContext tokens: accent, muted, ...). The aliases remain for const
/// contexts (IconData/TextStyle/BoxDecoration trees) and are asserted to equal
/// [PlannerTokens.light] by test/unit/planner_tokens_test.dart.
abstract final class PlannerColors {
  static const background = PlannerPalette.canvas;
  static const surface = PlannerPalette.surface;
  static const surfaceMuted = PlannerPalette.surfaceMuted;
  static const sidebar = PlannerPalette.sidebar;
  static const hover = PlannerPalette.hover;
  static const selected = PlannerPalette.selected;

  static const text = PlannerPalette.text;
  static const muted = PlannerPalette.muted;
  static const subtle = PlannerPalette.subtle;

  static const border = PlannerPalette.border;
  static const borderStrong = PlannerPalette.borderStrong;

  static const blue = PlannerPalette.accent;
  static const blueHover = PlannerPalette.accentHover;
  static const blueSoft = PlannerPalette.accentSoft;
  static const green = PlannerPalette.success;
  static const orange = PlannerPalette.warning;
  static const danger = PlannerPalette.danger;
  static const focusRing = PlannerPalette.focusRing;
}

/// Physical hairline: 1 logical px at dpr 1, thinner on hiDPI so 1 px borders
/// do not turn muddy after scaling.
double plannerHairline(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return dpr >= 2 ? 1 / dpr : 1.0;
}

/// Hairline border with the stroke inside so adjacent borders do not double.
BorderSide plannerBorderSide(
  BuildContext context, {
  Color color = PlannerPalette.border,
}) => BorderSide(
  color: color,
  width: plannerHairline(context),
  strokeAlign: BorderSide.strokeAlignInside,
);

/// Soft, single-purpose elevation for floating layers only (never on cards).
List<BoxShadow> plannerShadow() => const [
  BoxShadow(color: Color(0x0f0f172a), blurRadius: 16, offset: Offset(0, 4)),
];

/// Digits in time and quantity columns line up, matching tabular-nums on the Web.
const tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
