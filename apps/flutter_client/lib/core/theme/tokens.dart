import 'package:flutter/material.dart';

/// Semantic design tokens for the Mist Ink visual language (W3).
///
/// The role split follows shadcn/ui + Radix Colors (MIT, design reference only):
/// every colour answers exactly one question, so a dark palette (W5) can be
/// added without touching feature code. The radius ladder keeps one base value
/// and derives the family (flex_color_scheme, BSD-3, design reference only):
/// cards 12 / dialogs 14 / controls 10 / chips 8.
///
/// Keep the literal values in [PlannerPalette] as the single source of truth;
/// [PlannerTokens.light] turns them into the theme extension and the legacy
/// PlannerColors aliases mirror them for const contexts.
@immutable
class PlannerTokens extends ThemeExtension<PlannerTokens> {
  const PlannerTokens({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.sidebar,
    required this.hover,
    required this.selected,
    required this.text,
    required this.muted,
    required this.subtle,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentHover,
    required this.accentSoft,
    required this.accentOn,
    required this.success,
    required this.warning,
    required this.danger,
    required this.focusRing,
    required this.selection,
    required this.shadow,
    required this.scrim,
    required this.snackAction,
    required this.noticeSuccessBackground,
    required this.noticeSuccessBorder,
    required this.noticeSuccessInk,
    required this.noticeWarningBackground,
    required this.noticeWarningBorder,
    required this.noticeWarningInk,
    required this.noticeErrorBackground,
    required this.noticeErrorBorder,
    required this.noticeErrorInk,
    required this.accentBorder,
    required this.floatingShadow,
    required this.inverseOn,
    required this.tagFallbackColors,
    required this.hoverAlpha,
    required this.pressedAlpha,
    required this.radiusCard,
    required this.radiusDialog,
    required this.radiusControl,
    required this.radiusSmall,
    required this.radiusXs,
    required this.radiusPill,
    required this.motionFast,
    required this.motionBase,
    required this.motionSlow,
    required this.motionCurve,
  });

  // Surfaces -----------------------------------------------------------------
  /// App canvas behind every page.
  final Color canvas;

  /// Cards, panels, dialogs and other raised paper.
  final Color surface;

  /// Inset blocks, progress tracks and muted fills.
  final Color surfaceMuted;

  /// Desktop navigation rail background.
  final Color sidebar;

  /// Hover state for rows and icon actions.
  final Color hover;

  /// Selected navigation / segmented state.
  final Color selected;

  // Ink ----------------------------------------------------------------------
  /// Primary text and icons.
  final Color text;

  /// Secondary text: descriptions and metadata.
  final Color muted;

  /// Tertiary text: hints, axis labels and placeholders.
  final Color subtle;

  // Lines --------------------------------------------------------------------
  /// 1 px hairline used everywhere.
  final Color border;

  /// Input borders and emphasised separators.
  final Color borderStrong;

  // Accent + semantic --------------------------------------------------------
  /// The only accent: primary actions, selection and running timers.
  final Color accent;
  final Color accentHover;
  final Color accentSoft;

  /// Text/icon colour on top of [accent].
  final Color accentOn;

  /// Finished / goal reached.
  final Color success;

  /// Extra study, over-plan and "unscheduled" states.
  final Color warning;

  /// Destructive actions only.
  final Color danger;

  /// Keyboard focus ring (semi-transparent accent).
  final Color focusRing;

  /// Text selection highlight.
  final Color selection;

  /// Floating-layer shadow (never used on cards).
  final Color shadow;

  /// Modal scrim.
  final Color scrim;

  /// Snackbar action label.
  final Color snackAction;

  /// PlannerNotice success tone (soft background, border, text).
  final Color noticeSuccessBackground;
  final Color noticeSuccessBorder;
  final Color noticeSuccessInk;

  /// PlannerNotice warning tone.
  final Color noticeWarningBackground;
  final Color noticeWarningBorder;
  final Color noticeWarningInk;

  /// PlannerNotice error tone.
  final Color noticeErrorBackground;
  final Color noticeErrorBorder;
  final Color noticeErrorInk;

  /// Selected tag border (blue-grey hairline).
  final Color accentBorder;

  /// Tiny floating shadow (segmented thumb, popovers).
  final Color floatingShadow;

  /// Text/icon on inverse surfaces (snackbar, tooltip).
  final Color inverseOn;

