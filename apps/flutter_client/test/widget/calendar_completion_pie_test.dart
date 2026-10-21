import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/core/widgets.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_completion_data.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_completion_pie.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';

CalendarCompletionSlice _slice({
  required String id,
  required String title,
  required int minutes,
  List<String> tagNames = const [],
  String? tagColor,
}) => CalendarCompletionSlice(
  id: id,
  title: title,
  tagNames: tagNames,
  tagColor: tagColor,
  minutes: minutes,
);

CalendarCompletionData _data(List<CalendarCompletionSlice> slices) =>
    CalendarCompletionData(
      slices: List.unmodifiable(slices),
      totalMinutes: slices.fold<int>(0, (sum, slice) => sum + slice.minutes),
    );

final Finder _legendRows = find.byWidgetPredicate((widget) {
  final key = widget.key;
  return key is ValueKey<String> &&
      key.value.startsWith('calendar-period-pie-slice-');
});

Finder _row(String id) => find.byKey(ValueKey('calendar-period-pie-slice-$id'));

String _totalText(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('calendar-period-pie-total')))
    .data!;

/// Percentages read from the legend timing labels, in legend order.
List<int> _legendPercents(WidgetTester tester) {
  final percents = <int>[];
  final texts = find.descendant(of: _legendRows, matching: find.byType(Text));
  for (final element in texts.evaluate()) {
    final label = (element.widget as Text).data ?? '';
    final match = RegExp(r'(\d+)%\s*$').firstMatch(label);
    if (match != null) percents.add(int.parse(match.group(1)!));
  }
  return percents;
}

