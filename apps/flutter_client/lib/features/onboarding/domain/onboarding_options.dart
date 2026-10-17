/// “其他”自定义回答入口在单选控件里的内部标识；它只用于界面状态，永不作为回答提交。
const otherOptionKey = '__other__';
const otherOptionLabel = '其他';

/// 通用“自填”占位项：只匹配整个选项，不做前缀匹配，
/// 避免把“其他语言课程”这类有具体含义的业务选项误删。
final _otherPlaceholder = RegExp(
  r'^(?:其他|其它|other)\s*(?:[：:]\s*)?(?:[（(]\s*(?:自填|自定义|请填写|请补充|填写|请说明)\s*[）)])?$',
  caseSensitive: false,
);

/// 归一化服务端题目选项：去首尾空格、去空项、忽略大小写去重，并移除“其他”等自填占位项。
///
/// 服务端只返回具体业务选项，“其他”入口统一由客户端提供。该函数也用于读取旧会话，
/// 因此旧响应里残留的“其他”不会和客户端入口重复；有效选项保持首次出现的顺序。
List<String> normalizeQuestionOptions(Iterable<String> options) {
  final seen = <String>{};
  final normalized = <String>[];
  for (final raw in options) {
    final option = raw.trim();
    if (option.isEmpty || _otherPlaceholder.hasMatch(option)) continue;
    if (!seen.add(option.toLowerCase())) continue;
    normalized.add(option);
  }
  return normalized;
}
