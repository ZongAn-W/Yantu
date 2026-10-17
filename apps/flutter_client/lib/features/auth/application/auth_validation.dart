String? validateEmail(String? value) =>
    value != null &&
        RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
    ? null
    : '请输入有效的邮箱';

String? validateUsername(String? value) {
  final text = value?.trim() ?? '';
  if (text.length < 2 || text.length > 24) return '用户名需为 2 至 24 个字符';
  if (!RegExp(r'^[\u3400-\u4dbf\u4e00-\u9fffA-Za-z0-9_]+$').hasMatch(text)) {
    return '用户名只能包含中文、英文字母、数字和下划线';
  }
  return null;
}

String? validatePassword(String? value, {required bool register}) {
  final password = value ?? '';
  if (password.isEmpty) return '请输入密码';
  if (register &&
      (password.length < 9 ||
          password.length > 128 ||
          !RegExp('[A-Za-z]').hasMatch(password) ||
          !RegExp('[0-9]').hasMatch(password))) {
    return '密码需为 9 至 128 位，包含英文字母和数字';
  }
  return password.length > 200 ? '密码不能超过 200 位' : null;
}

String? validateCode(String? value) =>
    RegExp(r'^\d{6}$').hasMatch(value ?? '') ? null : '请输入 6 位邮箱验证码';
