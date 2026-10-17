import 'package:freezed_annotation/freezed_annotation.dart';
import 'planner_models.dart';

part 'api_models.freezed.dart';
part 'api_models.g.dart';

@freezed
abstract class OnboardingProfile with _$OnboardingProfile {
  const factory OnboardingProfile({
    required String examType,
    required String examDate,
    @Default('') String targetSchool,
    @Default('') String targetProgram,
    @Default('') String currentProgress,
    @Default({'0': 0, '1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0})
    Map<String, int> weeklyMinutes,
    @Default('') String constraintsText,
  }) = _OnboardingProfile;
  factory OnboardingProfile.fromJson(JsonMap json) =>
      _$OnboardingProfileFromJson(json);
}

@freezed
abstract class CourseDraft with _$CourseDraft {
  const factory CourseDraft({
    required String id,
    required String name,
    @Default('') String description,
    @Default(2) int priority,
  }) = _CourseDraft;
  factory CourseDraft.fromJson(JsonMap json) => _$CourseDraftFromJson(json);
}

@freezed
abstract class ItemDraft with _$ItemDraft {
  const factory ItemDraft({
    required String id,
    required String courseId,
    required String title,
    @Default('') String description,
    @Default('') String completionCriteria,
    required int estimatedMinutes,
    String? earliestDate,
    required String deadline,
    @Default(2) int priority,
  }) = _ItemDraft;
  factory ItemDraft.fromJson(JsonMap json) => _$ItemDraftFromJson(json);
}

@freezed
abstract class PlanDraft with _$PlanDraft {
  const factory PlanDraft({
    required List<CourseDraft> courses,
    required List<ItemDraft> items,
    required String analysisSummary,
    @Default([]) List<String> assumptions,
    @Default([]) List<String> warnings,
  }) = _PlanDraft;
  factory PlanDraft.fromJson(JsonMap json) => _$PlanDraftFromJson(json);
}

@freezed
abstract class DraftResponse with _$DraftResponse {
  const factory DraftResponse({required String id, required PlanDraft draft}) =
      _DraftResponse;
  factory DraftResponse.fromJson(JsonMap json) => _$DraftResponseFromJson(json);
}

@freezed
abstract class DailyEntry with _$DailyEntry {
  const factory DailyEntry({
    required String itemId,
    required int actualMinutes,
    required CompletionStatus completionStatus,
    @Default('') String feedback,
  }) = _DailyEntry;
  factory DailyEntry.fromJson(JsonMap json) => _$DailyEntryFromJson(json);
}

@freezed
abstract class DailyReview with _$DailyReview {
  const factory DailyReview({
    @Default('') String feedback,
    @Default([]) List<DailyEntry> entries,
  }) = _DailyReview;
  factory DailyReview.fromJson(JsonMap json) => _$DailyReviewFromJson(json);
}