  /// Fallback tag colours for tasks without an explicit colour.
  final List<Color> tagFallbackColors;

  /// True when this token set is the Dense Graphite dark palette.
  bool get isDark => canvas.computeLuminance() < 0.5;

  // State overlays -----------------------------------------------------------
  /// Super Productivity style alpha overlays for hover/pressed feedback.
  /// Components should blend these over the local surface instead of inventing
  /// new opaque greys.
  final double hoverAlpha;
  final double pressedAlpha;

  // Radius ladder ------------------------------------------------------------
  final double radiusCard;
  final double radiusDialog;
  final double radiusControl;
  final double radiusSmall;
  final double radiusXs;
  final double radiusPill;

  // Motion -------------------------------------------------------------------
  final Duration motionFast;
  final Duration motionBase;
  final Duration motionSlow;
  final Curve motionCurve;

  /// Data-driven colours (tag colours) stay readable on the dark canvas: in
  /// dark mode they are lightened before they are blended with the surface.
  Color dataTone(Color color) =>
      isDark ? Color.lerp(color, const Color(0xffffffff), 0.45)! : color;

  /// Blend the hover overlay over [base] (state feedback without extra tokens).
  Color hoverOn(Color base) =>
      Color.alphaBlend(text.withValues(alpha: hoverAlpha), base);

  /// Blend the pressed overlay over [base].
  Color pressedOn(Color base) =>
      Color.alphaBlend(text.withValues(alpha: pressedAlpha), base);

  /// The light "Mist Ink" palette.
  static const PlannerTokens light = PlannerTokens(
    canvas: PlannerPalette.canvas,
    surface: PlannerPalette.surface,
    surfaceMuted: PlannerPalette.surfaceMuted,
    sidebar: PlannerPalette.sidebar,
    hover: PlannerPalette.hover,
    selected: PlannerPalette.selected,
    text: PlannerPalette.text,
    muted: PlannerPalette.muted,
    subtle: PlannerPalette.subtle,
    border: PlannerPalette.border,
    borderStrong: PlannerPalette.borderStrong,
    accent: PlannerPalette.accent,
    accentHover: PlannerPalette.accentHover,
    accentSoft: PlannerPalette.accentSoft,
    accentOn: PlannerPalette.accentOn,
    success: PlannerPalette.success,
    warning: PlannerPalette.warning,
    danger: PlannerPalette.danger,
    focusRing: PlannerPalette.focusRing,
    selection: PlannerPalette.selection,
    shadow: PlannerPalette.shadow,
    scrim: PlannerPalette.scrim,
    snackAction: PlannerPalette.snackAction,
    noticeSuccessBackground: PlannerPalette.noticeSuccessBackground,
    noticeSuccessBorder: PlannerPalette.noticeSuccessBorder,
    noticeSuccessInk: PlannerPalette.noticeSuccessInk,
    noticeWarningBackground: PlannerPalette.noticeWarningBackground,
    noticeWarningBorder: PlannerPalette.noticeWarningBorder,
    noticeWarningInk: PlannerPalette.noticeWarningInk,
    noticeErrorBackground: PlannerPalette.noticeErrorBackground,
    noticeErrorBorder: PlannerPalette.noticeErrorBorder,
    noticeErrorInk: PlannerPalette.noticeErrorInk,
    accentBorder: PlannerPalette.accentBorder,
    floatingShadow: PlannerPalette.floatingShadow,
    inverseOn: PlannerPalette.inverseOn,
    tagFallbackColors: PlannerPalette.tagFallbackColors,
    hoverAlpha: 0.06,
    pressedAlpha: 0.14,
    radiusCard: PlannerRadius.card,
    radiusDialog: PlannerRadius.dialog,
    radiusControl: PlannerRadius.control,
    radiusSmall: PlannerRadius.small,
    radiusXs: PlannerRadius.xs,
    radiusPill: PlannerRadius.pill,
    motionFast: PlannerDurations.fast,
    motionBase: PlannerDurations.base,
    motionSlow: PlannerDurations.slow,
    motionCurve: PlannerDurations.curve,
  );

