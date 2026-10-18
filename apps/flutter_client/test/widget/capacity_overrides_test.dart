import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/settings/presentation/capacity_overrides_dialog.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

const _stamp = '2026-01-01T00:00:00.000Z';

PlannerData _data() => PlannerData(
  version: 1,
  profile: Profile(
    userId: 'u1',
    planStartDate: '2026-10-12',
    planEndDate: '2026-11-08',
    weeklyMinutes: {for (var day = 0; day < 7; day++) '$day': 60},
    capacityBasis: CapacityBasis.net,
    dailyLimitMinutes: 480,
    granularityMinutes: 30,
    bufferMinutes: 30,
    subjectLimitMinutes: 240,
    studyStartMinute: 0,
    studyEndMinute: 1440,
    foundation: '',
  ),
  subjects: const [],
  tasks: [
    Task(
      id: 't',
      userId: 'u1',
      subjectId: 's',
      title: '事项',
      estimatedMinutes: 600,
      completedMinutes: 0,
      priority: 2,
      deadline: '2026-11-08',
      isFixed: false,
      status: TaskStatus.notStarted,
      createdAt: _stamp,
      updatedAt: _stamp,
    ),
  ],
  blocks: const [],
  logs: const [],
  fixedEvents: const [],
  replanRuns: const [],
  phases: const [],
);

const _snapshot = PlannerSnapshot(
  data: null,
  revision: 0,
  pending: false,
  status: SyncStatus.connected,
  message: '',
  blocked: false,
  ready: true,
  busy: false,
  conflicts: [],
);

Future<void> _mount(
  WidgetTester tester, {
  required PlannerData data,
  required void Function() onOpen,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        plannerDataProvider.overrideWithValue(
          PlannerSnapshot(
            data: data,
            revision: _snapshot.revision,
            pending: _snapshot.pending,
            status: _snapshot.status,
            message: _snapshot.message,
            blocked: _snapshot.blocked,
            ready: _snapshot.ready,
            busy: _snapshot.busy,
            conflicts: _snapshot.conflicts,
          ),
        ),
      ],
      child: MaterialApp(
        theme: plannerTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () {
                  onOpen();
                  CapacityOverridesDialog.show(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('capacity editor adds a week override and previews impacts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = false;
    await _mount(tester, data: _data(), onOpen: () => opened = true);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.text('容量假设与例外'), findsOneWidget);
    expect(find.text('每周最少能学'), findsNothing);
    expect(find.text('管理特定周与日期容量'), findsNothing);

    // 添加特定周：周一 120 分钟覆盖 + 周总量 60，必然产生周总量冲突。
    await tester.tap(find.text('添加特定周'));
    await tester.pumpAndSettle();
    expect(find.text('特定周容量'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('capacity-week-total')),
      '60',
    );
    await tester.enterText(
      find.byKey(const ValueKey('capacity-week-day-1')),
      '120',
    );
    await tester.tap(find.byKey(const ValueKey('capacity-week-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('超过周总量'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('capacity-accept-conflicts')),
      findsOneWidget,
    );

    // 未接受冲突时不能预览影响。
    await tester.tap(find.text('预览容量影响'));
    await tester.pumpAndSettle();
    expect(find.textContaining('容量设置存在冲突'), findsOneWidget);

    // 明确接受冲突后可以预览影响，并显示保留/移动/未安排/真实截止影响。
    await tester.tap(find.byKey(const ValueKey('capacity-accept-conflicts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预览容量影响'));
    await tester.pumpAndSettle();
    expect(find.text('容量变化影响预览'), findsOneWidget);
    expect(find.text('保持不变（历史/固定/已完成/已有记录）'), findsOneWidget);
    expect(find.text('移动/释放的未来安排'), findsOneWidget);
    expect(find.text('仍未安排'), findsOneWidget);
    expect(find.text('确认应用'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity editor shows provenance and clears date overrides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final data = _data().copyWith(
      profile: _data().profile.copyWith(
        dateCapacityOverrides: {'2026-10-13': 0, '2026-10-14': 90},
      ),
    );
    await _mount(tester, data: data, onOpen: () {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('休息日（0 分钟，不回退默认容量）'), findsOneWidget);
    expect(find.textContaining('净容量 1小时30分 · 来源：具体日期覆盖'), findsOneWidget);
    // 删除日期覆盖 = 恢复上层规则（不是设为 0）。
    await tester.tap(find.byTooltip('删除覆盖（恢复上层规则）').first);
    await tester.pumpAndSettle();
    expect(find.text('休息日（0 分钟，不回退默认容量）'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
