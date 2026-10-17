import 'package:flutter_test/flutter_test.dart';
import 'package:sjtu_study_planner_client/core/storage/planner_json.dart';
import 'package:sjtu_study_planner_client/core/sync/merge_plans.dart';
import 'package:sjtu_study_planner_client/features/planner/domain/study_day.dart';
import 'package:sjtu_study_planner_client/shared/models/planner_models.dart';

import '../support/planner_fixture.dart';

void main() {
  const date = '2026-10-16';
  test(
    'an unchanged task-day review preserves distinct block fields and logs',
    () {
      final base = plannerFixture();
      final data = base.copyWith(
        blocks: [
          base.blocks.single.copyWith(
            feedback: '第一条',
            completionStatus: CompletionStatus.partial,
          ),
          base.blocks.single.copyWith(
            id: 'second',
            feedback: '第二条',
            status: BlockStatus.completed,
            completionStatus: CompletionStatus.completed,
          ),
        ],
      );
      final entries = dailyReviewEntries(data, date);
      final result = applyDailyReview(
        data,
        date,
        original: entries,
        edited: entries,
        originalFeedback: '',
        feedback: '',
      );
      expect(result, data);
    },
  );

  test(
    'only edited fields replace current values, with all entries validated first',
    () {
      final data = plannerFixture();
      final original = dailyReviewEntries(data, date);
      final current = data.copyWith(
        blocks: [
          data.blocks.single.copyWith(
            feedback: '后台更新的反馈',
            completionStatus: CompletionStatus.skipped,
          ),
        ],
      );
      final result = applyDailyReview(
        current,
        date,
        original: original,
        edited: [original.single.copyWith(actualMinutes: 70)],
        originalFeedback: '',
        feedback: '今天的总结',
      );
      expect(result.blocks.single.feedback, '后台更新的反馈');
      expect(result.blocks.single.completionStatus, CompletionStatus.skipped);
      expect(taskDayMinutes(result, data.tasks.single.id, date), 70);
      expect(result.dailyFeedback, {date: '今天的总结'});
      expect(
        () => applyDailyReview(
          current,
          date,
          original: original,
          edited: [original.single.copyWith(actualMinutes: 1441)],
          originalFeedback: '',
          feedback: '',
        ),
        throwsStateError,
      );
      expect(
        () => applyDailyReview(
          current.copyWith(tasks: [], blocks: [], logs: []),
          date,
          original: original,
          edited: original,
          originalFeedback: '',
          feedback: '',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'an explicit completion change updates status and preserves feedback',
    () {
      final base = plannerFixture();
      final data = base.copyWith(
        blocks: [
          base.blocks.single.copyWith(
            feedback: '原卡点',
            completionStatus: CompletionStatus.partial,
          ),
        ],
      );
      final original = dailyReviewEntries(data, date);
      final result = applyDailyReview(
        data,
        date,
        original: original,
        edited: [
          original.single.copyWith(
            completionStatus: CompletionStatus.completed,
          ),
        ],
        originalFeedback: '',
        feedback: '',
      );
      expect(result.blocks.single.status, BlockStatus.completed);
      expect(result.blocks.single.completionStatus, CompletionStatus.completed);
      expect(result.blocks.single.feedback, '原卡点');
    },
  );

  test('overall feedback round-trips JSON and merges independent dates', () {
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
  });
}
