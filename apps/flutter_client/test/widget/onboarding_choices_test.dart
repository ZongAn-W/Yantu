import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/auth/token_store.dart';
import 'package:sjtu_study_planner_client/core/config/app_config.dart';
import 'package:sjtu_study_planner_client/core/http/api_client.dart';
import 'package:sjtu_study_planner_client/core/providers.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/features/onboarding/domain/onboarding_options.dart';
import 'package:sjtu_study_planner_client/features/onboarding/domain/onboarding_session.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import '../support/http_adapter.dart';
import '../support/onboarding_fixture.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    Map<String, dynamic> session, {
    Respond? respond,
  }) async {
    final client = ApiClient(
      config: const AppConfig(apiBaseUrl: 'http://api.test'),
      tokenStore: MemoryTokenStore(),
      dio: Dio()
        ..httpClientAdapter = TestAdapter(
          respond ?? (_) async => jsonResponse({'session': session}),
        ),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(client)],
        child: MaterialApp(theme: plannerTheme(), home: const OnboardingPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  test('legacy sessions keep free text and default recommendation fields', () {
    final session = OnboardingSession.fromJson(onboardingFixture());
    expect(session.questionOptions, isEmpty);
    expect(session.questionMultiple, isFalse);
    expect(session.recommendations.targetDate, isEmpty);
    expect(session.recommendations.weeklyMinutes, isEmpty);
  });

  test(
    'legacy session options are normalized and reserve Other for the client',
    () {
      final session = OnboardingSession.fromJson({
        ...onboardingFixture(),
        'question_options': [
          ' 考试备考 ',
          '',
          '考试备考',
          '其他',
          '其它',
          'Other',
          '其他（自填）',
          '其他语言课程',
          '课程学习',
        ],
      });
      // 通用自填占位项被移除，有效业务选项保持原顺序。
      expect(session.questionOptions, ['考试备考', '其他语言课程', '课程学习']);
      // “其他语言课程”是有具体含义的业务选项，不能被宽泛前缀过滤误删。
      expect(normalizeQuestionOptions(['其他语言课程', '其他', 'Other']), ['其他语言课程']);
      expect(normalizeQuestionOptions(['Python', 'python', '  ']), ['Python']);
      expect(normalizeQuestionOptions(['Other（自填）', ' 其它 ', '二外']), ['二外']);
    },
  );

  testWidgets(
    'first question renders four options plus exactly one Other entry',
    (tester) async {
      final session = onboardingFixture()
        ..['question_options'] = ['考试备考', '课程学习', '技能提升', '自主学习'];
      await mount(tester, session);
      for (final option in ['考试备考', '课程学习', '技能提升', '自主学习']) {
        expect(find.text(option), findsOneWidget);
      }
      expect(find.text('其他'), findsOneWidget);
      expect(find.byType(RadioListTile<String>), findsNWidgets(5));
    },
  );

  testWidgets(
    'saved sessions with duplicate placeholder options keep a single Other entry',
    (tester) async {
      final session = onboardingFixture()
        ..['question_options'] = [
          '考试备考',
          '考试备考',
          '其他',
          '其它',
          'Other',
          '其他（自填）',
          '课程学习',
        ];
      await mount(tester, session);
      expect(find.text('其他'), findsOneWidget);
      expect(find.text('考试备考'), findsOneWidget);
      // 两个具体业务选项 + 客户端唯一“其他”入口。
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
    },
  );

  testWidgets(
    'single choice requires a selection and resets for the next question',
    (tester) async {
      var session = onboardingFixture()..['question_options'] = ['考研', '考公'];
      Map? action;
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            action = (request.data as Map)['action'] as Map;
            session = onboardingFixture(answers: 1)
              ..['question_options'] = ['刚开始', '已完成一轮'];
          }
          return jsonResponse({'session': session});
        },
      );
      expect(find.byType(TextFormField), findsNothing);
      await tester.tap(find.text('提交回答，继续'));
      await tester.pumpAndSettle();
      expect(action, isNull);
      expect(find.text('请选择一个选项或填写其他回答'), findsOneWidget);
      await tester.tap(find.text('考研'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交回答，继续'));
      await tester.pumpAndSettle();
      expect(action!['answer'], '考研');
      expect(find.text('刚开始'), findsOneWidget);
      expect(
        tester
            .widget<RadioGroup<String>>(find.byType(RadioGroup<String>))
            .groupValue,
        isNull,
      );
    },
  );

  testWidgets('other accepts text and retains it after a failed request', (
    tester,
  ) async {
    final session = onboardingFixture()..['question_options'] = ['考研', '考公'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
          return jsonResponse({'error': '请稍后重试'}, 502);
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '备考雅思7分');
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action!['answer'], '备考雅思7分');
    expect(find.text('备考雅思7分'), findsOneWidget);
    expect(find.text('请稍后重试'), findsOneWidget);
  });

  testWidgets('single choice other requires non-empty text and submits it', (
    tester,
  ) async {
    final session = onboardingFixture()..['question_options'] = ['考研', '考公'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
          return jsonResponse({'error': '请稍后重试'}, 502);
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '   ');
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    // 只选“其他”但没填写内容时阻止提交并显示字段错误。
    expect(action, isNull);
    expect(find.text('请先填写回答'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '  备考雅思7分  ');
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    // 提交实际输入内容，不提交裸“其他”或内部标识。
    expect(action!['answer'], '备考雅思7分');
  });

  testWidgets('switching back to a normal option does not submit hidden text', (
    tester,
  ) async {
    final session = onboardingFixture()..['question_options'] = ['考研', '考公'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
          return jsonResponse({'error': '请稍后重试'}, 502);
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '这段内容不应提交');
    await tester.tap(find.text('考研'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action!['answer'], '考研');
    expect(action!['answer'], isNot(contains('不应提交')));
  });

  testWidgets(
    'question without options keeps direct free text and no Other entry',
    (tester) async {
      final session = onboardingFixture();
      Map? action;
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            action = (request.data as Map)['action'] as Map;
            return jsonResponse({'error': '请稍后重试'}, 502);
          }
          return jsonResponse({'session': session});
        },
      );
      expect(find.text('其他'), findsNothing);
      expect(find.byType(TextFormField), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '直接回答的内容');
      await tester.ensureVisible(find.text('提交回答，继续'));
      await tester.tap(find.text('提交回答，继续'));
      await tester.pumpAndSettle();
      expect(action!['answer'], '直接回答的内容');
    },
  );

  testWidgets('business option containing Other stays selectable', (
    tester,
  ) async {
    final session = onboardingFixture()
      ..['question_options'] = ['其他语言课程', '课程学习'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
          return jsonResponse({'error': '请稍后重试'}, 502);
        }
        return jsonResponse({'session': session});
      },
    );
    expect(find.text('其他语言课程'), findsOneWidget);
    expect(find.text('其他'), findsOneWidget);
    await tester.tap(find.text('其他语言课程'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action!['answer'], '其他语言课程');
  });

  testWidgets('mobile shows custom input, field error and submit button', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = onboardingFixture()
      ..['question_options'] = ['考试备考', '课程学习', '技能提升', '自主学习'];
    await mount(tester, session);
    expect(find.text('其他'), findsOneWidget);
    expect(find.text('提交回答，继续'), findsOneWidget);
    await tester.ensureVisible(find.text('其他'));
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsOneWidget);
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(find.text('请先填写回答'), findsOneWidget);
    expect(find.text('提交回答，继续'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('multiple choice submits selected options and additional text', (
    tester,
  ) async {
    final session = onboardingFixture(answers: 2)
      ..['question_multiple'] = true
      ..['question_options'] = ['数学基础较弱', '英语需要强化', '专业课刚开始'];
    Map? action;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          action = (request.data as Map)['action'] as Map;
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.tap(find.text('数学基础较弱'));
    await tester.tap(find.text('英语需要强化'));
    await tester.tap(find.text('其他'));
    await tester.pumpAndSettle();
    // 多选时普通选项可以和“其他”同时选择，但选中“其他”后必须填写文本。
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action, isNull);
    expect(find.text('请先填写回答'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), '周三晚上有课');
    await tester.ensureVisible(find.text('提交回答，继续'));
    await tester.tap(find.text('提交回答，继续'));
    await tester.pumpAndSettle();
    expect(action!['answer'], '数学基础较弱；英语需要强化；周三晚上有课');
  });

  testWidgets('generation is hidden before five answers but shown afterwards', (
    tester,
  ) async {
    await mount(tester, onboardingFixture(answers: 4));
    expect(find.text('第 5 问'), findsOneWidget);
    expect(find.text('根据当前回答生成科目'), findsNothing);
  });

  testWidgets('five answers keep the interview going with generation', (
    tester,
  ) async {
    await mount(tester, onboardingFixture(answers: 5));
    expect(find.text('第 6 问'), findsOneWidget);
    expect(find.text('根据当前回答生成科目'), findsOneWidget);
    expect(find.text('信息已记录'), findsNothing);
    expect(find.text('继续完善信息'), findsNothing);
    expect(find.text('提交回答'), findsOneWidget);
  });

  testWidgets('legacy checkpoint sessions resume on the next question', (
    tester,
  ) async {
    await mount(tester, onboardingFixture(answers: 5, stage: 'checkpoint'));
    expect(find.text('信息已记录'), findsNothing);
    expect(find.text('继续完善信息'), findsNothing);
    expect(find.text('第 6 问'), findsOneWidget);
    expect(find.text('根据当前回答生成科目'), findsOneWidget);
  });

  testWidgets(
    'generating ignores the unsubmitted answer and retries on failure',
    (tester) async {
      final session = onboardingFixture(answers: 5);
      final actions = <Map>[];
      var failure = true;
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            actions.add((request.data as Map)['action'] as Map);
            if (failure) return jsonResponse({'error': 'AI 暂时不可用'}, 502);
            return jsonResponse({
              'session': onboardingFixture(stage: 'courses', answers: 5),
            });
          }
          return jsonResponse({'session': session});
        },
      );
      await tester.enterText(find.byType(TextFormField), '这条回答还没有提交');
      await tester.ensureVisible(find.text('根据当前回答生成科目'));
      await tester.tap(find.text('根据当前回答生成科目'));
      await tester.pumpAndSettle();
      // 不触发当前问题的必填校验，也不把未提交内容当作回答发送。
      expect(actions.single['type'], 'generate_courses');
      expect(actions.single.containsKey('answer'), isFalse);
      expect(find.text('请先填写回答'), findsNothing);
      expect(find.text('AI 暂时不可用'), findsOneWidget);
      expect(find.text('这条回答还没有提交'), findsOneWidget);
      expect(find.text('第 6 问'), findsOneWidget);
      failure = false;
      await tester.tap(find.text('根据当前回答生成科目'));
      await tester.pumpAndSettle();
      expect(find.text('确认你的课程'), findsOneWidget);
    },
  );

  testWidgets('waiting prompt and disabled actions during a submit request', (
    tester,
  ) async {
    final session = onboardingFixture(answers: 5);
    final response = Completer<ResponseBody>();
    var posts = 0;
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') {
          posts++;
          return response.future;
        }
        return jsonResponse({'session': session});
      },
    );
    await tester.enterText(find.byType(TextFormField), '第六个回答');
    await tester.tap(find.text('提交回答'));
    await tester.pump();
    expect(find.text('AI 正在思考中…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final submit = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交回答'),
    );
    final generate = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '根据当前回答生成科目'),
    );
    expect(submit.onPressed, isNull);
    expect(generate.onPressed, isNull);
    // 处理中重复点击不会发起第二个请求。
    await tester.tap(find.text('提交回答'), warnIfMissed: false);
    await tester.tap(find.text('根据当前回答生成科目'), warnIfMissed: false);
    await tester.pump();
    response.complete(jsonResponse({'error': '失败保留输入'}, 502));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('AI 正在思考中…'), findsNothing);
    expect(find.text('失败保留输入'), findsOneWidget);
    expect(find.text('第六个回答'), findsOneWidget);
    expect(find.text('第 6 问'), findsOneWidget);
  });

  testWidgets(
    'waiting prompt appears during generation and clears on failure',
    (tester) async {
      final session = onboardingFixture(answers: 5);
      final response = Completer<ResponseBody>();
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') return response.future;
          return jsonResponse({'session': session});
        },
      );
      await tester.tap(find.text('根据当前回答生成科目'));
      await tester.pump();
      expect(find.text('AI 正在思考中…'), findsOneWidget);
      response.complete(jsonResponse({'error': '生成失败，请重试'}, 502));
      await tester.pumpAndSettle();
      expect(find.text('AI 正在思考中…'), findsNothing);
      expect(find.text('生成失败，请重试'), findsOneWidget);
      expect(find.text('根据当前回答生成科目'), findsOneWidget);
    },
  );

  testWidgets('answer limit hides the question but keeps generation', (
    tester,
  ) async {
    await mount(tester, onboardingFixture(answers: 50));
    expect(find.text('已达到 50 题上限'), findsOneWidget);
    expect(find.text('根据当前回答生成科目'), findsOneWidget);
    expect(find.text('提交回答'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
  });

  testWidgets('mobile layout shows waiting prompt without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = onboardingFixture(answers: 5);
    final response = Completer<ResponseBody>();
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') return response.future;
        return jsonResponse({'session': session});
      },
    );
    expect(find.text('根据当前回答生成科目'), findsOneWidget);
    await tester.tap(find.text('根据当前回答生成科目'));
    await tester.pump();
    expect(find.text('AI 正在思考中…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    response.complete(jsonResponse({'error': '请稍后重试'}, 502));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop layout keeps generation and waiting prompt aligned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = onboardingFixture(answers: 5)
      ..['question_options'] = ['保持进度', '放慢一点'];
    final response = Completer<ResponseBody>();
    await mount(
      tester,
      session,
      respond: (request) async {
        if (request.method == 'POST') return response.future;
        return jsonResponse({'session': session});
      },
    );
    expect(find.text('根据当前回答生成科目'), findsOneWidget);
    await tester.tap(find.text('保持进度'));
    await tester.tap(find.text('提交回答'));
    await tester.pump();
    expect(find.text('AI 正在思考中…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    response.complete(jsonResponse({'error': '请稍后重试'}, 502));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'schedule prefills recommendations, restores them and submits user edits',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = onboardingFixture(stage: 'schedule', answers: 5);
      session['recommendations'] = {
        'target_date': '2027-12-18',
        'target_date_reason': '按2027年考研安排估计',
        'target_date_estimated': true,
        'plan_end_date': '2026-11-13',
        'plan_end_date_reason': '本次规划周期默认为从今天开始的未来28个自然日',
        'weekly_minutes': {
          for (var i = 0; i < 7; i++) '$i': i == 0 || i == 6 ? 240 : 120,
        },
        'weekly_minutes_reason': '在校期间工作日两小时，周末四小时',
      };
      Map? action;
      await mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            action = (request.data as Map)['action'] as Map;
            return jsonResponse({'error': '测试保留当前页面'}, 400);
          }
          return jsonResponse({'session': session});
        },
      );
      expect(find.text('2026-11-13'), findsOneWidget);
      expect(find.text('2027-12-18'), findsOneWidget);
      expect(find.text('以正式通知为准，你也可以清空目标日期。'), findsOneWidget);
      expect(find.text('建议依据：在校期间工作日两小时，周末四小时'), findsOneWidget);
      final monday = find.byKey(const ValueKey('weekly-1-1'));
      await tester.enterText(monday, '180');
      await tester.tap(find.text('恢复推荐时间'));
      await tester.pumpAndSettle();
      final restored = find.byKey(const ValueKey('weekly-2-1'));
      expect(tester.widget<TextFormField>(restored).initialValue, '120');
      await tester.enterText(restored, '150');
      await tester.tap(find.text('确认并生成每日计划'));
      await tester.pumpAndSettle();
      expect(action!['end_date'], '2026-11-13');
      expect(action!['target_date'], '2027-12-18');
      expect((action!['weekly_minutes'] as Map)['1'], 150);
      expect((action!['weekly_minutes'] as Map)['0'], 240);
    },
  );

  testWidgets('long options wrap on mobile without overflow', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = onboardingFixture()
      ..['question_options'] = [
        '准备上海交通大学计算机技术专业研究生考试并参加408统考',
        '在职备考公务员，工作日晚上有时间',
      ];
    await mount(tester, session);
    expect(find.text('其他'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
