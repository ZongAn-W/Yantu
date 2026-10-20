import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';

void main() {
  group('PlannerTokens light palette', () {
    test('legacy aliases mirror the semantic tokens exactly', () {
      const t = PlannerTokens.light;
      expect(PlannerColors.background, t.canvas);
      expect(PlannerColors.surface, t.surface);
      expect(PlannerColors.surfaceMuted, t.surfaceMuted);
      expect(PlannerColors.sidebar, t.sidebar);
      expect(PlannerColors.hover, t.hover);
      expect(PlannerColors.selected, t.selected);
      expect(PlannerColors.text, t.text);
      expect(PlannerColors.muted, t.muted);
      expect(PlannerColors.subtle, t.subtle);
      expect(PlannerColors.border, t.border);
      expect(PlannerColors.borderStrong, t.borderStrong);
      expect(PlannerColors.blue, t.accent);
      expect(PlannerColors.blueHover, t.accentHover);
      expect(PlannerColors.blueSoft, t.accentSoft);
      expect(PlannerColors.green, t.success);
      expect(PlannerColors.orange, t.warning);
      expect(PlannerColors.danger, t.danger);
      expect(PlannerColors.focusRing, t.focusRing);

      expect(PlannerRadius.card, t.radiusCard);
      expect(PlannerRadius.dialog, t.radiusDialog);
      expect(PlannerRadius.control, t.radiusControl);
      expect(PlannerRadius.small, t.radiusSmall);
      expect(PlannerRadius.xs, t.radiusXs);
      expect(PlannerRadius.pill, t.radiusPill);
    });

    test('state overlay and motion tokens keep their contract', () {
      const t = PlannerTokens.light;
      expect(t.hoverAlpha, 0.06);
      expect(t.pressedAlpha, 0.14);
      expect(t.hoverAlpha, lessThan(t.pressedAlpha));
      expect(t.motionFast.inMilliseconds, 120);
      expect(t.motionBase.inMilliseconds, 180);
      expect(t.motionSlow.inMilliseconds, 240);
      expect(t.motionFast, lessThan(t.motionBase));
      expect(t.motionBase, lessThan(t.motionSlow));
      expect(t.motionCurve, Curves.easeOutCubic);

      final hovered = t.hoverOn(const Color(0xffffffff));
      expect(hovered, isNot(const Color(0xffffffff)));
      expect(hovered.a, 1.0);
    });

    test('copyWith and lerp produce coherent token sets', () {
      const t = PlannerTokens.light;
      final dark = t.copyWith(
        canvas: const Color(0xff101418),
        text: const Color(0xfff2f4f7),
        accent: const Color(0xff7aa7cf),
        motionBase: const Duration(milliseconds: 300),
        radiusCard: 10,
      );
      expect(dark.canvas, const Color(0xff101418));
      expect(dark.text, const Color(0xfff2f4f7));
      expect(dark.accent, const Color(0xff7aa7cf));

      final mid = t.lerp(dark, 0.5);
      expect(mid.canvas, Color.lerp(t.canvas, dark.canvas, 0.5));
      expect(mid.text, Color.lerp(t.text, dark.text, 0.5));
      expect(mid.motionBase.inMilliseconds, 240);
      expect(mid.radiusCard, 11);
      expect(mid.border, t.border);
    });

    testWidgets('plannerTheme registers the tokens extension', (tester) async {
      final theme = plannerTheme();
      expect(theme.extension<PlannerTokens>(), PlannerTokens.light);
      expect(theme.scaffoldBackgroundColor, PlannerTokens.light.canvas);
      expect(theme.textTheme.bodyMedium?.fontSize, 13);
      expect(theme.textTheme.headlineSmall?.fontSize, 22);
      final focusedBorder = theme.inputDecorationTheme.focusedBorder;
      expect(focusedBorder, isA<OutlineInputBorder>());
      expect(
        (focusedBorder! as OutlineInputBorder).borderSide.color,
        PlannerTokens.light.accent,
      );
      expect(theme.dialogTheme.backgroundColor, PlannerTokens.light.surface);
      expect(theme.navigationBarTheme.height, 62);

      late PlannerTokens observed;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (context) {
              observed = context.tokens;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(observed, PlannerTokens.light);
      expect(theme.cardTheme.color, PlannerTokens.light.surface);
    });

    testWidgets('PlannerTokens.of falls back to light outside a theme', (
      tester,
    ) async {
      late PlannerTokens observed;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              observed = PlannerTokens.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(observed, PlannerTokens.light);
    });
  });
}
