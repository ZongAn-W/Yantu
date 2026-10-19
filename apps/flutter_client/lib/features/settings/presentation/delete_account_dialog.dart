import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../auth/application/auth_controller.dart';

/// Password confirmation stays open until deletion has a definite outcome.
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
    return PopScope(
      canPop: !locked,
      child: AlertDialog(
        title: const Text('永久注销账号？'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '注销会永久删除云端账号、学习目标、课程与事项、计划、学习记录和 AI 访谈数据，并清理本机此账号的数据及恢复备份。历史损坏文件若无法自动清理，会提示你手动处理。',
                  ),
                  const SizedBox(height: 12),
                  const Text('此操作无法撤销。如需保留记录，请先导出本地数据。其他设备已下载的数据需在对应设备上清理。'),
                  if (widget.onExport != null) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: locked ? null : _export,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(_exporting ? '正在导出…' : '导出本地数据'),
                      ),
                    ),
                  ],
                  if (_exportNotice != null) ...[
                    const SizedBox(height: 8),
                    PlannerNotice(
                      _exportNotice!,
                      tone: PlannerNoticeTone.success,
                    ),
                  ],
                  const SizedBox(height: 16),
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
                    const SizedBox(height: 12),
                    const PlannerNotice(
                      '尚未确认服务器是否已完成注销。请保持联网，用相同密码重试以确认结果。',
                      tone: PlannerNoticeTone.warning,
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Semantics(
                      liveRegion: true,
                      child: PlannerNotice(
                        _error!,
                        tone: PlannerNoticeTone.error,
                      ),
                    ),
                  ],
                  if (busy) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(semanticsLabel: '正在注销账号，请稍候'),
                    const SizedBox(height: 8),
                    const Text('正在删除账号和数据，请稍候…'),
                  ],
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: locked ? null : () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('delete-account-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: PlannerColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: locked ? null : _delete,
            child: Text(busy ? '正在注销…' : '永久注销'),
          ),
        ],
      ),
    );
  }
}
