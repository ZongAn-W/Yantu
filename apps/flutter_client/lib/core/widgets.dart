import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planner_ui_vendor/planner_ui_vendor.dart';

import '../shared/models/task_lifecycle.dart';
import 'motion.dart';
import 'theme.dart';

/// Page scaffold used by every workbench route: one heading row plus a scrollable
/// body, centred at [plannerPageMaxWidth] so desktop widths never stretch rows.
class PlannerPage extends StatelessWidget {
  const PlannerPage({
    this.title = '',
    this.subtitle = '',
    this.eyebrow = '',
    required this.children,
    this.actions = const [],
    this.scrollable = true,
    this.maxWidth = plannerPageMaxWidth,
    super.key,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final List<Widget> children;
  final List<Widget> actions;
  final bool scrollable;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title.isNotEmpty ||
            subtitle.isNotEmpty ||
            eyebrow.isNotEmpty ||
            actions.isNotEmpty) ...[
          PageHeader(
            title: title,
            subtitle: subtitle,
            eyebrow: eyebrow,
            actions: actions,
          ),
          const SizedBox(height: PlannerSpace.xl),
        ],
        ...children,
      ],
    );
    final compact = MediaQuery.sizeOf(context).width < 700;
    final padding = EdgeInsets.fromLTRB(
      compact ? 16 : 28,
      compact ? 16 : 24,
      compact ? 16 : 28,
      40,
    );
    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: scrollable
              ? ListView(padding: padding, children: [content])
              : SingleChildScrollView(padding: padding, child: content),
        ),
      ),
    );
  }
}

