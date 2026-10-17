import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';

class InterviewAnswer {
  const InterviewAnswer(this.question, this.answer);
  final String question;
  final String answer;
}

class PlanningRecommendations {
  const PlanningRecommendations({
    this.targetDate = '',
    this.targetDateReason = '',
    this.targetDateEstimated = true,
    this.planEndDate = '',
    this.planEndDateReason = '',
    this.weeklyMinutes = const {},
    this.weeklyMinutesReason = '',
  });

  factory PlanningRecommendations.fromJson(JsonMap json) =>
      PlanningRecommendations(
        targetDate: json['target_date'] as String? ?? '',
        targetDateReason: json['target_date_reason'] as String? ?? '',
        targetDateEstimated: json['target_date_estimated'] as bool? ?? true,
        planEndDate: json['plan_end_date'] as String? ?? '',
        planEndDateReason: json['plan_end_date_reason'] as String? ?? '',
        weeklyMinutes: (json['weekly_minutes'] as Map? ?? const {}).map(
          (key, value) => MapEntry(key as String, value as int),
        ),
        weeklyMinutesReason: json['weekly_minutes_reason'] as String? ?? '',
      );

  /// 用户目标日期，可以为空；与本次规划周期分别表达。
  final String targetDate;
  final String targetDateReason;
  final bool targetDateEstimated;

  /// 本次规划周期的结束日期，必须是有限区间。
  final String planEndDate;
  final String planEndDateReason;
  final Map<String, int> weeklyMinutes;
  final String weeklyMinutesReason;
}

class OnboardingSession {
  const OnboardingSession({
    required this.revision,
    this.hasPlan = false,
    this.replanning = false,
    this.planRevision,
    required this.stage,
    required this.question,
    this.questionOptions = const [],
    this.questionMultiple = false,
    this.recommendations = const PlanningRecommendations(),
    required this.answers,
    required this.profile,
    required this.courses,
    required this.items,
    required this.summary,
    required this.assumptions,
    required this.warnings,
    required this.startDate,
    this.endDate = '',
  });

  factory OnboardingSession.fromJson(JsonMap json) => OnboardingSession(
    revision: json['revision'] as int,
    hasPlan: json['has_plan'] as bool? ?? false,
    replanning: json['replanning'] as bool? ?? false,
    planRevision: json['plan_revision'] as int?,
    stage: json['stage'] as String,
    question: json['question'] as String,
    questionOptions: (json['question_options'] as List? ?? const [])
        .cast<String>(),
    questionMultiple: json['question_multiple'] as bool? ?? false,
    recommendations: PlanningRecommendations.fromJson(
      JsonMap.from(json['recommendations'] as Map? ?? const {}),
    ),
    answers: (json['answers'] as List)
        .map(
          (entry) => InterviewAnswer(
            entry['question'] as String,
            entry['answer'] as String,
          ),
        )
        .toList(),
    profile: OnboardingProfile.fromJson(JsonMap.from(json['profile'] as Map)),
    courses: (json['courses'] as List)
        .map((entry) => CourseDraft.fromJson(JsonMap.from(entry as Map)))
        .toList(),
    items: (json['items'] as List)
        .map((entry) => ItemDraft.fromJson(JsonMap.from(entry as Map)))
        .toList(),
    summary: json['summary'] as String,
    assumptions: (json['assumptions'] as List).cast<String>(),
    warnings: (json['warnings'] as List).cast<String>(),
    startDate: json['start_date'] as String? ?? '',
    endDate: json['end_date'] as String? ?? '',
  );

  final int revision;
  final bool hasPlan;
  final bool replanning;
  final int? planRevision;
  final String stage;
  final String question;
  final List<String> questionOptions;
  final bool questionMultiple;
  final PlanningRecommendations recommendations;
  final List<InterviewAnswer> answers;
  final OnboardingProfile profile;
  final List<CourseDraft> courses;
  final List<ItemDraft> items;
  final String summary;
  final List<String> assumptions;
  final List<String> warnings;
  final String startDate;

  /// 本次规划周期的结束日期；目标日期允许为空，周期必须有边界。
  final String endDate;

  OnboardingSession edit({
    List<CourseDraft>? courses,
    List<ItemDraft>? items,
  }) => OnboardingSession(
    revision: revision,
    hasPlan: hasPlan,
    replanning: replanning,
    planRevision: planRevision,
    stage: stage,
    question: question,
    questionOptions: questionOptions,
    questionMultiple: questionMultiple,
    recommendations: recommendations,
    answers: answers,
    profile: profile,
    courses: courses ?? this.courses,
    items: items ?? this.items,
    summary: summary,
    assumptions: assumptions,
    warnings: warnings,
    startDate: startDate,
    endDate: endDate,
  );
}
