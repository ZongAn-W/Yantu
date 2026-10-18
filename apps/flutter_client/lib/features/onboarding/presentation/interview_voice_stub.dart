/// 非 Web 平台的语音输入兜底实现。
///
/// 桌面/移动端没有浏览器语音识别能力，因此始终不可用、不会启动识别，
/// 也不会触发任何回调；调用方可根据 [InterviewVoiceInput.isSupported]
/// 决定是否展示语音入口。
class InterviewVoiceInput {
  /// 非 Web 平台不支持语音输入。
  static bool get isSupported => false;

  /// 兜底实现不会启动识别，始终返回 false。
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
    required void Function() onDone,
  }) async => false;

  /// 空操作，可重复调用。
  Future<void> stop() async {}

  /// 空操作，可重复调用。
  Future<void> dispose() async {}
}
