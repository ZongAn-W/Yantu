import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'planner_fonts.dart';

/// Design tokens shared with `DESIGN.md` (「雾蓝墨水 / Mist Ink」).
///
/// The visual language is borrowed from open-source projects:
/// - neutral token layering + radius/type ladder: AppFlowy (`appflowy_ui`),
/// - task/time-tracking density and state alphas: Super Productivity,
/// - near-black brand + hairline calendar surfaces: Cal.com (cal.diy),
/// - semantic `border` / `input` / `ring` separation: shadcn/ui + Radix Colors.
///
/// Keep this file the single source of colour/radius/spacing truth; feature
/// widgets should not hard-code new `Color(0x...)` values.
abstract final class PlannerColors {
  // Surfaces — never seed-tinted; Material's tonal palette turns blue into
  // lavender-grey, which is what made the old UI look washed out.
  static const background = Color(0xfff6f7f9); // app canvas
  static const surface = Color(0xffffffff); // cards, sheets
  static const surfaceMuted = Color(0xfff0f3f7); // inset blocks, hover rows
  static const sidebar = Color(0xfff3f5f8);
  static const hover = Color(0xfff1f3f6);
  static const selected = Color(0xffe9f1f8);

  // Ink
  static const text = Color(0xff1c2530);
  static const muted = Color(0xff5a6675);
  static const subtle = Color(0xff8b96a5);

  // Lines
  static const border = Color(0xffe4e8ee);
  static const borderStrong = Color(0xffcdd5df);

