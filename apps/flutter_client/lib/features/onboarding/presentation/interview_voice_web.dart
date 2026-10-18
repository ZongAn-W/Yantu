import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web 端语音输入实现：直接调用浏览器 Web Speech API。
///
/// 通过全局 `SpeechRecognition`（或 Chromium 的 `webkitSpeechRecognition`）
/// 动态构造识别器，避免依赖 `package:web` 或新增 pub 依赖。仅 Chrome / Edge
/// 等 Chromium 浏览器在安全上下文（HTTPS 或 localhost）中支持该能力；
/// 离线或内网环境下识别服务可能返回 network 错误。
class InterviewVoiceInput {
  JSObject? _recognition;
  bool _sessionActive = false;
  bool _doneNotified = false;
  bool _disposed = false;
  void Function(String text, bool isFinal)? _onText;
  void Function(String message)? _onError;
  void Function()? _onDone;

  /// 浏览器提供可调用的识别构造函数，且当前处于安全上下文。
  static bool get isSupported {
    if (_findRecognitionConstructor() == null) return false;
    final secureContext = globalContext['isSecureContext'];
    if (secureContext != null &&
        secureContext.isA<JSBoolean>() &&
        !(secureContext as JSBoolean).toDart) {
      return false;
    }
    return true;
  }

  /// 开始一段新的识别会话；不支持或已有会话在运行时返回 false。
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    required void Function(String message) onError,
    required void Function() onDone,
  }) async {
    if (_disposed || _sessionActive) return false;
    final constructor = _findRecognitionConstructor();
    if (constructor == null) return false;
    final JSObject recognition;
    try {
      recognition = constructor.callAsConstructor<JSObject>();
    } catch (_) {
      return false;
    }
    _recognition = recognition;
    _sessionActive = true;
    _doneNotified = false;
    _onText = onText;
    _onError = onError;
    _onDone = onDone;
    // 识别器属性通过 JSObject 动态设置，避免引入 package:web 的静态接口。
    recognition['lang'] = 'zh-CN'.toJS;
    recognition['continuous'] = true.toJS;
    recognition['interimResults'] = true.toJS;
    recognition['onresult'] = ((JSObject event) => _handleResult(event)).toJS;
    recognition['onerror'] = ((JSObject event) => _handleError(event)).toJS;
    recognition['onend'] = (() => _handleEnd()).toJS;
    try {
      recognition.callMethod<JSAny?>('start'.toJS);
    } catch (_) {
      // 例如识别器状态异常时 start 会抛错，按启动失败处理，且不触发回调。
      _teardownSession();
      return false;
    }
    return true;
  }

  /// 请求结束当前会话；最终由浏览器的 `onend` 事件确认并触发 onDone。
  Future<void> stop() async {
    if (_disposed || !_sessionActive) return;
    final recognition = _recognition;
    if (recognition == null) return;
    try {
      recognition.callMethod<JSAny?>('stop'.toJS);
    } catch (_) {
      // 识别器可能已自行结束，兜底结束会话以保证 onDone 恰好触发一次。
      _finishSession();
    }
  }

  /// 释放识别器；重复调用安全，释放后不再触发任何回调。
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final recognition = _recognition;
    _teardownSession();
    if (recognition == null) return;
    try {
      recognition.callMethod<JSAny?>('abort'.toJS);
    } catch (_) {
      // 识别器已失效时忽略。
    }
  }

  void _handleResult(JSObject event) {
    if (_disposed || !_sessionActive) return;
    final results = event['results'];
    if (results == null || !results.isA<JSObject>()) return;
    final resultList = results as JSObject;
    final lengthValue = resultList['length'];
    final length = lengthValue != null && lengthValue.isA<JSNumber>()
        ? (lengthValue as JSNumber).toDartInt
        : 0;
    final buffer = StringBuffer();
    var hasFinal = false;
    for (var index = 0; index < length; index++) {
      // DOM 结果列表没有 Dart 侧接口，用数字键动态读取元素。
      final resultValue = resultList.getProperty<JSAny?>(index.toJS);
      if (resultValue == null || !resultValue.isA<JSObject>()) continue;
      final result = resultValue as JSObject;
      final isFinalValue = result['isFinal'];
      final isFinal =
          isFinalValue != null &&
          isFinalValue.isA<JSBoolean>() &&
          (isFinalValue as JSBoolean).toDart;
      if (isFinal) hasFinal = true;
      final alternativeValue = result.getProperty<JSAny?>(0.toJS);
      if (alternativeValue == null || !alternativeValue.isA<JSObject>()) {
        continue;
      }
      final transcript = (alternativeValue as JSObject)['transcript'];
      if (transcript != null && transcript.isA<JSString>()) {
        buffer.write((transcript as JSString).toDart);
      }
    }
    // 按索引顺序拼接 final 与 interim 段，回调始终传累计文本。
    _onText?.call(buffer.toString(), hasFinal);
  }

  void _handleError(JSObject event) {
    if (_disposed || !_sessionActive) return;
    final errorValue = event['error'];
    final code = errorValue != null && errorValue.isA<JSString>()
        ? (errorValue as JSString).toDart
        : '';
    final onError = _onError;
    // 先通知错误再结束会话，避免 onDone 把失败前的临时文本提交出去。
    onError?.call(_messageForError(code));
    _finishSession();
  }

  void _handleEnd() {
    if (_disposed || !_sessionActive) return;
    _finishSession();
  }

  /// 结束当前会话并触发一次 onDone；标志位保证每段会话只通知一次。
  void _finishSession() {
    if (_doneNotified) return;
    _doneNotified = true;
    _onText = null;
    _onError = null;
    final onDone = _onDone;
    _onDone = null;
    _teardownSession();
    if (!_disposed) onDone?.call();
  }

  /// 清理会话状态并解除事件绑定，不触发任何回调。
  void _teardownSession() {
    _sessionActive = false;
    final recognition = _recognition;
    _recognition = null;
    _onText = null;
    _onError = null;
    _onDone = null;
    if (recognition == null) return;
    try {
      recognition['onresult'] = null;
      recognition['onerror'] = null;
      recognition['onend'] = null;
    } catch (_) {
      // 识别器已失效时忽略。
    }
  }

  static JSFunction? _findRecognitionConstructor() {
    for (final name in const ['SpeechRecognition', 'webkitSpeechRecognition']) {
      final candidate = globalContext[name];
      if (candidate != null && candidate.typeofEquals('function')) {
        return candidate as JSFunction;
      }
    }
    return null;
  }

  static String _messageForError(String code) {
    switch (code) {
      case 'not-allowed':
      case 'service-not-allowed':
        return '麦克风权限被拒绝';
      case 'no-speech':
        return '没有听到声音';
      case 'audio-capture':
        return '找不到麦克风';
      case 'network':
        return '语音服务连接失败（需要网络）';
      case 'aborted':
        return '语音输入已取消';
      default:
        return '语音输入失败，请重试';
    }
  }
}
