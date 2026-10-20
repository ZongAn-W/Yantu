import 'package:flutter/material.dart';

import '../motion.dart';
import 'tokens.dart';

/// Material component sub-themes built from [PlannerTokens].
///
/// Organisation follows flex_color_scheme (BSD-3, design reference only):
/// one function per component family receives the token object instead of
/// reading global constants, so W5 can swap in a dark token set without
/// touching the feature widgets. Values here mirror the W2 theme exactly; see
/// test/unit/planner_tokens_test.dart for the compatibility guard.
abstract final class PlannerComponentThemes {
  static OutlineInputBorder _outline(
    PlannerTokens tokens,
    Color color, [
    double width = 1,
  ]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(tokens.radiusControl),
    borderSide: BorderSide(color: color, width: width),
  );

  static AppBarTheme appBar(PlannerTokens tokens, TextTheme textTheme) =>
      AppBarTheme(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: tokens.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleMedium,
      );

  static CardThemeData card(PlannerTokens tokens) => CardThemeData(
    color: tokens.surface,
    elevation: 0,
    shadowColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: tokens.border),
      borderRadius: BorderRadius.circular(tokens.radiusCard),
    ),
  );

  static DialogThemeData dialog(PlannerTokens tokens, TextTheme textTheme) =>
      DialogThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: tokens.border),
          borderRadius: BorderRadius.circular(tokens.radiusDialog),
        ),
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontSize: 17,
          height: 24 / 17,
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          fontSize: 13.5,
          height: 1.6,
          color: tokens.muted,
        ),
        barrierColor: tokens.scrim,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      );

  /// Material date picker (calendar header) styled with planner tokens.
  ///
  /// The default picker is the last large Material-owned surface in the app;
  /// without this it would ignore the Dense Graphite palette and the radius
  /// ladder. Time picker is not used.
  static DatePickerThemeData datePicker(
    PlannerTokens tokens,
    TextTheme textTheme,
  ) => DatePickerThemeData(
    backgroundColor: tokens.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusDialog),
      side: BorderSide(color: tokens.border),
    ),
    headerBackgroundColor: tokens.surface,
    headerForegroundColor: tokens.text,
    headerHeadlineStyle: textTheme.titleLarge,
    headerHelpStyle: textTheme.labelMedium?.copyWith(color: tokens.muted),
    weekdayStyle: textTheme.labelSmall?.copyWith(
      fontSize: 11.5,
      color: tokens.muted,
    ),
    dayStyle: textTheme.bodyMedium?.copyWith(fontSize: 13),
    dayForegroundColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.selected)) return tokens.accentOn;
      if (states.contains(WidgetState.disabled)) return tokens.subtle;
      return tokens.text;
    }),
    dayBackgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? tokens.accent
          : Colors.transparent,
    ),
    dayOverlayColor: WidgetStatePropertyAll(tokens.hover),
    todayForegroundColor: WidgetStatePropertyAll(tokens.accent),
    todayBackgroundColor: WidgetStatePropertyAll(tokens.accentSoft),
    todayBorder: BorderSide(color: tokens.accent),
    yearStyle: textTheme.bodyMedium,
    yearForegroundColor: WidgetStateProperty.resolveWith(
      (states) =>
          states.contains(WidgetState.selected) ? tokens.accentOn : tokens.text,
    ),
    yearBackgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? tokens.accent
          : Colors.transparent,
    ),
    dividerColor: tokens.border,
    cancelButtonStyle: TextButton.styleFrom(
      foregroundColor: tokens.muted,
      textStyle: textTheme.labelLarge,
    ),
    confirmButtonStyle: TextButton.styleFrom(
      foregroundColor: tokens.accent,
      textStyle: textTheme.labelLarge,
    ),
  );

  static FilledButtonThemeData filledButton(
    PlannerTokens tokens,
    TextTheme textTheme,
  ) => FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      elevation: 0,
      shadowColor: Colors.transparent,
      backgroundColor: tokens.accent,
      foregroundColor: tokens.accentOn,
      disabledBackgroundColor: tokens.surfaceMuted,
      disabledForegroundColor: tokens.subtle,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusControl),
      ),
      textStyle: textTheme.labelLarge?.copyWith(color: tokens.accentOn),
    ),
  );

  static OutlinedButtonThemeData outlinedButton(
    PlannerTokens tokens,
    TextTheme textTheme,
  ) => OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      foregroundColor: tokens.text,
      side: BorderSide(color: tokens.borderStrong),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusControl),
      ),
      textStyle: textTheme.labelLarge,
    ),
  );

  static TextButtonThemeData textButton(
    PlannerTokens tokens,
    TextTheme textTheme,
  ) => TextButtonThemeData(
    style: TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      foregroundColor: tokens.accent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tokens.radiusSmall),
      ),
      textStyle: textTheme.labelLarge,
    ),
  );

  static IconButtonThemeData iconButton(PlannerTokens tokens) =>
      IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: tokens.muted,
          minimumSize: const Size(32, 32),
          iconSize: 19,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(tokens.radiusSmall),
          ),
        ),
      );

  static InputDecorationTheme input(PlannerTokens tokens) =>
      InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: tokens.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
        hintStyle: TextStyle(color: tokens.subtle, fontSize: 13, height: 1.4),
        labelStyle: TextStyle(color: tokens.muted, fontSize: 13),
        floatingLabelStyle: TextStyle(color: tokens.accent, fontSize: 12),
        border: _outline(tokens, tokens.border),
        enabledBorder: _outline(tokens, tokens.border),
        focusedBorder: _outline(tokens, tokens.accent, 1.5),
        errorBorder: _outline(tokens, tokens.danger),
        focusedErrorBorder: _outline(tokens, tokens.danger, 1.5),
        disabledBorder: _outline(tokens, tokens.border),
      );

  static ChipThemeData chip(PlannerTokens tokens) => ChipThemeData(
    backgroundColor: tokens.surfaceMuted,
    selectedColor: tokens.selected,
    disabledColor: tokens.surfaceMuted,
    side: BorderSide(color: tokens.border),
    labelStyle: TextStyle(color: tokens.muted, fontSize: 12, height: 1.3),
    secondaryLabelStyle: TextStyle(
      color: tokens.accent,
      fontSize: 12,
      height: 1.3,
      fontWeight: FontWeight.w500,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusSmall),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
  );

  static PopupMenuThemeData popupMenu(
    PlannerTokens tokens,
    TextTheme textTheme,
  ) => PopupMenuThemeData(
    color: tokens.surface,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: tokens.border),
      borderRadius: BorderRadius.circular(tokens.radiusControl),
    ),
    textStyle: textTheme.bodyMedium,
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
  );

  static SnackBarThemeData snackBar(PlannerTokens tokens) => SnackBarThemeData(
    backgroundColor: tokens.text,
    contentTextStyle: TextStyle(
      color: tokens.inverseOn,
      fontSize: 13,
      height: 1.45,
    ),
    behavior: SnackBarBehavior.floating,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(tokens.radiusControl),
    ),
    actionTextColor: tokens.snackAction,
  );

  static TooltipThemeData tooltip(PlannerTokens tokens) => TooltipThemeData(
    waitDuration: const Duration(milliseconds: 450),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: tokens.text,
      borderRadius: BorderRadius.circular(tokens.radiusXs),
    ),
    textStyle: TextStyle(color: tokens.inverseOn, fontSize: 11.5, height: 1.3),
  );

  static ProgressIndicatorThemeData progress(PlannerTokens tokens) =>
      ProgressIndicatorThemeData(
        color: tokens.accent,
        linearTrackColor: tokens.border,
        circularTrackColor: tokens.border,
      );

  static NavigationRailThemeData navigationRail(PlannerTokens tokens) =>
      NavigationRailThemeData(
        backgroundColor: tokens.sidebar,
        indicatorColor: tokens.selected,
        selectedIconTheme: IconThemeData(color: tokens.accent, size: 20),
        unselectedIconTheme: IconThemeData(color: tokens.muted, size: 20),
        selectedLabelTextStyle: TextStyle(
          color: tokens.accent,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelTextStyle: TextStyle(color: tokens.muted, fontSize: 12),
      );

  static NavigationBarThemeData navigationBar(PlannerTokens tokens) =>
      NavigationBarThemeData(
        backgroundColor: tokens.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: tokens.selected,
        elevation: 0,
        height: 62,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? tokens.accent
                : tokens.muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 21,
            color: states.contains(WidgetState.selected)
                ? tokens.accent
                : tokens.muted,
          ),
        ),
      );

  static SwitchThemeData toggleSwitch(PlannerTokens tokens) => SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? tokens.accentOn
          : tokens.surface,
    ),
    trackColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? tokens.accent
          : tokens.borderStrong,
    ),
    trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
  );

  static CheckboxThemeData checkbox(PlannerTokens tokens) => CheckboxThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? tokens.accent
          : Colors.transparent,
    ),
    side: BorderSide(color: tokens.borderStrong, width: 1.2),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    visualDensity: VisualDensity.compact,
  );

  static RadioThemeData radio(PlannerTokens tokens) => RadioThemeData(
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? tokens.accent
          : tokens.borderStrong,
    ),
    visualDensity: VisualDensity.compact,
  );

  static ScrollbarThemeData scrollbar(PlannerTokens tokens) =>
      ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(7),
        radius: const Radius.circular(4),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.dragged)
              ? tokens.muted.withValues(alpha: 0.30)
              : tokens.muted.withValues(alpha: 0.18),
        ),
        crossAxisMargin: 2,
      );

  /// Applies every planner sub-theme on top of [base].
  static ThemeData apply(
    ThemeData base, {
    required PlannerTokens tokens,
    required TextTheme textTheme,
  }) => base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: tokens.accent,
      selectionColor: tokens.selection,
    ),
    iconTheme: IconThemeData(color: tokens.muted, size: 20),
    dividerTheme: DividerThemeData(
      color: tokens.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: card(tokens),
    appBarTheme: appBar(tokens, textTheme),
    filledButtonTheme: filledButton(tokens, textTheme),
    outlinedButtonTheme: outlinedButton(tokens, textTheme),
    textButtonTheme: textButton(tokens, textTheme),
    iconButtonTheme: iconButton(tokens),
    inputDecorationTheme: input(tokens),
    chipTheme: chip(tokens),
    dialogTheme: dialog(tokens, textTheme),
    datePickerTheme: datePicker(tokens, textTheme),
    popupMenuTheme: popupMenu(tokens, textTheme),
    snackBarTheme: snackBar(tokens),
    tooltipTheme: tooltip(tokens),
    progressIndicatorTheme: progress(tokens),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: PlannerPageTransitionsBuilder(),
        TargetPlatform.iOS: PlannerPageTransitionsBuilder(),
        TargetPlatform.linux: PlannerPageTransitionsBuilder(),
        TargetPlatform.macOS: PlannerPageTransitionsBuilder(),
        TargetPlatform.windows: PlannerPageTransitionsBuilder(),
        TargetPlatform.fuchsia: PlannerPageTransitionsBuilder(),
      },
    ),
    navigationRailTheme: navigationRail(tokens),
    navigationBarTheme: navigationBar(tokens),
    switchTheme: toggleSwitch(tokens),
    checkboxTheme: checkbox(tokens),
    radioTheme: radio(tokens),
    scrollbarTheme: scrollbar(tokens),
  );
}
