import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sjtu_study_planner_client/core/sync/sync_state.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/auth/application/auth_controller.dart';
import 'package:sjtu_study_planner_client/features/auth/data/auth_repository.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_session.dart';
import 'package:sjtu_study_planner_client/features/settings/presentation/delete_account_dialog.dart';
import 'package:sjtu_study_planner_client/features/settings/presentation/settings_page.dart';

const _user = AuthUser(
  id: 'account-to-delete',
  email: 'student@example.com',
  username: '学习者',
);

class _DeletionController extends AuthController {
  final passwords = <String>[];
  final pending = <Completer<bool>>[];
  String? failure;
  bool uncertain = false;

  @override
  AuthState build() => const AuthState(user: _user);

  @override
  Future<bool> deleteAccount(String password) async {
    passwords.add(password);
    final result = Completer<bool>();
    pending.add(result);
    state = const AuthState(user: _user, loading: true);
    final deleted = await result.future;
    state = deleted
        ? const AuthState()
        : AuthState(user: _user, error: failure, deletionPending: uncertain);
    return deleted;
  }
}

class _RedirectingDeletionController extends AuthController {
  _RedirectingDeletionController(this.redirect);
  final ValueNotifier<bool> redirect;
  final cleanup = Completer<void>();

  @override
  AuthState build() => const AuthState(user: _user);

  @override
  Future<bool> deleteAccount(String password) async {
    state = const AuthState(loading: true);
    redirect.value = true;
    await cleanup.future;
    state = const AuthState();
    return true;
  }
}

Future<void> _mountDialog(
  WidgetTester tester,
  _DeletionController controller, {
  double width = 390,
  Future<void> Function()? onExport,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [authControllerProvider.overrideWith(() => controller)],
      child: MaterialApp(
        theme: plannerTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  DeleteAccountDialog.show(context, onExport: onExport),
              child: const Text('注销账号'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('注销账号'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'delayed cleanup never pops the login page after auth redirects',
    (tester) async {
      final redirect = ValueNotifier(false);
      final controller = _RedirectingDeletionController(redirect);
      final router = GoRouter(
        initialLocation: '/settings',
        refreshListenable: redirect,
        redirect: (_, state) =>
            redirect.value && state.matchedLocation != '/login'
            ? '/login'
            : null,
        routes: [
          GoRoute(
            path: '/settings',
            builder: (context, _) => Scaffold(
              body: TextButton(
                onPressed: () => DeleteAccountDialog.show(context),
                child: const Text('注销账号'),
              ),
            ),
          ),
          GoRoute(
            path: '/login',
            builder: (_, _) => const Scaffold(body: Text('登录入口')),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(redirect.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith(() => controller)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('注销账号'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('delete-account-password')),
        'password',
      );
      await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      controller.cleanup.complete();
      await tester.pumpAndSettle();
      expect(find.text('登录入口'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'deletion requires password and protects pending request at $width',
      (tester) async {
        final controller = _DeletionController();
        await _mountDialog(tester, controller, width: width);
        expect(find.text('永久注销账号？'), findsOneWidget);
        expect(find.textContaining('无法撤销'), findsOneWidget);
        final password = find.byKey(const ValueKey('delete-account-password'));
        final editable = tester.widget<EditableText>(
          find.descendant(of: password, matching: find.byType(EditableText)),
        );
        expect(editable.obscureText, isTrue);

        await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
        await tester.pumpAndSettle();
        expect(find.text('请输入当前密码以确认注销'), findsOneWidget);
        expect(controller.passwords, isEmpty);

        // Passwords are sent exactly as typed, including significant spaces.
        await tester.enterText(password, ' Study4089 ');
        await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
        await tester.pump();
        expect(controller.passwords, [' Study4089 ']);
        expect(find.text('正在注销…'), findsOneWidget);
        expect(
          tester
              .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
              .onPressed,
          isNull,
        );
        expect(tester.widget<TextFormField>(password).enabled, isFalse);
        await tester.binding.handlePopRoute();
        await tester.pump();
        expect(find.byType(AlertDialog), findsOneWidget);

        controller.pending.single.complete(true);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('wrong password leaves dialog open and permits correction', (
    tester,
  ) async {
    final controller = _DeletionController()..failure = '密码不正确';
    await _mountDialog(tester, controller);
    final password = find.byKey(const ValueKey('delete-account-password'));
    await tester.enterText(password, 'wrong-password');
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.pump();
    controller.pending.single.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('密码不正确'), findsOneWidget);
    expect(tester.widget<TextFormField>(password).enabled, isTrue);

    await tester.enterText(password, 'Study4089');
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.pump();
    expect(controller.passwords, ['wrong-password', 'Study4089']);
    controller.pending.last.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('uncertain deletion stays open and retries with same password', (
    tester,
  ) async {
    final controller = _DeletionController()
      ..failure = '连接超时'
      ..uncertain = true;
    await _mountDialog(tester, controller);
    await tester.enterText(
      find.byKey(const ValueKey('delete-account-password')),
      'Study4089',
    );
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.pump();
    controller.pending.single.complete(false);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('尚未确认服务器是否已完成注销'), findsOneWidget);
    expect(find.text('连接超时'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('delete-account-confirm')));
    await tester.pump();
    expect(controller.passwords, ['Study4089', 'Study4089']);
    controller.pending.last.complete(true);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('export finishes before deletion can start', (tester) async {
    final controller = _DeletionController();
    final exported = Completer<void>();
    var exports = 0;
    await _mountDialog(
      tester,
      controller,
      onExport: () {
        exports++;
        return exported.future;
      },
    );
    await tester.tap(find.text('导出本地数据'));
    await tester.pump();
    expect(exports, 1);
    expect(find.text('正在导出…'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('delete-account-confirm')),
          )
          .onPressed,
      isNull,
    );
    exported.complete();
    await tester.pumpAndSettle();
    expect(find.text('已导出本地数据，请妥善保存。'), findsOneWidget);
    expect(controller.passwords, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  for (final state in ['loading', 'empty', 'blocked']) {
    testWidgets('account deletion is reachable while planner is $state', (
      tester,
    ) async {
      final snapshot = PlannerSnapshot(
        data: null,
        revision: 0,
        pending: false,
        status: SyncStatus.error,
        message: state == 'blocked' ? '本机数据损坏' : '',
        blocked: state == 'blocked',
        ready: state != 'loading',
        busy: false,
        conflicts: const [],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            plannerDataProvider.overrideWithValue(snapshot),
            authControllerProvider.overrideWith(_DeletionController.new),
          ],
          child: MaterialApp(
            theme: plannerTheme(),
            home: const Scaffold(body: SettingsPage()),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('账号管理'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('settings-delete-account')));
      // Loading the planner must not prevent interaction with account settings.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('永久注销账号？'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
