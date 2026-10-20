import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
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
    final editingEnabled = !auth.loading && !auth.restoring;
    if (auth.restoring) {
      return Scaffold(
        body: Center(
          child: Semantics(liveRegion: true, child: const Text('正在检查登录状态…')),
        ),
      );
    }
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              padding: const EdgeInsets.all(PlannerSpace.xl),
              decoration: BoxDecoration(
                color: PlannerColors.surface,
                border: Border.all(color: PlannerColors.border),
                borderRadius: BorderRadius.circular(PlannerRadius.dialog),
              ),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: PlannerColors.blue,
                              borderRadius: BorderRadius.circular(9),
                            ),
                            child: const Icon(
                              Icons.auto_stories_outlined,
                              color: Colors.white,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '不白学',
                                style: text.titleMedium?.copyWith(fontSize: 16),
                              ),
                              Text(
                                '学习执行台',
                                style: text.labelSmall?.copyWith(
                                  color: PlannerColors.subtle,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: PlannerSpace.xl),
                      Text(
                        _register ? '创建账号' : '登录不白学 · 学习执行台',
                        style: text.titleLarge?.copyWith(fontSize: 18.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _register
                            ? '注册后开始记录每天的真实学习用时'
                            : '登录后多端同步；计时、事项与日历属于同一个学习计划。',
                        style: text.bodySmall?.copyWith(
                          color: PlannerColors.muted,
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: PlannerSpace.lg),
                      IgnorePointer(
                        ignoring: busy,
                        child: Opacity(
                          opacity: busy ? 0.6 : 1,
                          child: PlannerSegmented<bool>(
                            value: _register,
                            height: 32,
                            items: const [(false, '登录'), (true, '注册')],
                            onChanged: (register) => setState(() {
                              _register = register;
                              _password.clear();
                              _confirmation.clear();
                              _visible = false;
                              _formKey.currentState?.reset();
                            }),
                          ),
                        ),
                      ),
                      const SizedBox(height: PlannerSpace.xl),
                      if (_register) ...[
                        TextFormField(
                          controller: _username,
                          enabled: editingEnabled,
                          decoration: const InputDecoration(labelText: '用户名'),
                          autofillHints: const [AutofillHints.nickname],
                          textInputAction: TextInputAction.next,
                          validator: validateUsername,
                        ),
                        const SizedBox(height: PlannerSpace.lg),
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
                        const SizedBox(height: PlannerSpace.lg),
                        TextFormField(
                          controller: _code,
                          enabled: editingEnabled,
                          decoration: InputDecoration(
                            labelText: '邮箱验证码',
                            suffixIcon: Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: TextButton(
                                onPressed: busy || auth.retrySeconds > 0
                                    ? null
                                    : () {
                                        if (_emailKey.currentState!
                                            .validate()) {
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
                      const SizedBox(height: PlannerSpace.lg),
                      TextFormField(
                        controller: _password,
                        enabled: editingEnabled,
                        decoration: InputDecoration(
                          labelText: '密码',
                          helperText: _register ? '至少 9 位，包含英文字母和数字' : null,
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _visible = !_visible),
                            tooltip: _visible ? '隐藏密码' : '显示密码',
                            icon: Icon(
                              _visible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 19,
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
                        const SizedBox(height: PlannerSpace.lg),
                        TextFormField(
                          controller: _confirmation,
                          enabled: editingEnabled,
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
                          padding: const EdgeInsets.only(top: PlannerSpace.lg),
                          child: PlannerNotice(
                            auth.notice!,
                            tone: PlannerNoticeTone.success,
                          ),
                        ),
                      if (auth.error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: PlannerSpace.lg),
                          child: PlannerNotice(
                            auth.error!,
                            tone: PlannerNoticeTone.error,
                          ),
                        ),
                      const SizedBox(height: PlannerSpace.xl),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        onPressed: busy ? null : _submit,
                        icon: auth.loading
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                _register
                                    ? Icons.person_add_outlined
                                    : Icons.login,
                                size: 18,
                              ),
                        label: Text(
                          auth.loading
                              ? (_register ? '正在注册…' : '正在登录…')
                              : _register
                              ? '注册并登录'
                              : '登录',
                        ),
                      ),
                      const SizedBox(height: PlannerSpace.md),
                      Text(
                        '计时、事项与日历都属于同一个学习计划；登录后自动同步。',
                        textAlign: TextAlign.center,
                        style: text.labelSmall?.copyWith(
                          color: PlannerColors.subtle,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