  /// The "Dense Graphite" dark palette (W5).
  ///
  /// Neutral role mapping follows the research report §7.3: near-black canvas,
  /// #2A2F3A hairlines and a single cool accent. The accent keeps the ink-blue
  /// hue of the light theme (lightened for contrast) instead of the report's
  /// indigo, so the product never carries two accent hues; see DESIGN.md.
  static const PlannerTokens dark = PlannerTokens(
    canvas: PlannerDarkPalette.canvas,
    surface: PlannerDarkPalette.surface,
    surfaceMuted: PlannerDarkPalette.surfaceMuted,
    sidebar: PlannerDarkPalette.sidebar,
    hover: PlannerDarkPalette.hover,
    selected: PlannerDarkPalette.selected,
    text: PlannerDarkPalette.text,
    muted: PlannerDarkPalette.muted,
    subtle: PlannerDarkPalette.subtle,
    border: PlannerDarkPalette.border,
    borderStrong: PlannerDarkPalette.borderStrong,
    accent: PlannerDarkPalette.accent,
    accentHover: PlannerDarkPalette.accentHover,
    accentSoft: PlannerDarkPalette.accentSoft,
    accentOn: PlannerDarkPalette.accentOn,
    success: PlannerDarkPalette.success,
    warning: PlannerDarkPalette.warning,
    danger: PlannerDarkPalette.danger,
    focusRing: PlannerDarkPalette.focusRing,
    selection: PlannerDarkPalette.selection,
    shadow: PlannerDarkPalette.shadow,
    scrim: PlannerDarkPalette.scrim,
    snackAction: PlannerDarkPalette.snackAction,
    noticeSuccessBackground: PlannerDarkPalette.noticeSuccessBackground,
    noticeSuccessBorder: PlannerDarkPalette.noticeSuccessBorder,
    noticeSuccessInk: PlannerDarkPalette.noticeSuccessInk,
    noticeWarningBackground: PlannerDarkPalette.noticeWarningBackground,
    noticeWarningBorder: PlannerDarkPalette.noticeWarningBorder,
    noticeWarningInk: PlannerDarkPalette.noticeWarningInk,
    noticeErrorBackground: PlannerDarkPalette.noticeErrorBackground,
    noticeErrorBorder: PlannerDarkPalette.noticeErrorBorder,
    noticeErrorInk: PlannerDarkPalette.noticeErrorInk,
    accentBorder: PlannerDarkPalette.accentBorder,
    floatingShadow: PlannerDarkPalette.floatingShadow,
    inverseOn: PlannerDarkPalette.inverseOn,
    tagFallbackColors: PlannerDarkPalette.tagFallbackColors,
    hoverAlpha: 0.08,
    pressedAlpha: 0.16,
    radiusCard: PlannerRadius.card,
    radiusDialog: PlannerRadius.dialog,
    radiusControl: PlannerRadius.control,
    radiusSmall: PlannerRadius.small,
    radiusXs: PlannerRadius.xs,
    radiusPill: PlannerRadius.pill,
    motionFast: PlannerDurations.fast,
    motionBase: PlannerDurations.base,
    motionSlow: PlannerDurations.slow,
    motionCurve: PlannerDurations.curve,
  );

  /// The tokens of the current theme, falling back to [light] when a widget is
  /// built outside a Theme (tests, bootstrap screens).
  static PlannerTokens of(BuildContext context) =>
      Theme.of(context).extension<PlannerTokens>() ?? light;

