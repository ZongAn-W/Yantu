import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/onboarding/presentation/interview_voice.dart';

void main() {
  test('非 Web 平台解析到 stub：不支持、start 返回 false 且不回调', () async {
    expect(InterviewVoiceInput.isSupported, isFalse);
    final voice = InterviewVoiceInput();
    var textCalls = 0;
    var errorCalls = 0;
    var doneCalls = 0;
    final started = await voice.start(
      onText: (text, isFinal) => textCalls++,
      onError: (message) => errorCalls++,
      onDone: () => doneCalls++,
    );
    expect(started, isFalse);
    expect(textCalls, 0);
    expect(errorCalls, 0);
    expect(doneCalls, 0);
    await voice.stop();
    await voice.stop();
    await voice.dispose();
    await voice.dispose();
    // stub 的 stop/dispose 都是幂等空操作，不会产生任何回调或异常。
    expect(textCalls + errorCalls + doneCalls, 0);
  });

  test('stub 的 start 可重复调用且始终返回 false', () async {
    final voice = InterviewVoiceInput();
    expect(
      await voice.start(
        onText: (text, isFinal) {},
        onError: (message) {},
        onDone: () {},
      ),
      isFalse,
    );
    expect(
      await voice.start(
        onText: (text, isFinal) {},
        onError: (message) {},
        onDone: () {},
      ),
      isFalse,
    );
  });
}