/// Page heading: optional eyebrow label, 22 px title and 13 px subtitle.
class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    this.subtitle = '',
    this.eyebrow = '',
    this.actions = const [],
    super.key,
  });

  final String title;
  final String subtitle;
  final String eyebrow;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: PlannerSpace.lg,
      runSpacing: PlannerSpace.md,
      children: [
        if (title.isNotEmpty || subtitle.isNotEmpty || eyebrow.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 200, maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (eyebrow.isNotEmpty) ...[
                  Text(
                    eyebrow,
                    style: text.labelMedium?.copyWith(
                      color: context.tokens.subtle,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
                if (title.isNotEmpty) Text(title, style: text.headlineSmall),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: text.bodyMedium?.copyWith(
                      color: context.tokens.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (actions.isNotEmpty)
          Wrap(
            spacing: PlannerSpace.sm,
            runSpacing: PlannerSpace.sm,
            children: actions,
          ),
      ],
    );
  }
}

/// One white panel (`一层面板仅分割不同功能区域`): 12 px radius, hairline border,
/// 1 px micro shadow. Sections inside a panel use dividers, not nested cards.
class PlannerPanel extends StatelessWidget {
  const PlannerPanel({
    required this.child,
    this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.padding = const EdgeInsets.all(PlannerSpace.lg),
    super.key,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hasHeader = title != null || leading != null || trailing != null;
    // W7: a panel is a long-lived section; page rebuilds must not repaint it.
    return RepaintBoundary(
      child: PlannerSurface(
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (hasHeader) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: PlannerSpace.sm),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (title != null)
                            Text(title!, style: text.titleMedium),
                          if (subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitle!,
                              style: text.bodySmall?.copyWith(
                                color: context.tokens.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: PlannerSpace.md),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

/// White paper surface with the panel hairline and micro shadow.
///
/// Use this for the rare panel that is not a [PlannerPanel] (for example the
/// flat task list card) instead of a bare [Card], so every panel in a page
/// shares the same edge in both themes.
class PlannerSurface extends StatelessWidget {
  const PlannerSurface({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      borderRadius: PlannerRadius.cardRadius,
      boxShadow: plannerPanelShadow(context),
    ),
    child: Card(child: child),
  );
}

/// Section heading inside a page (e.g. 今日学习 / 全部事项).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.count,
    this.trailing,
    this.centered = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final int? count;
  final Widget? trailing;

  /// Centers the title/count group inside the full width (used by the merged
  /// 「今日安排」 and 「全部事项」 blocks).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final content = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: centered ? WrapAlignment.center : WrapAlignment.start,
      spacing: PlannerSpace.sm,
      runSpacing: 2,
      children: [
        Semantics(header: true, child: Text(title, style: text.titleMedium)),
        if (count != null && count! > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: context.tokens.surfaceMuted,
              borderRadius: BorderRadius.circular(PlannerRadius.xs),
            ),
            child: Text(
              '$count',
              style: text.labelSmall?.copyWith(
                color: context.tokens.muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        if (subtitle != null)
          Text(
            subtitle!,
            style: text.bodySmall?.copyWith(color: context.tokens.muted),
          ),
      ],
    );
    if (centered) {
      // True page centering even when the block keeps right-aligned actions.
      return Stack(
        alignment: Alignment.center,
        children: [
          Center(child: content),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing!),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: content),
        if (trailing != null) ...[
          const SizedBox(width: PlannerSpace.md),
          trailing!,
        ],
      ],
    );
  }
}

/// Semantic tone for a task time-progress pill.
///
/// Completed → success, already started → accent, not started/archived → muted.
/// The pill then carries state colour without adding a second accent hue.
Color taskProgressTone(TaskTimeProgress progress, PlannerTokens tokens) {
  if (progress.archived) return tokens.muted;
  if (progress.completed) return tokens.success;
  if (progress.started) return tokens.accent;
  return tokens.muted;
}

/// Inline message used for sync/offline/error states.
class PlannerNotice extends StatelessWidget {
  const PlannerNotice(
    this.message, {
    this.tone = PlannerNoticeTone.info,
    super.key,
  });

  final String message;
  final PlannerNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, border, foreground, dot) = switch (tone) {
      PlannerNoticeTone.info => (
        context.tokens.surface,
        context.tokens.border,
        context.tokens.text,
        context.tokens.subtle,
      ),
      PlannerNoticeTone.success => (
        context.tokens.noticeSuccessBackground,
        context.tokens.noticeSuccessBorder,
        context.tokens.noticeSuccessInk,
        context.tokens.success,
      ),
      PlannerNoticeTone.warning => (
        context.tokens.noticeWarningBackground,
        context.tokens.noticeWarningBorder,
        context.tokens.noticeWarningInk,
        context.tokens.warning,
      ),
      PlannerNoticeTone.error => (
        context.tokens.noticeErrorBackground,
        context.tokens.noticeErrorBorder,
        context.tokens.noticeErrorInk,
        context.tokens.danger,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: PlannerSpace.md,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(PlannerRadius.control),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: StatusDot(color: dot, size: 6),
            ),
            const SizedBox(width: PlannerSpace.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: foreground, fontSize: 13, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum PlannerNoticeTone { info, success, warning, error }

/// Thin planned/actual progress track used by the dashboard and calendar rows.
class TimeProgressTrack extends StatelessWidget {
  const TimeProgressTrack({
    required this.planned,
    required this.actual,
    required this.color,
    this.semanticsLabel,
    this.height = 6,
    super.key,
  });

  final int planned;
  final int actual;
  final Color color;
  final String? semanticsLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ratio = planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: planned <= 0 ? null : '${(ratio * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: height,
          backgroundColor: context.tokens.surfaceMuted,
          valueColor: AlwaysStoppedAnimation(color),
        ),
      ),
    );
  }
}

/// Key/value row used in summary blocks.
class PlannerStat extends StatelessWidget {
  const PlannerStat({
    required this.label,
    required this.value,
    this.tone,
    this.valueKey,
    super.key,
  });

  final String label;
  final String value;
  final Color? tone;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: context.tokens.muted, fontSize: 13),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: tabularFigures.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: tone ?? context.tokens.text,
            ),
          ),
        ],
      ),
    );
  }
}

