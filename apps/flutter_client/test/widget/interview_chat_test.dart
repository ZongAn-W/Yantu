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
import 'package:sjtu_study_planner_client/features/onboarding/presentation/learning_context_view.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/onboarding_page.dart';
import '../support/http_adapter.dart';
import '../support/onboarding_fixture.dart';

final _answerInput = find.byKey(const ValueKey('interview-answer-input'));
final _sendButton = find.byKey(const ValueKey('interview-send'));
const _typingText = '对方正在输入中';

/// 聊天页里“对方正在输入中”带循环动画，等待态不能用 pumpAndSettle，
/// 因此手动推进几帧让未来任务和重建都完成。
Future<void> _pumpFrames(WidgetTester tester, {int frames = 6}) async {
  for (var frame = 0; frame < frames; frame++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

Future<TestAdapter> _mount(
  WidgetTester tester,
  Map<String, dynamic> session, {
  Respond? respond,
  bool settle = true,
}) async {
  final adapter = TestAdapter(
    respond ?? (_) async => jsonResponse({'session': session}),
  );
  final client = ApiClient(
    config: const AppConfig(apiBaseUrl: 'http://api.test'),
    tokenStore: MemoryTokenStore(),
    dio: Dio()..httpClientAdapter = adapter,
  );
  addTearDown(client.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [apiClientProvider.overrideWithValue(client)],
      child: MaterialApp(theme: plannerTheme(), home: const OnboardingPage()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await _pumpFrames(tester);
  }
  return adapter;
}

Map<dynamic, dynamic>? _lastAction(TestAdapter adapter) {
  final posts = adapter.requests
      .where((request) => request.method == 'POST')
      .toList();
  if (posts.isEmpty) return null;
  return (posts.last.data as Map)['action'] as Map;
}

String _inputText(WidgetTester tester) =>
    tester.widget<TextFormField>(_answerInput).controller!.text;

void main() {
  group('聊天式访谈布局', () {
    testWidgets('shows the chat header, question history and composer', (
      tester,
    ) async {
      final session = onboardingFixture(answers: 2);
      await _mount(tester, session);

      expect(find.text('目标访谈'), findsOneWidget);
      expect(find.text('不白学助手'), findsOneWidget);
      expect(find.text('第 3 问'), findsOneWidget);
      expect(find.textContaining('已答 2 问'), findsOneWidget);
      expect(find.text('重新访谈'), findsOneWidget);
      expect(find.byTooltip('学习情况与官方资料'), findsOneWidget);

      // 历史消息以气泡形式逐题展示。
      expect(
        find.byKey(const ValueKey('interview-question-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('interview-answer-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('interview-question-2')),
        findsOneWidget,
      );
      expect(find.text('问题1'), findsOneWidget);
      expect(find.text('回答1'), findsOneWidget);
      expect(find.text(session['question'] as String), findsOneWidget);
      // 气泡使用普通 Text（不是 SelectableText）。
      expect(find.byType(SelectableText), findsNothing);

      expect(_answerInput, findsOneWidget);
      expect(find.text('输入你的回答…'), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
      expect(find.byTooltip('语音输入'), findsOneWidget);
    });

    testWidgets('server question options no longer render choice controls', (
      tester,
    ) async {
      final session = onboardingFixture(answers: 1)
        ..['question_type'] = 'multiple_choice'
        ..['question_multiple'] = true
        ..['question_options'] = ['数学', '英语'];
      await _mount(tester, session);

      expect(find.byType(RadioListTile<String>), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text('数学'), findsNothing);
      expect(find.text('英语'), findsNothing);
      expect(find.text('其他'), findsNothing);
      expect(find.text('直接填写'), findsNothing);
      expect(find.text('改用选项'), findsNothing);
      expect(find.textContaining('可多选'), findsNothing);
      expect(_answerInput, findsOneWidget);
      expect(find.text('第 2 问'), findsOneWidget);
    });

    testWidgets('legacy checkpoint sessions use the same chat view', (
      tester,
    ) async {
      await _mount(tester, onboardingFixture(answers: 5, stage: 'checkpoint'));

      expect(find.text('不白学助手'), findsOneWidget);
      expect(find.text('第 6 问'), findsOneWidget);
      expect(find.text('根据当前回答生成科目'), findsOneWidget);
      expect(find.text('信息已记录'), findsNothing);
      expect(find.text('继续完善信息'), findsNothing);
    });

    testWidgets('mobile width renders the chat page without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _mount(tester, onboardingFixture(answers: 3));

      expect(find.text('不白学助手'), findsOneWidget);
      expect(_answerInput, findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('发送与校验', () {
    testWidgets(
      'empty and whitespace answers show validation without posting',
      (tester) async {
        final adapter = await _mount(tester, onboardingFixture());

        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(find.text('请先填写回答'), findsOneWidget);
        expect(_lastAction(adapter), isNull);

        await tester.enterText(_answerInput, '   ');
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(find.text('请先填写回答'), findsOneWidget);
        expect(_lastAction(adapter), isNull);
      },
    );

    testWidgets('sending an answer posts the trimmed text and clears input', (
      tester,
    ) async {
      final session = onboardingFixture();
      final next = onboardingFixture(answers: 1);
      final adapter = await _mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            return jsonResponse({'session': next});
          }
          return jsonResponse({'session': session});
        },
      );

      await tester.enterText(_answerInput, '  准备计算机专业研究生考试  ');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();

      final action = _lastAction(adapter)!;
      expect(action['type'], 'answer');
      expect(action['answer'], '准备计算机专业研究生考试');
      expect(_inputText(tester), isEmpty);
      expect(find.text('第 2 问'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('interview-question-0')),
        findsOneWidget,
      );
      expect(find.text('回答1'), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
    });

    testWidgets('failed send keeps the draft and shows the request error', (
      tester,
    ) async {
      final session = onboardingFixture();
      final adapter = await _mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            return jsonResponse({'error': 'AI 暂时不可用，请重试'}, 502);
          }
          return jsonResponse({'session': session});
        },
      );

      await tester.enterText(_answerInput, '英语阅读需要继续加强');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();

      expect(_lastAction(adapter)!['answer'], '英语阅读需要继续加强');
      expect(_inputText(tester), '英语阅读需要继续加强');
      expect(find.text('AI 暂时不可用，请重试'), findsOneWidget);
      // 失败后仍停留在第 1 问，问题不会前进。
      expect(find.text('第 1 问'), findsOneWidget);
      expect(find.text('重新读取已保存进度'), findsOneWidget);
    });
  });

  group('AI 等待态', () {
    testWidgets(
      'typing indicator disables sending and draft survives failure',
      (tester) async {
        final session = onboardingFixture(answers: 5);
        final response = Completer<ResponseBody>();
        var posts = 0;
        await _mount(
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

        await tester.enterText(_answerInput, '第六个回答');
        await tester.tap(find.text('发送'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(_typingText), findsOneWidget);
        expect(find.text('AI 正在思考中…'), findsNothing);
        expect(tester.widget<FilledButton>(_sendButton).onPressed, isNull);
        expect(tester.widget<TextFormField>(_answerInput).enabled, isFalse);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('interview-sending')),
            matching: find.text('第六个回答'),
          ),
          findsOneWidget,
        );

        // 处理中重复点击不会发起第二个请求。
        await tester.tap(find.text('发送'), warnIfMissed: false);
        await tester.pump();
        expect(posts, 1);

        response.complete(jsonResponse({'error': '失败保留输入'}, 502));
        await tester.pumpAndSettle();
        expect(posts, 1);
        expect(find.text(_typingText), findsNothing);
        expect(find.text('失败保留输入'), findsOneWidget);
        expect(_inputText(tester), '第六个回答');
        expect(find.text('第 6 问'), findsOneWidget);
      },
    );

    testWidgets(
      'generation shows the typing indicator and clears after failure',
      (tester) async {
        final session = onboardingFixture(answers: 5);
        final response = Completer<ResponseBody>();
        await _mount(
          tester,
          session,
          respond: (request) async {
            if (request.method == 'POST') return response.future;
            return jsonResponse({'session': session});
          },
        );

        await tester.tap(find.text('根据当前回答生成科目'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.text(_typingText), findsOneWidget);
        expect(find.text('AI 正在思考中…'), findsNothing);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, '根据当前回答生成科目'),
              )
              .onPressed,
          isNull,
        );

        response.complete(jsonResponse({'error': '生成失败，请重试'}, 502));
        await tester.pumpAndSettle();
        expect(find.text(_typingText), findsNothing);
        expect(find.text('生成失败，请重试'), findsOneWidget);
        expect(find.text('根据当前回答生成科目'), findsOneWidget);
      },
    );

    testWidgets('mobile layout keeps the typing indicator without overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = onboardingFixture(answers: 5);
      final response = Completer<ResponseBody>();
      await _mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') return response.future;
          return jsonResponse({'session': session});
        },
      );

      await tester.tap(find.text('根据当前回答生成科目'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(_typingText), findsOneWidget);
      expect(tester.takeException(), isNull);

      response.complete(jsonResponse({'error': '请稍后重试'}, 502));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('生成科目入口', () {
    testWidgets('generation is hidden before five answers', (tester) async {
      await _mount(tester, onboardingFixture(answers: 4));

      expect(find.text('第 5 问'), findsOneWidget);
      expect(find.text('根据当前回答生成科目'), findsNothing);
    });

    testWidgets('five answers keep the interview going with generation', (
      tester,
    ) async {
      await _mount(tester, onboardingFixture(answers: 5));

      expect(find.text('第 6 问'), findsOneWidget);
      expect(find.textContaining('已答 5 问'), findsOneWidget);
      expect(find.text('根据当前回答生成科目'), findsOneWidget);
      expect(find.text('发送'), findsOneWidget);
    });

    testWidgets('generation does not submit the unsubmitted draft', (
      tester,
    ) async {
      final session = onboardingFixture(answers: 5);
      final adapter = await _mount(
        tester,
        session,
        respond: (request) async {
          if (request.method == 'POST') {
            return jsonResponse({
              'session': onboardingFixture(stage: 'courses', answers: 5),
            });
          }
          return jsonResponse({'session': session});
        },
      );

      await tester.enterText(_answerInput, '这条回答还没有提交');
      await tester.tap(find.text('根据当前回答生成科目'));
      await tester.pumpAndSettle();

      final action = _lastAction(adapter)!;
      expect(action['type'], 'generate_courses');
      expect(action.containsKey('answer'), isFalse);
      expect(find.text('请先填写回答'), findsNothing);
      expect(find.text('确认你的课程'), findsOneWidget);
    });

    testWidgets('fifty answers reach the limit and keep only generation', (
      tester,
    ) async {
      await _mount(tester, onboardingFixture(answers: 50));

      expect(find.text('访谈已达到上限'), findsOneWidget);
      expect(find.text('已达到 50 题上限'), findsOneWidget);
      expect(find.text('根据当前回答生成科目'), findsOneWidget);
      expect(find.text('发送'), findsNothing);
      expect(_answerInput, findsNothing);
      expect(find.byTooltip('语音输入'), findsNothing);
    });
  });

  group('重新访谈与辅助入口', () {
    testWidgets(
      'restart asks for confirmation and resets to the first question',
      (tester) async {
        final session = onboardingFixture(answers: 3);
        final adapter = await _mount(
          tester,
          session,
          respond: (request) async {
            if (request.method == 'POST') {
              return jsonResponse({'session': onboardingFixture()});
            }
            return jsonResponse({'session': session});
          },
        );

        await tester.tap(find.text('重新访谈'));
        await tester.pumpAndSettle();
        expect(find.text('重新开始访谈？'), findsOneWidget);
        expect(_lastAction(adapter), isNull);

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(find.text('重新开始访谈？'), findsNothing);
        expect(_lastAction(adapter), isNull);

        await tester.tap(find.text('重新访谈'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('重新开始'));
        await tester.pumpAndSettle();
        expect(_lastAction(adapter)!['type'], 'restart_interview');
        expect(find.text('你的长期目标是什么？'), findsOneWidget);
        expect(find.text('第 1 问'), findsOneWidget);
      },
    );

    testWidgets('learning context sheet opens from the header action', (
      tester,
    ) async {
      final current = DateTime.now().year;
      final session = onboardingFixture(answers: 2)
        ..['learning_context'] = {
          'facts': {
            'identity': {'value': '本科大三', 'answer_index': 0, 'quote': '本科大三'},
          },
          'timing': {
            'exam_year': current + 1,
            'admission_year': current + 2,
            'estimated': true,
            'reason': '按四年制本科应届升学推算',
          },
        };
      await _mount(tester, session);

      await tester.tap(find.byTooltip('学习情况与官方资料'));
      await tester.pumpAndSettle();
      expect(find.byType(LearningContextView), findsOneWidget);
      expect(find.text('当前学习情况'), findsOneWidget);
      expect(find.textContaining('年初试'), findsOneWidget);

      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(LearningContextView), findsNothing);
    });

    testWidgets('research status is shown as a system line in the chat', (
      tester,
    ) async {
      final session = onboardingFixture(answers: 5)
        ..['research'] = {
          'key': 'same-goal',
          'status': 'not_found',
          'message': '暂未核实目标年度要求',
          'facts': <Map<String, dynamic>>[],
          'sources': <Map<String, dynamic>>[],
        };
      await _mount(tester, session);

      expect(find.text('暂未核实目标年度要求'), findsOneWidget);
      expect(find.text('第 6 问'), findsOneWidget);
    });

    testWidgets('voice mode falls back with a snackbar when unsupported', (
      tester,
    ) async {
      await _mount(tester, onboardingFixture());

      await tester.tap(find.byTooltip('语音输入'));
      await tester.pumpAndSettle();
      expect(find.text('按住 说话'), findsOneWidget);
      expect(_answerInput, findsNothing);
      expect(find.text('发送'), findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('按住 说话')),
      );
      await tester.pump();
      expect(find.text('当前环境暂不支持语音输入，请直接输入文字'), findsOneWidget);
      await gesture.up();

      // SnackBar 的 4 秒自动消失计时器在入场动画（250ms）结束后才启动：
      // 先播完入场动画，再推进 4 秒并等退场动画结束，避免它遮挡底部按钮。
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('当前环境暂不支持语音输入，请直接输入文字'), findsNothing);

      await tester.tap(find.byTooltip('切换文字输入'));
      await tester.pumpAndSettle();
      expect(_answerInput, findsOneWidget);
      expect(find.text('按住 说话'), findsNothing);
    });
  });

  group('领域模型兼容', () {
    test(
      'legacy sessions keep free text and default recommendation fields',
      () {
        final session = OnboardingSession.fromJson(onboardingFixture());
        expect(session.questionOptions, isEmpty);
        expect(session.questionMultiple, isFalse);
        expect(session.recommendations.targetDate, isEmpty);
        expect(session.recommendations.weeklyMinutes, isEmpty);
      },
    );

    test(
      'explicit question types override stale legacy presentation fields',
      () {
        OnboardingSession read(
          String type,
          bool multiple,
          List<dynamic> options,
        ) => OnboardingSession.fromJson({
          ...onboardingFixture(),
          'question_type': type,
          'question_multiple': multiple,
          'question_options': options,
        });

        final text = read('text', true, ['考研', '考公']);
        expect(text.questionType, 'text');
        expect(text.effectiveQuestionType, 'text');
        expect(text.effectiveQuestionOptions, isEmpty);
        expect(text.effectiveQuestionMultiple, isFalse);
        expect(
          text.edit(research: {'status': 'verified'}).questionType,
          'text',
        );

        final single = read('single_choice', true, ['考研', '考公']);
        expect(single.effectiveQuestionType, 'single_choice');
        expect(single.effectiveQuestionMultiple, isFalse);
        final multiple = read('multiple_choice', false, ['考研', '考公']);
        expect(multiple.effectiveQuestionType, 'multiple_choice');
        expect(multiple.effectiveQuestionMultiple, isTrue);

        for (final type in ['single_choice', 'multiple_choice']) {
          final invalid = read(type, true, ['', 'Other', '其他', 12, null]);
          expect(invalid.effectiveQuestionType, 'text');
          expect(invalid.effectiveQuestionOptions, isEmpty);
          expect(invalid.effectiveQuestionMultiple, isFalse);
        }
        final legacy = OnboardingSession.fromJson({
          ...onboardingFixture(),
          'question_multiple': true,
          'question_options': ['考研', '考公'],
        });
        expect(legacy.questionType, isNull);
        expect(legacy.effectiveQuestionType, 'multiple_choice');
        for (final invalid in [
          null,
          'bad options',
          {'bad': true},
        ]) {
          final session = OnboardingSession.fromJson({
            ...onboardingFixture(),
            'question_type': 'single_choice',
            'question_options': invalid,
          });
          expect(session.effectiveQuestionType, 'text');
        }
      },
    );

    test('legacy session options are normalized and reserve Other', () {
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
    });
  });
}