  @override
  PlannerTokens copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceMuted,
    Color? sidebar,
    Color? hover,
    Color? selected,
    Color? text,
    Color? muted,
    Color? subtle,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentHover,
    Color? accentSoft,
    Color? accentOn,
    Color? success,
    Color? warning,
    Color? danger,
    Color? focusRing,
    Color? selection,
    Color? shadow,
    Color? scrim,
    Color? snackAction,
    Color? noticeSuccessBackground,
    Color? noticeSuccessBorder,
    Color? noticeSuccessInk,
    Color? noticeWarningBackground,
    Color? noticeWarningBorder,
    Color? noticeWarningInk,
    Color? noticeErrorBackground,
    Color? noticeErrorBorder,
    Color? noticeErrorInk,
    Color? accentBorder,
    Color? floatingShadow,
    Color? inverseOn,
    List<Color>? tagFallbackColors,
    double? hoverAlpha,
    double? pressedAlpha,
    double? radiusCard,
    double? radiusDialog,
    double? radiusControl,
    double? radiusSmall,
    double? radiusXs,
    double? radiusPill,
    Duration? motionFast,
    Duration? motionBase,
    Duration? motionSlow,
    Curve? motionCurve,
  }) => PlannerTokens(
    canvas: canvas ?? this.canvas,
    surface: surface ?? this.surface,
    surfaceMuted: surfaceMuted ?? this.surfaceMuted,
    sidebar: sidebar ?? this.sidebar,
    hover: hover ?? this.hover,
    selected: selected ?? this.selected,
    text: text ?? this.text,
    muted: muted ?? this.muted,
    subtle: subtle ?? this.subtle,
    border: border ?? this.border,
    borderStrong: borderStrong ?? this.borderStrong,
    accent: accent ?? this.accent,
    accentHover: accentHover ?? this.accentHover,
    accentSoft: accentSoft ?? this.accentSoft,
    accentOn: accentOn ?? this.accentOn,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    danger: danger ?? this.danger,
    focusRing: focusRing ?? this.focusRing,
    selection: selection ?? this.selection,
    shadow: shadow ?? this.shadow,
    scrim: scrim ?? this.scrim,
    snackAction: snackAction ?? this.snackAction,
    noticeSuccessBackground:
        noticeSuccessBackground ?? this.noticeSuccessBackground,
    noticeSuccessBorder: noticeSuccessBorder ?? this.noticeSuccessBorder,
    noticeSuccessInk: noticeSuccessInk ?? this.noticeSuccessInk,
    noticeWarningBackground:
        noticeWarningBackground ?? this.noticeWarningBackground,
    noticeWarningBorder: noticeWarningBorder ?? this.noticeWarningBorder,
    noticeWarningInk: noticeWarningInk ?? this.noticeWarningInk,
    noticeErrorBackground: noticeErrorBackground ?? this.noticeErrorBackground,
    noticeErrorBorder: noticeErrorBorder ?? this.noticeErrorBorder,
    noticeErrorInk: noticeErrorInk ?? this.noticeErrorInk,
    accentBorder: accentBorder ?? this.accentBorder,
    floatingShadow: floatingShadow ?? this.floatingShadow,
    inverseOn: inverseOn ?? this.inverseOn,
    tagFallbackColors: tagFallbackColors ?? this.tagFallbackColors,
    hoverAlpha: hoverAlpha ?? this.hoverAlpha,
    pressedAlpha: pressedAlpha ?? this.pressedAlpha,
    radiusCard: radiusCard ?? this.radiusCard,
    radiusDialog: radiusDialog ?? this.radiusDialog,
    radiusControl: radiusControl ?? this.radiusControl,
    radiusSmall: radiusSmall ?? this.radiusSmall,
    radiusXs: radiusXs ?? this.radiusXs,
    radiusPill: radiusPill ?? this.radiusPill,
    motionFast: motionFast ?? this.motionFast,
    motionBase: motionBase ?? this.motionBase,
    motionSlow: motionSlow ?? this.motionSlow,
    motionCurve: motionCurve ?? this.motionCurve,
  );

  @override
  PlannerTokens lerp(covariant PlannerTokens? other, double t) {
    if (other == null) return this;
    Color mixColor(Color a, Color b) => Color.lerp(a, b, t)!;
    Duration mixDuration(Duration a, Duration b) => Duration(
      microseconds:
          (a.inMicroseconds + (b.inMicroseconds - a.inMicroseconds) * t)
              .round(),
    );
    double mixDouble(double a, double b) => a + (b - a) * t;
    return PlannerTokens(
      canvas: mixColor(canvas, other.canvas),
      surface: mixColor(surface, other.surface),
      surfaceMuted: mixColor(surfaceMuted, other.surfaceMuted),
      sidebar: mixColor(sidebar, other.sidebar),
      hover: mixColor(hover, other.hover),
      selected: mixColor(selected, other.selected),
      text: mixColor(text, other.text),
      muted: mixColor(muted, other.muted),
      subtle: mixColor(subtle, other.subtle),
      border: mixColor(border, other.border),
      borderStrong: mixColor(borderStrong, other.borderStrong),
      accent: mixColor(accent, other.accent),
      accentHover: mixColor(accentHover, other.accentHover),
      accentSoft: mixColor(accentSoft, other.accentSoft),
      accentOn: mixColor(accentOn, other.accentOn),
      success: mixColor(success, other.success),
      warning: mixColor(warning, other.warning),
      danger: mixColor(danger, other.danger),
      focusRing: mixColor(focusRing, other.focusRing),
      selection: mixColor(selection, other.selection),
      shadow: mixColor(shadow, other.shadow),
      scrim: mixColor(scrim, other.scrim),
      snackAction: mixColor(snackAction, other.snackAction),
      noticeSuccessBackground: mixColor(
        noticeSuccessBackground,
        other.noticeSuccessBackground,
      ),
      noticeSuccessBorder: mixColor(
        noticeSuccessBorder,
        other.noticeSuccessBorder,
      ),
      noticeSuccessInk: mixColor(noticeSuccessInk, other.noticeSuccessInk),
      noticeWarningBackground: mixColor(
        noticeWarningBackground,
        other.noticeWarningBackground,
      ),
      noticeWarningBorder: mixColor(
        noticeWarningBorder,
        other.noticeWarningBorder,
      ),
      noticeWarningInk: mixColor(noticeWarningInk, other.noticeWarningInk),
      noticeErrorBackground: mixColor(
        noticeErrorBackground,
        other.noticeErrorBackground,
      ),
      noticeErrorBorder: mixColor(noticeErrorBorder, other.noticeErrorBorder),
      noticeErrorInk: mixColor(noticeErrorInk, other.noticeErrorInk),
      accentBorder: mixColor(accentBorder, other.accentBorder),
      floatingShadow: mixColor(floatingShadow, other.floatingShadow),
      inverseOn: mixColor(inverseOn, other.inverseOn),
      tagFallbackColors: [
        for (var i = 0; i < tagFallbackColors.length; i++)
          mixColor(
            tagFallbackColors[i],
            other.tagFallbackColors[i % other.tagFallbackColors.length],
          ),
      ],
      hoverAlpha: mixDouble(hoverAlpha, other.hoverAlpha),
      pressedAlpha: mixDouble(pressedAlpha, other.pressedAlpha),
      radiusCard: mixDouble(radiusCard, other.radiusCard),
      radiusDialog: mixDouble(radiusDialog, other.radiusDialog),
      radiusControl: mixDouble(radiusControl, other.radiusControl),
      radiusSmall: mixDouble(radiusSmall, other.radiusSmall),
      radiusXs: mixDouble(radiusXs, other.radiusXs),
      radiusPill: mixDouble(radiusPill, other.radiusPill),
      motionFast: mixDuration(motionFast, other.motionFast),
      motionBase: mixDuration(motionBase, other.motionBase),
      motionSlow: mixDuration(motionSlow, other.motionSlow),
      motionCurve: t >= 0.5 ? other.motionCurve : motionCurve,
    );
  }
}

