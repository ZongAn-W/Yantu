import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets.dart';
import '../../../core/sync/sync_state.dart';
import '../application/planner_session.dart';

/// Renders the shared loading / failure / blocked states around a page body.
///
/// Every workbench route uses this so asynchronous loading, success, failure and
/// retry stay consistent, and no page silently shows empty data.
class PlannerPageState extends ConsumerWidget {
  const PlannerPageState({required this.builder, super.key});

  final Widget Function(BuildContext context, PlannerSnapshot snapshot) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(plannerDataProvider);
    if (!snapshot.ready) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: const Text('正在读取本机计划…'),
              ),
            ],
          ),
        ),
      );
    }
    if (snapshot.blocked) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlannerNotice(
                  snapshot.message.isEmpty
                      ? '本地数据读取失败，已停止编辑和同步。'
                      : snapshot.message,
                  tone: PlannerNoticeTone.error,
                ),
                const SizedBox(height: 12),
                const Text('请重新读取数据，或从 JSON 备份恢复；两种操作都在设置页。'),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () =>
                      ref.read(plannerSessionProvider).reload(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重新读取本机数据'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (snapshot.data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const PlannerEmpty(
                  icon: Icons.cloud_off_outlined,
                  message: '还没有读取到学习计划。',
                  hint: '登录后会从服务器载入；离线时本机缓存也可继续使用。',
                ),
                const SizedBox(height: 8),
                PlannerNotice(
                  snapshot.message,
                  tone: snapshot.status == SyncStatus.error
                      ? PlannerNoticeTone.error
                      : PlannerNoticeTone.info,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: snapshot.busy
                      ? null
                      : () => ref.read(plannerSessionProvider).sync(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试加载'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return builder(context, snapshot);
  }
}
