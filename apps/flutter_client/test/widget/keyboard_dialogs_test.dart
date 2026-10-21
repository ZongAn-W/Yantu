import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/core/widgets.dart' show confirmAction;
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';
import 'package:sjtu_study_planner_client/features/auth/data/auth_repository.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/settings/presentation/capacity_overrides_dialog.dart';
import 'package:sjtu_study_planner_client/features/settings/presentation/delete_account_dialog.dart';
import 'package:sjtu_study_planner_client/router/app_router.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import 'planner_ui_test.dart' as harness;

/// W2-C keyboard audit of the dialog surface.
///
/// Material dialogs already provide Esc close, modal focus containment and focus
/// restore; these tests lock that contract in with real key events and cover the
/// one exception (the delete-account confirm keeps barrierDismissible: false but
/// treats Esc as the explicit 取消 action).

/// True when the primary focus currently lives inside an AlertDialog subtree.
bool _focusInsideDialog() {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  var inside = false;
  context.visitAncestorElements((element) {
    if (element.widget is AlertDialog) {
      inside = true;
      return false;
    }
    return true;
  });
  return inside;
}

Future<void> _pressEscape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

class _RecordingAuthController extends AuthController {
  int deleteCalls = 0;

  @override
  AuthState build() => const AuthState(
    user: AuthUser(
      id: 'keyboard-dialogs',
      email: 'student@example.com',
      username: '学习者',
    ),
  );

  @override
  Future<bool> deleteAccount(String password) async {
    deleteCalls++;
    return false;
  }
}

const _stamp = '2026-01-01T00:00:00.000Z';

PlannerData _capacityData() => PlannerData(
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
  tasks: const [
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

PlannerSnapshot _snapshot(PlannerData data) => PlannerSnapshot(
  data: data,
  revision: 0,
  pending: false,
  status: SyncStatus.connected,
  message: '',
  blocked: false,
  ready: true,
  busy: false,
  conflicts: const [],
);

void main() {
  testWidgets(
    'today page: the new-task dialog keeps text input, traps Tab and closes on Esc',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = harness.FakeSyncServer();
      final container = await harness.signIn(tester, respond: server.respond);
      container.read(appRouterProvider).go('/');
      await tester.pumpAndSettle();

      final trigger = find.byKey(const Key('new-task-button'));
      await tester.ensureVisible(trigger);
      await tester.pumpAndSettle();
      await tester.tap(trigger);
      await tester.pumpAndSettle();

      final titleField = find.byKey(const Key('task-title-field'));
      expect(titleField, findsOneWidget);
      // Typing is never intercepted by the dialog surface.
      await tester.enterText(titleField, '线性代数 矩阵');
      await tester.pump();
      expect(find.text('线性代数 矩阵'), findsOneWidget);
      expect(_focusInsideDialog(), isTrue);

      // Enter keeps its stock single-line behaviour: no submit side effect.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(titleField, findsOneWidget);

      // The focus trap must survive twelve Tab presses.
      for (var index = 0; index < 12; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _focusInsideDialog(),
          isTrue,
          reason: 'Tab #$index escaped the dialog',
        );
      }

      await _pressEscape(tester);
      expect(titleField, findsNothing);
      expect(_focusInsideDialog(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tag-management dialog: text entry works, Tab stays inside and Esc closes',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final server = harness.FakeSyncServer();
      final container = await harness.signIn(tester, respond: server.respond);
      container.read(appRouterProvider).go('/tasks');
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manage-tags-button')));
      await tester.pumpAndSettle();
      expect(find.text('标签管理'), findsOneWidget);

      final nameField = find.byKey(const Key('new-managed-tag-field'));
      await tester.enterText(nameField, '键盘验证标签');
      await tester.pump();
      expect(find.text('键盘验证标签'), findsOneWidget);

      for (var index = 0; index < 12; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _focusInsideDialog(),
          isTrue,
          reason: 'Tab #$index escaped the tag dialog',
        );
      }

      await _pressEscape(tester);
      expect(find.text('标签管理'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('confirmAction: Esc cancels and resolves to false', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: plannerTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: OutlinedButton(
                key: const Key('open-confirm'),
                autofocus: true,
                onPressed: () async {
                  result = await confirmAction(
                    context,
                    title: '删除标签',
                    message: '删除「键盘」？',
                    confirmLabel: '删除标签',
                    destructive: true,
                  );
                },
                child: const Text('打开确认'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('删除「键盘」？'), findsOneWidget);

    await _pressEscape(tester);
    await tester.pump();
    expect(find.text('删除「键盘」？'), findsNothing);
    expect(result, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'delete-account dialog: Esc is an explicit cancel that restores trigger focus',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final controller = _RecordingAuthController();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      bool? result;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(() => controller)],
          child: MaterialApp(
            theme: plannerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: OutlinedButton(
                    key: const Key('open-delete-account'),
                    focusNode: focusNode,
                    onPressed: () async {
                      result = await DeleteAccountDialog.show(context);
                    },
                    child: const Text('注销账号'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('永久注销账号？'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('delete-account-password')),
        'secret',
      );
      await tester.pump();
      expect(_focusInsideDialog(), isTrue);

      await _pressEscape(tester);
      await tester.pump();
      expect(find.text('永久注销账号？'), findsNothing);
      expect(
        controller.deleteCalls,
        0,
        reason: 'Esc must not delete the account',
      );
      expect(result, isFalse);
      expect(
        focusNode.hasFocus,
        isTrue,
        reason: 'focus must return to the trigger',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'capacity dialog: Tab traversal is contained and Esc closes without saving',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final data = _capacityData();
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [plannerDataProvider.overrideWithValue(_snapshot(data))],
          child: MaterialApp(
            theme: plannerTheme(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: OutlinedButton(
                    key: const Key('open-capacity'),
                    focusNode: focusNode,
                    onPressed: () async {
                      await CapacityOverridesDialog.show(context);
                    },
                    child: const Text('打开容量'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      focusNode.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('容量假设与例外'), findsOneWidget);

      for (var index = 0; index < 12; index++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        expect(
          _focusInsideDialog(),
          isTrue,
          reason: 'Tab #$index escaped the capacity dialog',
        );
      }

      await _pressEscape(tester);
      expect(find.text('容量假设与例外'), findsNothing);
      expect(
        focusNode.hasFocus,
        isTrue,
        reason: 'focus must return to the trigger',
      );
      expect(tester.takeException(), isNull);
    },
  );
}
