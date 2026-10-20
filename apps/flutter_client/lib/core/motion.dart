import 'package:flutter/material.dart';

import 'theme.dart';

/// Motion discipline for the Mist Ink UI (W4).
///
/// Rules:
/// - only state-change animations (page enter, mode switch, collapse, hover);
/// - durations come from PlannerDurations (120/180/240 ms) and the one curve;
/// - only opacity/transform animate, never layout properties;
/// - every animation respects MediaQuery.disableAnimationsOf by collapsing to
///   Duration.zero, so reduced-motion users (and widget tests) see the final
///   state immediately and pumpAndSettle never waits on decoration;
/// - no infinite/repeating animations.
abstract final class PlannerMotion {
  /// The duration for a state animation, or Duration.zero when animations are
  /// disabled by the platform/MediaQuery.
  static Duration duration(BuildContext context, {Duration? preferred}) {
    if (MediaQuery.disableAnimationsOf(context)) return Duration.zero;
    return preferred ?? context.tokens.motionBase;
  }

  /// The shared motion curve, or a linear no-op curve when animations are off.
  static Curve curve(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
      ? Curves.linear
      : context.tokens.motionCurve;

  /// The page-enter transition duration.
  static Duration page(BuildContext context) =>
      duration(context, preferred: context.tokens.motionBase);
}

/// Fade + 6 px rise used for page-level content entry.
///
/// The child is laid out immediately; only opacity/transform animate. With
/// reduced motion the child is shown at its final state, so no ticker is
/// created and pumpAndSettle never waits.
class PlannerFadeSlide extends StatefulWidget {
  const PlannerFadeSlide({
    required this.child,
    this.duration,
    this.delay = Duration.zero,
    super.key,
  });

  final Widget child;
  final Duration? duration;
  final Duration delay;

  @override
  State<PlannerFadeSlide> createState() => _PlannerFadeSlideState();
}

class _PlannerFadeSlideState extends State<PlannerFadeSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PlannerDurations.base,
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: PlannerDurations.curve,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).animate(_fade);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final duration = PlannerMotion.duration(
      context,
      preferred: widget.duration ?? context.tokens.motionBase,
    );
    if (duration == Duration.zero) {
      _controller.value = 1;
      return;
    }
    _controller.duration = duration;
    if (widget.delay > Duration.zero) {
      Future<void>.delayed(widget.delay, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _offset, child: widget.child),
    );
  }
}

/// Custom page transition: 180 ms fade + 6 px rise, reduced-motion aware.
///
/// Installed through pageTransitionsTheme in PlannerComponentThemes so every
/// route (today, calendar, adjust, settings, auth) shares the same motion.
class PlannerPageTransitionsBuilder extends PageTransitionsBuilder {
  const PlannerPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final curve = CurvedAnimation(
      parent: animation,
      curve: PlannerDurations.curve,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curve),
        child: child,
      ),
    );
  }
}