/// Motion ladder shared by every planner animation (W4).
///
/// 120 / 180 / 240 ms with one curve; components must not invent their own
/// durations. PlannerTokens carries the same values so a dark or denser theme
/// can adjust motion without changing call sites.
abstract final class PlannerDurations {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration base = Duration(milliseconds: 180);
  static const Duration slow = Duration(milliseconds: 240);
  static const Curve curve = Curves.easeOutCubic;
}

/// The literal "Mist Ink" palette. This is the only place colour values are
/// written down; [PlannerTokens.light] and the legacy aliases both read it.
abstract final class PlannerPalette {
  static const canvas = Color(0xfff6f7f9);
  static const surface = Color(0xffffffff);
  static const surfaceMuted = Color(0xfff0f3f7);
  static const sidebar = Color(0xfff3f5f8);
  static const hover = Color(0xfff1f3f6);
  static const selected = Color(0xffe9f1f8);

  static const text = Color(0xff1c2530);
  static const muted = Color(0xff5a6675);
  static const subtle = Color(0xff8b96a5);

  static const border = Color(0xffe4e8ee);
  static const borderStrong = Color(0xffcdd5df);

  static const accent = Color(0xff2f5d8a);
  static const accentHover = Color(0xff244a70);
  static const accentSoft = Color(0xffe9f1f8);
  static const accentOn = Colors.white;
  static const success = Color(0xff2e7d66);
  static const warning = Color(0xffb7791f);
  static const danger = Color(0xffb54747);
  static const focusRing = Color(0x592f5d8a);
  static const selection = Color(0x332f5d8a);
  static const shadow = Color(0x1a0f172a);
  static const scrim = Color(0x660f172a);
  static const snackAction = Color(0xffa9c8e5);
  static const noticeSuccessBackground = Color(0xffeef7f2);
  static const noticeSuccessBorder = Color(0xffcfe7db);
  static const noticeSuccessInk = Color(0xff1f5f4a);
  static const noticeWarningBackground = Color(0xfffdf6e8);
  static const noticeWarningBorder = Color(0xffecd9b0);
  static const noticeWarningInk = Color(0xff8a5a12);
  static const noticeErrorBackground = Color(0xfffcefed);
  static const noticeErrorBorder = Color(0xfff0ccc7);
  static const noticeErrorInk = Color(0xff8f3733);
  static const accentBorder = Color(0xffb8cfe4);
  static const floatingShadow = Color(0x0a0f172a);
  static const inverseOn = Color(0xffffffff);
  static const tagFallbackColors = <Color>[
    Color(0xff537c87),
    Color(0xff7d629f),
    Color(0xffa06145),
    Color(0xff537e52),
    Color(0xff985c78),
    Color(0xff66739b),
  ];
}

