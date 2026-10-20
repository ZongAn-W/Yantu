import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/storage_repository.dart';
import 'package:sjtu_study_planner_client/core/storage/study_timer_store.dart';
import 'package:sjtu_study_planner_client/core/sync/planner_coordinator.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_api.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/core/widgets.dart';
import 'package:sjtu_study_planner_client/features/calendar/application/calendar_view_preference.dart';
import 'package:sjtu_study_planner_client/features/calendar/domain/calendar_view.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_month_chart.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_page.dart';
import 'package:sjtu_study_planner_client/features/calendar/presentation/calendar_week_chart.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/planner/application/study_timer.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/planner_format.dart';
import 'package:sjtu_study_planner_client/features/tasks/presentation/task_directory.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

/// Keyboard and focus coverage for the shared desktop controls (W2-B).
///
/// The tests drive real focus nodes with [WidgetTester.sendKeyEvent]; they do
/// not fabricate key state, so a regression in the real focus tree fails here.

const _segmentedRing = Key('planner-segmented-focus-ring');
const _tagRing = Key('planner-tag-focus-ring');

class _MemoryDayViewStore implements CalendarViewPreferenceStore {
  CalendarView value = CalendarView.rivers;

  @override
  Future<CalendarView> load() async => value;

  @override
  Future<void> save(CalendarView view) async {
    value = view;
  }
}

class _MemoryWeekViewStore implements CalendarWeekViewPreferenceStore {
  CalendarWeekView value = CalendarWeekView.mirror;

  @override
  Future<CalendarWeekView> load() async => value;

  @override
  Future<void> save(CalendarWeekView view) async {
    value = view;
  }
}

class _NoopSync implements SyncApi {
  @override
  Future<RemoteSnapshot> pull({int? revision}) async =>
      const RemoteSnapshot(null, 0);

  @override
  Future<RemoteSnapshot> push(
    PlannerData data,
    PlannerData? base,
    int revision,
  ) async => RemoteSnapshot(data, revision + 1);
}

class _MemoryTimerStore implements StudyTimerStore {
  JsonMap? value;

  @override
  Future<JsonMap?> load(String key) async => value;

  @override
  Future<void> save(String key, JsonMap value) async {
    this.value = value;
  }
}

PlannerSnapshot _snapshot(PlannerData data) => PlannerSnapshot(
  data: data,
  revision: 1,
  pending: false,
  status: SyncStatus.demo,
  message: '',
  blocked: false,
  ready: true,
  busy: false,
  conflicts: const [],
);

PlannerData _calendarData() {
  final base = plannerFixture();
  return base.copyWith(
    blocks: [base.blocks.single.copyWith(date: shanghaiToday())],
    logs: const [],
  );
}

/// Three tags with one uniquely tagged task each, so an OR filter can be
/// observed purely from which titles are listed.
PlannerData _tagData() {
  final base = plannerFixture();
  final task = base.tasks.single;
  final planTag = base.tags.single;
  final english = planTag.copyWith(id: 'english', name: '英语', color: '#1f7a5c');
  final math = planTag.copyWith(id: 'math', name: '数学', color: '#2f5d8a');
  return base.copyWith(
    tags: [planTag, english, math],
    tasks: [
      task.copyWith(id: 'task-plan', tagIds: [planTag.id], title: '高数基础'),
      task.copyWith(id: 'task-en', tagIds: [english.id], title: '英语真题'),
      task.copyWith(id: 'task-math', tagIds: [math.id], title: '数学练习'),
    ],
    blocks: const [],
    logs: const [],
    fixedEvents: const [],
  );
}

