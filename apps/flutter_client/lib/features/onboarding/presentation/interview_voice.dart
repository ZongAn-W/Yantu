// 访谈页语音输入模块入口：调用方统一 import 本文件，无需关心平台。
// Web 端使用浏览器 SpeechRecognition，其他平台回退到不可用的 stub。
export 'interview_voice_stub.dart'
    if (dart.library.js_interop) 'interview_voice_web.dart';
