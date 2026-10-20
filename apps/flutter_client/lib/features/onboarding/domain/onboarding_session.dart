import '../../../shared/models/api_models.dart';
import '../../../shared/models/planner_models.dart';
import 'onboarding_options.dart';

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
    this.questionType,
    this.questionOptions = const [],
    this.questionMultiple = false,
    this.recommendations = const PlanningRecommendations(),
    required this.answers,
    required this.profile,
    required this.items,
    required this.summary,
    required this.assumptions,
    required this.warnings,
    required this.startDate,
    this.endDate = '',
    this.learningContext = const {},
    this.research = const {},
    this.planning,
    this.preview,
    this.constraintsConfirmed = false,
    this.currentPlan,
  });

  factory OnboardingSession.fromJson(JsonMap json) => OnboardingSession(
    revision: json['revision'] as int,
    hasPlan: json['has_plan'] as bool? ?? false,
    replanning: json['replanning'] as bool? ?? false,
    planRevision: json['plan_revision'] as int?,
    stage: json['stage'] == 'courses' ? 'items' : json['stage'] as String,
    question: json['question'] as String,
    questionType: json['question_type'] is String
        ? json['question_type'] as String
        : null,
    questionOptions: normalizeQuestionOptions(
      json['question_options'] is List
          ? (json['question_options'] as List).whereType<String>()
          : const <String>[],
    ),
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
    items: _normalizedSessionItems(
      json,
    ).map((entry) => ItemDraft.fromJson(JsonMap.from(entry as Map))).toList(),
    summary: json['summary'] as String,
    assumptions: (json['assumptions'] as List).cast<String>(),
    warnings: (json['warnings'] as List).cast<String>(),
    startDate: json['start_date'] as String? ?? '',
    endDate: json['end_date'] as String? ?? '',
    learningContext: JsonMap.from(json['learning_context'] as Map? ?? const {}),
    research: JsonMap.from(json['research'] as Map? ?? const {}),
    planning: json['planning'] is Map
        ? JsonMap.from(json['planning'] as Map)
        : null,
    preview: json['preview'] is Map
        ? JsonMap.from(json['preview'] as Map)
        : null,
    constraintsConfirmed: json['constraints_confirmed'] as bool? ?? false,
    currentPlan: json['current_plan'] is Map
        ? JsonMap.from(json['current_plan'] as Map)
        : null,
  );

  final int revision;
  final bool hasPlan;
  final bool replanning;
  final int? planRevision;
  final String stage;
  final String question;
  final String? questionType;
  final List<String> questionOptions;
  final bool questionMultiple;

  String get effectiveQuestionType {
    if (questionType == 'text' ||
        normalizeQuestionOptions(questionOptions).isEmpty) {
      return 'text';
    }
    return switch (questionType) {
      'single_choice' => 'single_choice',
      'multiple_choice' => 'multiple_choice',
      _ => questionMultiple ? 'multiple_choice' : 'single_choice',
    };
  }

  List<String> get effectiveQuestionOptions => effectiveQuestionType == 'text'
      ? const []
      : normalizeQuestionOptions(questionOptions);

  bool get effectiveQuestionMultiple =>
      effectiveQuestionType == 'multiple_choice';

  final PlanningRecommendations recommendations;
  final List<InterviewAnswer> answers;
  final OnboardingProfile profile;
  final List<ItemDraft> items;
  final String summary;
  final List<String> assumptions;
  final List<String> warnings;
  final String startDate;

  /// 本次规划周期的结束日期；目标日期允许为空，周期必须有边界。
  final String endDate;
  final JsonMap learningContext;
  final JsonMap research;
  final JsonMap? planning;
  final JsonMap? preview;
  final bool constraintsConfirmed;
  final JsonMap? currentPlan;

  OnboardingSession edit({List<ItemDraft>? items, JsonMap? research}) =>
      OnboardingSession(
        revision: revision,
        hasPlan: hasPlan,
        replanning: replanning,
        planRevision: planRevision,
        stage: stage,
        question: question,
        questionType: questionType,
        questionOptions: questionOptions,
        questionMultiple: questionMultiple,
        recommendations: recommendations,
        answers: answers,
        profile: profile,
        items: items ?? this.items,
        summary: summary,
        assumptions: assumptions,
        warnings: warnings,
        startDate: startDate,
        endDate: endDate,
        learningContext: learningContext,
        research: research ?? this.research,
        planning: planning,
        preview: items != null ? null : preview,
        constraintsConfirmed: constraintsConfirmed,
        currentPlan: currentPlan,
      );
}

List<dynamic> _normalizedSessionItems(JsonMap json) {
  final items = json['items'];
  if (items is! List) return const [];
  final coursesById = <String, String>{};
  final courses = json['courses'];
  if (courses is List) {
    for (final value in courses) {
      if (value is Map && value['id'] is String && value['name'] is String) {
        coursesById[value['id'] as String] = value['name'] as String;
      }
    }
  }
  return [
    for (final value in items)
      if (value is Map)
        () {
          final item = JsonMap.from(value);
          if (!item.containsKey('tag_names')) {
            final courseId =
                item.remove('course_id') ?? item.remove('courseId');
            final name = courseId is String ? coursesById[courseId] : null;
            item['tag_names'] = name == null ? <String>[] : <String>[name];
          } else {
            item.remove('course_id');
            item.remove('courseId');
          }
          return item;
        }(),
  ];
}
