import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/sync/merge_plans.dart';

import '../support/planner_fixture.dart';

void main() {
  const date = '2026-10-16';

  // 每日反馈已不再在本客户端产生新数据，但历史账号、旧导出和旧客户端仍可能带来
  // `daily_feedback`，所以 JSON 往返与多端合并规则必须保持可读、可保留。
  test(
    'legacy overall feedback round-trips JSON and merges independent dates',
    () {
      final base = plannerFixture();
      final local = base.copyWith(dailyFeedback: {date: '本机总结'});
      final remote = base.copyWith(dailyFeedback: {'2026-10-17': '另一日总结'});
      final merged = mergePlans(base, local, remote);
      expect(merged.conflicts, isEmpty);
      expect(merged.data.dailyFeedback, {date: '本机总结', '2026-10-17': '另一日总结'});
      expect(parsePlannerJson(merged.data.toJsonString()), merged.data);
      final conflict = mergePlans(
        base,
        local,
        base.copyWith(dailyFeedback: {date: '另一设备总结'}),
      );
      expect(conflict.conflicts, contains('每日反馈'));
      expect(conflict.data.dailyFeedback?[date], '本机总结');
    },
  );
}
