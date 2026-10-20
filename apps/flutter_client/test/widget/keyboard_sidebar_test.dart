import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';

import 'planner_ui_test.dart' as harness;

Future<void> _pumpDesktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1366, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await harness.signIn(tester, respond: harness.plannerResponder(today: true));
  await tester.pumpAndSettle();
}

String? _focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

Future<void> _focusSidebarNav(WidgetTester tester) async {
  for (var attempt = 0; attempt < 12; attempt++) {
    if (_focusedLabel()?.startsWith('sidebar-nav-') ?? false) return;
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('could not focus the sidebar navigation through Tab');
}

Finder _focusRingFinder() => find.byWidgetPredicate(
  (widget) =>
      widget is DecoratedBox &&
      widget.decoration is BoxDecoration &&
      ((widget.decoration as BoxDecoration).boxShadow?.any(
            (shadow) => shadow.color == PlannerColors.focusRing,
          ) ??
          false),
  description: 'sidebar focus ring',
);

void main() {
  testWidgets('sidebar arrow keys, Home/End and Enter navigate the workbench', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    await _focusSidebarNav(tester);
    expect(_focusedLabel(), 'sidebar-nav-/');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusedLabel(), 'sidebar-nav-/calendar');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusedLabel(), 'sidebar-nav-/adjust');

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pump();
    expect(_focusedLabel(), 'sidebar-nav-/settings');

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(_focusedLabel(), 'sidebar-nav-/');

    // Focus the calendar destination and activate it with Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold).first),
    );
    expect(container.read(appRouterProvider).state.uri.path, '/calendar');
    expect(find.byKey(const ValueKey('calendar-overview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar collapses to a 64 px icon rail and expands back', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    final sidebar = find.byKey(const ValueKey('app-sidebar'));
    expect(tester.getSize(sidebar).width, 240);
    expect(find.text('工作台'), findsOneWidget);
    expect(find.text('当前目标'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar-collapse-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 64);
    expect(find.text('工作台'), findsNothing);
    expect(find.text('当前目标'), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-nav-/calendar')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sidebar-collapse-toggle')));
    await tester.pumpAndSettle();
    expect(tester.getSize(sidebar).width, 240);
    expect(find.text('工作台'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('focused sidebar destination draws the focus ring', (
    tester,
  ) async {
    await _pumpDesktop(tester);
    expect(_focusRingFinder(), findsNothing);
    await _focusSidebarNav(tester);
    await tester.pump();
    expect(_focusRingFinder(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(_focusRingFinder(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile shell keeps the bottom nav and has no collapse control', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await harness.signIn(
      tester,
      respond: harness.plannerResponder(today: true),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byKey(const ValueKey('app-sidebar')), findsNothing);
    expect(find.byKey(const ValueKey('sidebar-collapse-toggle')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
