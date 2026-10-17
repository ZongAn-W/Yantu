import 'package:flutter/material.dart';

import 'theme.dart';

/// Page scaffold used by every workbench route: one heading row plus a scrollable
/// body. Keeping it shared avoids duplicated nested-card layouts.
class PlannerPage extends StatelessWidget {
  const PlannerPage({
    required this.title,
    required this.subtitle,
    required this.children,
    this.actions = const [],
    this.scrollable = true,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(title: title, subtitle: subtitle, actions: actions),
        const SizedBox(height: 16),
        ...children,
      ],
    );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: scrollable
            ? ListView(children: [content])
            : SingleChildScrollView(child: content),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.headlineSmall),
              if (subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: text.bodyMedium?.copyWith(color: PlannerColors.muted),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty)
          Wrap(spacing: 8, runSpacing: 8, children: actions),
      ],
    );
  }
}

/// One panel (`一层面板仅分割不同功能区域`).
class PlannerPanel extends StatelessWidget {
  const PlannerPanel({
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
    super.key,
  });

  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(title!, style: text.titleMedium),
                  ?trailing,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Inline message with the Web notice/error colours.
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
    final (background, border, foreground) = switch (tone) {
      PlannerNoticeTone.info => (
        PlannerColors.surface,
        PlannerColors.border,
        PlannerColors.text,
      ),
      PlannerNoticeTone.success => (
        const Color(0xffeef7f2),
        const Color(0xffbfe0cf),
        PlannerColors.green,
      ),
      PlannerNoticeTone.warning => (
        const Color(0xfffdf5e9),
        const Color(0xffe8d3ae),
        PlannerColors.orange,
      ),
      PlannerNoticeTone.error => (
        const Color(0xfffdecea),
        const Color(0xfff0c4bf),
        PlannerColors.danger,
      ),
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: TextStyle(color: foreground),
        ),
      ),
    );
  }
}

enum PlannerNoticeTone { info, success, warning, error }

/// Colour chip for a course, used in lists, charts and detail rows.
class SubjectChip extends StatelessWidget {
  const SubjectChip({
    required this.name,
    required this.color,
    this.compact = false,
    super.key,
  });

  final String name;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: compact ? FontWeight.w500 : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

/// Thin planned/actual progress track used by the dashboard and calendar rows.
class TimeProgressTrack extends StatelessWidget {
  const TimeProgressTrack({
    required this.planned,
    required this.actual,
    required this.color,
    this.semanticsLabel,
    super.key,
  });

  final int planned;
  final int actual;
  final Color color;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ratio = planned <= 0 ? 0.0 : (actual / planned).clamp(0.0, 1.0);
    return Semantics(
      label: semanticsLabel,
      value: planned <= 0 ? null : '${(ratio * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: ratio,
          minHeight: 6,
          backgroundColor: PlannerColors.border,
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
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: PlannerColors.muted),
            ),
          ),
          Text(
            value,
            key: valueKey,
            style: tabularFigures.copyWith(
              fontWeight: FontWeight.w600,
              color: tone ?? PlannerColors.text,
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(icon, size: 30, color: PlannerColors.muted),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: PlannerColors.muted, fontSize: 12),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
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
      content: Text(message),
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
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : widget.icon == null
        ? const SizedBox.shrink()
        : Icon(widget.icon, size: 18);
    final label = Text(widget.label);
    final onPressed = widget.enabled && !_running ? _run : null;
    final button = widget.filled
        ? FilledButton.icon(
            onPressed: onPressed,
            icon: child,
            label: label,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: child,
            label: label,
          );
    return widget.tooltip == null
        ? button
        : Tooltip(message: widget.tooltip!, child: button);
  }
}
