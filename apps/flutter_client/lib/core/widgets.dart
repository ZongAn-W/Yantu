import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
              ? Scrollbar(
                  child: ListView(
                    padding: padding,
                    children: [content],
                  ),
                )
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
                      color: PlannerColors.subtle,
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
                      color: PlannerColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        if (actions.isNotEmpty)
          Wrap(spacing: PlannerSpace.sm, runSpacing: PlannerSpace.sm, children: actions),
      ],
    );
  }
}

/// One white panel (`一层面板仅分割不同功能区域`): 12 px radius, hairline border,
/// no shadow. Sections inside a panel use dividers, not nested cards.
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
    return Card(
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
                        if (title != null) Text(title!, style: text.titleMedium),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: text.bodySmall?.copyWith(
                              color: PlannerColors.muted,
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
    );
  }
}

/// Section heading inside a page (e.g. 今日学习 / 全部事项).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.subtitle,
    this.count,
    this.trailing,
    super.key,
  });

  final String title;
  final String? subtitle;
  final int? count;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: PlannerSpace.sm,
            runSpacing: 2,
            children: [
              Semantics(
                header: true,
                child: Text(title, style: text.titleMedium),
              ),
              if (count != null && count! > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: PlannerColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(PlannerRadius.xs),
                  ),
                  child: Text(
                    '$count',
                    style: text.labelSmall?.copyWith(
                      color: PlannerColors.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: text.bodySmall?.copyWith(color: PlannerColors.muted),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: PlannerSpace.md),
          trailing!,
        ],
      ],
    );
  }
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
        PlannerColors.surface,
        PlannerColors.border,
        PlannerColors.text,
        PlannerColors.subtle,
      ),
      PlannerNoticeTone.success => (
        const Color(0xffeef7f2),
        const Color(0xffcfe7db),
        const Color(0xff1f5f4a),
        PlannerColors.green,
      ),
      PlannerNoticeTone.warning => (
        const Color(0xfffdf6e8),
        const Color(0xffecd9b0),
        const Color(0xff8a5a12),
        PlannerColors.orange,
      ),
      PlannerNoticeTone.error => (
        const Color(0xfffcefed),
        const Color(0xfff0ccc7),
        const Color(0xff8f3733),
        PlannerColors.danger,
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
          backgroundColor: PlannerColors.surfaceMuted,
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
              style: const TextStyle(color: PlannerColors.muted, fontSize: 13),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: tabularFigures.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: tone ?? PlannerColors.text,
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
            color: tone ?? PlannerColors.text,
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
    this.icon = Icons.inbox_outlined,
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
            decoration: const BoxDecoration(
              color: PlannerColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 21, color: PlannerColors.muted),
          ),
          const SizedBox(height: PlannerSpace.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: text.titleSmall?.copyWith(color: PlannerColors.text),
          ),
          if (hint != null) ...[
            const SizedBox(height: PlannerSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                hint!,
                textAlign: TextAlign.center,
                style: text.bodySmall?.copyWith(color: PlannerColors.muted),
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

/// Small tinted tag. Used for labels, filters and subject marks.
class PlannerTag extends StatelessWidget {
  const PlannerTag({
    required this.label,
    this.color,
    this.selected = false,
    this.onTap,
    this.icon,
    this.dense = false,
    super.key,
  });

  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tone = color ?? PlannerColors.muted;
    final foreground = selected ? PlannerColors.blue : tone;
    final background = selected
        ? PlannerColors.blueSoft
        : Color.alphaBlend(tone.withValues(alpha: 0.08), PlannerColors.surface);
    final borderColor = selected
        ? const Color(0xffb8cfe4)
        : (color == null ? PlannerColors.border : tone.withValues(alpha: 0.22));
    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 7,
        vertical: dense ? 1.5 : 2.5,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: dense ? 11 : 11.5,
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
    if (onTap == null) return decorated;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PlannerRadius.xs),
          child: decorated,
        ),
      ),
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
class PlannerSegmented<T> extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final index = items.indexWhere((item) => item.$1 == value);
    final selectedIndex = index < 0 ? 0 : index;
    final count = items.length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 240.0;
        final segmentWidth = (width - 4) / count;
        return Container(
          height: height,
          width: constraints.maxWidth.isFinite ? null : count * 64.0,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: PlannerColors.surfaceMuted,
            borderRadius: BorderRadius.circular(PlannerRadius.small),
            border: Border.all(color: PlannerColors.border),
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                alignment: Alignment(
                  count == 1 ? 0 : -1 + 2 * selectedIndex / (count - 1),
                  0,
                ),
                child: Container(
                  width: segmentWidth,
                  height: height - 4,
                  decoration: BoxDecoration(
                    color: PlannerColors.surface,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: PlannerColors.borderStrong),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0a0f172a),
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
                          key: itemKey?.call(items[i].$1, i),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onChanged(items[i].$1),
                          child: Center(
                            child: Text(
                              items[i].$2,
                              style: TextStyle(
                                fontSize: 12.5,
                                height: 1.4,
                                fontWeight: i == selectedIndex
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: i == selectedIndex
                                    ? PlannerColors.text
                                    : PlannerColors.muted,
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
        );
      },
    );
  }
}

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
    final enabled = onPressed != null;
    final color = enabled ? (tone ?? PlannerColors.muted) : PlannerColors.subtle;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(PlannerRadius.xs),
          hoverColor: PlannerColors.hover,
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
              ? FilledButton.styleFrom(backgroundColor: PlannerColors.danger)
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
            ? PlannerColors.danger
            : tone == PlannerNoticeTone.success
            ? PlannerColors.green
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
        ? const SizedBox.square(
            dimension: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
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
