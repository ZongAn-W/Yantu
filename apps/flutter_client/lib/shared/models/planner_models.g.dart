// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'planner_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_PlannerData _$PlannerDataFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_PlannerData',
  json,
  ($checkedConvert) {
    final val = _PlannerData(
      version: $checkedConvert('version', (v) => _versionOne(v)),
      profile: $checkedConvert(
        'profile',
        (v) => Profile.fromJson(v as Map<String, dynamic>),
      ),
      subjects: $checkedConvert(
        'subjects',
        (v) => (v as List<dynamic>)
            .map((e) => Subject.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      tasks: $checkedConvert(
        'tasks',
        (v) => (v as List<dynamic>)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      blocks: $checkedConvert(
        'blocks',
        (v) => (v as List<dynamic>)
            .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      logs: $checkedConvert(
        'logs',
        (v) => (v as List<dynamic>)
            .map((e) => TimeLog.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      fixedEvents: $checkedConvert(
        'fixed_events',
        (v) => (v as List<dynamic>)
            .map((e) => FixedEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      replanRuns: $checkedConvert(
        'replan_runs',
        (v) => (v as List<dynamic>)
            .map((e) => ReplanRun.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      phases: $checkedConvert(
        'phases',
        (v) => (v as List<dynamic>)
            .map((e) => Phase.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      dailyFeedback: $checkedConvert(
        'daily_feedback',
        (v) => (v as Map<String, dynamic>?)?.map(
          (k, e) => MapEntry(k, e as String),
        ),
      ),
      planning: $checkedConvert('planning', (v) => v as Map<String, dynamic>?),
    );
    return val;
  },
  fieldKeyMap: const {
    'fixedEvents': 'fixed_events',
    'replanRuns': 'replan_runs',
    'dailyFeedback': 'daily_feedback',
  },
);

Map<String, dynamic> _$PlannerDataToJson(_PlannerData instance) =>
    <String, dynamic>{
      'version': instance.version,
      'profile': instance.profile.toJson(),
      'subjects': instance.subjects.map((e) => e.toJson()).toList(),
      'tasks': instance.tasks.map((e) => e.toJson()).toList(),
      'blocks': instance.blocks.map((e) => e.toJson()).toList(),
      'logs': instance.logs.map((e) => e.toJson()).toList(),
      'fixed_events': instance.fixedEvents.map((e) => e.toJson()).toList(),
      'replan_runs': instance.replanRuns.map((e) => e.toJson()).toList(),
      'phases': instance.phases.map((e) => e.toJson()).toList(),
      'daily_feedback': ?instance.dailyFeedback,
      'planning': ?instance.planning,
    };

_Profile _$ProfileFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_Profile',
  json,
  ($checkedConvert) {
    final val = _Profile(
      userId: $checkedConvert('user_id', (v) => v as String),
      storedPlanningMode: $checkedConvert(
        'planning_mode',
        (v) => $enumDecodeNullable(_$PlanningModeEnumMap, v),
      ),
      goalText: $checkedConvert('goal_text', (v) => v as String? ?? ''),
      goalType: $checkedConvert(
        'goal_type',
        (v) => $enumDecodeNullable(_$GoalTypeEnumMap, v) ?? GoalType.other,
      ),
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
      weeklyMinutes: $checkedConvert(
        'weekly_minutes',
        (v) => (v as Map<String, dynamic>?)?.map(
          (k, e) => MapEntry(k, (e as num).toInt()),
        ),
      ),
      constraints: $checkedConvert('constraints', (v) => v as String? ?? ''),
      targetSchool: $checkedConvert('target_school', (v) => v as String? ?? ''),
      targetProgram: $checkedConvert(
        'target_program',
        (v) => v as String? ?? '',
      ),
      examDate: $checkedConvert('exam_date', (v) => v as String? ?? ''),
      examEndDate: $checkedConvert('exam_end_date', (v) => v as String? ?? ''),
      dailyLimitMinutes: $checkedConvert(
        'daily_limit_minutes',
        (v) => (v as num).toInt(),
      ),
      granularityMinutes: $checkedConvert(
        'granularity_minutes',
        (v) => (v as num).toInt(),
      ),
      bufferMinutes: $checkedConvert(
        'buffer_minutes',
        (v) => (v as num).toInt(),
      ),
      subjectLimitMinutes: $checkedConvert(
        'subject_limit_minutes',
        (v) => (v as num).toInt(),
      ),
      studyStartMinute: $checkedConvert(
        'study_start_minute',
        (v) => (v as num).toInt(),
      ),
      studyEndMinute: $checkedConvert(
        'study_end_minute',
        (v) => (v as num).toInt(),
      ),
      foundation: $checkedConvert('foundation', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'storedPlanningMode': 'planning_mode',
    'goalText': 'goal_text',
    'goalType': 'goal_type',
    'goalSubtype': 'goal_subtype',
    'targetDate': 'target_date',
    'targetDateConfirmed': 'target_date_confirmed',
    'planStartDate': 'plan_start_date',
    'planEndDate': 'plan_end_date',
    'weeklyMinutes': 'weekly_minutes',
    'targetSchool': 'target_school',
    'targetProgram': 'target_program',
    'examDate': 'exam_date',
    'examEndDate': 'exam_end_date',
    'dailyLimitMinutes': 'daily_limit_minutes',
    'granularityMinutes': 'granularity_minutes',
    'bufferMinutes': 'buffer_minutes',
    'subjectLimitMinutes': 'subject_limit_minutes',
    'studyStartMinute': 'study_start_minute',
    'studyEndMinute': 'study_end_minute',
  },
);

Map<String, dynamic> _$ProfileToJson(_Profile instance) => <String, dynamic>{
  'user_id': instance.userId,
  'planning_mode': ?_$PlanningModeEnumMap[instance.storedPlanningMode],
  'goal_text': instance.goalText,
  'goal_type': _$GoalTypeEnumMap[instance.goalType]!,
  'goal_subtype': instance.goalSubtype,
  'target_date': instance.targetDate,
  'target_date_confirmed': instance.targetDateConfirmed,
  'plan_start_date': instance.planStartDate,
  'plan_end_date': instance.planEndDate,
  'weekly_minutes': ?instance.weeklyMinutes,
  'constraints': instance.constraints,
  'target_school': instance.targetSchool,
  'target_program': instance.targetProgram,
  'exam_date': instance.examDate,
  'exam_end_date': instance.examEndDate,
  'daily_limit_minutes': instance.dailyLimitMinutes,
  'granularity_minutes': instance.granularityMinutes,
  'buffer_minutes': instance.bufferMinutes,
  'subject_limit_minutes': instance.subjectLimitMinutes,
  'study_start_minute': instance.studyStartMinute,
  'study_end_minute': instance.studyEndMinute,
  'foundation': instance.foundation,
};

const _$PlanningModeEnumMap = {
  PlanningMode.daily: 'daily',
  PlanningMode.timed: 'timed',
};

const _$GoalTypeEnumMap = {
  GoalType.exam: 'exam',
  GoalType.course: 'course',
  GoalType.skill: 'skill',
  GoalType.selfStudy: 'self_study',
  GoalType.other: 'other',
};

_Subject _$SubjectFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_Subject', json, ($checkedConvert) {
      final val = _Subject(
        id: $checkedConvert('id', (v) => v as String),
        userId: $checkedConvert('user_id', (v) => v as String),
        name: $checkedConvert('name', (v) => v as String),
        color: $checkedConvert('color', (v) => v as String),
        priority: $checkedConvert('priority', (v) => _priority(v)),
      );
      return val;
    }, fieldKeyMap: const {'userId': 'user_id'});

Map<String, dynamic> _$SubjectToJson(_Subject instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'name': instance.name,
  'color': instance.color,
  'priority': instance.priority,
};

_Task _$TaskFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_Task',
  json,
  ($checkedConvert) {
    final val = _Task(
      id: $checkedConvert('id', (v) => v as String),
      userId: $checkedConvert('user_id', (v) => v as String),
      subjectId: $checkedConvert('subject_id', (v) => v as String),
      title: $checkedConvert('title', (v) => v as String),
      description: $checkedConvert('description', (v) => v as String?),
      estimatedMinutes: $checkedConvert(
        'estimated_minutes',
        (v) => (v as num).toInt(),
      ),
      completedMinutes: $checkedConvert(
        'completed_minutes',
        (v) => (v as num).toInt(),
      ),
      priority: $checkedConvert('priority', (v) => _priority(v)),
      deadline: $checkedConvert('deadline', (v) => v as String),
      deadlineKind: $checkedConvert(
        'deadline_kind',
        (v) =>
            $enumDecodeNullable(_$ItemDateKindEnumMap, v) ??
            ItemDateKind.deadline,
      ),
      earliestDate: $checkedConvert('earliest_date', (v) => v as String?),
      isFixed: $checkedConvert('is_fixed', (v) => v as bool),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$TaskStatusEnumMap, v),
      ),
      createdAt: $checkedConvert('created_at', (v) => v as String),
      updatedAt: $checkedConvert('updated_at', (v) => v as String),
      planning: $checkedConvert('planning', (v) => v as Map<String, dynamic>?),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'subjectId': 'subject_id',
    'estimatedMinutes': 'estimated_minutes',
    'completedMinutes': 'completed_minutes',
    'deadlineKind': 'deadline_kind',
    'earliestDate': 'earliest_date',
    'isFixed': 'is_fixed',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$TaskToJson(_Task instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'subject_id': instance.subjectId,
  'title': instance.title,
  'description': ?instance.description,
  'estimated_minutes': instance.estimatedMinutes,
  'completed_minutes': instance.completedMinutes,
  'priority': instance.priority,
  'deadline': instance.deadline,
  'deadline_kind': _$ItemDateKindEnumMap[instance.deadlineKind]!,
  'earliest_date': ?instance.earliestDate,
  'is_fixed': instance.isFixed,
  'status': _$TaskStatusEnumMap[instance.status]!,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'planning': ?instance.planning,
};

const _$ItemDateKindEnumMap = {
  ItemDateKind.deadline: 'deadline',
  ItemDateKind.planEnd: 'plan_end',
};

const _$TaskStatusEnumMap = {
  TaskStatus.notStarted: 'not_started',
  TaskStatus.inProgress: 'in_progress',
  TaskStatus.completed: 'completed',
  TaskStatus.delayed: 'delayed',
  TaskStatus.conflict: 'conflict',
  TaskStatus.archived: 'archived',
};

_ScheduleBlock _$ScheduleBlockFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      '_ScheduleBlock',
      json,
      ($checkedConvert) {
        final val = _ScheduleBlock(
          id: $checkedConvert('id', (v) => v as String),
          userId: $checkedConvert('user_id', (v) => v as String),
          taskId: $checkedConvert('task_id', (v) => v as String),
          date: $checkedConvert('date', (v) => v as String),
          startMinute: $checkedConvert(
            'start_minute',
            (v) => (v as num).toInt(),
          ),
          durationMinutes: $checkedConvert(
            'duration_minutes',
            (v) => (v as num).toInt(),
          ),
          actualMinutes: $checkedConvert(
            'actual_minutes',
            (v) => (v as num).toInt(),
          ),
          isFixed: $checkedConvert('is_fixed', (v) => v as bool),
          status: $checkedConvert(
            'status',
            (v) => $enumDecode(_$BlockStatusEnumMap, v),
          ),
          createdAt: $checkedConvert('created_at', (v) => v as String),
          updatedAt: $checkedConvert('updated_at', (v) => v as String),
          adviceText: $checkedConvert('advice_text', (v) => v as String?),
          adviceTopics: $checkedConvert(
            'advice_topics',
            (v) => (v as List<dynamic>?)?.map((e) => e as String).toList(),
          ),
          completionStatus: $checkedConvert(
            'completion_status',
            (v) => $enumDecodeNullable(_$CompletionStatusEnumMap, v),
          ),
          feedback: $checkedConvert('feedback', (v) => v as String?),
          activityInstanceId: $checkedConvert(
            'activity_instance_id',
            (v) => v as String?,
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'userId': 'user_id',
        'taskId': 'task_id',
        'startMinute': 'start_minute',
        'durationMinutes': 'duration_minutes',
        'actualMinutes': 'actual_minutes',
        'isFixed': 'is_fixed',
        'createdAt': 'created_at',
        'updatedAt': 'updated_at',
        'adviceText': 'advice_text',
        'adviceTopics': 'advice_topics',
        'completionStatus': 'completion_status',
        'activityInstanceId': 'activity_instance_id',
      },
    );

Map<String, dynamic> _$ScheduleBlockToJson(
  _ScheduleBlock instance,
) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'task_id': instance.taskId,
  'date': instance.date,
  'start_minute': instance.startMinute,
  'duration_minutes': instance.durationMinutes,
  'actual_minutes': instance.actualMinutes,
  'is_fixed': instance.isFixed,
  'status': _$BlockStatusEnumMap[instance.status]!,
  'created_at': instance.createdAt,
  'updated_at': instance.updatedAt,
  'advice_text': ?instance.adviceText,
  'advice_topics': ?instance.adviceTopics,
  'completion_status': ?_$CompletionStatusEnumMap[instance.completionStatus],
  'feedback': ?instance.feedback,
  'activity_instance_id': ?instance.activityInstanceId,
};

const _$BlockStatusEnumMap = {
  BlockStatus.planned: 'planned',
  BlockStatus.completed: 'completed',
};

const _$CompletionStatusEnumMap = {
  CompletionStatus.notStarted: 'not_started',
  CompletionStatus.partial: 'partial',
  CompletionStatus.completed: 'completed',
  CompletionStatus.skipped: 'skipped',
};

_TimeLog _$TimeLogFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_TimeLog',
  json,
  ($checkedConvert) {
    final val = _TimeLog(
      id: $checkedConvert('id', (v) => v as String),
      userId: $checkedConvert('user_id', (v) => v as String),
      taskId: $checkedConvert('task_id', (v) => v as String),
      blockId: $checkedConvert('block_id', (v) => v as String?),
      date: $checkedConvert('date', (v) => v as String),
      minutes: $checkedConvert('minutes', (v) => (v as num).toInt()),
      startedAt: $checkedConvert('started_at', (v) => v as String),
      endedAt: $checkedConvert('ended_at', (v) => v as String),
      source: $checkedConvert(
        'source',
        (v) => $enumDecode(_$LogSourceEnumMap, v),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'taskId': 'task_id',
    'blockId': 'block_id',
    'startedAt': 'started_at',
    'endedAt': 'ended_at',
  },
);

Map<String, dynamic> _$TimeLogToJson(_TimeLog instance) => <String, dynamic>{
  'id': instance.id,
  'user_id': instance.userId,
  'task_id': instance.taskId,
  'block_id': instance.blockId,
  'date': instance.date,
  'minutes': instance.minutes,
  'started_at': instance.startedAt,
  'ended_at': instance.endedAt,
  'source': _$LogSourceEnumMap[instance.source]!,
};

const _$LogSourceEnumMap = {
  LogSource.timer: 'timer',
  LogSource.manual: 'manual',
};

_FixedEvent _$FixedEventFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_FixedEvent',
  json,
  ($checkedConvert) {
    final val = _FixedEvent(
      id: $checkedConvert('id', (v) => v as String),
      userId: $checkedConvert('user_id', (v) => v as String),
      title: $checkedConvert('title', (v) => v as String),
      date: $checkedConvert('date', (v) => v as String),
      startMinute: $checkedConvert('start_minute', (v) => (v as num).toInt()),
      durationMinutes: $checkedConvert(
        'duration_minutes',
        (v) => (v as num).toInt(),
      ),
      kind: $checkedConvert(
        'kind',
        (v) => $enumDecode(_$FixedEventKindEnumMap, v),
      ),
      repeat: $checkedConvert(
        'repeat',
        (v) => $enumDecode(_$EventRepeatEnumMap, v),
      ),
      createdAt: $checkedConvert('created_at', (v) => v as String),
      updatedAt: $checkedConvert('updated_at', (v) => v as String),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'startMinute': 'start_minute',
    'durationMinutes': 'duration_minutes',
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
  },
);

Map<String, dynamic> _$FixedEventToJson(_FixedEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'title': instance.title,
      'date': instance.date,
      'start_minute': instance.startMinute,
      'duration_minutes': instance.durationMinutes,
      'kind': _$FixedEventKindEnumMap[instance.kind]!,
      'repeat': _$EventRepeatEnumMap[instance.repeat]!,
      'created_at': instance.createdAt,
      'updated_at': instance.updatedAt,
    };

const _$FixedEventKindEnumMap = {
  FixedEventKind.course: 'course',
  FixedEventKind.exam: 'exam',
  FixedEventKind.rest: 'rest',
  FixedEventKind.officialExam: 'official_exam',
};

const _$EventRepeatEnumMap = {
  EventRepeat.none: 'none',
  EventRepeat.daily: 'daily',
  EventRepeat.weekly: 'weekly',
};

_Phase _$PhaseFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_Phase', json, ($checkedConvert) {
      final val = _Phase(
        id: $checkedConvert('id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        start: $checkedConvert('start', (v) => v as String),
        end: $checkedConvert('end', (v) => v as String),
        description: $checkedConvert('description', (v) => v as String),
      );
      return val;
    });

Map<String, dynamic> _$PhaseToJson(_Phase instance) => <String, dynamic>{
  'id': instance.id,
  'title': instance.title,
  'start': instance.start,
  'end': instance.end,
  'description': instance.description,
};

_ReplanChange _$ReplanChangeFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      '_ReplanChange',
      json,
      ($checkedConvert) {
        final val = _ReplanChange(
          id: $checkedConvert('id', (v) => v as String),
          userId: $checkedConvert('user_id', (v) => v as String),
          runId: $checkedConvert('run_id', (v) => v as String),
          type: $checkedConvert(
            'type',
            (v) => $enumDecode(_$ChangeTypeEnumMap, v),
          ),
          blockId: $checkedConvert('block_id', (v) => v as String),
          before: $checkedConvert(
            'before',
            (v) => v == null
                ? null
                : ScheduleBlock.fromJson(v as Map<String, dynamic>),
          ),
          after: $checkedConvert(
            'after',
            (v) => v == null
                ? null
                : ScheduleBlock.fromJson(v as Map<String, dynamic>),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'userId': 'user_id',
        'runId': 'run_id',
        'blockId': 'block_id',
      },
    );

Map<String, dynamic> _$ReplanChangeToJson(_ReplanChange instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'run_id': instance.runId,
      'type': _$ChangeTypeEnumMap[instance.type]!,
      'block_id': instance.blockId,
      'before': instance.before?.toJson(),
      'after': instance.after?.toJson(),
    };

const _$ChangeTypeEnumMap = {
  ChangeType.added: 'added',
  ChangeType.deleted: 'deleted',
  ChangeType.moved: 'moved',
};

_Conflict _$ConflictFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_Conflict', json, ($checkedConvert) {
      final val = _Conflict(
        taskId: $checkedConvert('task_id', (v) => v as String),
        title: $checkedConvert('title', (v) => v as String),
        minutes: $checkedConvert('minutes', (v) => (v as num).toInt()),
        reason: $checkedConvert('reason', (v) => v as String),
      );
      return val;
    }, fieldKeyMap: const {'taskId': 'task_id'});

Map<String, dynamic> _$ConflictToJson(_Conflict instance) => <String, dynamic>{
  'task_id': instance.taskId,
  'title': instance.title,
  'minutes': instance.minutes,
  'reason': instance.reason,
};

_DayChange _$DayChangeFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_DayChange',
  json,
  ($checkedConvert) {
    final val = _DayChange(
      date: $checkedConvert('date', (v) => v as String),
      beforeMinutes: $checkedConvert(
        'before_minutes',
        (v) => (v as num).toInt(),
      ),
      afterMinutes: $checkedConvert('after_minutes', (v) => (v as num).toInt()),
    );
    return val;
  },
  fieldKeyMap: const {
    'beforeMinutes': 'before_minutes',
    'afterMinutes': 'after_minutes',
  },
);

Map<String, dynamic> _$DayChangeToJson(_DayChange instance) =>
    <String, dynamic>{
      'date': instance.date,
      'before_minutes': instance.beforeMinutes,
      'after_minutes': instance.afterMinutes,
    };

_TaskStatusSnapshot _$TaskStatusSnapshotFromJson(Map<String, dynamic> json) =>
    $checkedCreate('_TaskStatusSnapshot', json, ($checkedConvert) {
      final val = _TaskStatusSnapshot(
        id: $checkedConvert('id', (v) => v as String),
        status: $checkedConvert(
          'status',
          (v) => $enumDecode(_$TaskStatusEnumMap, v),
        ),
      );
      return val;
    });

Map<String, dynamic> _$TaskStatusSnapshotToJson(_TaskStatusSnapshot instance) =>
    <String, dynamic>{
      'id': instance.id,
      'status': _$TaskStatusEnumMap[instance.status]!,
    };

_ReplanPreview _$ReplanPreviewFromJson(Map<String, dynamic> json) =>
    $checkedCreate(
      '_ReplanPreview',
      json,
      ($checkedConvert) {
        final val = _ReplanPreview(
          id: $checkedConvert('id', (v) => v as String),
          userId: $checkedConvert('user_id', (v) => v as String),
          createdAt: $checkedConvert('created_at', (v) => v as String),
          before: $checkedConvert(
            'before',
            (v) => (v as List<dynamic>)
                .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          after: $checkedConvert(
            'after',
            (v) => (v as List<dynamic>)
                .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          changes: $checkedConvert(
            'changes',
            (v) => (v as List<dynamic>)
                .map((e) => ReplanChange.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          postponed: $checkedConvert(
            'postponed',
            (v) => (v as List<dynamic>).map((e) => e as String).toList(),
          ),
          advanced: $checkedConvert(
            'advanced',
            (v) => (v as List<dynamic>).map((e) => e as String).toList(),
          ),
          conflicts: $checkedConvert(
            'conflicts',
            (v) => (v as List<dynamic>)
                .map((e) => Conflict.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
          dailyChanges: $checkedConvert(
            'daily_changes',
            (v) => (v as List<dynamic>)
                .map((e) => DayChange.fromJson(e as Map<String, dynamic>))
                .toList(),
          ),
        );
        return val;
      },
      fieldKeyMap: const {
        'userId': 'user_id',
        'createdAt': 'created_at',
        'dailyChanges': 'daily_changes',
      },
    );

Map<String, dynamic> _$ReplanPreviewToJson(_ReplanPreview instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'created_at': instance.createdAt,
      'before': instance.before.map((e) => e.toJson()).toList(),
      'after': instance.after.map((e) => e.toJson()).toList(),
      'changes': instance.changes.map((e) => e.toJson()).toList(),
      'postponed': instance.postponed,
      'advanced': instance.advanced,
      'conflicts': instance.conflicts.map((e) => e.toJson()).toList(),
      'daily_changes': instance.dailyChanges.map((e) => e.toJson()).toList(),
    };

_ReplanRun _$ReplanRunFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_ReplanRun',
  json,
  ($checkedConvert) {
    final val = _ReplanRun(
      id: $checkedConvert('id', (v) => v as String),
      userId: $checkedConvert('user_id', (v) => v as String),
      createdAt: $checkedConvert('created_at', (v) => v as String),
      before: $checkedConvert(
        'before',
        (v) => (v as List<dynamic>)
            .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      after: $checkedConvert(
        'after',
        (v) => (v as List<dynamic>)
            .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      changes: $checkedConvert(
        'changes',
        (v) => (v as List<dynamic>)
            .map((e) => ReplanChange.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      postponed: $checkedConvert(
        'postponed',
        (v) => (v as List<dynamic>).map((e) => e as String).toList(),
      ),
      advanced: $checkedConvert(
        'advanced',
        (v) => (v as List<dynamic>).map((e) => e as String).toList(),
      ),
      conflicts: $checkedConvert(
        'conflicts',
        (v) => (v as List<dynamic>)
            .map((e) => Conflict.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      dailyChanges: $checkedConvert(
        'daily_changes',
        (v) => (v as List<dynamic>)
            .map((e) => DayChange.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      status: $checkedConvert(
        'status',
        (v) => $enumDecode(_$ReplanStatusEnumMap, v),
      ),
      taskStatusBefore: $checkedConvert(
        'task_status_before',
        (v) => (v as List<dynamic>?)
            ?.map((e) => TaskStatusSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      taskStatusAfter: $checkedConvert(
        'task_status_after',
        (v) => (v as List<dynamic>?)
            ?.map((e) => TaskStatusSnapshot.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      localUndoGuard: $checkedConvert(
        'local_undo_guard',
        (v) => v as Map<String, dynamic>?,
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'userId': 'user_id',
    'createdAt': 'created_at',
    'dailyChanges': 'daily_changes',
    'taskStatusBefore': 'task_status_before',
    'taskStatusAfter': 'task_status_after',
    'localUndoGuard': 'local_undo_guard',
  },
);

Map<String, dynamic> _$ReplanRunToJson(_ReplanRun instance) =>
    <String, dynamic>{
      'id': instance.id,
      'user_id': instance.userId,
      'created_at': instance.createdAt,
      'before': instance.before.map((e) => e.toJson()).toList(),
      'after': instance.after.map((e) => e.toJson()).toList(),
      'changes': instance.changes.map((e) => e.toJson()).toList(),
      'postponed': instance.postponed,
      'advanced': instance.advanced,
      'conflicts': instance.conflicts.map((e) => e.toJson()).toList(),
      'daily_changes': instance.dailyChanges.map((e) => e.toJson()).toList(),
      'status': _$ReplanStatusEnumMap[instance.status]!,
      'task_status_before': ?instance.taskStatusBefore
          ?.map((e) => e.toJson())
          .toList(),
      'task_status_after': ?instance.taskStatusAfter
          ?.map((e) => e.toJson())
          .toList(),
      'local_undo_guard': ?instance.localUndoGuard,
    };

const _$ReplanStatusEnumMap = {
  ReplanStatus.confirmed: 'confirmed',
  ReplanStatus.undone: 'undone',
};

_ReplanInput _$ReplanInputFromJson(Map<String, dynamic> json) => $checkedCreate(
  '_ReplanInput',
  json,
  ($checkedConvert) {
    final val = _ReplanInput(
      tasks: $checkedConvert(
        'tasks',
        (v) => (v as List<dynamic>)
            .map((e) => Task.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      blocks: $checkedConvert(
        'blocks',
        (v) => (v as List<dynamic>)
            .map((e) => ScheduleBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      logs: $checkedConvert(
        'logs',
        (v) => (v as List<dynamic>)
            .map((e) => TimeLog.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      fixedEvents: $checkedConvert(
        'fixed_events',
        (v) => (v as List<dynamic>)
            .map((e) => FixedEvent.fromJson(e as Map<String, dynamic>))
            .toList(),
      ),
      profile: $checkedConvert(
        'profile',
        (v) => Profile.fromJson(v as Map<String, dynamic>),
      ),
      today: $checkedConvert('today', (v) => v as String),
      mode: $checkedConvert('mode', (v) => $enumDecode(_$ReplanModeEnumMap, v)),
      excessMinutes: $checkedConvert(
        'excess_minutes',
        (v) => (v as num?)?.toInt(),
      ),
    );
    return val;
  },
  fieldKeyMap: const {
    'fixedEvents': 'fixed_events',
    'excessMinutes': 'excess_minutes',
  },
);

Map<String, dynamic> _$ReplanInputToJson(_ReplanInput instance) =>
    <String, dynamic>{
      'tasks': instance.tasks.map((e) => e.toJson()).toList(),
      'blocks': instance.blocks.map((e) => e.toJson()).toList(),
      'logs': instance.logs.map((e) => e.toJson()).toList(),
      'fixed_events': instance.fixedEvents.map((e) => e.toJson()).toList(),
      'profile': instance.profile.toJson(),
      'today': instance.today,
      'mode': _$ReplanModeEnumMap[instance.mode]!,
      'excess_minutes': ?instance.excessMinutes,
    };

const _$ReplanModeEnumMap = {
  ReplanMode.unfinished: 'unfinished',
  ReplanMode.overcompleted: 'overcompleted',
};

_SyncMetadata _$SyncMetadataFromJson(
  Map<String, dynamic> json,
) => $checkedCreate('_SyncMetadata', json, ($checkedConvert) {
  final val = _SyncMetadata(
    version: $checkedConvert('version', (v) => v == null ? 1 : _versionOne(v)),
    revision: $checkedConvert('revision', (v) => v == null ? 0 : _revision(v)),
    pending: $checkedConvert('pending', (v) => v as bool? ?? false),
    base: $checkedConvert(
      'base',
      (v) => v == null ? null : PlannerData.fromJson(v as Map<String, dynamic>),
    ),
    updatedAt: $checkedConvert(
      'updatedAt',
      (v) => v == null ? null : DateTime.parse(v as String),
    ),
  );
  return val;
});

Map<String, dynamic> _$SyncMetadataToJson(_SyncMetadata instance) =>
    <String, dynamic>{
      'version': instance.version,
      'revision': instance.revision,
      'pending': instance.pending,
      'base': instance.base?.toJson(),
      'updatedAt': instance.updatedAt?.toIso8601String(),
    };
