import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';

double _luminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void _expectContrast(
  Color foreground,
  Color background,
  double minimum,
  String label,
) {
  expect(
    _contrast(foreground, background),
    greaterThanOrEqualTo(minimum),
    reason: '$label 对比度不足',
  );
}

void main() {
  group('Dense Graphite dark tokens', () {
    test('dark token set is marked dark and keeps the shared ladder', () {
      const dark = PlannerTokens.dark;
      expect(dark.isDark, isTrue);
      expect(PlannerTokens.light.isDark, isFalse);
      expect(dark.radiusCard, PlannerTokens.light.radiusCard);
      expect(dark.radiusDialog, PlannerTokens.light.radiusDialog);
      expect(dark.motionBase, PlannerTokens.light.motionBase);
      expect(dark.canvas.computeLuminance(), lessThan(0.05));
      expect(dark.surface.computeLuminance(), lessThan(0.05));
      expect(dark.text.computeLuminance(), greaterThan(0.6));
    });

    test('body and semantic text meet WCAG AA on canvas and surface', () {
      const d = PlannerTokens.dark;
      _expectContrast(d.text, d.canvas, 7, 'dark text/canvas');
      _expectContrast(d.muted, d.canvas, 4.5, 'dark muted/canvas');
      _expectContrast(d.subtle, d.canvas, 4.5, 'dark subtle/canvas');
      _expectContrast(d.text, d.surface, 7, 'dark text/surface');
      _expectContrast(d.muted, d.surface, 4.5, 'dark muted/surface');
      _expectContrast(d.subtle, d.surface, 4.5, 'dark subtle/surface');
      _expectContrast(d.accent, d.canvas, 4.5, 'dark accent/canvas');
      _expectContrast(d.accent, d.surface, 4.5, 'dark accent/surface');
      _expectContrast(d.accentOn, d.accent, 4.5, 'dark onAccent/accent');
      _expectContrast(d.success, d.canvas, 4.5, 'dark success/canvas');
      _expectContrast(d.warning, d.canvas, 4.5, 'dark warning/canvas');
      _expectContrast(d.danger, d.canvas, 4.5, 'dark danger/canvas');
    });

    test('notice tones and fallback tags stay legible', () {
      const d = PlannerTokens.dark;
      _expectContrast(
        d.noticeSuccessInk,
        d.noticeSuccessBackground,
        4.5,
        'dark notice success',
      );
      _expectContrast(
        d.noticeWarningInk,
        d.noticeWarningBackground,
        4.5,
        'dark notice warning',
      );
      _expectContrast(
        d.noticeErrorInk,
        d.noticeErrorBackground,
        4.5,
        'dark notice error',
      );
      for (final tone in d.tagFallbackColors) {
        _expectContrast(tone, d.surface, 4.5, 'dark tag tone');
      }

      const l = PlannerTokens.light;
      _expectContrast(
        l.noticeSuccessInk,
        l.noticeSuccessBackground,
        4.5,
        'light notice success',
      );
      _expectContrast(
        l.noticeWarningInk,
        l.noticeWarningBackground,
        4.5,
        'light notice warning',
      );
      _expectContrast(
        l.noticeErrorInk,
        l.noticeErrorBackground,
        4.5,
        'light notice error',
      );
      expect(l.isDark, isFalse);
    });

    test('data colours are lightened only in dark mode', () {
      const raw = Color(0xff537c87);
      expect(PlannerTokens.light.dataTone(raw), raw);
      final lightened = PlannerTokens.dark.dataTone(raw);
      expect(lightened, isNot(raw));
      expect(lightened.computeLuminance(), greaterThan(raw.computeLuminance()));
      _expectContrast(
        lightened,
        PlannerTokens.dark.surface,
        4.5,
        'dataTone/surface',
      );
    });

    test('plannerDarkTheme registers the dark extension and surfaces', () {
      final theme = plannerDarkTheme();
      expect(theme.brightness, Brightness.dark);
      expect(theme.extension<PlannerTokens>(), PlannerTokens.dark);
      expect(theme.scaffoldBackgroundColor, PlannerTokens.dark.canvas);
      expect(theme.textTheme.bodyMedium?.color, PlannerTokens.dark.text);
      expect(
        theme.snackBarTheme.contentTextStyle?.color,
        PlannerTokens.dark.inverseOn,
      );
      expect(theme.tooltipTheme.textStyle?.color, PlannerTokens.dark.inverseOn);
      expect(theme.dialogTheme.backgroundColor, PlannerTokens.dark.surface);
      expect(theme.cardTheme.color, PlannerTokens.dark.surface);
    });
  });
}
