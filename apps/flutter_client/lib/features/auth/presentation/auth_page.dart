import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/auth_controller.dart';
import '../application/auth_validation.dart';

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _username = TextEditingController();
  final _confirmation = TextEditingController();
  final _code = TextEditingController();
  bool _register = false;
  bool _visible = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _username.dispose();
    _confirmation.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final controller = ref.read(authControllerProvider.notifier);
    if (_register) {
      await controller.register(
        email: _email.text,
        username: _username.text,
        password: _password.text,
        code: _code.text,
      );
    } else {
      await controller.login(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final busy = auth.loading || auth.codeSending || auth.restoring;
    if (auth.restoring) {
      return Scaffold(
        body: Center(
          child: Semantics(liveRegion: true, child: const Text('正在检查登录状态…')),
        ),
      );
    }
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.school_outlined, size: 30),
                        SizedBox(width: 12),
                        Text(
                          '不白学',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _register ? '创建账号' : '登录考研执行台',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('登录')),
                        ButtonSegment(value: true, label: Text('注册')),
                      ],
                      selected: {_register},
                      onSelectionChanged: busy
                          ? null
                          : (values) => setState(() {
                              _register = values.single;
                              _password.clear();
                              _confirmation.clear();
                              _visible = false;
                              _formKey.currentState?.reset();
                            }),
                    ),
                    const SizedBox(height: 24),
                    if (_register) ...[
                      TextFormField(
                        controller: _username,
                        enabled: !busy,
                        decoration: const InputDecoration(labelText: '用户名'),
                        autofillHints: const [AutofillHints.nickname],
                        textInputAction: TextInputAction.next,
                        validator: validateUsername,
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      key: _emailKey,
                      controller: _email,
                      enabled: !busy,
                      decoration: const InputDecoration(labelText: '邮箱'),
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: validateEmail,
                    ),
                    if (_register) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _code,
                        enabled: !busy,
                        decoration: InputDecoration(
                          labelText: '邮箱验证码',
                          suffixIcon: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: TextButton(
                              onPressed: busy || auth.retrySeconds > 0
                                  ? null
                                  : () {
                                      if (_emailKey.currentState!.validate()) {
                                        ref
                                            .read(
                                              authControllerProvider.notifier,
                                            )
                                            .requestRegistrationCode(
                                              _email.text,
                                            );
                                      }
                                    },
                              child: Text(
                                auth.codeSending
                                    ? '发送中…'
                                    : auth.retrySeconds > 0
                                    ? '${auth.retrySeconds} 秒后重发'
                                    : '发送验证码',
                              ),
                            ),
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        autofillHints: const [AutofillHints.oneTimeCode],
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        textInputAction: TextInputAction.next,
                        validator: validateCode,
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _password,
                      enabled: !busy,
                      decoration: InputDecoration(
                        labelText: '密码',
                        helperText: _register ? '至少 9 位，包含英文字母和数字' : null,
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _visible = !_visible),
                          tooltip: _visible ? '隐藏密码' : '显示密码',
                          icon: Icon(
                            _visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      obscureText: !_visible,
                      autofillHints: [
                        _register
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: _register
                          ? TextInputAction.next
                          : TextInputAction.done,
                      onFieldSubmitted: busy || _register
                          ? null
                          : (_) => _submit(),
                      validator: (value) =>
                          validatePassword(value, register: _register),
                    ),
                    if (_register) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmation,
                        enabled: !busy,
                        obscureText: !_visible,
                        decoration: const InputDecoration(labelText: '确认密码'),
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: busy ? null : (_) => _submit(),
                        validator: (value) =>
                            value == _password.text ? null : '两次输入的密码不一致',
                      ),
                    ],
                    if (auth.notice != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            auth.notice!,
                            style: const TextStyle(color: Color(0xff237354)),
                          ),
                        ),
                      ),
                    if (auth.error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            auth.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: busy ? null : _submit,
                      icon: auth.loading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              _register
                                  ? Icons.person_add_outlined
                                  : Icons.login,
                            ),
                      label: Text(
                        auth.loading
                            ? (_register ? '正在注册…' : '正在登录…')
                            : _register
                            ? '注册并登录'
                            : '登录',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
