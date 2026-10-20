import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:planner_ui_vendor/planner_ui_vendor.dart';

import '../../core/sync/sync_state.dart';
import '../../core/motion.dart';
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

Color syncTone(SyncStatus status, PlannerTokens tokens) => switch (status) {
  SyncStatus.connected => tokens.success,
  SyncStatus.syncing || SyncStatus.connecting => tokens.accent,
  SyncStatus.offline || SyncStatus.conflict => tokens.warning,
  SyncStatus.error => tokens.danger,
  _ => tokens.subtle,
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
  ShellDestination(path: '/', label: '今日', icon: LucideIcons.circleCheck),
  ShellDestination(
    path: '/calendar',
    label: '日历',
    icon: LucideIcons.calendarDays,
  ),
  ShellDestination(
    path: '/adjust',
    label: '调整',
    icon: LucideIcons.slidersHorizontal,
  ),
  ShellDestination(path: '/settings', label: '设置', icon: LucideIcons.settings),
];

class AppShell extends StatefulWidget {
  const AppShell({required this.selectedPath, required this.child, super.key});

  final String selectedPath;
  final Widget child;

  /// Below this width the sidebar is replaced by the bottom navigation bar.
  static const sidebarBreakpoint = 900.0;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Desktop-only: the sidebar collapses from 240 px to an icon rail of 64 px.
  /// Mobile keeps its bottom navigation bar and never collapses.
  bool _sidebarCollapsed = false;

