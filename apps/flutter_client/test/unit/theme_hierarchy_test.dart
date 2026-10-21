import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/theme.dart';
import 'package:sjtu_study_planner_client/core/widgets.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';
import 'package:sjtu_study_planner_client/shared/models/task_lifecycle.dart';

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

/// Mirrors PlannerTag's Mist Ink 2.0 paint: 12% tone over surface.
Color _tagFill(Color tone, PlannerTokens tokens) =>
    Color.alphaBlend(tone.withValues(alpha: 0.12), tokens.surface);

/// Mirrors PlannerTag's label colour: tone mixed 70/30 with body ink.
Color _tagInk(Color tone, PlannerTokens tokens) =>
    Color.lerp(tone, tokens.text, 0.30)!;

Task _task({String? completedAt, bool archived = false}) => Task(
  id: 'task-hierarchy',
  userId: 'user-hierarchy',
  title: '示例事项',
  estimatedMinutes: 60,
  completedMinutes: 0,
  priority: 2,
  deadline: '2026-11-08',
  isFixed: false,
  archived: archived,
  createdAt: '2026-10-01T00:00:00Z',
  updatedAt: '2026-10-01T00:00:00Z',
  completedAt: completedAt,
);

TaskTimeProgress _progress({
  int actualMinutes = 0,
  bool archived = false,
  bool completed = false,
}) => TaskTimeProgress(
  task: _task(
    archived: archived,
    completedAt: completed ? '2026-10-01T00:00:00Z' : null,
  ),
  actualMinutes: actualMinutes,
  archived: archived,
  completed: completed,
  ratio: actualMinutes / 60,
);

void main() {
  group('Mist Ink 2.0 surface ladder', () {
    test('canvas, sidebar, surface and inset are distinct planes', () {
      const t = PlannerTokens.light;
      expect(t.canvas, isNot(t.surface));
      expect(t.sidebar, isNot(t.canvas));
      expect(t.surfaceInset, isNot(t.surface));
      expect(t.surfaceInset, isNot(t.surfaceMuted));
      expect(
        t.surface.computeLuminance(),
        greaterThan(t.canvas.computeLuminance()),
      );
      expect(
        t.canvas.computeLuminance(),
        greaterThan(t.sidebar.computeLuminance()),
      );
    });

    test('panel shadow stays a hairline-scale shadow in both themes', () {
      for (final tokens in [PlannerTokens.light, PlannerTokens.dark]) {
        expect(tokens.panelShadow.a, greaterThan(0));
        expect(tokens.panelShadow.a, lessThan(0.35));
        expect(tokens.panelShadow, isNot(tokens.shadow));
      }
    });

    test('form controls sit on the inset plane', () {
      final theme = plannerTheme();
      expect(
        theme.inputDecorationTheme.fillColor,
        PlannerTokens.light.surfaceInset,
      );
      expect(theme.cardTheme.color, PlannerTokens.light.surface);
    });
  });

  group('tag and progress tones', () {
    test('tag fill + ink mix clears 4.5:1 on the light surface', () {
      const t = PlannerTokens.light;
      for (final tone in t.tagFallbackColors) {
        final ratio = _contrast(_tagInk(tone, t), _tagFill(tone, t));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'light tag $tone contrast $ratio',
        );
      }
    });

    test('dark tag tones stay legible after dataTone lightening', () {
      const t = PlannerTokens.dark;
      for (final raw in t.tagFallbackColors) {
        final tone = t.dataTone(raw);
        final ratio = _contrast(_tagInk(tone, t), _tagFill(tone, t));
        expect(
          ratio,
          greaterThanOrEqualTo(4.5),
          reason: 'dark tag $tone contrast $ratio',
        );
      }
    });

    test('progress pills carry semantic tones instead of one grey', () {
      const t = PlannerTokens.light;
      expect(taskProgressTone(_progress(completed: true), t), t.success);
      expect(taskProgressTone(_progress(actualMinutes: 30), t), t.accent);
      expect(taskProgressTone(_progress(), t), t.muted);
      expect(
        taskProgressTone(_progress(actualMinutes: 30, archived: true), t),
        t.muted,
      );
    });
  });
}