/// The "Dense Graphite" dark palette (W5).
///
/// Same semantic roles as PlannerPalette; values tuned for >=4.5:1 body text
/// contrast on canvas/surface (see test/unit/planner_dark_theme_test.dart).
abstract final class PlannerDarkPalette {
  static const canvas = Color(0xff0f1115);
  static const surface = Color(0xff161a20);
  static const surfaceMuted = Color(0xff1c2128);
  static const sidebar = Color(0xff12161b);
  static const hover = Color(0xff232b35);
  static const selected = Color(0xff1e2f42);

  static const text = Color(0xffe7eaf0);
  static const muted = Color(0xffa8b2c0);
  static const subtle = Color(0xff808c9b);

  static const border = Color(0xff2a2f3a);
  static const borderStrong = Color(0xff3c4552);

  static const accent = Color(0xff7faad8);
  static const accentHover = Color(0xff9ac0e8);
  static const accentSoft = Color(0xff1b2b3d);
  static const accentOn = Color(0xff0b0e12);
  static const success = Color(0xff6cc7a6);
  static const warning = Color(0xffe0ae5a);
  static const danger = Color(0xffe68a8a);
  static const focusRing = Color(0x997faad8);
  static const selection = Color(0x557faad8);
  static const shadow = Color(0x66000000);
  static const scrim = Color(0x99000000);
  static const snackAction = Color(0xffa9c8e5);

  static const noticeSuccessBackground = Color(0xff16332a);
  static const noticeSuccessBorder = Color(0xff2e5748);
  static const noticeSuccessInk = Color(0xff7fd3b3);
  static const noticeWarningBackground = Color(0xff332a16);
  static const noticeWarningBorder = Color(0xff5c4a2a);
  static const noticeWarningInk = Color(0xffe8c177);
  static const noticeErrorBackground = Color(0xff331d1b);
  static const noticeErrorBorder = Color(0xff5a3633);
  static const noticeErrorInk = Color(0xffeda39c);
  static const accentBorder = Color(0xff3e5a78);
  static const floatingShadow = Color(0x33000000);
  static const inverseOn = Color(0xff0b0e12);
  static const tagFallbackColors = <Color>[
    Color(0xff8fb3bf),
    Color(0xffa894c4),
    Color(0xffc89577),
    Color(0xff88b58a),
    Color(0xffc08fa8),
    Color(0xff93a0c9),
  ];
}

/// Spacing on an 8 px grid (4 px for optical adjustments).
abstract final class PlannerSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double section = 28;
}

/// One base radius with a derived family: cards 12, controls 10, chips 8.
abstract final class PlannerRadius {
  static const double card = 12;
  static const double dialog = 14;
  static const double control = 10;
  static const double small = 8;
  static const double xs = 6;
  static const double pill = 999;
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );
  static const BorderRadius controlRadius = BorderRadius.all(
    Radius.circular(control),
  );
}

/// Maximum content width of a workbench page on desktop.
const double plannerPageMaxWidth = 1200;

/// Shorthand for feature widgets: context.tokens.muted.
extension PlannerTokensBuildContext on BuildContext {
  PlannerTokens get tokens => PlannerTokens.of(this);
}
