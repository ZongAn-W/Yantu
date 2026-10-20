import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/planner_date_picker.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';

Widget _host({required void Function(DateTime?) onPicked}) => MaterialApp(
  theme: plannerTheme(),
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: FilledButton(
          key: const ValueKey('open-picker'),
          onPressed: () async {
            final picked = await showPlannerDatePicker(
              context,
              initialDate: DateTime(2026, 10, 21),
              title: '选择查看日期',
            );
            onPicked(picked);
          },
          child: const Text('打开'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'planner date picker is Chinese, selectable and returns the day',
    (tester) async {
      DateTime? picked;
      await tester.pumpWidget(_host(onPicked: (value) => picked = value));
      await tester.tap(find.byKey(const ValueKey('open-picker')));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('planner-date-picker')), findsOneWidget);
      expect(find.text('选择查看日期'), findsOneWidget);
      expect(find.text('2026年10月'), findsOneWidget);
      expect(find.text('October 2026'), findsNothing);
      for (final weekday in ['一', '二', '三', '四', '五', '六', '日']) {
        expect(find.text(weekday), findsOneWidget);
      }

      await tester.tap(
        find.byKey(const ValueKey('planner-date-picker-day-2026-10-15')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('planner-date-picker-confirm')),
      );
      await tester.pumpAndSettle();
      expect(picked, DateTime(2026, 10, 15));
      expect(find.byKey(const ValueKey('planner-date-picker')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('planner date picker navigates months and cancels', (
    tester,
  ) async {
    DateTime? picked;
    var calls = 0;
    await tester.pumpWidget(
      _host(
        onPicked: (value) {
          picked = value;
          calls++;
        },
      ),
    );
    await tester.tap(find.byKey(const ValueKey('open-picker')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('planner-date-picker-next')));
    await tester.pump();
    expect(find.text('2026年11月'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('planner-date-picker-previous')),
    );
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey('planner-date-picker-previous')),
    );
    await tester.pump();
    expect(find.text('2026年9月'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('planner-date-picker-cancel')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
