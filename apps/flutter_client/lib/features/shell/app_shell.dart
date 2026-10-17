import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sync/sync_state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../auth/application/auth_controller.dart';
import '../planner/application/planner_session.dart';
import '../planner/domain/planner_format.dart';

const syncLabels = <SyncStatus, String>{
  SyncStatus.demo: '本地计划',
  SyncStatus.loginRequired: '请登录',
  SyncStatus.connecting: '正在连接',
  SyncStatus.syncing: '正在同步',
  SyncStatus.connected: '云端已同步',
  SyncStatus.offline: '离线 · 等待同步',
  SyncStatus.conflict: '需要处理冲突',
  SyncStatus.error: '同步失败',
};

Color syncTone(SyncStatus status) => switch (status) {
  SyncStatus.connected => PlannerColors.green,
  SyncStatus.syncing || SyncStatus.connecting => PlannerColors.blue,
  SyncStatus.offline || SyncStatus.conflict => PlannerColors.orange,
  SyncStatus.error => PlannerColors.danger,
  _ => PlannerColors.muted,
};

class ShellDestination {
  const ShellDestination({
    required this.path,
    required this.label,
    required this.icon,
  });

  final String path;
  final String label;
  final IconData icon;
}

/// Mobile keeps a bottom bar; Web and Windows use the left sidebar, matching the
/// Web client where the same routes are reachable on every breakpoint.
const shellDestinations = <ShellDestination>[
  ShellDestination(path: '/', label: '今日', icon: Icons.check_circle_outline),
  ShellDestination(
    path: '/calendar',
    label: '日历',
    icon: Icons.calendar_today_outlined,
  ),
  ShellDestination(path: '/tasks', label: '事项', icon: Icons.list_alt_outlined),
  ShellDestination(
    path: '/progress',
    label: '进度',
    icon: Icons.bar_chart_outlined,
  ),
  ShellDestination(path: '/interview', label: '访谈', icon: Icons.forum_outlined),
  ShellDestination(
    path: '/settings',
    label: '设置',
    icon: Icons.settings_outlined,
  ),
];

class AppShell extends StatelessWidget {
  const AppShell({required this.selectedPath, required this.child, super.key});

  final String selectedPath;
  final Widget child;

  /// Below this width the sidebar is replaced by the bottom navigation bar.
  static const sidebarBreakpoint = 900.0;

  void _go(BuildContext context, String path) {
    if (path != selectedPath) context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= sidebarBreakpoint;
    final selected = shellDestinations.indexWhere(
      (item) => item.path == selectedPath,
    );
    final index = selected < 0 ? 0 : selected;
    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            _Sidebar(
              selectedIndex: index,
              onSelect: (path) => _go(context, path),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _Workspace(child: child)),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          shellDestinations[index].label,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: const [_SyncAction(), _AccountAction()],
      ),
      body: _Workspace(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) =>
            _go(context, shellDestinations[value].path),
        destinations: [
          for (final item in shellDestinations)
            NavigationDestination(
              icon: Icon(item.icon),
              label: item.label,
              tooltip: item.label,
            ),
        ],
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _StatusBanners(),
      Expanded(child: child),
    ],
  );
}

/// Surfaces storage and sync problems above the page, mirroring the Web notice area.
class _StatusBanners extends ConsumerWidget {
  const _StatusBanners();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(plannerDataProvider);
    final Widget? banner;
    if (snapshot.blocked) {
      banner = const PlannerNotice(
        '本地数据读取失败，已停止编辑和同步。请在设置页重新读取，或从 JSON 备份恢复。',
        tone: PlannerNoticeTone.error,
      );
    } else if (snapshot.status == SyncStatus.conflict) {
      banner = PlannerNotice(
        '检测到并发修改：${snapshot.message}。请在设置页选择冲突处理方式。',
        tone: PlannerNoticeTone.warning,
      );
    } else if (snapshot.status == SyncStatus.offline) {
      banner = const PlannerNotice(
        '当前离线：修改会先保存到本机，恢复网络后自动同步。',
        tone: PlannerNoticeTone.warning,
      );
    } else {
      banner = null;
    }
    if (banner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: banner,
    );
  }
}

class _Sidebar extends ConsumerWidget {
  const _Sidebar({required this.selectedIndex, required this.onSelect});

