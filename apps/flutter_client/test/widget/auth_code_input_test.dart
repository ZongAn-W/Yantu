import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/storage/identity_store.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/auth/presentation/auth_page.dart';

import '../support/http_adapter.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'code accepts keyboard input while email sends and during cooldown at width $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final sent = Completer<ResponseBody>();
        final client = ApiClient(
          config: const AppConfig(apiBaseUrl: 'http://api.test'),
          tokenStore: MemoryTokenStore(),
          dio: Dio()
            ..httpClientAdapter = TestAdapter((request) async {
              expect(request.path, '/api/auth/registration-code');
              return sent.future;
            }),
        );
        addTearDown(client.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              apiClientProvider.overrideWithValue(client),
              identityStoreProvider.overrideWithValue(MemoryIdentityStore()),
            ],
            child: MaterialApp(theme: plannerTheme(), home: const AuthPage()),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('注册'));
        await tester.pumpAndSettle();

        Finder field(String label) => find.ancestor(
          of: find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == label,
          ),
          matching: find.byType(TextFormField),
        );
        await tester.enterText(field('邮箱'), 'student@example.com');
        await tester.tap(find.text('发送验证码'));
        await tester.pump();
        expect(find.text('发送中…'), findsOneWidget);
        expect(tester.widget<TextFormField>(field('邮箱')).enabled, isFalse);
        final code = field('邮箱验证码');
        await tester.ensureVisible(code);
        await tester.tapAt(tester.getTopLeft(code) + const Offset(30, 20));
        await tester.pump();
        final editable = find.descendant(
          of: code,
          matching: find.byType(EditableText),
        );
        expect(
          tester.widget<EditableText>(editable).focusNode.hasFocus,
          isTrue,
        );
        tester.testTextInput.enterText('123456');
        await tester.pump();
        expect(tester.widget<TextFormField>(code).controller!.text, '123456');

        sent.complete(jsonResponse({'ok': true, 'retryAfter': 60}));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.widget<TextFormField>(code).controller!.text, '123456');
        await tester.tapAt(tester.getTopLeft(code) + const Offset(30, 20));
        tester.testTextInput.enterText('654321');
        await tester.pump();
        expect(tester.widget<TextFormField>(code).controller!.text, '654321');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