/// Metric tile used in overview strips: label, big tabular value and a note.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    this.note,
    this.tone,
    this.valueKey,
    super.key,
  });

  final String label;
  final String value;
  final String? note;
  final Color? tone;
  final Key? valueKey;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: text.labelMedium),
        const SizedBox(height: 3),
        Text(
          value,
          key: valueKey,
          style: tabularFigures.copyWith(
            fontSize: 21,
            height: 1.2,
            fontWeight: FontWeight.w600,
            color: tone ?? context.tokens.text,
            letterSpacing: -0.2,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: 3),
          Text(note!, style: text.bodySmall?.copyWith(fontSize: 12)),
        ],
      ],
    );
  }
}

/// Centred empty state with an optional primary action.
class PlannerEmpty extends StatelessWidget {
  const PlannerEmpty({
    required this.message,
    this.icon = LucideIcons.inbox,
    this.hint,
    this.action,
    super.key,
  });

  final String message;
  final IconData icon;
  final String? hint;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PlannerSpace.lg,
        vertical: PlannerSpace.xl,
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: context.tokens.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: context.tokens.muted),
          ),
          const SizedBox(height: PlannerSpace.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(color: context.tokens.text),
          ),
          if (hint != null) ...[
            const SizedBox(height: PlannerSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: context.tokens.muted),
              ),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: PlannerSpace.md),
            action!,
          ],
        ],
      ),
    );
  }
}

/// Small token-coloured spinner used inside buttons and inline busy states.
///
/// Replaces the raw Material indicator so every waiting affordance shares the
/// same accent colour, track colour and stroke weight in both themes.
class PlannerSpinner extends StatelessWidget {
  const PlannerSpinner({this.size = 15, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CircularProgressIndicator(
      strokeWidth: 2,
      color: context.tokens.accent,
      backgroundColor: context.tokens.border,
    ),
  );
}

/// Shared page-level loading state: one spinner plus a live-region label.
///
/// Used by the router bootstrap and [PlannerPageState] so first paint, local
/// database reads and profile reads look identical instead of falling back to
/// the default centered Material spinner.
class PlannerLoading extends StatelessWidget {
  const PlannerLoading({this.message = '正在读取本机计划…', super.key});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(PlannerSpace.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PlannerSpinner(size: 20),
          const SizedBox(height: PlannerSpace.md),
          Semantics(
            liveRegion: true,
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: context.tokens.muted,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Small tinted tag. Used for labels, filters and subject marks.
///
/// Only interactive filter chips pass a [focusNode]: that makes the chip one
/// keyboard stop with a 2 px [context.tokens.focusRing] ring, while purely
/// display tags (no [onTap]) never enter the tab order at all.
class PlannerTag extends StatefulWidget {
  const PlannerTag({
    required this.label,
    this.color,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dense = false,
    this.focusNode,
    super.key,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool dense;
  final FocusNode? focusNode;

  @override
  State<PlannerTag> createState() => _PlannerTagState();
}

class _PlannerTagState extends State<PlannerTag> {
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final tone = widget.color ?? tokens.muted;
    final explicitTone = widget.color;
    // Mist Ink 2.0: 12% fill + 30% border keeps tags readable on white, while the
    // label is mixed 70/30 with body ink so 11–11.5 px Chinese still clears 4.5:1.
    final foreground = widget.selected
        ? tokens.accent
        : (explicitTone == null
              ? tone
              : Color.lerp(explicitTone, tokens.text, 0.30)!);
    final background = widget.selected
        ? tokens.accentSoft
        : Color.alphaBlend(tone.withValues(alpha: 0.12), tokens.surface);
    final borderColor = widget.selected
        ? tokens.accentBorder
        : (explicitTone == null ? tokens.border : tone.withValues(alpha: 0.30));
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: widget.dense ? 6 : 7,
        vertical: widget.dense ? 1.5 : 2.5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.dense ? 11 : 11.5,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: foreground,
            ),
          ),
        ],
      ),
    );
    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PlannerRadius.xs),
        border: Border.all(color: borderColor),
      ),
      child: content,
    );
    final onTap = widget.onTap;
    if (onTap == null) return decorated;
    final focusNode = widget.focusNode;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          focusNode: focusNode,
          focusColor: focusNode == null ? null : Colors.transparent,
          onTap: () {
            focusNode?.requestFocus();
            onTap();
          },
          borderRadius: BorderRadius.circular(PlannerRadius.xs),
          child: _focusRing(decorated),
        ),
      ),
    );
  }

  /// 2 px ring painted inside the chip while it owns the keyboard focus. Tags
  /// without a [FocusNode] keep their previous behaviour and never show a ring.
  Widget _focusRing(Widget child) {
    final node = widget.focusNode;
    if (node == null) return child;
    return ListenableBuilder(
      listenable: node,
      child: child,
      builder: (context, child) {
        if (!node.hasFocus) return child!;
        return DecoratedBox(
          key: const Key('planner-tag-focus-ring'),
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(PlannerRadius.xs),
            border: Border.all(color: context.tokens.focusRing, width: 2),
          ),
          child: child,
        );
      },
    );
  }
}

