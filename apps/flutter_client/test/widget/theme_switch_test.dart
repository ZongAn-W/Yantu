import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/settings/presentation/settings_page.dart';

import 'planner_ui_test.dart' as harness;

Future<void> _openSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await harness.signIn(tester, respond: harness.plannerResponder(today: true));
  await tester.pumpAndSettle();
  await tester.tap(find.text('设置'));
  await tester.pumpAndSettle();
}

ThemeMode? _themeMode(WidgetTester tester) =>
    tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode;

void main() {
  testWidgets('appearance setting switches light, dark and system', (
    tester,
  ) async {
    await _openSettings(tester);
    expect(find.text('外观'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-theme-mode')), findsOneWidget);
    expect(_themeMode(tester), ThemeMode.system);

    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.dark,
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('浅色'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.light);
    expect(
      Theme.of(tester.element(find.byType(SettingsPage))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('跟随系统'));
    await tester.pumpAndSettle();
    expect(_themeMode(tester), ThemeMode.system);
    expect(tester.takeException(), isNull);
  });
}
