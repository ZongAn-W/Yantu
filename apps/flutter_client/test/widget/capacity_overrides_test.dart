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
    studyStartMinute: 0,
    studyEndMinute: 1440,
    foundation: '',
  ),
  tags: const [],
  tasks: [
    Task(
      id: 't',
      userId: 'u1',
      title: '事项',
      estimatedMinutes: 600,
      completedMinutes: 0,
      priority: 2,
      deadline: '2026-11-08',
      isFixed: false,
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

/// Records the [PlannerSession.edit] calls the dialog makes without touching a
/// real coordinator/database: saving capacity must write exactly once and must
/// not schedule anything else.
class _RecordingSession implements PlannerSession {
  _RecordingSession(this.data);

  @override
  PlannerData data;
  int edits = 0;
  PlannerData? written;

  @override
  Future<void> edit(PlannerData Function(PlannerData) change) async {
    edits++;
    data = change(data);
    written = data;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _mount(
  WidgetTester tester, {
  required PlannerData data,
  _RecordingSession? session,
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
        if (session != null) plannerSessionProvider.overrideWithValue(session),
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
  testWidgets('capacity editor saves capacity without previewing a replan', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _RecordingSession(_data());
    var opened = false;
    await _mount(
      tester,
      data: _data(),
      session: session,
      onOpen: () => opened = true,
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(opened, isTrue);
    expect(find.text('容量假设与例外'), findsOneWidget);
    expect(find.text('每周最少能学'), findsNothing);
    expect(find.text('管理特定周与日期容量'), findsNothing);
    // 不再展示旧的两阶段重排预览入口。
    expect(find.text('预览容量影响'), findsNothing);
    expect(find.text('容量变化影响预览'), findsNothing);
    expect(find.text('保存容量'), findsOneWidget);

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

    // 未接受冲突时保存被阻止，也不写入任何数据。
    await tester.tap(find.text('保存容量'));
    await tester.pumpAndSettle();
    expect(find.textContaining('容量设置存在冲突'), findsOneWidget);
    expect(session.edits, 0);
    expect(find.text('容量假设与例外'), findsOneWidget);

    // 明确接受冲突后保存：写入新容量、关闭对话框并提示到调整页重排。
    await tester.tap(find.byKey(const ValueKey('capacity-accept-conflicts')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存容量'));
    await tester.pumpAndSettle();
    expect(session.edits, 1);
    final written = session.written!;
    expect(written.profile.weekCapacityOverrides, isNotNull);
    final override = written.profile.weekCapacityOverrides!.values.single;
    expect(override.totalMinutes, 60);
    expect(override.days, {'1': 120});
    // 只写容量，不改动任何事项或旧的重排运行记录。
    expect(written.tasks, hasLength(1));
    expect(written.replanRuns, isEmpty);
    expect(find.text('容量假设与例外'), findsNothing);
    expect(find.textContaining('容量已保存；请到调整页使用一键调整后续计划重排未来安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('capacity editor surfaces validation errors and blocks saving', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = _RecordingSession(_data());
    await _mount(tester, data: _data(), session: session, onOpen: () {});
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // 启用周容量范围后填入下限大于上限，校验错误必须展示并禁用保存。
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('capacity-range-min')),
      '600',
    );
    await tester.enterText(
      find.byKey(const ValueKey('capacity-range-max')),
      '300',
    );
    await tester.pumpAndSettle();
    expect(find.text('周容量范围下限不能大于上限'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('capacity-save')))
          .onPressed,
      isNull,
    );
    expect(session.edits, 0);
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
