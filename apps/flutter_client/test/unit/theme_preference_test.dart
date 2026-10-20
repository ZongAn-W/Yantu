import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/settings/application/theme_preference.dart';

class _FakeThemeStore implements ThemePreferenceStore {
  _FakeThemeStore(this._loaded);

  final PlannerThemeMode _loaded;
  PlannerThemeMode? saved;
  Completer<PlannerThemeMode>? gate;

  @override
  Future<PlannerThemeMode> load() async {
    final pending = gate;
    if (pending != null) return pending.future;
    return _loaded;
  }

  @override
  Future<void> save(PlannerThemeMode mode) async {
    saved = mode;
  }
}

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlannerThemeMode', () {
    test('maps to Flutter ThemeMode and parses stored values', () {
      expect(PlannerThemeMode.system.themeMode, ThemeMode.system);
      expect(PlannerThemeMode.light.themeMode, ThemeMode.light);
      expect(PlannerThemeMode.dark.themeMode, ThemeMode.dark);
      expect(PlannerThemeMode.fromStored('dark'), PlannerThemeMode.dark);
      expect(PlannerThemeMode.fromStored('light'), PlannerThemeMode.light);
      expect(
        PlannerThemeMode.fromStored('unexpected'),
        PlannerThemeMode.system,
      );
      expect(PlannerThemeMode.fromStored(null), PlannerThemeMode.system);
      expect(PlannerThemeMode.system.label, '跟随系统');
    });

    test('restores the saved appearance', () async {
      final store = _FakeThemeStore(PlannerThemeMode.dark);
      final controller = PlannerThemeModeController(store);
      addTearDown(controller.dispose);
      await _flush();
      expect(controller.state, PlannerThemeMode.dark);
    });

    test('a choice made during restore wins and is persisted', () async {
      final store = _FakeThemeStore(PlannerThemeMode.light);
      store.gate = Completer<PlannerThemeMode>();
      final controller = PlannerThemeModeController(store);
      addTearDown(controller.dispose);
      await controller.setMode(PlannerThemeMode.dark);
      expect(controller.state, PlannerThemeMode.dark);
      expect(store.saved, PlannerThemeMode.dark);

      store.gate!.complete(PlannerThemeMode.light);
      await _flush();
      expect(controller.state, PlannerThemeMode.dark);
    });

    test('a broken local store keeps the in-memory choice', () async {
      final store = _BrokenThemeStore();
      final controller = PlannerThemeModeController(store);
      addTearDown(controller.dispose);
      await _flush();
      expect(controller.state, PlannerThemeMode.system);
      await controller.setMode(PlannerThemeMode.light);
      expect(controller.state, PlannerThemeMode.light);
    });
  });
}

class _BrokenThemeStore implements ThemePreferenceStore {
  @override
  Future<PlannerThemeMode> load() =>
      Future<PlannerThemeMode>.error(StateError('storage unavailable'));

  @override
  Future<void> save(PlannerThemeMode mode) =>
      Future<void>.error(StateError('storage unavailable'));
}
