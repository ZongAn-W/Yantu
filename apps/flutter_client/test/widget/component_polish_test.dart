import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/core/widgets.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/presentation/planner_page_state.dart';

Widget _host(Widget child) => MaterialApp(
  theme: plannerTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('shared loading states', () {
    testWidgets('PlannerLoading renders a token spinner and live label', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const PlannerLoading()));
      expect(find.text('正在读取本机计划…'), findsOneWidget);
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.color, PlannerTokens.light.accent);
      expect(spinner.backgroundColor, PlannerTokens.light.border);
      final semantics = tester.ensureSemantics();
      expect(find.bySemanticsLabel('正在读取本机计划…'), findsOneWidget);
      semantics.dispose();
    });

    testWidgets('PlannerSpinner honours size and token colours', (
      tester,
    ) async {
      await tester.pumpWidget(_host(const PlannerSpinner(size: 20)));
      expect(tester.getSize(find.byType(PlannerSpinner)), const Size(20, 20));
      final spinner = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(spinner.strokeWidth, 2);
      expect(spinner.color, PlannerTokens.light.accent);
    });

    testWidgets('PlannerPageState uses PlannerLoading while not ready', (
      tester,
    ) async {
      const snapshot = PlannerSnapshot(
        data: null,
        revision: 0,
        pending: false,
        status: SyncStatus.connecting,
        message: '',
        blocked: false,
        ready: false,
        busy: false,
        conflicts: [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [plannerDataProvider.overrideWithValue(snapshot)],
          child: MaterialApp(
            theme: plannerTheme(),
            home: PlannerPageState(
              builder: (context, snapshot) => const SizedBox.shrink(),
            ),
          ),
        ),
      );
      expect(find.byType(PlannerLoading), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('component theme polish', () {
    final theme = plannerTheme();
    const tokens = PlannerTokens.light;

    test('dialog shell uses planner scrim, radius and spacing', () {
      expect(theme.dialogTheme.barrierColor, tokens.scrim);
      expect(
        theme.dialogTheme.insetPadding,
        const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      );
      expect(
        theme.dialogTheme.actionsPadding,
        const EdgeInsets.fromLTRB(20, 0, 20, 16),
      );
      final shape = theme.dialogTheme.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(tokens.radiusDialog));
      expect((shape.side).color, tokens.border);
    });

    test('date picker is fully token themed', () {
      final picker = theme.datePickerTheme;
      expect(picker.backgroundColor, tokens.surface);
      expect(picker.todayBackgroundColor?.resolve({}), tokens.accentSoft);
      expect(picker.todayForegroundColor?.resolve({}), tokens.accent);
      expect(picker.todayBorder?.color, tokens.accent);
      expect(picker.headerBackgroundColor, tokens.surface);
      expect(picker.headerForegroundColor, tokens.text);
      expect(
        picker.confirmButtonStyle?.foregroundColor?.resolve({}),
        tokens.accent,
      );
      final shape = picker.shape! as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(tokens.radiusDialog));
    });

    test('menus, tooltips and snackbars stay on tokens', () {
      expect(theme.popupMenuTheme.color, tokens.surface);
      final menuShape = theme.popupMenuTheme.shape! as RoundedRectangleBorder;
      expect(
        menuShape.borderRadius,
        BorderRadius.circular(tokens.radiusControl),
      );
      expect(theme.tooltipTheme.textStyle?.color, tokens.inverseOn);
      expect(theme.snackBarTheme.contentTextStyle?.color, tokens.inverseOn);
      expect(theme.snackBarTheme.actionTextColor, tokens.snackAction);
      expect(theme.scrollbarTheme.thickness?.resolve({}), 7);
      expect(theme.cardTheme.color, tokens.surface);
    });

    test('Chinese typography floor: body >=12.5, labels >=11', () {
      final text = theme.textTheme;
      expect(text.bodyMedium?.fontSize, greaterThanOrEqualTo(12.5));
      expect(text.bodySmall?.fontSize, greaterThanOrEqualTo(12.5));
      expect(text.titleSmall?.fontSize, greaterThanOrEqualTo(12.5));
      expect(text.labelMedium?.fontSize, greaterThanOrEqualTo(11));
      expect(text.labelSmall?.fontSize, greaterThanOrEqualTo(11));
    });
  });
}
