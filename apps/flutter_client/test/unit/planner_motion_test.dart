import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/motion.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';

Widget _host({required bool disableAnimations, required Widget child}) =>
    MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    );

void main() {
  group('PlannerDurations', () {
    test('uses the one 120/180/240 ms ladder and a single curve', () {
      expect(PlannerDurations.fast.inMilliseconds, 120);
      expect(PlannerDurations.base.inMilliseconds, 180);
      expect(PlannerDurations.slow.inMilliseconds, 240);
      expect(PlannerDurations.fast, lessThan(PlannerDurations.base));
      expect(PlannerDurations.base, lessThan(PlannerDurations.slow));
      expect(PlannerDurations.curve, Curves.easeOutCubic);
      expect(PlannerTokens.light.motionFast, PlannerDurations.fast);
      expect(PlannerTokens.light.motionBase, PlannerDurations.base);
      expect(PlannerTokens.light.motionSlow, PlannerDurations.slow);
      expect(PlannerTokens.light.motionCurve, PlannerDurations.curve);
    });

    testWidgets('motion helpers collapse to zero with reduced motion', (
      tester,
    ) async {
      late Duration normal;
      late Duration reduced;
      late Curve reducedCurve;
      await tester.pumpWidget(
        _host(
          disableAnimations: false,
          child: Builder(
            builder: (context) {
              normal = PlannerMotion.duration(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        _host(
          disableAnimations: true,
          child: Builder(
            builder: (context) {
              reduced = PlannerMotion.duration(
                context,
                preferred: PlannerDurations.slow,
              );
              reducedCurve = PlannerMotion.curve(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(normal, PlannerDurations.base);
      expect(reduced, Duration.zero);
      expect(reducedCurve, Curves.linear);
    });
  });

  group('PlannerFadeSlide', () {
    testWidgets('animates from 0 to full opacity over motionBase', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          disableAnimations: false,
          child: const PlannerFadeSlide(child: Text('内容')),
        ),
      );
      await tester.pump();
      final start = tester
          .widget<FadeTransition>(find.byType(FadeTransition))
          .opacity
          .value;
      expect(start, lessThan(1.0));
      await tester.pumpAndSettle();
      final end = tester
          .widget<FadeTransition>(find.byType(FadeTransition))
          .opacity
          .value;
      expect(end, 1.0);
    });

    testWidgets('reduced motion shows the final state without a ticker', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          disableAnimations: true,
          child: const PlannerFadeSlide(child: Text('内容')),
        ),
      );
      await tester.pump();
      final opacity = tester
          .widget<FadeTransition>(find.byType(FadeTransition))
          .opacity
          .value;
      expect(opacity, 1.0);
      final offset = tester
          .widget<SlideTransition>(find.byType(SlideTransition))
          .position
          .value;
      expect(offset, Offset.zero);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });

  group('page transitions', () {
    test('plannerTheme installs the shared builder on every platform', () {
      final theme = plannerTheme();
      for (final platform in TargetPlatform.values) {
        expect(
          theme.pageTransitionsTheme.builders[platform],
          isA<PlannerPageTransitionsBuilder>(),
        );
      }
    });

    testWidgets('route fade runs and settles', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: plannerTheme(),
          home: const Scaffold(body: Text('首页')),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('第二页')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.byType(FadeTransition), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.text('第二页'), findsOneWidget);
    });

    testWidgets('reduced motion renders the destination immediately', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          theme: plannerTheme(),
          home: const Scaffold(body: Text('首页')),
        ),
      );
      navigatorKey.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('第二页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('第二页'), findsOneWidget);
      // No page-transition fade is installed for reduced motion.
      expect(
        find.ancestor(
          of: find.text('第二页'),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
    });
  });
}
