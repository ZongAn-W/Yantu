import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/features/planner/application/planner_snapshot.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

void main() {
  test('daily grouping sums plan blocks but counts each actual log once', () {
    final data = PlannerData.fromJson(
      jsonDecode(File('test/fixtures/planner_v1.json').readAsStringSync())
          as JsonMap,
    );
    final block = data.blocks.single.copyWith(
      date: '2026-10-16',
      durationMinutes: 30,
      actualMinutes: 999,
    );
    final items = todayItems(
      data.copyWith(
        blocks: [
          block,
          block.copyWith(id: 'second'),
        ],
      ),
      '2026-10-16',
    );
    expect(items, hasLength(1));
    expect(items.single.plannedMinutes, 60);
    expect(items.single.actualMinutes, 35);
    expect(items.single.tags, [data.tags.single.name]);
    expect(
      todayItems(data.copyWith(blocks: []), '2026-10-16').single.actualMinutes,
      35,
    );
    expect(todayItems(data, '2000-01-01'), isEmpty);
  });
}