  void _go(BuildContext context, String path) {
    if (path != GoRouterState.of(context).uri.path) context.go(path);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= AppShell.sidebarBreakpoint;
    final selected = shellDestinations.indexWhere(
      (item) => item.path == widget.selectedPath,
    );
    final index = selected < 0 ? 0 : selected;
    if (desktop) {
      return Scaffold(
        body: Row(
          children: [
            // W7: the rail is long-lived; page rebuilds must not repaint it.
            RepaintBoundary(
              child: _Sidebar(
                selectedIndex: index,
                collapsed: _sidebarCollapsed,
                onToggleCollapsed: () =>
                    setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                onSelect: (path) => _go(context, path),
              ),
            ),
            Expanded(child: _Workspace(child: widget.child)),
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
                color: context.tokens.accent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                LucideIcons.bookOpenText,
                color: context.tokens.accentOn,
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
      body: _Workspace(child: widget.child),
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
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(bottom: BorderSide(color: context.tokens.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 7, 12, 7),
      child: Row(
        children: [
          StatusDot(color: context.tokens.success),
          const SizedBox(width: PlannerSpace.md),
          Text(
            relationLabel,
            style: TextStyle(
              fontSize: 11.5,
              color: context.tokens.muted,
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
              color: context.tokens.accent,
            ),
          ),
          const SizedBox(width: PlannerSpace.sm),
          PlannerIconAction(
            tooltip: '暂停当前计时',
            icon: LucideIcons.pause,
            tone: context.tokens.accent,
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

/// Moves keyboard focus between the sidebar destinations.
class _SidebarMoveIntent extends Intent {
  const _SidebarMoveIntent(this.delta);

  final int delta;
}

/// Moves keyboard focus to the first or last sidebar destination.
class _SidebarEdgeIntent extends Intent {
  const _SidebarEdgeIntent(this.atEnd);

  final bool atEnd;
}

class _Sidebar extends ConsumerStatefulWidget {
  const _Sidebar({
    required this.selectedIndex,
    required this.collapsed,
    required this.onToggleCollapsed,
    required this.onSelect,
  });

  final int selectedIndex;
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<String> onSelect;

  @override
  ConsumerState<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<_Sidebar> {
  late final List<FocusNode> _navFocusNodes;

  @override
  void initState() {
    super.initState();
    _navFocusNodes = [
      for (final destination in shellDestinations)
        FocusNode(debugLabel: 'sidebar-nav-${destination.path}'),
    ];
  }

  @override
  void dispose() {
    for (final node in _navFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _focusedNavIndex =>
      _navFocusNodes.indexWhere((node) => node.hasPrimaryFocus);

  void _focusNav(int index) {
    final target = index.clamp(0, _navFocusNodes.length - 1);
    _navFocusNodes[target].requestFocus();
  }

  void _moveFocus(int delta) {
    final current = _focusedNavIndex;
    if (current < 0) {
      _focusNav(delta > 0 ? 0 : _navFocusNodes.length - 1);
      return;
    }
    _focusNav(current + delta);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = ref.watch(plannerDataProvider);
    final profile = snapshot.data?.profile;
    final collapsed = widget.collapsed;
    final targetWidth = collapsed ? 64.0 : 240.0;
    return AnimatedContainer(
      key: const ValueKey('app-sidebar'),
      duration: PlannerMotion.duration(context),
      curve: PlannerMotion.curve(context),
      width: targetWidth,
      decoration: BoxDecoration(
        color: context.tokens.sidebar,
        border: Border(right: BorderSide(color: context.tokens.border)),
      ),
      child: SafeArea(
        // The outer width animates, while the content is laid out at the
        // destination width and clipped, so collapsing never squeezes rows.
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: targetWidth,
            maxWidth: targetWidth,
            child: SizedBox(
              width: targetWidth,
              child: Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.arrowDown):
                      _SidebarMoveIntent(1),
                  SingleActivator(LogicalKeyboardKey.arrowUp):
                      _SidebarMoveIntent(-1),
                  SingleActivator(LogicalKeyboardKey.home): _SidebarEdgeIntent(
                    false,
                  ),
                  SingleActivator(LogicalKeyboardKey.end): _SidebarEdgeIntent(
                    true,
                  ),
                },
                child: Actions(
                  actions: <Type, Action<Intent>>{
                    _SidebarMoveIntent: CallbackAction<_SidebarMoveIntent>(
                      onInvoke: (intent) {
                        _moveFocus(intent.delta);
                        return null;
                      },
                    ),
                    _SidebarEdgeIntent: CallbackAction<_SidebarEdgeIntent>(
                      onInvoke: (intent) {
                        _focusNav(intent.atEnd ? _navFocusNodes.length - 1 : 0);
                        return null;
                      },
                    ),
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Brand(
                        collapsed: collapsed,
                        onToggleCollapsed: widget.onToggleCollapsed,
                      ),
                      SizedBox(height: collapsed ? 6 : PlannerSpace.lg),
                      if (!collapsed)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                          child: Text(
                            '工作台',
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w500,
                              color: context.tokens.subtle,
                            ),
                          ),
                        ),
                      for (
                        var index = 0;
                        index < shellDestinations.length;
                        index++
                      )
                        _SidebarTile(
                          key: ValueKey(
                            'sidebar-nav-${shellDestinations[index].path}',
                          ),
                          destination: shellDestinations[index],
                          selected: index == widget.selectedIndex,
                          collapsed: collapsed,
                          focusNode: _navFocusNodes[index],
                          onTap: () {
                            _navFocusNodes[index].requestFocus();
                            widget.onSelect(shellDestinations[index].path);
                          },
                        ),
                      const Spacer(),
                      if (!collapsed && profile != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: context.tokens.surface,
                              border: Border.all(color: context.tokens.border),
                              borderRadius: BorderRadius.circular(
                                PlannerRadius.control,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    StatusDot(
                                      color: context.tokens.accent,
                                      size: 6,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '当前目标',
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.4,
                                        letterSpacing: 0.4,
                                        fontWeight: FontWeight.w500,
                                        color: context.tokens.subtle,
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
                                  style: TextStyle(
                                    color: context.tokens.muted,
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
                        padding: EdgeInsets.fromLTRB(
                          collapsed ? 8 : 12,
                          8,
                          collapsed ? 8 : 12,
                          12,
                        ),
                        child: _SyncTile(
                          status: snapshot.status,
                          pending: snapshot.pending,
                          collapsed: collapsed,
                          onTap: () => context.go('/settings'),
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

class _Brand extends StatelessWidget {
  const _Brand({required this.collapsed, required this.onToggleCollapsed});

  final bool collapsed;
  final VoidCallback onToggleCollapsed;

  @override
  Widget build(BuildContext context) {
    final logo = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: context.tokens.accent,
        borderRadius: BorderRadius.circular(9),
        boxShadow: [
          BoxShadow(
            color: context.tokens.accent.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Icon(
        LucideIcons.bookOpenText,
        color: context.tokens.accentOn,
        size: 18,
      ),
    );
    final toggle = IconButton(
      key: const ValueKey('sidebar-collapse-toggle'),
      tooltip: collapsed ? '展开侧栏' : '收起侧栏',
      onPressed: onToggleCollapsed,
      icon: Icon(
        collapsed ? LucideIcons.chevronRight : LucideIcons.chevronLeft,
        size: 16,
      ),
      style: IconButton.styleFrom(
        foregroundColor: context.tokens.subtle,
        minimumSize: const Size(26, 26),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
    );
    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 19, 8, 0),
        child: Column(children: [logo, const SizedBox(height: 4), toggle]),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 10, 0),
      child: Row(
        children: [
          logo,
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
                    color: context.tokens.text,
                  ),
                ),
                Text(
                  '学习执行台',
                  style: TextStyle(
                    color: context.tokens.subtle,
                    fontSize: 11,
                    height: 1.5,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          toggle,
        ],
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.focusNode,
    required this.onTap,
    super.key,
  });

  final ShellDestination destination;
  final bool selected;
  final bool collapsed;
  final FocusNode focusNode;
  final VoidCallback onTap;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hover = false;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focused = widget.focusNode.hasFocus;
    widget.focusNode.addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _SidebarTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      _focused = widget.focusNode.hasFocus;
      widget.focusNode.addListener(_handleFocusChange);
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_handleFocusChange);
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final collapsed = widget.collapsed;
    final content = Row(
      mainAxisAlignment: collapsed
          ? MainAxisAlignment.center
          : MainAxisAlignment.start,
      children: [
        if (!collapsed) ...[
          if (selected) ...[
            Container(
              width: 3,
              height: 14,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: context.tokens.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ] else
            const SizedBox(width: 11),
        ],
        Icon(
          widget.destination.icon,
          size: 17,
          color: selected ? context.tokens.accent : context.tokens.muted,
        ),
        if (!collapsed) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.destination.label,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? context.tokens.accent : context.tokens.text,
              ),
            ),
          ),
        ],
      ],
    );
    final tile = Material(
      color: selected
          ? context.tokens.selected
          : (_hover ? context.tokens.hover : Colors.transparent),
      borderRadius: BorderRadius.circular(PlannerRadius.small),
      child: InkWell(
        focusNode: widget.focusNode,
        canRequestFocus: true,
        onTap: widget.onTap,
        onHover: (hovering) => setState(() => _hover = hovering),
        borderRadius: BorderRadius.circular(PlannerRadius.small),
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        child: Container(
          height: 34,
          padding: EdgeInsets.symmetric(horizontal: collapsed ? 0 : 10),
          child: collapsed
              ? Tooltip(
                  message: widget.destination.label,
                  child: Center(child: content),
                )
              : content,
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: collapsed ? 8 : 10,
        vertical: 1,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(PlannerRadius.small),
          boxShadow: _focused
              ? [
                  BoxShadow(
                    color: context.tokens.focusRing,
                    blurRadius: 0,
                    spreadRadius: 2,
                  ),
                ]
              : const [],
        ),
        child: tile,
      ),
    );
  }
}

class _SyncTile extends StatefulWidget {
  const _SyncTile({
    required this.status,
    required this.pending,
    required this.collapsed,
    required this.onTap,
  });

  final SyncStatus status;
  final bool pending;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  State<_SyncTile> createState() => _SyncTileState();
}

class _SyncTileState extends State<_SyncTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final label = syncLabels[widget.status] ?? '等待同步';
    final icon = Icon(
      LucideIcons.cloud,
      size: widget.collapsed ? 17 : 15,
      color: syncTone(widget.status, context.tokens),
    );
    final Widget content = widget.collapsed
        ? Tooltip(
            message: widget.pending ? '$label · 有待同步修改' : label,
            child: SizedBox(
              height: 34,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  icon,
                  if (widget.pending)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: StatusDot(color: context.tokens.warning, size: 5),
                    ),
                ],
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                icon,
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: context.tokens.muted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.pending)
                  Tooltip(
                    message: '有待同步修改',
                    child: Icon(
                      LucideIcons.cloudOff,
                      size: 14,
                      color: context.tokens.warning,
                    ),
                  ),
              ],
            ),
          );
    return Material(
      color: _hover ? context.tokens.hover : Colors.transparent,
      borderRadius: BorderRadius.circular(PlannerRadius.small),
      child: InkWell(
        onTap: widget.onTap,
        onHover: (hovering) => setState(() => _hover = hovering),
        borderRadius: BorderRadius.circular(PlannerRadius.small),
        hoverColor: Colors.transparent,
        child: content,
      ),
    );
  }
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
          snapshot.pending ? LucideIcons.cloudOff : LucideIcons.cloud,
          size: 16,
          color: syncTone(snapshot.status, context.tokens),
        ),
        label: Text(
          syncLabels[snapshot.status] ?? '等待同步',
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