/// A subject/status dot; replaces saturated full-width colour fills.
class StatusDot extends StatelessWidget {
  const StatusDot({required this.color, this.size = 7, super.key});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: color.withValues(alpha: 0.22),
          blurRadius: 0,
          spreadRadius: 2.5,
        ),
      ],
    ),
  );
}

/// Custom segmented control: 30 px tall, animated pill, no Material chrome.
///
/// The whole group is a single tab stop. While it owns the keyboard focus,
/// ArrowLeft/ArrowRight move the selection by one item (clamped, no wrap),
/// Home/End jump to the first/last item and Space/Enter keep the current value
/// (already committed, like a native segmented control). The 2 px focus ring is
/// painted only while focused, so resting visuals and sizes do not change.
class PlannerSegmented<T> extends StatefulWidget {
  const PlannerSegmented({
    required this.value,
    required this.items,
    required this.onChanged,
    this.height = 30,
    this.itemKey,
    super.key,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final double height;
  final Key Function(T value, int index)? itemKey;

  @override
  State<PlannerSegmented<T>> createState() => _PlannerSegmentedState<T>();
}

class _PlannerSegmentedState<T> extends State<PlannerSegmented<T>> {
  final _focusNode = FocusNode(debugLabel: 'planner-segmented');
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  int get _selectedIndex {
    final index = widget.items.indexWhere((item) => item.$1 == widget.value);
    return index < 0 ? 0 : index;
  }

  void _select(int index) {
    if (index < 0 || index >= widget.items.length || index == _selectedIndex) {
      return;
    }
    widget.onChanged(widget.items[index].$1);
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _select(_selectedIndex - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      _select(_selectedIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _select(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _select(widget.items.length - 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      // The current item is already committed; confirming never changes it.
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = _selectedIndex;
    final count = widget.items.length;
    return Focus(
      focusNode: _focusNode,
      onFocusChange: (focused) {
        if (focused != _focused) setState(() => _focused = focused);
      },
      onKeyEvent: _handleKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : 240.0;
          final segmentWidth = (width - 4) / count;
          return Stack(
            children: [
              Container(
                height: widget.height,
                width: constraints.maxWidth.isFinite ? null : count * 64.0,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: context.tokens.surfaceInset,
                  borderRadius: BorderRadius.circular(PlannerRadius.small),
                  border: Border.all(color: context.tokens.border),
                ),
                child: Stack(
                  children: [
                    AnimatedAlign(
                      duration: PlannerMotion.duration(
                        context,
                        preferred: PlannerDurations.fast,
                      ),
                      curve: PlannerMotion.curve(context),
                      alignment: Alignment(
                        count == 1 ? 0 : -1 + 2 * selectedIndex / (count - 1),
                        0,
                      ),
                      child: Container(
                        width: segmentWidth,
                        height: widget.height - 4,
                        decoration: BoxDecoration(
                          color: context.tokens.surface,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: context.tokens.borderStrong,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: context.tokens.floatingShadow,
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < count; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: i == selectedIndex,
                              child: GestureDetector(
                                key: widget.itemKey?.call(
                                  widget.items[i].$1,
                                  i,
                                ),
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  _focusNode.requestFocus();
                                  widget.onChanged(widget.items[i].$1);
                                },
                                child: Center(
                                  child: Text(
                                    widget.items[i].$2,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.4,
                                      fontWeight: i == selectedIndex
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: i == selectedIndex
                                          ? context.tokens.text
                                          : context.tokens.muted,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_focused)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      key: const Key('planner-segmented-focus-ring'),
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(
                          PlannerRadius.small,
                        ),
                        border: Border.all(
                          color: context.tokens.focusRing,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Compact icon-button chrome on the inset plane.
///
/// Mirrors [PlannerIconAction] so bare [IconButton]s in dense rows (expand,
/// undo, move) share the same 30 px inset square as the planner actions.
ButtonStyle plannerIconButtonStyle(BuildContext context) =>
    IconButton.styleFrom(
      foregroundColor: context.tokens.muted,
      backgroundColor: context.tokens.surfaceInset,
      minimumSize: const Size(30, 30),
      padding: EdgeInsets.zero,
      iconSize: 17,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(PlannerRadius.xs),
        side: BorderSide(color: context.tokens.border),
      ),
    );

/// Compact icon action with a desktop hover state, used inside dense rows.
class PlannerIconAction extends StatelessWidget {
  const PlannerIconAction({
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.size = 30,
    this.iconSize = 17,
    this.tone,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPressed != null;
    final color = enabled ? (tone ?? tokens.muted) : tokens.subtle;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: enabled ? tokens.surfaceInset : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PlannerRadius.xs),
          side: BorderSide(color: enabled ? tokens.border : Colors.transparent),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(PlannerRadius.xs),
          hoverColor: tokens.hover,
          child: SizedBox.square(
            dimension: size,
            child: Icon(icon, size: iconSize, color: color),
          ),
        ),
      ),
    );
  }
}

/// Desktop scroll behaviour: no Android glow, mouse/trackpad dragging allowed.
class PlannerScrollBehavior extends MaterialScrollBehavior {
  const PlannerScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;

  @override
  Set<PointerDeviceKind> get dragDevices => const {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = '确认',
  String cancelLabel = '取消',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Text(message),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(
        PlannerSpace.xl,
        0,
        PlannerSpace.xl,
        PlannerSpace.lg,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: context.tokens.danger)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Shows a message; errors are announced as alerts.
void showPlannerMessage(
  BuildContext context,
  String message, {
  PlannerNoticeTone tone = PlannerNoticeTone.info,
}) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: tone == PlannerNoticeTone.error
            ? context.tokens.danger
            : tone == PlannerNoticeTone.success
            ? context.tokens.success
            : null,
      ),
    );
}

/// Guarded button that disables itself while an async task runs, so a page cannot
/// submit the same command twice.
class AsyncActionButton extends StatefulWidget {
  const AsyncActionButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = true,
    this.enabled = true,
    this.onError,
    this.tooltip,
    super.key,
  });

  final String label;
  final IconData? icon;
  final bool filled;
  final bool enabled;
  final Future<void> Function() onPressed;
  final void Function(Object error)? onError;
  final String? tooltip;

  @override
  State<AsyncActionButton> createState() => _AsyncActionButtonState();
}

class _AsyncActionButtonState extends State<AsyncActionButton> {
  bool _running = false;

  Future<void> _run() async {
    if (_running) return;
    setState(() => _running = true);
    try {
      await widget.onPressed();
    } catch (error) {
      if (mounted && widget.onError != null) {
        widget.onError!(error);
      } else if (mounted) {
        showPlannerMessage(
          context,
          error is StateError ? error.message : '$error',
          tone: PlannerNoticeTone.error,
        );
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = _running
        ? const PlannerSpinner()
        : widget.icon == null
        ? const SizedBox.shrink()
        : Icon(widget.icon, size: 17);
    final label = Text(widget.label);
    final onPressed = widget.enabled && !_running ? _run : null;
    final button = widget.filled
        ? FilledButton.icon(onPressed: onPressed, icon: child, label: label)
        : OutlinedButton.icon(onPressed: onPressed, icon: child, label: label);
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}
