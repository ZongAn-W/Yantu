import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/sync/sync_state.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../planner/application/planner_session.dart';
import '../planner/application/study_timer.dart';
import '../planner/domain/planner_format.dart';
import '../planner/domain/study_day.dart' show timeLogRelationLabels;

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
  _ => PlannerColors.subtle,
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
  ShellDestination(path: '/adjust', label: '调整', icon: Icons.tune_outlined),
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
    if (path != GoRouterState.of(context).uri.path) context.go(path);
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
            Expanded(child: _Workspace(child: child)),
          ],
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: PlannerColors.blue,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.auto_stories_outlined,
                color: Colors.white,
                size: 13,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              shellDestinations[index].label,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ],
        ),
        actions: const [_SyncAction(), SizedBox(width: 6)],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
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
      const _ActiveTimerStrip(),
      Expanded(child: child),
    ],
  );
}

class _ActiveTimerStrip extends ConsumerWidget {
  const _ActiveTimerStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timer = ref.watch(studyTimerProvider);
    final taskId = timer.activeTaskId;
    if (taskId == null) return const SizedBox.shrink();
    final data = ref.watch(plannerDataProvider).data;
    final task = data?.tasks.where((task) => task.id == taskId).firstOrNull;
    final relation = timer.activeRelation;
    final relationLabel = relation == null
        ? ''
        : '${timeLogRelationLabels[relation] ?? ''} · ';
    final date = shanghaiToday();
    final elapsed = timer.elapsedFor(taskId, date);
    final clock =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:'
        '${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    return Container(
      decoration: const BoxDecoration(
        color: PlannerColors.surface,
        border: Border(bottom: BorderSide(color: PlannerColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 7, 12, 7),
      child: Row(
        children: [
          const StatusDot(color: PlannerColors.green),
          const SizedBox(width: PlannerSpace.md),
          Text(
            relationLabel,
            style: const TextStyle(
              fontSize: 11.5,
              color: PlannerColors.muted,
              fontWeight: FontWeight.w500,
            ),
          ),
          Expanded(
            child: Text(
              task?.title ?? '正在计时',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
          ),
          Text(
            clock,
            style: tabularFigures.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: PlannerColors.blue,
            ),
          ),
          const SizedBox(width: PlannerSpace.sm),
          PlannerIconAction(
            tooltip: '暂停当前计时',
            icon: Icons.pause,
            tone: PlannerColors.blue,
            onPressed: timer.busy
                ? null
                : () async {
                    try {
                      await timer.pause();
                    } catch (_) {
                      if (context.mounted) {
                        showPlannerMessage(
                          context,
                          timer.error ?? '计时保存失败',
                          tone: PlannerNoticeTone.error,
                        );
                      }
                    }
                  },
          ),
        ],
      ),
    );
  }
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
    final compact = MediaQuery.sizeOf(context).width < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 24, 12, compact ? 16 : 24, 0),
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
    return Container(
      width: 240,
      decoration: const BoxDecoration(
        color: PlannerColors.sidebar,
        border: Border(right: BorderSide(color: PlannerColors.border)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Brand(),
            const SizedBox(height: PlannerSpace.lg),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Text(
                '工作台',
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w500,
                  color: PlannerColors.subtle,
                ),
              ),
            ),
            for (var index = 0; index < shellDestinations.length; index++)
              _SidebarTile(
                destination: shellDestinations[index],
                selected: index == selectedIndex,
                onTap: () => onSelect(shellDestinations[index].path),
              ),
            const Spacer(),
            if (profile != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: PlannerColors.surface,
                    border: Border.all(color: PlannerColors.border),
                    borderRadius: BorderRadius.circular(PlannerRadius.control),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const StatusDot(color: PlannerColors.blue, size: 6),
                          const SizedBox(width: 6),
                          Text(
                            '当前目标',
                            style: TextStyle(
                              fontSize: 10.5,
                              height: 1.4,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w500,
                              color: PlannerColors.subtle,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        goalHeadline(profile),
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        goalStatusLine(profile, shanghaiToday()),
                        style: const TextStyle(
                          color: PlannerColors.muted,
                          fontSize: 11.5,
                          height: 1.45,
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
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
    child: Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: PlannerColors.blue,
            borderRadius: BorderRadius.circular(9),
            boxShadow: const [
              BoxShadow(
                color: Color(0x26305d8a),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.auto_stories_outlined,
            color: Colors.white,
            size: 18,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '不白学',
                style: TextStyle(
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: PlannerColors.text,
                ),
              ),
              Text(
                '学习执行台',
                style: TextStyle(
                  color: PlannerColors.subtle,
                  fontSize: 10.5,
                  height: 1.5,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: Material(
          color: selected
              ? PlannerColors.selected
              : (_hover ? PlannerColors.hover : Colors.transparent),
          borderRadius: BorderRadius.circular(PlannerRadius.small),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(PlannerRadius.small),
            hoverColor: Colors.transparent,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  if (selected) ...[
                    Container(
                      width: 3,
                      height: 14,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: PlannerColors.blue,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ] else
                    const SizedBox(width: 11),
                  Icon(
                    widget.destination.icon,
                    size: 17,
                    color: selected ? PlannerColors.blue : PlannerColors.muted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.destination.label,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.3,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: selected
                            ? PlannerColors.blue
                            : PlannerColors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SyncTile extends StatefulWidget {
  const _SyncTile({
    required this.status,
    required this.pending,
    required this.onTap,
  });

  final SyncStatus status;
  final bool pending;
  final VoidCallback onTap;

  @override
  State<_SyncTile> createState() => _SyncTileState();
}

class _SyncTileState extends State<_SyncTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: Material(
      color: _hover ? PlannerColors.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(PlannerRadius.small),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(PlannerRadius.small),
        hoverColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 15,
                color: syncTone(widget.status),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  syncLabels[widget.status] ?? '等待同步',
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: PlannerColors.muted,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.pending)
                const Tooltip(
                  message: '有待同步修改',
                  child: Icon(
                    Icons.sync_problem,
                    size: 14,
                    color: PlannerColors.orange,
                  ),
                ),
            ],
          ),
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