Future<void> _pumpPie(
  WidgetTester tester,
  CalendarCompletionData data, {
  ThemeData? theme,
  Size size = const Size(1200, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? plannerTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: CalendarCompletionPie(data: data),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders title, subtitle, centre total and legend rows', (
    tester,
  ) async {
    final data = _data([
      _slice(
        id: 'task:calculus',
        title: '高数',
        minutes: 90,
        tagNames: ['数学'],
        tagColor: '#3366ff',
      ),
      _slice(id: 'task:english', title: '英语', minutes: 30),
    ]);
    await _pumpPie(tester, data);

    expect(find.byKey(const ValueKey('calendar-period-pie')), findsOneWidget);
    expect(
      tester.widget(find.byKey(const ValueKey('calendar-period-pie'))),
      isA<PlannerPanel>(),
    );
    expect(find.text('本期完成事项'), findsOneWidget);
    expect(find.text('按实际学习用时'), findsOneWidget);
    expect(_totalText(tester), duration(120));
    expect(find.text('共 2 个事项'), findsOneWidget);

    expect(_row('task:calculus'), findsOneWidget);
    expect(_row('task:english'), findsOneWidget);
    expect(
      find.descendant(of: _row('task:calculus'), matching: find.text('高数')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row('task:calculus'),
        matching: find.text('${duration(90)} · 75%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: _row('task:english'),
        matching: find.text('${duration(30)} · 25%'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-period-pie')),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      ),
      findsWidgets,
      reason: 'the donut ring is painted',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('legend percentages always add up to exactly 100', (
    tester,
  ) async {
    final distributions = <List<int>>[
      [10, 10, 10],
      [1, 1, 1, 1, 1, 1, 1],
      [1, 2, 3],
      [7, 11, 13],
      [47, 53],
      [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5],
    ];
    for (final minutes in distributions) {
      final slices = [
        for (var index = 0; index < minutes.length; index++)
          _slice(
            id: 'item-$index',
            title: '事项 $index',
            minutes: minutes[index],
          ),
      ];
      await _pumpPie(tester, _data(slices));
      final percents = _legendPercents(tester);
      // The pie folds any tail beyond eight items into one "其他" row, so the
      // visible row count is eight at most.
      expect(percents, hasLength(minutes.length <= 8 ? minutes.length : 8));
      expect(
        percents.fold<int>(0, (sum, value) => sum + value),
        100,
        reason: 'minutes=$minutes',
      );
      expect(percents.every((value) => value >= 1), isTrue);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('empty period shows the quiet empty state', (tester) async {
    await _pumpPie(tester, CalendarCompletionData.empty);

    expect(find.byKey(const ValueKey('calendar-period-pie')), findsOneWidget);
    expect(find.text('本期完成事项'), findsOneWidget);
    expect(find.text('按实际学习用时'), findsOneWidget);
    final empty = find.byKey(const ValueKey('calendar-period-pie-empty'));
    expect(empty, findsOneWidget);
    expect(tester.widget<Text>(empty).data, '本期还没有学习记录');
    expect(
      find.byKey(const ValueKey('calendar-period-pie-total')),
      findsNothing,
    );
    expect(find.text('共 0 个事项'), findsNothing);
    expect(_legendRows, findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('calendar-period-pie')),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      ),
      findsNothing,
      reason: 'the empty state draws no ring',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('folds items beyond eight into one other row', (tester) async {
    final slices = [
      for (var index = 0; index < 10; index++)
        _slice(id: 'item-$index', title: '事项 $index', minutes: 100 - index * 5),
    ];
    await _pumpPie(tester, _data(slices));

    // The centre always reports the true item count.
    expect(find.text('共 10 个事项'), findsOneWidget);
    expect(_totalText(tester), duration(775));
    for (var index = 0; index < 7; index++) {
      expect(_row('item-$index'), findsOneWidget, reason: 'item-$index');
    }
    expect(_row('item-7'), findsNothing);
    expect(_row('item-8'), findsNothing);
    expect(_row('item-9'), findsNothing);
    final other = _row('other');
    expect(other, findsOneWidget);
    expect(
      find.descendant(of: other, matching: find.text('其他 3 个事项')),
      findsOneWidget,
    );
    expect(_legendRows, findsNWidgets(8));
    final percents = _legendPercents(tester);
    expect(percents, hasLength(8));
    expect(percents.fold<int>(0, (sum, value) => sum + value), 100);
    expect(tester.takeException(), isNull);

    // Exactly eight items is the boundary: every item keeps its own row.
    final boundary = [for (var index = 0; index < 8; index++) slices[index]];
    await _pumpPie(tester, _data(boundary));
    expect(_legendRows, findsNWidgets(8));
    expect(_row('other'), findsNothing);
    expect(find.text('共 8 个事项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a 320px wide surface without overflow', (tester) async {
    final data = _data([
      _slice(
        id: 'task:long',
        title: '高等数学第一轮基础复习：极限、导数与多元积分',
        minutes: 240,
        tagNames: ['考研数学'],
        tagColor: '#3366ff',
      ),
      _slice(id: 'task:b', title: '英语长难句与真题阅读', minutes: 90),
      _slice(id: 'task:c', title: '408 数据结构', minutes: 60),
      _slice(id: 'task:d', title: '操作系统', minutes: 45),
      _slice(id: 'task:e', title: '政治', minutes: 15),
    ]);
    await _pumpPie(tester, data, size: const Size(320, 1400));

    final pie = find.byKey(const ValueKey('calendar-period-pie'));
    expect(pie, findsOneWidget);
    expect(tester.getSize(pie).width, lessThanOrEqualTo(320));
    for (final row in _legendRows.evaluate()) {
      expect(
        tester.getRect(find.byWidget(row.widget)).right,
        lessThanOrEqualTo(320.5),
      );
    }
    expect(_totalText(tester), duration(450));
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders in the dark theme without exceptions', (tester) async {
    final data = _data([
      _slice(
        id: 'task:a',
        title: '高数',
        minutes: 60,
        tagNames: ['数学'],
        tagColor: '#3366ff',
      ),
      _slice(id: 'legacy', title: '历史学习记录', minutes: 20),
      _slice(id: 'deleted', title: '已删除事项', minutes: 10),
    ]);
    await _pumpPie(
      tester,
      data,
      theme: plannerDarkTheme(),
      size: const Size(1000, 800),
    );

    expect(find.text('本期完成事项'), findsOneWidget);
    expect(_totalText(tester), duration(90));
    expect(find.text('共 3 个事项'), findsOneWidget);
    expect(_row('task:a'), findsOneWidget);
    expect(_row('legacy'), findsOneWidget);
    expect(_row('deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'legend colours prefer the tag colour and hash a stable fallback',
    (tester) async {
      Color legendDot(String id) {
        final dot = tester.widget<Container>(
          find.descendant(of: _row(id), matching: find.byType(Container)).first,
        );
        return (dot.decoration! as BoxDecoration).color!;
      }

      // A tag colour is kept exactly for its first slice. Fallback colours come
      // from the token palette; when two owners hash to the same palette entry,
      // the duplicate is lifted towards the surface/ink instead of repeating.
      Set<Color> allowedShades(PlannerTokens tokens) {
        final lift = tokens.isDark ? tokens.text : tokens.surface;
        return {
          for (final base in tokens.tagFallbackColors) ...[
            base,
            for (var step = 1; step <= 3; step++)
              Color.lerp(base, lift, 0.18 * step)!,
          ],
        };
      }

      final tagged = _slice(
        id: 'task:tagged',
        title: '高数',
        minutes: 30,
        tagColor: '#3366ff',
      );
      final plainOne = _slice(id: 'task:plain-one', title: '英语', minutes: 20);
      final plainTwo = _slice(id: 'task:plain-two', title: '408', minutes: 10);
      final data = _data([tagged, plainOne, plainTwo]);
      await _pumpPie(tester, data);

      final light = PlannerTokens.light;
      expect(
        legendDot('task:tagged'),
        light.dataTone(const Color(0xff3366ff)),
        reason: 'an explicit tag colour keeps its hue in light mode',
      );
      final lightShades = allowedShades(light);
      expect(lightShades, contains(legendDot('task:plain-one')));
      expect(lightShades, contains(legendDot('task:plain-two')));
      expect(
        legendDot('task:plain-one'),
        isNot(legendDot('task:plain-two')),
        reason: 'two visible slices must never share one legend colour',
      );

      // The fallback is hashed from the owner id, so a rebuild keeps the colour.
      final stable = legendDot('task:plain-one');
      await _pumpPie(tester, data);
      expect(legendDot('task:plain-one'), stable);

      // Two tasks of the same tag keep the hue but can be told apart.
      final sameTag = _slice(
        id: 'task:tagged-two',
        title: '高数二轮',
        minutes: 5,
        tagColor: '#3366ff',
      );
      await _pumpPie(tester, _data([tagged, sameTag]));
      expect(
        legendDot('task:tagged-two'),
        Color.lerp(
          light.dataTone(const Color(0xff3366ff)),
          light.surface,
          0.18,
        ),
        reason: 'a duplicate tag colour is lifted instead of repeated',
      );

      // Dark mode lifts the explicit colour through tokens.dataTone.
      await _pumpPie(tester, data, theme: plannerDarkTheme());
      expect(
        legendDot('task:tagged'),
        PlannerTokens.dark.dataTone(const Color(0xff3366ff)),
      );
      expect(
        allowedShades(PlannerTokens.dark),
        contains(legendDot('task:plain-one')),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the pie is read-only: no timer, edit or completion controls', (
    tester,
  ) async {
    final data = _data([
      _slice(id: 'task:a', title: '高数', minutes: 30),
      _slice(id: 'task:b', title: '英语', minutes: 30),
    ]);
    await _pumpPie(tester, data);

    final pie = find.byKey(const ValueKey('calendar-period-pie'));
    for (final control in <Finder>[
      find.byType(TextButton),
      find.byType(FilledButton),
      find.byType(OutlinedButton),
      find.byType(IconButton),
      find.byType(TextField),
      find.byType(Checkbox),
      find.byType(Switch),
    ]) {
      expect(
        find.descendant(of: pie, matching: control),
        findsNothing,
        reason: '$control must not appear inside the read-only pie',
      );
    }
    expect(find.text('开始计时'), findsNothing);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
