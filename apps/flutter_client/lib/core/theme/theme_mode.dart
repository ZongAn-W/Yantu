import 'package:flutter/material.dart';

/// User-facing appearance setting (W5).
enum PlannerThemeMode {
  system('跟随系统'),
  light('浅色'),
  dark('深色');

  const PlannerThemeMode(this.label);

  final String label;

  ThemeMode get themeMode => switch (this) {
    PlannerThemeMode.system => ThemeMode.system,
    PlannerThemeMode.light => ThemeMode.light,
    PlannerThemeMode.dark => ThemeMode.dark,
  };

  /// Stable key used by the local preferences store.
  String get storedValue => name;

  static PlannerThemeMode fromStored(String? value) => switch (value) {
    'light' => PlannerThemeMode.light,
    'dark' => PlannerThemeMode.dark,
    _ => PlannerThemeMode.system,
  };
}
