import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../auth/application/auth_controller.dart';

/// Password confirmation stays open until deletion has a definite outcome.
///
/// 视觉：Mist Ink / 雾蓝墨水。白底 + 14px 圆角 + 发丝边框；表头 / 表尾各一条
/// 发丝分隔线，表尾按钮右对齐；内容区独立滚动，危险操作按钮保留 danger 语义。
class DeleteAccountDialog extends ConsumerStatefulWidget {
  const DeleteAccountDialog({this.onExport, super.key});

  final Future<void> Function()? onExport;

  static Future<bool> show(
    BuildContext context, {
    Future<void> Function()? onExport,
  }) async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DeleteAccountDialog(onExport: onExport),
      ) ==
      true;

  @override
  ConsumerState<DeleteAccountDialog> createState() =>
      _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<DeleteAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _submitting = false;
  bool _exporting = false;
  String? _error;
  String? _exportNotice;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_submitting || _exporting || !_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final deleted = await ref
          .read(authControllerProvider.notifier)
          .deleteAccount(_password.text);
      if (!mounted) return;
      if (deleted) {
        // The auth redirect may already have replaced the underlying page.
        // Remove this exact dialog route so we never pop the new login page.
        final route = ModalRoute.of(context);
        if (route != null && route.isActive) {
          Navigator.of(context).removeRoute(route, true);
        }
      } else {
        setState(() {
          _error = ref.read(authControllerProvider).error ?? '未能完成注销，请重试。';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = '暂时无法确认注销结果，请保持联网后重试。');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _export() async {
    if (_exporting || _submitting || widget.onExport == null) return;
    setState(() {
      _exporting = true;
      _error = null;
      _exportNotice = null;
    });
    try {
      await widget.onExport!();
      if (mounted) setState(() => _exportNotice = '已导出本地数据，请妥善保存。');
    } catch (_) {
      if (mounted) setState(() => _error = '导出失败，请重试或取消注销后到数据管理中导出。');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final busy = _submitting || auth.deletingAccount;
    final locked = busy || _exporting;
    final width = MediaQuery.sizeOf(context).width - 64 < 460
        ? MediaQuery.sizeOf(context).width - 64
        : 460.0;
    return PopScope(
      canPop: !locked,
      // barrierDismissible stays false (outside taps never discard the form),
      // but Esc is an explicit keyboard cancel equivalent to the 取消 button.
      child: Focus(
        autofocus: true,
        // Keep the keyboard-cancel surface out of Tab traversal: Tab must move
        // between the real controls only.
        skipTraversal: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            if (!locked) Navigator.of(context).pop(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: AlertDialog(
          contentPadding: EdgeInsets.zero,
          titlePadding: EdgeInsets.zero,
          actionsPadding: EdgeInsets.zero,
          insetPadding: const EdgeInsets.all(PlannerSpace.xl),
          content: _DialogFrame(
            width: width,
            title: '永久注销账号？',
            subtitle: '永久删除账号与数据前，请先确认已导出需要保留的内容。',
            body: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '注销会永久删除云端账号、学习目标、标签与事项、计划、学习记录和 AI 访谈数据，'
                    '并清理本机此账号的数据及恢复备份。历史损坏文件若无法自动清理，会提示你手动处理。',
                    style: _bodyStyle(context),
                  ),
                  const SizedBox(height: PlannerSpace.md),
                  Text(
                    '此操作无法撤销。如需保留记录，请先导出本地数据。其他设备已下载的数据需在对应设备上清理。',
                    style: _bodyStyle(context),
                  ),
                  if (widget.onExport != null) ...[
                    const SizedBox(height: PlannerSpace.sm),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: locked ? null : _export,
                        icon: const Icon(Icons.download_outlined, size: 17),
                        label: Text(_exporting ? '正在导出…' : '导出本地数据'),
                      ),
                    ),
                  ],
                  if (_exportNotice != null) ...[
                    const SizedBox(height: PlannerSpace.sm),
                    PlannerNotice(
                      _exportNotice!,
                      tone: PlannerNoticeTone.success,
                    ),
                  ],
                  const SizedBox(height: PlannerSpace.lg),
                  TextFormField(
                    key: const ValueKey('delete-account-password'),
                    controller: _password,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    autofillHints: const [AutofillHints.password],
                    enabled: !locked,
                    decoration: const InputDecoration(labelText: '当前密码'),
                    validator: (value) =>
                        value == null || value.isEmpty ? '请输入当前密码以确认注销' : null,
                  ),
                  if (auth.deletionUncertain) ...[
                    const SizedBox(height: PlannerSpace.md),
                    const PlannerNotice(
                      '尚未确认服务器是否已完成注销。请保持联网，用相同密码重试以确认结果。',
                      tone: PlannerNoticeTone.warning,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: PlannerSpace.md),
                    Semantics(
                      liveRegion: true,
                      child: PlannerNotice(
                        _error!,
                        tone: PlannerNoticeTone.error,
                      ),
                    ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: PlannerSpace.lg),
                    const LinearProgressIndicator(semanticsLabel: '正在注销账号，请稍候'),
                    const SizedBox(height: PlannerSpace.sm),
                    Text('正在删除账号和数据，请稍候…', style: _bodyStyle(context)),
                  ],
                ],
              ),
            ),
            actions: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: locked
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                const SizedBox(width: PlannerSpace.sm),
                FilledButton(
                  key: const ValueKey('delete-account-confirm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.tokens.danger,
                    foregroundColor: context.tokens.inverseOn,
                  ),
                  onPressed: locked ? null : _delete,
                  child: Text(busy ? '正在注销…' : '永久注销'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 正文说明：13 / 1.6。
TextStyle _bodyStyle(BuildContext context) =>
    TextStyle(fontSize: 13, height: 1.6, color: context.tokens.muted);

/// 统一对话框外壳：20–24 内边距、表头 / 表尾发丝分隔线、按钮右对齐。
class _DialogFrame extends StatelessWidget {
  const _DialogFrame({
    required this.width,
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
  });

  final double width;
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hairline = plannerHairline(context);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlannerSpace.xl,
              20,
              PlannerSpace.xl,
              14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleLarge),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: context.tokens.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(height: hairline, color: context.tokens.border),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                PlannerSpace.xl,
                18,
                PlannerSpace.xl,
                18,
              ),
              child: body,
            ),
          ),
          Container(height: hairline, color: context.tokens.border),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PlannerSpace.xl,
              14,
              PlannerSpace.xl,
              16,
            ),
            child: actions,
          ),
        ],
      ),
    );
  }
}
