// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'api_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_OnboardingProfile _$OnboardingProfileFromJson(
  Map<String, dynamic> json,
) => $checkedCreate(
  '_OnboardingProfile',
  json,
  ($checkedConvert) {
    final val = _OnboardingProfile(
      goalText: $checkedConvert('goal_text', (v) => v as String? ?? ''),
      goalType: $checkedConvert('goal_type', (v) => v as String? ?? 'other'),
      goalSubtype: $checkedConvert('goal_subtype', (v) => v as String? ?? ''),
      targetDate: $checkedConvert('target_date', (v) => v as String? ?? ''),
      targetDateConfirmed: $checkedConvert(
        'target_date_confirmed',
        (v) => v as bool? ?? false,
      ),
      planStartDate: $checkedConvert(
        'plan_start_date',
        (v) => v as String? ?? '',
      ),
      planEndDate: $checkedConvert('plan_end_date', (v) => v as String? ?? ''),
      targetSchool: $checkedConvert('target_school', (v) => v as String? ?? ''),
      targetProgram: $checkedConvert(
        'target_program',
        (v) => v as String? ?? '',
      ),
      currentProgress: $checkedConvert(
        'current_progress',
        (v) => v as String? ?? '',
      ),
      weeklyMinutes: $checkedConvert(
        'weekly_minutes',
        (v) =>
            (v as Map<String, dynamic>?)?.map(
              (k, e) => MapEntry(k, (e as num).toInt()),
            ) ??
            const {'0': 0, '1': 0, '2': 0, '3': 0, '4': 0, '5': 0, '6': 0},
      ),
      constraintsText: $checkedConvert(
        'constraints_text',
        (v) => v as String? ?? '',
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'goalText': 'goal_text',
    'goalType': 'goal_type',
    'goalSubtype': 'goal_subtype',
    'targetDate': 'target_date',
    'targetDateConfirmed': 'target_date_confirmed',
    'planStartDate': 'plan_start_date',
    'planEndDate': 'plan_end_date',
    'targetSchool': 'target_school',
    'targetProgram': 'target_program',
    'currentProgress': 'current_progress',
    'weeklyMinutes': 'weekly_minutes',
    'constraintsText': 'constraints_text',
  },
);

Map<String, dynamic> _$OnboardingProfileToJson(_OnboardingProfile instance) =>
    <String, dynamic>{
      'goal_text': instance.goalText,
      'goal_type': instance.goalType,
      'goal_subtype': instance.goalSubtype,
      'target_date': instance.targetDate,
      'target_date_confirmed': instance.targetDateConfirmed,
      'plan_start_date': instance.planStartDate,
      'plan_end_date': instance.planEndDate,
      'target_school': instance.targetSchool,
      'target_program': instance.targetProgram,
      'current_progress': instance.currentProgress,
      'weekly_minutes': instance.weeklyMinutes,
      'constraints_text': instance.constraintsText,
    };

_CourseDraft _$CourseDraftFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_CourseDraft', json, ($checkedConvert) {
      final val = _CourseDraft(
        id: $checkedConvert('id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        description: $checkedConvert('description', (v) => v as String? ?? ''),
        priority: $checkedConvert('priority', (v) => (v as num?)?.toInt() ?? 2),
      );
      return val;
    });

Map<String, dynamic> _$CourseDraftToJson(_CourseDraft instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'priority': instance.priority,
    };

_ItemDraft _$ItemDraftFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_ItemDraft',
  json,
  ($checkedConvert) {
    final val = _ItemDraft(
      id: $checkedConvert('id', (v) => v as String),
      tagNames: $checkedConvert(
        'tag_names',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      title: $checkedConvert('title', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String? ?? ''),
      completionCriteria: $checkedConvert(
        'completion_criteria',
        (v) => v as String? ?? '',
      ),
      estimatedMinutes: $checkedConvert(
        'estimated_minutes',
        (v) => (v as num).toInt(),
      ),
      earliestDate: $checkedConvert('earliest_date', (v) => v as String?),
      deadline: $checkedConvert('deadline', (v) => v as String),
      deadlineKind: $checkedConvert(
        'deadline_kind',
        (v) =>
            $enumDecodeNullable(_$ItemDateKindEnumMap, v) ??
            ItemDateKind.deadline,
      ),
      priority: $checkedConvert('priority', (v) => (v as num?)?.toInt() ?? 2),
      planning: $checkedConvert('planning', (v) => v as Map<String, dynamic>?),
    );
    return val;
  },
  fieldKeyMap: const {
    'tagNames': 'tag_names',
    'completionCriteria': 'completion_criteria',
    'estimatedMinutes': 'estimated_minutes',
    'earliestDate': 'earliest_date',
    'deadlineKind': 'deadline_kind',
  },
);

Map<String, dynamic> _$ItemDraftToJson(_ItemDraft instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tag_names': instance.tagNames,
      'title': instance.title,
      'description': instance.description,
      'completion_criteria': instance.completionCriteria,
      'estimated_minutes': instance.estimatedMinutes,
      'earliest_date': ?instance.earliestDate,
      'deadline': instance.deadline,
      'deadline_kind': _$ItemDateKindEnumMap[instance.deadlineKind]!,
      'priority': instance.priority,
      'planning': ?instance.planning,
    };

const _$ItemDateKindEnumMap = {
  ItemDateKind.deadline: 'deadline',
  ItemDateKind.planEnd: 'plan_end',
};

_PlanDraft _$PlanDraftFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_PlanDraft',
  json,
  ($checkedConvert) {
    final val = _PlanDraft(
      items: $checkedConvert(
        'items',
        (v) => (v as List<dynamic>)
            .map((e) => ItemDraft.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      analysisSummary: $checkedConvert('analysis_summary', (v) => v as String),
      assumptions: $checkedConvert(
        'assumptions',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      warnings: $checkedConvert(
        'warnings',
        (v) =>
            (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [],
      ),
      planning: $checkedConvert('planning', (v) => v as Map<String, dynamic>?),
    );
    return val;
  },
  fieldKeyMap: const {'analysisSummary': 'analysis_summary'},
);

Map<String, dynamic> _$PlanDraftToJson(_PlanDraft instance) =>
    <String, dynamic>{
      'items': instance.items.map((e) => e.toJson()).toList(),
      'analysis_summary': instance.analysisSummary,
      'assumptions': instance.assumptions,
      'warnings': instance.warnings,
      'planning': ?instance.planning,
    };

_DraftResponse _$DraftResponseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_DraftResponse', json, ($checkedConvert) {
      final val = _DraftResponse(
        id: $checkedConvert('id', (v) => v as String),
        draft: $checkedConvert(
          'draft',
          (v) => PlanDraft.fromJson(v as Map<String, dynamic>),
        ),
      );
      return val;
    });

Map<String, dynamic> _$DraftResponseToJson(_DraftResponse instance) =>
    <String, dynamic>{'id': instance.id, 'draft': instance.draft.toJson()};