Future<void> _pumpCalendarPage(WidgetTester tester, PlannerData data) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(
    overrides: [
      plannerDataProvider.overrideWithValue(_snapshot(data)),
      calendarViewPreferenceStoreProvider.overrideWithValue(
        _MemoryDayViewStore(),
      ),
      calendarWeekViewPreferenceStoreProvider.overrideWithValue(
        _MemoryWeekViewStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: plannerTheme(),
        home: const Scaffold(body: CalendarPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpTaskDirectory(WidgetTester tester, PlannerData data) async {
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final coordinator =
      PlannerCoordinator(
          userId: data.profile.userId,
          scope: 'keyboard-controls-widget',
          storage: MemoryStorageRepository(),
          api: _NoopSync(),
          retryInterval: null,
        )
        ..data = data
        ..ready = true;
  final container = ProviderContainer(
    overrides: [
      plannerDataProvider.overrideWithValue(_snapshot(data)),
      studyTimerProvider.overrideWith(
        (ref) => StudyTimer(
          coordinator: coordinator,
          store: _MemoryTimerStore(),
          tickInterval: null,
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    coordinator.dispose();
  });
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: plannerTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(PlannerSpace.lg),
            child: TaskDirectory(data: data, editable: false),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _SegmentedHost extends StatefulWidget {
  const _SegmentedHost();

  @override
  State<_SegmentedHost> createState() => _SegmentedHostState();
}

class _SegmentedHostState extends State<_SegmentedHost> {
  String value = 'a';

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: plannerTheme(),
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TextField(decoration: InputDecoration(labelText: '前')),
            const SizedBox(height: 12),
            SizedBox(
              width: 240,
              child: PlannerSegmented<String>(
                value: value,
                items: const [('a', '甲'), ('b', '乙'), ('c', '丙')],
                onChanged: (next) => setState(() => value = next),
              ),
            ),
            const SizedBox(height: 12),
            const TextField(decoration: InputDecoration(labelText: '后')),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'segmented arrows move the calendar scope and paint the focus ring',
    (tester) async {
      await _pumpCalendarPage(tester, _calendarData());
      expect(find.byKey(_segmentedRing), findsNothing);

      // Clicking focuses the whole group without changing the day scope.
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();
      expect(find.byKey(_segmentedRing), findsOneWidget);
      expect(
        find.byKey(const ValueKey('calendar-day-chart')),
        findsNWidgets(2),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byType(CalendarWeekChart), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byType(CalendarMonthChart), findsOneWidget);

      // The last item clamps instead of wrapping around.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.byType(CalendarMonthChart), findsOneWidget);
      expect(find.byKey(_segmentedRing), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'segmented Home/End jump to the ends and Space/Enter keep the value',
    (tester) async {
      await _pumpCalendarPage(tester, _calendarData());
      await tester.tap(find.text('日'));
      await tester.pumpAndSettle();

      CalendarMode mode() => tester
          .widget<PlannerSegmented<CalendarMode>>(
            find.byKey(const ValueKey('calendar-mode-switch')),
          )
          .value;

      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(mode(), CalendarMode.month);
      expect(find.byType(CalendarMonthChart), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(mode(), CalendarMode.day);

      final before = mode();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(mode(), before);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(mode(), before);
      // Confirming never steals focus from the control.
      expect(find.byKey(_segmentedRing), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tag filter chips move with arrow keys and toggle with Space/Enter',
    (tester) async {
      final data = _tagData();
      final planTag = data.tags.first;
      await _pumpTaskDirectory(tester, data);
      final chipA = find.byKey(Key('task-filter-tag-${planTag.id}'));
      final chipB = find.byKey(const Key('task-filter-tag-english'));
      expect(chipA, findsOneWidget);
      expect(chipB, findsOneWidget);
      expect(find.text('高数基础'), findsOneWidget);
      expect(find.text('英语真题'), findsOneWidget);

      // Clicking focuses the chip and applies its filter.
      await tester.tap(chipA);
      await tester.pumpAndSettle();
      expect(find.text('高数基础'), findsOneWidget);
      expect(find.text('英语真题'), findsNothing);
      expect(find.byKey(_tagRing), findsOneWidget);

      // ArrowRight moves the focus only: the filter must not change.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(find.text('英语真题'), findsNothing);
      expect(find.byKey(_tagRing), findsOneWidget);

      // Space activates the focused chip, so the OR filter lists both tasks.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('高数基础'), findsOneWidget);
      expect(find.text('英语真题'), findsOneWidget);
      expect(find.text('数学练习'), findsNothing);

      // ArrowLeft moves back, Enter toggles the first chip off again.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('高数基础'), findsNothing);
      expect(find.text('英语真题'), findsOneWidget);

      // Left at the first chip clamps: no wrap and no filter change.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(find.byKey(_tagRing), findsOneWidget);
      expect(find.text('高数基础'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('segmented control is a single tab stop that arrow keys drive', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const _SegmentedHost());
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    final state = tester.state<_SegmentedHostState>(
      find.byType(_SegmentedHost),
    );

    await tester.tap(fields.first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byKey(_segmentedRing), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(state.value, 'b');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(state.value, 'c');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(state.value, 'c');

    // One more Tab leaves the group for the next field instead of stepping
    // through the three segments individually.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(find.byKey(_segmentedRing), findsNothing);
    expect(
      tester
          .widget<EditableText>(
            find.descendant(
              of: fields.at(1),
              matching: find.byType(EditableText),
            ),
          )
          .focusNode
          .hasFocus,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'display-only PlannerTag stays out of the tab order and paints no ring',
    (tester) async {
      tester.view.physicalSize = const Size(800, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: plannerTheme(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  TextField(decoration: InputDecoration(labelText: '前')),
                  SizedBox(height: 12),
                  PlannerTag(label: '仅展示'),
                  SizedBox(height: 12),
                  TextField(decoration: InputDecoration(labelText: '后')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final displayTag = find.widgetWithText(PlannerTag, '仅展示');
      expect(displayTag, findsOneWidget);
      expect(
        find.descendant(of: displayTag, matching: find.byType(Focus)),
        findsNothing,
      );
      expect(
        find.descendant(of: displayTag, matching: find.byType(InkWell)),
        findsNothing,
      );
      await tester.tap(displayTag);
      await tester.pump();
      expect(find.byKey(_tagRing), findsNothing);

      // Tab skips the display tag: the second field is the next stop.
      final fields = find.byType(TextField);
      await tester.tap(fields.first);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: fields.at(1),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      expect(find.byKey(_tagRing), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