  // Accent + semantic
  static const blue = Color(0xff2f5d8a);
  static const blueHover = Color(0xff244a70);
  static const blueSoft = Color(0xffe9f1f8);
  static const green = Color(0xff2e7d66);
  static const orange = Color(0xffb7791f);
  static const danger = Color(0xffb54747);
  static const focusRing = Color(0x592f5d8a);
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

/// Physical hairline: 1 logical px at dpr 1, thinner on hiDPI so 1 px borders
/// do not turn muddy after scaling.
double plannerHairline(BuildContext context) {
  final dpr = MediaQuery.devicePixelRatioOf(context);
  return dpr >= 2 ? 1 / dpr : 1.0;
}

/// Hairline border with the stroke inside so adjacent borders do not double.
BorderSide plannerBorderSide(
  BuildContext context, {
  Color color = PlannerColors.border,
}) => BorderSide(
  color: color,
  width: plannerHairline(context),
  strokeAlign: BorderSide.strokeAlignInside,
);

/// Soft, single-purpose elevation for floating layers only (never on cards).
List<BoxShadow> plannerShadow() => const [
  BoxShadow(color: Color(0x0f0f172a), blurRadius: 16, offset: Offset(0, 4)),
];

ThemeData plannerTheme() {
  // Build the scheme explicitly: `fromSeed` is only used for the few Material
  // roles we do not override, and seeding is kept out of the neutrals.
  final seeded = ColorScheme.fromSeed(
    seedColor: PlannerColors.blue,
    brightness: Brightness.light,
  );
  final scheme = seeded.copyWith(
    primary: PlannerColors.blue,
    onPrimary: Colors.white,
    primaryContainer: PlannerColors.blueSoft,
    onPrimaryContainer: PlannerColors.blue,
    secondary: PlannerColors.green,
    onSecondary: Colors.white,
    secondaryContainer: PlannerColors.blueSoft,
    onSecondaryContainer: PlannerColors.blue,
    surface: PlannerColors.surface,
    onSurface: PlannerColors.text,
    onSurfaceVariant: PlannerColors.muted,
    surfaceContainerLowest: PlannerColors.surface,
    surfaceContainerLow: PlannerColors.background,
    surfaceContainer: PlannerColors.surfaceMuted,
    surfaceContainerHigh: PlannerColors.hover,
    surfaceContainerHighest: PlannerColors.selected,
    outline: PlannerColors.borderStrong,
    outlineVariant: PlannerColors.border,
    error: PlannerColors.danger,
    onError: Colors.white,
    shadow: const Color(0x1a0f172a),
    scrim: const Color(0x660f172a),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: PlannerColors.background,
    canvasColor: PlannerColors.background,
    dividerColor: PlannerColors.border,
    disabledColor: PlannerColors.subtle,
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
  );

  final text = base.textTheme.apply(
    bodyColor: PlannerColors.text,
    displayColor: PlannerColors.text,
  );

  TextStyle style(
    double size,
    double height,
    FontWeight weight, {
    Color color = PlannerColors.text,
    double letterSpacing = 0,
    List<FontFeature>? features,
  }) => TextStyle(
    fontSize: size,
    height: height / size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    fontFeatures: features,
  );

  final textTheme = text.copyWith(
    // Page title: 22 / 28.
    headlineSmall: style(22, 28, FontWeight.w600, letterSpacing: -0.2),
    // Dialog / big section title: 18 / 24.
    titleLarge: style(18, 24, FontWeight.w600),
    // Panel title: 15 / 22.
    titleMedium: style(15, 22, FontWeight.w600),
    // Row title / emphasised label: 13.5 / 20.
    titleSmall: style(13.5, 20, FontWeight.w600),
    bodyLarge: style(14, 22, FontWeight.w400),
    bodyMedium: style(13, 20, FontWeight.w400),
    bodySmall: style(12, 18, FontWeight.w400, color: PlannerColors.muted),
    labelLarge: style(13, 18, FontWeight.w500),
    labelMedium: style(12, 16, FontWeight.w500, color: PlannerColors.muted),
    labelSmall: style(11, 15, FontWeight.w500, color: PlannerColors.subtle),
  );

  OutlineInputBorder outline(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: PlannerRadius.controlRadius,
        borderSide: BorderSide(color: color, width: width),
      );

  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: PlannerColors.blue,
      selectionColor: Color(0x332f5d8a),
    ),
    iconTheme: const IconThemeData(color: PlannerColors.muted, size: 20),
    dividerTheme: const DividerThemeData(
      color: PlannerColors.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      color: PlannerColors.surface,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: PlannerColors.border),
        borderRadius: PlannerRadius.cardRadius,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: PlannerColors.surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: PlannerColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleMedium,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        elevation: 0,
        shadowColor: Colors.transparent,
        backgroundColor: PlannerColors.blue,
        foregroundColor: Colors.white,
        disabledBackgroundColor: PlannerColors.surfaceMuted,
        disabledForegroundColor: PlannerColors.subtle,
        shape: const RoundedRectangleBorder(
          borderRadius: PlannerRadius.controlRadius,
        ),
        textStyle: style(13, 18, FontWeight.w500, color: Colors.white),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: PlannerColors.text,
        side: const BorderSide(color: PlannerColors.borderStrong),
        shape: const RoundedRectangleBorder(
          borderRadius: PlannerRadius.controlRadius,
        ),
        textStyle: style(13, 18, FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        foregroundColor: PlannerColors.blue,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PlannerRadius.small)),
        ),
        textStyle: style(13, 18, FontWeight.w500),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: PlannerColors.muted,
        minimumSize: const Size(32, 32),
        iconSize: 19,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PlannerRadius.small)),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: PlannerColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      hintStyle: const TextStyle(
        color: PlannerColors.subtle,
        fontSize: 13,
        height: 1.4,
      ),
      labelStyle: const TextStyle(color: PlannerColors.muted, fontSize: 13),
      floatingLabelStyle: const TextStyle(
        color: PlannerColors.blue,
        fontSize: 12,
      ),
      border: outline(PlannerColors.border),
      enabledBorder: outline(PlannerColors.border),
      focusedBorder: outline(PlannerColors.blue, 1.5),
      errorBorder: outline(PlannerColors.danger),
      focusedErrorBorder: outline(PlannerColors.danger, 1.5),
      disabledBorder: outline(PlannerColors.border),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: PlannerColors.surfaceMuted,
      selectedColor: PlannerColors.selected,
      disabledColor: PlannerColors.surfaceMuted,
      side: const BorderSide(color: PlannerColors.border),
      labelStyle: const TextStyle(
        color: PlannerColors.muted,
        fontSize: 12,
        height: 1.3,
      ),
      secondaryLabelStyle: const TextStyle(
        color: PlannerColors.blue,
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w500,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(PlannerRadius.small)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: PlannerColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: PlannerColors.border),
        borderRadius: BorderRadius.all(Radius.circular(PlannerRadius.dialog)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 17,
        height: 24 / 17,
        fontWeight: FontWeight.w600,
        color: PlannerColors.text,
      ),
      contentTextStyle: TextStyle(
        fontSize: 13.5,
        height: 1.6,
        color: PlannerColors.muted,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: PlannerColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: PlannerColors.border),
        borderRadius: BorderRadius.circular(PlannerRadius.control),
      ),
      textStyle: textTheme.bodyMedium,
      menuPadding: const EdgeInsets.symmetric(vertical: 4),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: PlannerColors.text,
      contentTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 13,
        height: 1.45,
      ),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlannerRadius.control),
      ),
      actionTextColor: const Color(0xffa9c8e5),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: PlannerColors.text,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
        color: Colors.white,
        fontSize: 11.5,
        height: 1.3,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: PlannerColors.blue,
      linearTrackColor: PlannerColors.border,
      circularTrackColor: PlannerColors.border,
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: PlannerColors.sidebar,
      indicatorColor: PlannerColors.selected,
      selectedIconTheme: IconThemeData(color: PlannerColors.blue, size: 20),
      unselectedIconTheme: IconThemeData(color: PlannerColors.muted, size: 20),
      selectedLabelTextStyle: TextStyle(
        color: PlannerColors.blue,
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelTextStyle: TextStyle(
        color: PlannerColors.muted,
        fontSize: 12,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: PlannerColors.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: PlannerColors.selected,
      elevation: 0,
      height: 62,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11.5,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w400,
          color: states.contains(WidgetState.selected)
              ? PlannerColors.blue
              : PlannerColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 21,
          color: states.contains(WidgetState.selected)
              ? PlannerColors.blue
              : PlannerColors.muted,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.white
            : PlannerColors.surface,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PlannerColors.blue
            : PlannerColors.borderStrong,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PlannerColors.blue
            : Colors.transparent,
      ),
      side: const BorderSide(color: PlannerColors.borderStrong, width: 1.2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      visualDensity: VisualDensity.compact,
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? PlannerColors.blue
            : PlannerColors.borderStrong,
      ),
      visualDensity: VisualDensity.compact,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(7),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.dragged)
            ? const Color(0x4d5a6675)
            : const Color(0x2e5a6675),
      ),
      crossAxisMargin: 2,
    ),
  );
}

/// Digits in time and quantity columns line up, matching `tabular-nums` on the Web.
const tabularFigures = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