  final int selectedIndex;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(plannerDataProvider);
    final profile = snapshot.data?.profile;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 240,
      child: ColoredBox(
        color: PlannerColors.surface,
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: PlannerColors.blue,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.school_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('不白学', style: text.titleMedium),
                          const Text(
                            '学习执行台',
                            style: TextStyle(
                              color: PlannerColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    for (
                      var index = 0;
                      index < shellDestinations.length;
                      index++
                    )
                      _SidebarTile(
                        destination: shellDestinations[index],
                        selected: index == selectedIndex,
                        onTap: () => onSelect(shellDestinations[index].path),
                      ),
                  ],
                ),
              ),
              if (profile != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: PlannerColors.background,
                      border: Border.all(color: PlannerColors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          goalHeadline(profile),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          goalStatusLine(profile, shanghaiToday()),
                          style: const TextStyle(
                            color: PlannerColors.muted,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: _SyncTile(
                  status: snapshot.status,
                  pending: snapshot.pending,
                  onTap: () => context.go('/settings'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Material(
      color: selected ? const Color(0x14275e91) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(
                destination.icon,
                size: 18,
                color: selected ? PlannerColors.blue : PlannerColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destination.label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? PlannerColors.blue : PlannerColors.text,
                  ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: PlannerColors.blue,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SyncTile extends StatelessWidget {
  const _SyncTile({
    required this.status,
    required this.pending,
    required this.onTap,
  });

  final SyncStatus status;
  final bool pending;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: PlannerColors.background,
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.cloud_outlined, size: 16, color: syncTone(status)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                syncLabels[status] ?? '等待同步',
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (pending)
              const Tooltip(
                message: '有待同步修改',
                child: Icon(Icons.sync_problem, size: 15),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Compact sync indicator for the app bar on narrow screens.
class _SyncAction extends ConsumerWidget {
  const _SyncAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(plannerDataProvider);
    return Tooltip(
      message: snapshot.message.isEmpty
          ? (syncLabels[snapshot.status] ?? '等待同步')
          : snapshot.message,
      child: TextButton.icon(
        onPressed: () => context.go('/settings'),
        icon: Icon(
          snapshot.pending ? Icons.sync_problem : Icons.cloud_outlined,
          size: 16,
          color: syncTone(snapshot.status),
        ),
        label: Text(
          syncLabels[snapshot.status] ?? '等待同步',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}

class _AccountAction extends ConsumerWidget {
  const _AccountAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final initial = (user?.username.isNotEmpty ?? false)
        ? user!.username.characters.first
        : 'U';
    return IconButton(
      tooltip: '账号与同步',
      icon: CircleAvatar(
        radius: 14,
        backgroundColor: PlannerColors.blue,
        child: Text(
          initial,
          style: const TextStyle(color: Colors.white, fontSize: 13),
        ),
      ),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => const AccountDialog(),
      ),
    );
  }
}

/// Account and sync dialog reachable from every workbench route.
class AccountDialog extends ConsumerWidget {
  const AccountDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final snapshot = ref.watch(plannerDataProvider);
    return AlertDialog(
      title: const Text('账号与同步'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              auth.user?.username ?? auth.user?.email ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text('课程、事项、每日计划和实际学习记录保存在服务器，本机保留离线副本。'),
            const SizedBox(height: 16),
            PlannerStat(
              label: '同步状态',
              value: syncLabels[snapshot.status] ?? '等待同步',
              tone: syncTone(snapshot.status),
            ),
            PlannerStat(label: '云端版本', value: '${snapshot.revision}'),
            PlannerStat(label: '待同步修改', value: snapshot.pending ? '有' : '无'),
            const SizedBox(height: 8),
            if (snapshot.message.isNotEmpty)
              PlannerNotice(
                snapshot.message,
                tone: snapshot.status == SyncStatus.error
                    ? PlannerNoticeTone.error
                    : PlannerNoticeTone.info,
              ),
            if (auth.error != null) ...[
              const SizedBox(height: 8),
              PlannerNotice(auth.error!, tone: PlannerNoticeTone.error),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: auth.loading
              ? null
              : () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(plannerSessionProvider).sync();
                  } catch (error) {
                    messenger.showSnackBar(
                      SnackBar(content: Text('同步失败：$error')),
                    );
                  }
                },
          child: const Text('立即同步'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: auth.loading
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await ref.read(authControllerProvider.notifier).signOut();
                  if (navigator.mounted) navigator.pop();
                },
          icon: const Icon(Icons.logout, size: 18),
          style: FilledButton.styleFrom(backgroundColor: PlannerColors.danger),
          label: const Text('退出登录'),
        ),
      ],
    );
  }
}
