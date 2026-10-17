// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'planner_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$PlannerData {

@JsonKey(fromJson: _versionOne) int get version; Profile get profile; List<Subject> get subjects; List<Task> get tasks; List<ScheduleBlock> get blocks; List<TimeLog> get logs; List<FixedEvent> get fixedEvents; List<ReplanRun> get replanRuns; List<Phase> get phases; Map<String, String>? get dailyFeedback;
/// Create a copy of PlannerData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlannerDataCopyWith<PlannerData> get copyWith => _$PlannerDataCopyWithImpl<PlannerData>(this as PlannerData, _$identity);

  /// Serializes this PlannerData to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlannerData&&(identical(other.version, version) || other.version == version)&&(identical(other.profile, profile) || other.profile == profile)&&const DeepCollectionEquality().equals(other.subjects, subjects)&&const DeepCollectionEquality().equals(other.tasks, tasks)&&const DeepCollectionEquality().equals(other.blocks, blocks)&&const DeepCollectionEquality().equals(other.logs, logs)&&const DeepCollectionEquality().equals(other.fixedEvents, fixedEvents)&&const DeepCollectionEquality().equals(other.replanRuns, replanRuns)&&const DeepCollectionEquality().equals(other.phases, phases)&&const DeepCollectionEquality().equals(other.dailyFeedback, dailyFeedback));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,version,profile,const DeepCollectionEquality().hash(subjects),const DeepCollectionEquality().hash(tasks),const DeepCollectionEquality().hash(blocks),const DeepCollectionEquality().hash(logs),const DeepCollectionEquality().hash(fixedEvents),const DeepCollectionEquality().hash(replanRuns),const DeepCollectionEquality().hash(phases),const DeepCollectionEquality().hash(dailyFeedback));

@override
String toString() {
  return 'PlannerData(version: $version, profile: $profile, subjects: $subjects, tasks: $tasks, blocks: $blocks, logs: $logs, fixedEvents: $fixedEvents, replanRuns: $replanRuns, phases: $phases, dailyFeedback: $dailyFeedback)';
}


}

/// @nodoc
abstract mixin class $PlannerDataCopyWith<$Res>  {
  factory $PlannerDataCopyWith(PlannerData value, $Res Function(PlannerData) _then) = _$PlannerDataCopyWithImpl;
@useResult
$Res call({
@JsonKey(fromJson: _versionOne) int version, Profile profile, List<Subject> subjects, List<Task> tasks, List<ScheduleBlock> blocks, List<TimeLog> logs, List<FixedEvent> fixedEvents, List<ReplanRun> replanRuns, List<Phase> phases, Map<String, String>? dailyFeedback
});


$ProfileCopyWith<$Res> get profile;

}
/// @nodoc
class _$PlannerDataCopyWithImpl<$Res>
    implements $PlannerDataCopyWith<$Res> {
  _$PlannerDataCopyWithImpl(this._self, this._then);

  final PlannerData _self;
  final $Res Function(PlannerData) _then;

/// Create a copy of PlannerData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? profile = null,Object? subjects = null,Object? tasks = null,Object? blocks = null,Object? logs = null,Object? fixedEvents = null,Object? replanRuns = null,Object? phases = null,Object? dailyFeedback = freezed,}) {
  return _then(_self.copyWith(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as Profile,subjects: null == subjects ? _self.subjects : subjects // ignore: cast_nullable_to_non_nullable
as List<Subject>,tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<Task>,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,logs: null == logs ? _self.logs : logs // ignore: cast_nullable_to_non_nullable
as List<TimeLog>,fixedEvents: null == fixedEvents ? _self.fixedEvents : fixedEvents // ignore: cast_nullable_to_non_nullable
as List<FixedEvent>,replanRuns: null == replanRuns ? _self.replanRuns : replanRuns // ignore: cast_nullable_to_non_nullable
as List<ReplanRun>,phases: null == phases ? _self.phases : phases // ignore: cast_nullable_to_non_nullable
as List<Phase>,dailyFeedback: freezed == dailyFeedback ? _self.dailyFeedback : dailyFeedback // ignore: cast_nullable_to_non_nullable
as Map<String, String>?,
  ));
}
/// Create a copy of PlannerData
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res> get profile {
  
  return $ProfileCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// Adds pattern-matching-related methods to [PlannerData].
extension PlannerDataPatterns on PlannerData {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlannerData value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlannerData() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlannerData value)  $default,){
final _that = this;
switch (_that) {
case _PlannerData():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlannerData value)?  $default,){
final _that = this;
switch (_that) {
case _PlannerData() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(fromJson: _versionOne)  int version,  Profile profile,  List<Subject> subjects,  List<Task> tasks,  List<ScheduleBlock> blocks,  List<TimeLog> logs,  List<FixedEvent> fixedEvents,  List<ReplanRun> replanRuns,  List<Phase> phases,  Map<String, String>? dailyFeedback)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlannerData() when $default != null:
return $default(_that.version,_that.profile,_that.subjects,_that.tasks,_that.blocks,_that.logs,_that.fixedEvents,_that.replanRuns,_that.phases,_that.dailyFeedback);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(fromJson: _versionOne)  int version,  Profile profile,  List<Subject> subjects,  List<Task> tasks,  List<ScheduleBlock> blocks,  List<TimeLog> logs,  List<FixedEvent> fixedEvents,  List<ReplanRun> replanRuns,  List<Phase> phases,  Map<String, String>? dailyFeedback)  $default,) {final _that = this;
switch (_that) {
case _PlannerData():
return $default(_that.version,_that.profile,_that.subjects,_that.tasks,_that.blocks,_that.logs,_that.fixedEvents,_that.replanRuns,_that.phases,_that.dailyFeedback);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(fromJson: _versionOne)  int version,  Profile profile,  List<Subject> subjects,  List<Task> tasks,  List<ScheduleBlock> blocks,  List<TimeLog> logs,  List<FixedEvent> fixedEvents,  List<ReplanRun> replanRuns,  List<Phase> phases,  Map<String, String>? dailyFeedback)?  $default,) {final _that = this;
switch (_that) {
case _PlannerData() when $default != null:
return $default(_that.version,_that.profile,_that.subjects,_that.tasks,_that.blocks,_that.logs,_that.fixedEvents,_that.replanRuns,_that.phases,_that.dailyFeedback);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlannerData extends PlannerData {
  const _PlannerData({@JsonKey(fromJson: _versionOne) required this.version, required this.profile, required final  List<Subject> subjects, required final  List<Task> tasks, required final  List<ScheduleBlock> blocks, required final  List<TimeLog> logs, required final  List<FixedEvent> fixedEvents, required final  List<ReplanRun> replanRuns, required final  List<Phase> phases, final  Map<String, String>? dailyFeedback}): _subjects = subjects,_tasks = tasks,_blocks = blocks,_logs = logs,_fixedEvents = fixedEvents,_replanRuns = replanRuns,_phases = phases,_dailyFeedback = dailyFeedback,super._();
  factory _PlannerData.fromJson(Map<String, dynamic> json) => _$PlannerDataFromJson(json);

@override@JsonKey(fromJson: _versionOne) final  int version;
@override final  Profile profile;
 final  List<Subject> _subjects;
@override List<Subject> get subjects {
  if (_subjects is EqualUnmodifiableListView) return _subjects;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_subjects);
}

 final  List<Task> _tasks;
@override List<Task> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}

 final  List<ScheduleBlock> _blocks;
@override List<ScheduleBlock> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}

 final  List<TimeLog> _logs;
@override List<TimeLog> get logs {
  if (_logs is EqualUnmodifiableListView) return _logs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_logs);
}

 final  List<FixedEvent> _fixedEvents;
@override List<FixedEvent> get fixedEvents {
  if (_fixedEvents is EqualUnmodifiableListView) return _fixedEvents;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_fixedEvents);
}

 final  List<ReplanRun> _replanRuns;
@override List<ReplanRun> get replanRuns {
  if (_replanRuns is EqualUnmodifiableListView) return _replanRuns;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_replanRuns);
}

 final  List<Phase> _phases;
@override List<Phase> get phases {
  if (_phases is EqualUnmodifiableListView) return _phases;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_phases);
}

 final  Map<String, String>? _dailyFeedback;
@override Map<String, String>? get dailyFeedback {
  final value = _dailyFeedback;
  if (value == null) return null;
  if (_dailyFeedback is EqualUnmodifiableMapView) return _dailyFeedback;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of PlannerData
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlannerDataCopyWith<_PlannerData> get copyWith => __$PlannerDataCopyWithImpl<_PlannerData>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlannerDataToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlannerData&&(identical(other.version, version) || other.version == version)&&(identical(other.profile, profile) || other.profile == profile)&&const DeepCollectionEquality().equals(other._subjects, _subjects)&&const DeepCollectionEquality().equals(other._tasks, _tasks)&&const DeepCollectionEquality().equals(other._blocks, _blocks)&&const DeepCollectionEquality().equals(other._logs, _logs)&&const DeepCollectionEquality().equals(other._fixedEvents, _fixedEvents)&&const DeepCollectionEquality().equals(other._replanRuns, _replanRuns)&&const DeepCollectionEquality().equals(other._phases, _phases)&&const DeepCollectionEquality().equals(other._dailyFeedback, _dailyFeedback));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,version,profile,const DeepCollectionEquality().hash(_subjects),const DeepCollectionEquality().hash(_tasks),const DeepCollectionEquality().hash(_blocks),const DeepCollectionEquality().hash(_logs),const DeepCollectionEquality().hash(_fixedEvents),const DeepCollectionEquality().hash(_replanRuns),const DeepCollectionEquality().hash(_phases),const DeepCollectionEquality().hash(_dailyFeedback));

@override
String toString() {
  return 'PlannerData(version: $version, profile: $profile, subjects: $subjects, tasks: $tasks, blocks: $blocks, logs: $logs, fixedEvents: $fixedEvents, replanRuns: $replanRuns, phases: $phases, dailyFeedback: $dailyFeedback)';
}


}

/// @nodoc
abstract mixin class _$PlannerDataCopyWith<$Res> implements $PlannerDataCopyWith<$Res> {
  factory _$PlannerDataCopyWith(_PlannerData value, $Res Function(_PlannerData) _then) = __$PlannerDataCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(fromJson: _versionOne) int version, Profile profile, List<Subject> subjects, List<Task> tasks, List<ScheduleBlock> blocks, List<TimeLog> logs, List<FixedEvent> fixedEvents, List<ReplanRun> replanRuns, List<Phase> phases, Map<String, String>? dailyFeedback
});


@override $ProfileCopyWith<$Res> get profile;

}
/// @nodoc
class __$PlannerDataCopyWithImpl<$Res>
    implements _$PlannerDataCopyWith<$Res> {
  __$PlannerDataCopyWithImpl(this._self, this._then);

  final _PlannerData _self;
  final $Res Function(_PlannerData) _then;

/// Create a copy of PlannerData
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? profile = null,Object? subjects = null,Object? tasks = null,Object? blocks = null,Object? logs = null,Object? fixedEvents = null,Object? replanRuns = null,Object? phases = null,Object? dailyFeedback = freezed,}) {
  return _then(_PlannerData(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as Profile,subjects: null == subjects ? _self._subjects : subjects // ignore: cast_nullable_to_non_nullable
as List<Subject>,tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<Task>,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,logs: null == logs ? _self._logs : logs // ignore: cast_nullable_to_non_nullable
as List<TimeLog>,fixedEvents: null == fixedEvents ? _self._fixedEvents : fixedEvents // ignore: cast_nullable_to_non_nullable
as List<FixedEvent>,replanRuns: null == replanRuns ? _self._replanRuns : replanRuns // ignore: cast_nullable_to_non_nullable
as List<ReplanRun>,phases: null == phases ? _self._phases : phases // ignore: cast_nullable_to_non_nullable
as List<Phase>,dailyFeedback: freezed == dailyFeedback ? _self._dailyFeedback : dailyFeedback // ignore: cast_nullable_to_non_nullable
as Map<String, String>?,
  ));
}

/// Create a copy of PlannerData
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res> get profile {
  
  return $ProfileCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// @nodoc
mixin _$Profile {

 String get userId;@JsonKey(name: 'planning_mode') PlanningMode? get storedPlanningMode; String get targetSchool; String get targetProgram; String get examDate; String get examEndDate; int get dailyLimitMinutes; int get granularityMinutes; int get bufferMinutes; int get subjectLimitMinutes; int get studyStartMinute; int get studyEndMinute; String get foundation;
/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileCopyWith<Profile> get copyWith => _$ProfileCopyWithImpl<Profile>(this as Profile, _$identity);

  /// Serializes this Profile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Profile&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.storedPlanningMode, storedPlanningMode) || other.storedPlanningMode == storedPlanningMode)&&(identical(other.targetSchool, targetSchool) || other.targetSchool == targetSchool)&&(identical(other.targetProgram, targetProgram) || other.targetProgram == targetProgram)&&(identical(other.examDate, examDate) || other.examDate == examDate)&&(identical(other.examEndDate, examEndDate) || other.examEndDate == examEndDate)&&(identical(other.dailyLimitMinutes, dailyLimitMinutes) || other.dailyLimitMinutes == dailyLimitMinutes)&&(identical(other.granularityMinutes, granularityMinutes) || other.granularityMinutes == granularityMinutes)&&(identical(other.bufferMinutes, bufferMinutes) || other.bufferMinutes == bufferMinutes)&&(identical(other.subjectLimitMinutes, subjectLimitMinutes) || other.subjectLimitMinutes == subjectLimitMinutes)&&(identical(other.studyStartMinute, studyStartMinute) || other.studyStartMinute == studyStartMinute)&&(identical(other.studyEndMinute, studyEndMinute) || other.studyEndMinute == studyEndMinute)&&(identical(other.foundation, foundation) || other.foundation == foundation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,userId,storedPlanningMode,targetSchool,targetProgram,examDate,examEndDate,dailyLimitMinutes,granularityMinutes,bufferMinutes,subjectLimitMinutes,studyStartMinute,studyEndMinute,foundation);

@override
String toString() {
  return 'Profile(userId: $userId, storedPlanningMode: $storedPlanningMode, targetSchool: $targetSchool, targetProgram: $targetProgram, examDate: $examDate, examEndDate: $examEndDate, dailyLimitMinutes: $dailyLimitMinutes, granularityMinutes: $granularityMinutes, bufferMinutes: $bufferMinutes, subjectLimitMinutes: $subjectLimitMinutes, studyStartMinute: $studyStartMinute, studyEndMinute: $studyEndMinute, foundation: $foundation)';
}


}

/// @nodoc
abstract mixin class $ProfileCopyWith<$Res>  {
  factory $ProfileCopyWith(Profile value, $Res Function(Profile) _then) = _$ProfileCopyWithImpl;
@useResult
$Res call({
 String userId,@JsonKey(name: 'planning_mode') PlanningMode? storedPlanningMode, String targetSchool, String targetProgram, String examDate, String examEndDate, int dailyLimitMinutes, int granularityMinutes, int bufferMinutes, int subjectLimitMinutes, int studyStartMinute, int studyEndMinute, String foundation
});




}
/// @nodoc
class _$ProfileCopyWithImpl<$Res>
    implements $ProfileCopyWith<$Res> {
  _$ProfileCopyWithImpl(this._self, this._then);

  final Profile _self;
  final $Res Function(Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? userId = null,Object? storedPlanningMode = freezed,Object? targetSchool = null,Object? targetProgram = null,Object? examDate = null,Object? examEndDate = null,Object? dailyLimitMinutes = null,Object? granularityMinutes = null,Object? bufferMinutes = null,Object? subjectLimitMinutes = null,Object? studyStartMinute = null,Object? studyEndMinute = null,Object? foundation = null,}) {
  return _then(_self.copyWith(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,storedPlanningMode: freezed == storedPlanningMode ? _self.storedPlanningMode : storedPlanningMode // ignore: cast_nullable_to_non_nullable
as PlanningMode?,targetSchool: null == targetSchool ? _self.targetSchool : targetSchool // ignore: cast_nullable_to_non_nullable
as String,targetProgram: null == targetProgram ? _self.targetProgram : targetProgram // ignore: cast_nullable_to_non_nullable
as String,examDate: null == examDate ? _self.examDate : examDate // ignore: cast_nullable_to_non_nullable
as String,examEndDate: null == examEndDate ? _self.examEndDate : examEndDate // ignore: cast_nullable_to_non_nullable
as String,dailyLimitMinutes: null == dailyLimitMinutes ? _self.dailyLimitMinutes : dailyLimitMinutes // ignore: cast_nullable_to_non_nullable
as int,granularityMinutes: null == granularityMinutes ? _self.granularityMinutes : granularityMinutes // ignore: cast_nullable_to_non_nullable
as int,bufferMinutes: null == bufferMinutes ? _self.bufferMinutes : bufferMinutes // ignore: cast_nullable_to_non_nullable
as int,subjectLimitMinutes: null == subjectLimitMinutes ? _self.subjectLimitMinutes : subjectLimitMinutes // ignore: cast_nullable_to_non_nullable
as int,studyStartMinute: null == studyStartMinute ? _self.studyStartMinute : studyStartMinute // ignore: cast_nullable_to_non_nullable
as int,studyEndMinute: null == studyEndMinute ? _self.studyEndMinute : studyEndMinute // ignore: cast_nullable_to_non_nullable
as int,foundation: null == foundation ? _self.foundation : foundation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Profile].
extension ProfilePatterns on Profile {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Profile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Profile value)  $default,){
final _that = this;
switch (_that) {
case _Profile():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Profile value)?  $default,){
final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String userId, @JsonKey(name: 'planning_mode')  PlanningMode? storedPlanningMode,  String targetSchool,  String targetProgram,  String examDate,  String examEndDate,  int dailyLimitMinutes,  int granularityMinutes,  int bufferMinutes,  int subjectLimitMinutes,  int studyStartMinute,  int studyEndMinute,  String foundation)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.userId,_that.storedPlanningMode,_that.targetSchool,_that.targetProgram,_that.examDate,_that.examEndDate,_that.dailyLimitMinutes,_that.granularityMinutes,_that.bufferMinutes,_that.subjectLimitMinutes,_that.studyStartMinute,_that.studyEndMinute,_that.foundation);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String userId, @JsonKey(name: 'planning_mode')  PlanningMode? storedPlanningMode,  String targetSchool,  String targetProgram,  String examDate,  String examEndDate,  int dailyLimitMinutes,  int granularityMinutes,  int bufferMinutes,  int subjectLimitMinutes,  int studyStartMinute,  int studyEndMinute,  String foundation)  $default,) {final _that = this;
switch (_that) {
case _Profile():
return $default(_that.userId,_that.storedPlanningMode,_that.targetSchool,_that.targetProgram,_that.examDate,_that.examEndDate,_that.dailyLimitMinutes,_that.granularityMinutes,_that.bufferMinutes,_that.subjectLimitMinutes,_that.studyStartMinute,_that.studyEndMinute,_that.foundation);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String userId, @JsonKey(name: 'planning_mode')  PlanningMode? storedPlanningMode,  String targetSchool,  String targetProgram,  String examDate,  String examEndDate,  int dailyLimitMinutes,  int granularityMinutes,  int bufferMinutes,  int subjectLimitMinutes,  int studyStartMinute,  int studyEndMinute,  String foundation)?  $default,) {final _that = this;
switch (_that) {
case _Profile() when $default != null:
return $default(_that.userId,_that.storedPlanningMode,_that.targetSchool,_that.targetProgram,_that.examDate,_that.examEndDate,_that.dailyLimitMinutes,_that.granularityMinutes,_that.bufferMinutes,_that.subjectLimitMinutes,_that.studyStartMinute,_that.studyEndMinute,_that.foundation);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Profile extends Profile {
  const _Profile({required this.userId, @JsonKey(name: 'planning_mode') this.storedPlanningMode, required this.targetSchool, required this.targetProgram, required this.examDate, required this.examEndDate, required this.dailyLimitMinutes, required this.granularityMinutes, required this.bufferMinutes, required this.subjectLimitMinutes, required this.studyStartMinute, required this.studyEndMinute, required this.foundation}): super._();
  factory _Profile.fromJson(Map<String, dynamic> json) => _$ProfileFromJson(json);

@override final  String userId;
@override@JsonKey(name: 'planning_mode') final  PlanningMode? storedPlanningMode;
@override final  String targetSchool;
@override final  String targetProgram;
@override final  String examDate;
@override final  String examEndDate;
@override final  int dailyLimitMinutes;
@override final  int granularityMinutes;
@override final  int bufferMinutes;
@override final  int subjectLimitMinutes;
@override final  int studyStartMinute;
@override final  int studyEndMinute;
@override final  String foundation;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileCopyWith<_Profile> get copyWith => __$ProfileCopyWithImpl<_Profile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Profile&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.storedPlanningMode, storedPlanningMode) || other.storedPlanningMode == storedPlanningMode)&&(identical(other.targetSchool, targetSchool) || other.targetSchool == targetSchool)&&(identical(other.targetProgram, targetProgram) || other.targetProgram == targetProgram)&&(identical(other.examDate, examDate) || other.examDate == examDate)&&(identical(other.examEndDate, examEndDate) || other.examEndDate == examEndDate)&&(identical(other.dailyLimitMinutes, dailyLimitMinutes) || other.dailyLimitMinutes == dailyLimitMinutes)&&(identical(other.granularityMinutes, granularityMinutes) || other.granularityMinutes == granularityMinutes)&&(identical(other.bufferMinutes, bufferMinutes) || other.bufferMinutes == bufferMinutes)&&(identical(other.subjectLimitMinutes, subjectLimitMinutes) || other.subjectLimitMinutes == subjectLimitMinutes)&&(identical(other.studyStartMinute, studyStartMinute) || other.studyStartMinute == studyStartMinute)&&(identical(other.studyEndMinute, studyEndMinute) || other.studyEndMinute == studyEndMinute)&&(identical(other.foundation, foundation) || other.foundation == foundation));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,userId,storedPlanningMode,targetSchool,targetProgram,examDate,examEndDate,dailyLimitMinutes,granularityMinutes,bufferMinutes,subjectLimitMinutes,studyStartMinute,studyEndMinute,foundation);

@override
String toString() {
  return 'Profile(userId: $userId, storedPlanningMode: $storedPlanningMode, targetSchool: $targetSchool, targetProgram: $targetProgram, examDate: $examDate, examEndDate: $examEndDate, dailyLimitMinutes: $dailyLimitMinutes, granularityMinutes: $granularityMinutes, bufferMinutes: $bufferMinutes, subjectLimitMinutes: $subjectLimitMinutes, studyStartMinute: $studyStartMinute, studyEndMinute: $studyEndMinute, foundation: $foundation)';
}


}

/// @nodoc
abstract mixin class _$ProfileCopyWith<$Res> implements $ProfileCopyWith<$Res> {
  factory _$ProfileCopyWith(_Profile value, $Res Function(_Profile) _then) = __$ProfileCopyWithImpl;
@override @useResult
$Res call({
 String userId,@JsonKey(name: 'planning_mode') PlanningMode? storedPlanningMode, String targetSchool, String targetProgram, String examDate, String examEndDate, int dailyLimitMinutes, int granularityMinutes, int bufferMinutes, int subjectLimitMinutes, int studyStartMinute, int studyEndMinute, String foundation
});




}
/// @nodoc
class __$ProfileCopyWithImpl<$Res>
    implements _$ProfileCopyWith<$Res> {
  __$ProfileCopyWithImpl(this._self, this._then);

  final _Profile _self;
  final $Res Function(_Profile) _then;

/// Create a copy of Profile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? userId = null,Object? storedPlanningMode = freezed,Object? targetSchool = null,Object? targetProgram = null,Object? examDate = null,Object? examEndDate = null,Object? dailyLimitMinutes = null,Object? granularityMinutes = null,Object? bufferMinutes = null,Object? subjectLimitMinutes = null,Object? studyStartMinute = null,Object? studyEndMinute = null,Object? foundation = null,}) {
  return _then(_Profile(
userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,storedPlanningMode: freezed == storedPlanningMode ? _self.storedPlanningMode : storedPlanningMode // ignore: cast_nullable_to_non_nullable
as PlanningMode?,targetSchool: null == targetSchool ? _self.targetSchool : targetSchool // ignore: cast_nullable_to_non_nullable
as String,targetProgram: null == targetProgram ? _self.targetProgram : targetProgram // ignore: cast_nullable_to_non_nullable
as String,examDate: null == examDate ? _self.examDate : examDate // ignore: cast_nullable_to_non_nullable
as String,examEndDate: null == examEndDate ? _self.examEndDate : examEndDate // ignore: cast_nullable_to_non_nullable
as String,dailyLimitMinutes: null == dailyLimitMinutes ? _self.dailyLimitMinutes : dailyLimitMinutes // ignore: cast_nullable_to_non_nullable
as int,granularityMinutes: null == granularityMinutes ? _self.granularityMinutes : granularityMinutes // ignore: cast_nullable_to_non_nullable
as int,bufferMinutes: null == bufferMinutes ? _self.bufferMinutes : bufferMinutes // ignore: cast_nullable_to_non_nullable
as int,subjectLimitMinutes: null == subjectLimitMinutes ? _self.subjectLimitMinutes : subjectLimitMinutes // ignore: cast_nullable_to_non_nullable
as int,studyStartMinute: null == studyStartMinute ? _self.studyStartMinute : studyStartMinute // ignore: cast_nullable_to_non_nullable
as int,studyEndMinute: null == studyEndMinute ? _self.studyEndMinute : studyEndMinute // ignore: cast_nullable_to_non_nullable
as int,foundation: null == foundation ? _self.foundation : foundation // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$Subject {

 String get id; String get userId; String get name; String get color;@JsonKey(fromJson: _priority) int get priority;
/// Create a copy of Subject
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubjectCopyWith<Subject> get copyWith => _$SubjectCopyWithImpl<Subject>(this as Subject, _$identity);

  /// Serializes this Subject to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Subject&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&(identical(other.priority, priority) || other.priority == priority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,name,color,priority);

@override
String toString() {
  return 'Subject(id: $id, userId: $userId, name: $name, color: $color, priority: $priority)';
}


}

/// @nodoc
abstract mixin class $SubjectCopyWith<$Res>  {
  factory $SubjectCopyWith(Subject value, $Res Function(Subject) _then) = _$SubjectCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String name, String color,@JsonKey(fromJson: _priority) int priority
});




}
/// @nodoc
class _$SubjectCopyWithImpl<$Res>
    implements $SubjectCopyWith<$Res> {
  _$SubjectCopyWithImpl(this._self, this._then);

  final Subject _self;
  final $Res Function(Subject) _then;

/// Create a copy of Subject
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? name = null,Object? color = null,Object? priority = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [Subject].
extension SubjectPatterns on Subject {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Subject value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Subject() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Subject value)  $default,){
final _that = this;
switch (_that) {
case _Subject():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Subject value)?  $default,){
final _that = this;
switch (_that) {
case _Subject() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String name,  String color, @JsonKey(fromJson: _priority)  int priority)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Subject() when $default != null:
return $default(_that.id,_that.userId,_that.name,_that.color,_that.priority);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String name,  String color, @JsonKey(fromJson: _priority)  int priority)  $default,) {final _that = this;
switch (_that) {
case _Subject():
return $default(_that.id,_that.userId,_that.name,_that.color,_that.priority);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String name,  String color, @JsonKey(fromJson: _priority)  int priority)?  $default,) {final _that = this;
switch (_that) {
case _Subject() when $default != null:
return $default(_that.id,_that.userId,_that.name,_that.color,_that.priority);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Subject implements Subject {
  const _Subject({required this.id, required this.userId, required this.name, required this.color, @JsonKey(fromJson: _priority) required this.priority});
  factory _Subject.fromJson(Map<String, dynamic> json) => _$SubjectFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String name;
@override final  String color;
@override@JsonKey(fromJson: _priority) final  int priority;

/// Create a copy of Subject
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SubjectCopyWith<_Subject> get copyWith => __$SubjectCopyWithImpl<_Subject>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SubjectToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Subject&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.name, name) || other.name == name)&&(identical(other.color, color) || other.color == color)&&(identical(other.priority, priority) || other.priority == priority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,name,color,priority);

@override
String toString() {
  return 'Subject(id: $id, userId: $userId, name: $name, color: $color, priority: $priority)';
}


}

/// @nodoc
abstract mixin class _$SubjectCopyWith<$Res> implements $SubjectCopyWith<$Res> {
  factory _$SubjectCopyWith(_Subject value, $Res Function(_Subject) _then) = __$SubjectCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String name, String color,@JsonKey(fromJson: _priority) int priority
});




}
/// @nodoc
class __$SubjectCopyWithImpl<$Res>
    implements _$SubjectCopyWith<$Res> {
  __$SubjectCopyWithImpl(this._self, this._then);

  final _Subject _self;
  final $Res Function(_Subject) _then;

/// Create a copy of Subject
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? name = null,Object? color = null,Object? priority = null,}) {
  return _then(_Subject(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,color: null == color ? _self.color : color // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$Task {

 String get id; String get userId; String get subjectId; String get title; String? get description; int get estimatedMinutes; int get completedMinutes;@JsonKey(fromJson: _priority) int get priority; String get deadline; String? get earliestDate; bool get isFixed; TaskStatus get status; String get createdAt; String get updatedAt;
/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskCopyWith<Task> get copyWith => _$TaskCopyWithImpl<Task>(this as Task, _$identity);

  /// Serializes this Task to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Task&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.subjectId, subjectId) || other.subjectId == subjectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.estimatedMinutes, estimatedMinutes) || other.estimatedMinutes == estimatedMinutes)&&(identical(other.completedMinutes, completedMinutes) || other.completedMinutes == completedMinutes)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.earliestDate, earliestDate) || other.earliestDate == earliestDate)&&(identical(other.isFixed, isFixed) || other.isFixed == isFixed)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,subjectId,title,description,estimatedMinutes,completedMinutes,priority,deadline,earliestDate,isFixed,status,createdAt,updatedAt);

@override
String toString() {
  return 'Task(id: $id, userId: $userId, subjectId: $subjectId, title: $title, description: $description, estimatedMinutes: $estimatedMinutes, completedMinutes: $completedMinutes, priority: $priority, deadline: $deadline, earliestDate: $earliestDate, isFixed: $isFixed, status: $status, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $TaskCopyWith<$Res>  {
  factory $TaskCopyWith(Task value, $Res Function(Task) _then) = _$TaskCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String subjectId, String title, String? description, int estimatedMinutes, int completedMinutes,@JsonKey(fromJson: _priority) int priority, String deadline, String? earliestDate, bool isFixed, TaskStatus status, String createdAt, String updatedAt
});




}
/// @nodoc
class _$TaskCopyWithImpl<$Res>
    implements $TaskCopyWith<$Res> {
  _$TaskCopyWithImpl(this._self, this._then);

  final Task _self;
  final $Res Function(Task) _then;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? subjectId = null,Object? title = null,Object? description = freezed,Object? estimatedMinutes = null,Object? completedMinutes = null,Object? priority = null,Object? deadline = null,Object? earliestDate = freezed,Object? isFixed = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,subjectId: null == subjectId ? _self.subjectId : subjectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,estimatedMinutes: null == estimatedMinutes ? _self.estimatedMinutes : estimatedMinutes // ignore: cast_nullable_to_non_nullable
as int,completedMinutes: null == completedMinutes ? _self.completedMinutes : completedMinutes // ignore: cast_nullable_to_non_nullable
as int,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,deadline: null == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as String,earliestDate: freezed == earliestDate ? _self.earliestDate : earliestDate // ignore: cast_nullable_to_non_nullable
as String?,isFixed: null == isFixed ? _self.isFixed : isFixed // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Task].
extension TaskPatterns on Task {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Task value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Task value)  $default,){
final _that = this;
switch (_that) {
case _Task():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Task value)?  $default,){
final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String subjectId,  String title,  String? description,  int estimatedMinutes,  int completedMinutes, @JsonKey(fromJson: _priority)  int priority,  String deadline,  String? earliestDate,  bool isFixed,  TaskStatus status,  String createdAt,  String updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that.id,_that.userId,_that.subjectId,_that.title,_that.description,_that.estimatedMinutes,_that.completedMinutes,_that.priority,_that.deadline,_that.earliestDate,_that.isFixed,_that.status,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String subjectId,  String title,  String? description,  int estimatedMinutes,  int completedMinutes, @JsonKey(fromJson: _priority)  int priority,  String deadline,  String? earliestDate,  bool isFixed,  TaskStatus status,  String createdAt,  String updatedAt)  $default,) {final _that = this;
switch (_that) {
case _Task():
return $default(_that.id,_that.userId,_that.subjectId,_that.title,_that.description,_that.estimatedMinutes,_that.completedMinutes,_that.priority,_that.deadline,_that.earliestDate,_that.isFixed,_that.status,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String subjectId,  String title,  String? description,  int estimatedMinutes,  int completedMinutes, @JsonKey(fromJson: _priority)  int priority,  String deadline,  String? earliestDate,  bool isFixed,  TaskStatus status,  String createdAt,  String updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _Task() when $default != null:
return $default(_that.id,_that.userId,_that.subjectId,_that.title,_that.description,_that.estimatedMinutes,_that.completedMinutes,_that.priority,_that.deadline,_that.earliestDate,_that.isFixed,_that.status,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Task implements Task {
  const _Task({required this.id, required this.userId, required this.subjectId, required this.title, this.description, required this.estimatedMinutes, required this.completedMinutes, @JsonKey(fromJson: _priority) required this.priority, required this.deadline, this.earliestDate, required this.isFixed, required this.status, required this.createdAt, required this.updatedAt});
  factory _Task.fromJson(Map<String, dynamic> json) => _$TaskFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String subjectId;
@override final  String title;
@override final  String? description;
@override final  int estimatedMinutes;
@override final  int completedMinutes;
@override@JsonKey(fromJson: _priority) final  int priority;
@override final  String deadline;
@override final  String? earliestDate;
@override final  bool isFixed;
@override final  TaskStatus status;
@override final  String createdAt;
@override final  String updatedAt;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskCopyWith<_Task> get copyWith => __$TaskCopyWithImpl<_Task>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Task&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.subjectId, subjectId) || other.subjectId == subjectId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.estimatedMinutes, estimatedMinutes) || other.estimatedMinutes == estimatedMinutes)&&(identical(other.completedMinutes, completedMinutes) || other.completedMinutes == completedMinutes)&&(identical(other.priority, priority) || other.priority == priority)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.earliestDate, earliestDate) || other.earliestDate == earliestDate)&&(identical(other.isFixed, isFixed) || other.isFixed == isFixed)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,subjectId,title,description,estimatedMinutes,completedMinutes,priority,deadline,earliestDate,isFixed,status,createdAt,updatedAt);

@override
String toString() {
  return 'Task(id: $id, userId: $userId, subjectId: $subjectId, title: $title, description: $description, estimatedMinutes: $estimatedMinutes, completedMinutes: $completedMinutes, priority: $priority, deadline: $deadline, earliestDate: $earliestDate, isFixed: $isFixed, status: $status, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$TaskCopyWith<$Res> implements $TaskCopyWith<$Res> {
  factory _$TaskCopyWith(_Task value, $Res Function(_Task) _then) = __$TaskCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String subjectId, String title, String? description, int estimatedMinutes, int completedMinutes,@JsonKey(fromJson: _priority) int priority, String deadline, String? earliestDate, bool isFixed, TaskStatus status, String createdAt, String updatedAt
});




}
/// @nodoc
class __$TaskCopyWithImpl<$Res>
    implements _$TaskCopyWith<$Res> {
  __$TaskCopyWithImpl(this._self, this._then);

  final _Task _self;
  final $Res Function(_Task) _then;

/// Create a copy of Task
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? subjectId = null,Object? title = null,Object? description = freezed,Object? estimatedMinutes = null,Object? completedMinutes = null,Object? priority = null,Object? deadline = null,Object? earliestDate = freezed,Object? isFixed = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_Task(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,subjectId: null == subjectId ? _self.subjectId : subjectId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,estimatedMinutes: null == estimatedMinutes ? _self.estimatedMinutes : estimatedMinutes // ignore: cast_nullable_to_non_nullable
as int,completedMinutes: null == completedMinutes ? _self.completedMinutes : completedMinutes // ignore: cast_nullable_to_non_nullable
as int,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,deadline: null == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as String,earliestDate: freezed == earliestDate ? _self.earliestDate : earliestDate // ignore: cast_nullable_to_non_nullable
as String?,isFixed: null == isFixed ? _self.isFixed : isFixed // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ScheduleBlock {

 String get id; String get userId; String get taskId; String get date; int get startMinute; int get durationMinutes; int get actualMinutes; bool get isFixed; BlockStatus get status; String get createdAt; String get updatedAt; String? get adviceText; List<String>? get adviceTopics; CompletionStatus? get completionStatus; String? get feedback;
/// Create a copy of ScheduleBlock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScheduleBlockCopyWith<ScheduleBlock> get copyWith => _$ScheduleBlockCopyWithImpl<ScheduleBlock>(this as ScheduleBlock, _$identity);

  /// Serializes this ScheduleBlock to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ScheduleBlock&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.date, date) || other.date == date)&&(identical(other.startMinute, startMinute) || other.startMinute == startMinute)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes)&&(identical(other.actualMinutes, actualMinutes) || other.actualMinutes == actualMinutes)&&(identical(other.isFixed, isFixed) || other.isFixed == isFixed)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.adviceText, adviceText) || other.adviceText == adviceText)&&const DeepCollectionEquality().equals(other.adviceTopics, adviceTopics)&&(identical(other.completionStatus, completionStatus) || other.completionStatus == completionStatus)&&(identical(other.feedback, feedback) || other.feedback == feedback));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,taskId,date,startMinute,durationMinutes,actualMinutes,isFixed,status,createdAt,updatedAt,adviceText,const DeepCollectionEquality().hash(adviceTopics),completionStatus,feedback);

@override
String toString() {
  return 'ScheduleBlock(id: $id, userId: $userId, taskId: $taskId, date: $date, startMinute: $startMinute, durationMinutes: $durationMinutes, actualMinutes: $actualMinutes, isFixed: $isFixed, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, adviceText: $adviceText, adviceTopics: $adviceTopics, completionStatus: $completionStatus, feedback: $feedback)';
}


}

/// @nodoc
abstract mixin class $ScheduleBlockCopyWith<$Res>  {
  factory $ScheduleBlockCopyWith(ScheduleBlock value, $Res Function(ScheduleBlock) _then) = _$ScheduleBlockCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String taskId, String date, int startMinute, int durationMinutes, int actualMinutes, bool isFixed, BlockStatus status, String createdAt, String updatedAt, String? adviceText, List<String>? adviceTopics, CompletionStatus? completionStatus, String? feedback
});




}
/// @nodoc
class _$ScheduleBlockCopyWithImpl<$Res>
    implements $ScheduleBlockCopyWith<$Res> {
  _$ScheduleBlockCopyWithImpl(this._self, this._then);

  final ScheduleBlock _self;
  final $Res Function(ScheduleBlock) _then;

/// Create a copy of ScheduleBlock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? taskId = null,Object? date = null,Object? startMinute = null,Object? durationMinutes = null,Object? actualMinutes = null,Object? isFixed = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? adviceText = freezed,Object? adviceTopics = freezed,Object? completionStatus = freezed,Object? feedback = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,startMinute: null == startMinute ? _self.startMinute : startMinute // ignore: cast_nullable_to_non_nullable
as int,durationMinutes: null == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int,actualMinutes: null == actualMinutes ? _self.actualMinutes : actualMinutes // ignore: cast_nullable_to_non_nullable
as int,isFixed: null == isFixed ? _self.isFixed : isFixed // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BlockStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,adviceText: freezed == adviceText ? _self.adviceText : adviceText // ignore: cast_nullable_to_non_nullable
as String?,adviceTopics: freezed == adviceTopics ? _self.adviceTopics : adviceTopics // ignore: cast_nullable_to_non_nullable
as List<String>?,completionStatus: freezed == completionStatus ? _self.completionStatus : completionStatus // ignore: cast_nullable_to_non_nullable
as CompletionStatus?,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ScheduleBlock].
extension ScheduleBlockPatterns on ScheduleBlock {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ScheduleBlock value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ScheduleBlock() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ScheduleBlock value)  $default,){
final _that = this;
switch (_that) {
case _ScheduleBlock():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ScheduleBlock value)?  $default,){
final _that = this;
switch (_that) {
case _ScheduleBlock() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String taskId,  String date,  int startMinute,  int durationMinutes,  int actualMinutes,  bool isFixed,  BlockStatus status,  String createdAt,  String updatedAt,  String? adviceText,  List<String>? adviceTopics,  CompletionStatus? completionStatus,  String? feedback)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ScheduleBlock() when $default != null:
return $default(_that.id,_that.userId,_that.taskId,_that.date,_that.startMinute,_that.durationMinutes,_that.actualMinutes,_that.isFixed,_that.status,_that.createdAt,_that.updatedAt,_that.adviceText,_that.adviceTopics,_that.completionStatus,_that.feedback);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String taskId,  String date,  int startMinute,  int durationMinutes,  int actualMinutes,  bool isFixed,  BlockStatus status,  String createdAt,  String updatedAt,  String? adviceText,  List<String>? adviceTopics,  CompletionStatus? completionStatus,  String? feedback)  $default,) {final _that = this;
switch (_that) {
case _ScheduleBlock():
return $default(_that.id,_that.userId,_that.taskId,_that.date,_that.startMinute,_that.durationMinutes,_that.actualMinutes,_that.isFixed,_that.status,_that.createdAt,_that.updatedAt,_that.adviceText,_that.adviceTopics,_that.completionStatus,_that.feedback);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String taskId,  String date,  int startMinute,  int durationMinutes,  int actualMinutes,  bool isFixed,  BlockStatus status,  String createdAt,  String updatedAt,  String? adviceText,  List<String>? adviceTopics,  CompletionStatus? completionStatus,  String? feedback)?  $default,) {final _that = this;
switch (_that) {
case _ScheduleBlock() when $default != null:
return $default(_that.id,_that.userId,_that.taskId,_that.date,_that.startMinute,_that.durationMinutes,_that.actualMinutes,_that.isFixed,_that.status,_that.createdAt,_that.updatedAt,_that.adviceText,_that.adviceTopics,_that.completionStatus,_that.feedback);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ScheduleBlock implements ScheduleBlock {
  const _ScheduleBlock({required this.id, required this.userId, required this.taskId, required this.date, required this.startMinute, required this.durationMinutes, required this.actualMinutes, required this.isFixed, required this.status, required this.createdAt, required this.updatedAt, this.adviceText, final  List<String>? adviceTopics, this.completionStatus, this.feedback}): _adviceTopics = adviceTopics;
  factory _ScheduleBlock.fromJson(Map<String, dynamic> json) => _$ScheduleBlockFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String taskId;
@override final  String date;
@override final  int startMinute;
@override final  int durationMinutes;
@override final  int actualMinutes;
@override final  bool isFixed;
@override final  BlockStatus status;
@override final  String createdAt;
@override final  String updatedAt;
@override final  String? adviceText;
 final  List<String>? _adviceTopics;
@override List<String>? get adviceTopics {
  final value = _adviceTopics;
  if (value == null) return null;
  if (_adviceTopics is EqualUnmodifiableListView) return _adviceTopics;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

@override final  CompletionStatus? completionStatus;
@override final  String? feedback;

/// Create a copy of ScheduleBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScheduleBlockCopyWith<_ScheduleBlock> get copyWith => __$ScheduleBlockCopyWithImpl<_ScheduleBlock>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ScheduleBlockToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ScheduleBlock&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.date, date) || other.date == date)&&(identical(other.startMinute, startMinute) || other.startMinute == startMinute)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes)&&(identical(other.actualMinutes, actualMinutes) || other.actualMinutes == actualMinutes)&&(identical(other.isFixed, isFixed) || other.isFixed == isFixed)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.adviceText, adviceText) || other.adviceText == adviceText)&&const DeepCollectionEquality().equals(other._adviceTopics, _adviceTopics)&&(identical(other.completionStatus, completionStatus) || other.completionStatus == completionStatus)&&(identical(other.feedback, feedback) || other.feedback == feedback));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,taskId,date,startMinute,durationMinutes,actualMinutes,isFixed,status,createdAt,updatedAt,adviceText,const DeepCollectionEquality().hash(_adviceTopics),completionStatus,feedback);

@override
String toString() {
  return 'ScheduleBlock(id: $id, userId: $userId, taskId: $taskId, date: $date, startMinute: $startMinute, durationMinutes: $durationMinutes, actualMinutes: $actualMinutes, isFixed: $isFixed, status: $status, createdAt: $createdAt, updatedAt: $updatedAt, adviceText: $adviceText, adviceTopics: $adviceTopics, completionStatus: $completionStatus, feedback: $feedback)';
}


}

/// @nodoc
abstract mixin class _$ScheduleBlockCopyWith<$Res> implements $ScheduleBlockCopyWith<$Res> {
  factory _$ScheduleBlockCopyWith(_ScheduleBlock value, $Res Function(_ScheduleBlock) _then) = __$ScheduleBlockCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String taskId, String date, int startMinute, int durationMinutes, int actualMinutes, bool isFixed, BlockStatus status, String createdAt, String updatedAt, String? adviceText, List<String>? adviceTopics, CompletionStatus? completionStatus, String? feedback
});




}
/// @nodoc
class __$ScheduleBlockCopyWithImpl<$Res>
    implements _$ScheduleBlockCopyWith<$Res> {
  __$ScheduleBlockCopyWithImpl(this._self, this._then);

  final _ScheduleBlock _self;
  final $Res Function(_ScheduleBlock) _then;

/// Create a copy of ScheduleBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? taskId = null,Object? date = null,Object? startMinute = null,Object? durationMinutes = null,Object? actualMinutes = null,Object? isFixed = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,Object? adviceText = freezed,Object? adviceTopics = freezed,Object? completionStatus = freezed,Object? feedback = freezed,}) {
  return _then(_ScheduleBlock(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,startMinute: null == startMinute ? _self.startMinute : startMinute // ignore: cast_nullable_to_non_nullable
as int,durationMinutes: null == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int,actualMinutes: null == actualMinutes ? _self.actualMinutes : actualMinutes // ignore: cast_nullable_to_non_nullable
as int,isFixed: null == isFixed ? _self.isFixed : isFixed // ignore: cast_nullable_to_non_nullable
as bool,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BlockStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,adviceText: freezed == adviceText ? _self.adviceText : adviceText // ignore: cast_nullable_to_non_nullable
as String?,adviceTopics: freezed == adviceTopics ? _self._adviceTopics : adviceTopics // ignore: cast_nullable_to_non_nullable
as List<String>?,completionStatus: freezed == completionStatus ? _self.completionStatus : completionStatus // ignore: cast_nullable_to_non_nullable
as CompletionStatus?,feedback: freezed == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$TimeLog {

 String get id; String get userId; String get taskId;@JsonKey(includeIfNull: true) String? get blockId; String get date; int get minutes; String get startedAt; String get endedAt; LogSource get source;
/// Create a copy of TimeLog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimeLogCopyWith<TimeLog> get copyWith => _$TimeLogCopyWithImpl<TimeLog>(this as TimeLog, _$identity);

  /// Serializes this TimeLog to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimeLog&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.blockId, blockId) || other.blockId == blockId)&&(identical(other.date, date) || other.date == date)&&(identical(other.minutes, minutes) || other.minutes == minutes)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,taskId,blockId,date,minutes,startedAt,endedAt,source);

@override
String toString() {
  return 'TimeLog(id: $id, userId: $userId, taskId: $taskId, blockId: $blockId, date: $date, minutes: $minutes, startedAt: $startedAt, endedAt: $endedAt, source: $source)';
}


}

/// @nodoc
abstract mixin class $TimeLogCopyWith<$Res>  {
  factory $TimeLogCopyWith(TimeLog value, $Res Function(TimeLog) _then) = _$TimeLogCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String taskId,@JsonKey(includeIfNull: true) String? blockId, String date, int minutes, String startedAt, String endedAt, LogSource source
});




}
/// @nodoc
class _$TimeLogCopyWithImpl<$Res>
    implements $TimeLogCopyWith<$Res> {
  _$TimeLogCopyWithImpl(this._self, this._then);

  final TimeLog _self;
  final $Res Function(TimeLog) _then;

/// Create a copy of TimeLog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? taskId = null,Object? blockId = freezed,Object? date = null,Object? minutes = null,Object? startedAt = null,Object? endedAt = null,Object? source = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,blockId: freezed == blockId ? _self.blockId : blockId // ignore: cast_nullable_to_non_nullable
as String?,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,minutes: null == minutes ? _self.minutes : minutes // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as String,endedAt: null == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as LogSource,
  ));
}

}


/// Adds pattern-matching-related methods to [TimeLog].
extension TimeLogPatterns on TimeLog {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimeLog value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimeLog() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimeLog value)  $default,){
final _that = this;
switch (_that) {
case _TimeLog():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimeLog value)?  $default,){
final _that = this;
switch (_that) {
case _TimeLog() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String taskId, @JsonKey(includeIfNull: true)  String? blockId,  String date,  int minutes,  String startedAt,  String endedAt,  LogSource source)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimeLog() when $default != null:
return $default(_that.id,_that.userId,_that.taskId,_that.blockId,_that.date,_that.minutes,_that.startedAt,_that.endedAt,_that.source);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String taskId, @JsonKey(includeIfNull: true)  String? blockId,  String date,  int minutes,  String startedAt,  String endedAt,  LogSource source)  $default,) {final _that = this;
switch (_that) {
case _TimeLog():
return $default(_that.id,_that.userId,_that.taskId,_that.blockId,_that.date,_that.minutes,_that.startedAt,_that.endedAt,_that.source);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String taskId, @JsonKey(includeIfNull: true)  String? blockId,  String date,  int minutes,  String startedAt,  String endedAt,  LogSource source)?  $default,) {final _that = this;
switch (_that) {
case _TimeLog() when $default != null:
return $default(_that.id,_that.userId,_that.taskId,_that.blockId,_that.date,_that.minutes,_that.startedAt,_that.endedAt,_that.source);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TimeLog implements TimeLog {
  const _TimeLog({required this.id, required this.userId, required this.taskId, @JsonKey(includeIfNull: true) required this.blockId, required this.date, required this.minutes, required this.startedAt, required this.endedAt, required this.source});
  factory _TimeLog.fromJson(Map<String, dynamic> json) => _$TimeLogFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String taskId;
@override@JsonKey(includeIfNull: true) final  String? blockId;
@override final  String date;
@override final  int minutes;
@override final  String startedAt;
@override final  String endedAt;
@override final  LogSource source;

/// Create a copy of TimeLog
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimeLogCopyWith<_TimeLog> get copyWith => __$TimeLogCopyWithImpl<_TimeLog>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TimeLogToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimeLog&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.blockId, blockId) || other.blockId == blockId)&&(identical(other.date, date) || other.date == date)&&(identical(other.minutes, minutes) || other.minutes == minutes)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.endedAt, endedAt) || other.endedAt == endedAt)&&(identical(other.source, source) || other.source == source));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,taskId,blockId,date,minutes,startedAt,endedAt,source);

@override
String toString() {
  return 'TimeLog(id: $id, userId: $userId, taskId: $taskId, blockId: $blockId, date: $date, minutes: $minutes, startedAt: $startedAt, endedAt: $endedAt, source: $source)';
}


}

/// @nodoc
abstract mixin class _$TimeLogCopyWith<$Res> implements $TimeLogCopyWith<$Res> {
  factory _$TimeLogCopyWith(_TimeLog value, $Res Function(_TimeLog) _then) = __$TimeLogCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String taskId,@JsonKey(includeIfNull: true) String? blockId, String date, int minutes, String startedAt, String endedAt, LogSource source
});




}
/// @nodoc
class __$TimeLogCopyWithImpl<$Res>
    implements _$TimeLogCopyWith<$Res> {
  __$TimeLogCopyWithImpl(this._self, this._then);

  final _TimeLog _self;
  final $Res Function(_TimeLog) _then;

/// Create a copy of TimeLog
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? taskId = null,Object? blockId = freezed,Object? date = null,Object? minutes = null,Object? startedAt = null,Object? endedAt = null,Object? source = null,}) {
  return _then(_TimeLog(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,blockId: freezed == blockId ? _self.blockId : blockId // ignore: cast_nullable_to_non_nullable
as String?,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,minutes: null == minutes ? _self.minutes : minutes // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as String,endedAt: null == endedAt ? _self.endedAt : endedAt // ignore: cast_nullable_to_non_nullable
as String,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as LogSource,
  ));
}


}


/// @nodoc
mixin _$FixedEvent {

 String get id; String get userId; String get title; String get date; int get startMinute; int get durationMinutes; FixedEventKind get kind; EventRepeat get repeat; String get createdAt; String get updatedAt;
/// Create a copy of FixedEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FixedEventCopyWith<FixedEvent> get copyWith => _$FixedEventCopyWithImpl<FixedEvent>(this as FixedEvent, _$identity);

  /// Serializes this FixedEvent to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FixedEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.title, title) || other.title == title)&&(identical(other.date, date) || other.date == date)&&(identical(other.startMinute, startMinute) || other.startMinute == startMinute)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,title,date,startMinute,durationMinutes,kind,repeat,createdAt,updatedAt);

@override
String toString() {
  return 'FixedEvent(id: $id, userId: $userId, title: $title, date: $date, startMinute: $startMinute, durationMinutes: $durationMinutes, kind: $kind, repeat: $repeat, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $FixedEventCopyWith<$Res>  {
  factory $FixedEventCopyWith(FixedEvent value, $Res Function(FixedEvent) _then) = _$FixedEventCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String title, String date, int startMinute, int durationMinutes, FixedEventKind kind, EventRepeat repeat, String createdAt, String updatedAt
});




}
/// @nodoc
class _$FixedEventCopyWithImpl<$Res>
    implements $FixedEventCopyWith<$Res> {
  _$FixedEventCopyWithImpl(this._self, this._then);

  final FixedEvent _self;
  final $Res Function(FixedEvent) _then;

/// Create a copy of FixedEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? title = null,Object? date = null,Object? startMinute = null,Object? durationMinutes = null,Object? kind = null,Object? repeat = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,startMinute: null == startMinute ? _self.startMinute : startMinute // ignore: cast_nullable_to_non_nullable
as int,durationMinutes: null == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FixedEventKind,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as EventRepeat,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [FixedEvent].
extension FixedEventPatterns on FixedEvent {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FixedEvent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FixedEvent() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FixedEvent value)  $default,){
final _that = this;
switch (_that) {
case _FixedEvent():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FixedEvent value)?  $default,){
final _that = this;
switch (_that) {
case _FixedEvent() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String title,  String date,  int startMinute,  int durationMinutes,  FixedEventKind kind,  EventRepeat repeat,  String createdAt,  String updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FixedEvent() when $default != null:
return $default(_that.id,_that.userId,_that.title,_that.date,_that.startMinute,_that.durationMinutes,_that.kind,_that.repeat,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String title,  String date,  int startMinute,  int durationMinutes,  FixedEventKind kind,  EventRepeat repeat,  String createdAt,  String updatedAt)  $default,) {final _that = this;
switch (_that) {
case _FixedEvent():
return $default(_that.id,_that.userId,_that.title,_that.date,_that.startMinute,_that.durationMinutes,_that.kind,_that.repeat,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String title,  String date,  int startMinute,  int durationMinutes,  FixedEventKind kind,  EventRepeat repeat,  String createdAt,  String updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _FixedEvent() when $default != null:
return $default(_that.id,_that.userId,_that.title,_that.date,_that.startMinute,_that.durationMinutes,_that.kind,_that.repeat,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _FixedEvent implements FixedEvent {
  const _FixedEvent({required this.id, required this.userId, required this.title, required this.date, required this.startMinute, required this.durationMinutes, required this.kind, required this.repeat, required this.createdAt, required this.updatedAt});
  factory _FixedEvent.fromJson(Map<String, dynamic> json) => _$FixedEventFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String title;
@override final  String date;
@override final  int startMinute;
@override final  int durationMinutes;
@override final  FixedEventKind kind;
@override final  EventRepeat repeat;
@override final  String createdAt;
@override final  String updatedAt;

/// Create a copy of FixedEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FixedEventCopyWith<_FixedEvent> get copyWith => __$FixedEventCopyWithImpl<_FixedEvent>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$FixedEventToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _FixedEvent&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.title, title) || other.title == title)&&(identical(other.date, date) || other.date == date)&&(identical(other.startMinute, startMinute) || other.startMinute == startMinute)&&(identical(other.durationMinutes, durationMinutes) || other.durationMinutes == durationMinutes)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.repeat, repeat) || other.repeat == repeat)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,title,date,startMinute,durationMinutes,kind,repeat,createdAt,updatedAt);

@override
String toString() {
  return 'FixedEvent(id: $id, userId: $userId, title: $title, date: $date, startMinute: $startMinute, durationMinutes: $durationMinutes, kind: $kind, repeat: $repeat, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$FixedEventCopyWith<$Res> implements $FixedEventCopyWith<$Res> {
  factory _$FixedEventCopyWith(_FixedEvent value, $Res Function(_FixedEvent) _then) = __$FixedEventCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String title, String date, int startMinute, int durationMinutes, FixedEventKind kind, EventRepeat repeat, String createdAt, String updatedAt
});




}
/// @nodoc
class __$FixedEventCopyWithImpl<$Res>
    implements _$FixedEventCopyWith<$Res> {
  __$FixedEventCopyWithImpl(this._self, this._then);

  final _FixedEvent _self;
  final $Res Function(_FixedEvent) _then;

/// Create a copy of FixedEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? title = null,Object? date = null,Object? startMinute = null,Object? durationMinutes = null,Object? kind = null,Object? repeat = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_FixedEvent(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,startMinute: null == startMinute ? _self.startMinute : startMinute // ignore: cast_nullable_to_non_nullable
as int,durationMinutes: null == durationMinutes ? _self.durationMinutes : durationMinutes // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as FixedEventKind,repeat: null == repeat ? _self.repeat : repeat // ignore: cast_nullable_to_non_nullable
as EventRepeat,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$Phase {

 String get id; String get title; String get start; String get end; String get description;
/// Create a copy of Phase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PhaseCopyWith<Phase> get copyWith => _$PhaseCopyWithImpl<Phase>(this as Phase, _$identity);

  /// Serializes this Phase to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Phase&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,start,end,description);

@override
String toString() {
  return 'Phase(id: $id, title: $title, start: $start, end: $end, description: $description)';
}


}

/// @nodoc
abstract mixin class $PhaseCopyWith<$Res>  {
  factory $PhaseCopyWith(Phase value, $Res Function(Phase) _then) = _$PhaseCopyWithImpl;
@useResult
$Res call({
 String id, String title, String start, String end, String description
});




}
/// @nodoc
class _$PhaseCopyWithImpl<$Res>
    implements $PhaseCopyWith<$Res> {
  _$PhaseCopyWithImpl(this._self, this._then);

  final Phase _self;
  final $Res Function(Phase) _then;

/// Create a copy of Phase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? title = null,Object? start = null,Object? end = null,Object? description = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as String,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Phase].
extension PhasePatterns on Phase {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Phase value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Phase() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Phase value)  $default,){
final _that = this;
switch (_that) {
case _Phase():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Phase value)?  $default,){
final _that = this;
switch (_that) {
case _Phase() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String title,  String start,  String end,  String description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Phase() when $default != null:
return $default(_that.id,_that.title,_that.start,_that.end,_that.description);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String title,  String start,  String end,  String description)  $default,) {final _that = this;
switch (_that) {
case _Phase():
return $default(_that.id,_that.title,_that.start,_that.end,_that.description);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String title,  String start,  String end,  String description)?  $default,) {final _that = this;
switch (_that) {
case _Phase() when $default != null:
return $default(_that.id,_that.title,_that.start,_that.end,_that.description);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Phase implements Phase {
  const _Phase({required this.id, required this.title, required this.start, required this.end, required this.description});
  factory _Phase.fromJson(Map<String, dynamic> json) => _$PhaseFromJson(json);

@override final  String id;
@override final  String title;
@override final  String start;
@override final  String end;
@override final  String description;

/// Create a copy of Phase
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PhaseCopyWith<_Phase> get copyWith => __$PhaseCopyWithImpl<_Phase>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PhaseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Phase&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.start, start) || other.start == start)&&(identical(other.end, end) || other.end == end)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,title,start,end,description);

@override
String toString() {
  return 'Phase(id: $id, title: $title, start: $start, end: $end, description: $description)';
}


}

/// @nodoc
abstract mixin class _$PhaseCopyWith<$Res> implements $PhaseCopyWith<$Res> {
  factory _$PhaseCopyWith(_Phase value, $Res Function(_Phase) _then) = __$PhaseCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String start, String end, String description
});




}
/// @nodoc
class __$PhaseCopyWithImpl<$Res>
    implements _$PhaseCopyWith<$Res> {
  __$PhaseCopyWithImpl(this._self, this._then);

  final _Phase _self;
  final $Res Function(_Phase) _then;

/// Create a copy of Phase
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? start = null,Object? end = null,Object? description = null,}) {
  return _then(_Phase(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,start: null == start ? _self.start : start // ignore: cast_nullable_to_non_nullable
as String,end: null == end ? _self.end : end // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$ReplanChange {

 String get id; String get userId; String get runId; ChangeType get type; String get blockId;@JsonKey(includeIfNull: true) ScheduleBlock? get before;@JsonKey(includeIfNull: true) ScheduleBlock? get after;
/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplanChangeCopyWith<ReplanChange> get copyWith => _$ReplanChangeCopyWithImpl<ReplanChange>(this as ReplanChange, _$identity);

  /// Serializes this ReplanChange to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplanChange&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.type, type) || other.type == type)&&(identical(other.blockId, blockId) || other.blockId == blockId)&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,runId,type,blockId,before,after);

@override
String toString() {
  return 'ReplanChange(id: $id, userId: $userId, runId: $runId, type: $type, blockId: $blockId, before: $before, after: $after)';
}


}

/// @nodoc
abstract mixin class $ReplanChangeCopyWith<$Res>  {
  factory $ReplanChangeCopyWith(ReplanChange value, $Res Function(ReplanChange) _then) = _$ReplanChangeCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String runId, ChangeType type, String blockId,@JsonKey(includeIfNull: true) ScheduleBlock? before,@JsonKey(includeIfNull: true) ScheduleBlock? after
});


$ScheduleBlockCopyWith<$Res>? get before;$ScheduleBlockCopyWith<$Res>? get after;

}
/// @nodoc
class _$ReplanChangeCopyWithImpl<$Res>
    implements $ReplanChangeCopyWith<$Res> {
  _$ReplanChangeCopyWithImpl(this._self, this._then);

  final ReplanChange _self;
  final $Res Function(ReplanChange) _then;

/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? runId = null,Object? type = null,Object? blockId = null,Object? before = freezed,Object? after = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as ChangeType,blockId: null == blockId ? _self.blockId : blockId // ignore: cast_nullable_to_non_nullable
as String,before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as ScheduleBlock?,after: freezed == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as ScheduleBlock?,
  ));
}
/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ScheduleBlockCopyWith<$Res>? get before {
    if (_self.before == null) {
    return null;
  }

  return $ScheduleBlockCopyWith<$Res>(_self.before!, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ScheduleBlockCopyWith<$Res>? get after {
    if (_self.after == null) {
    return null;
  }

  return $ScheduleBlockCopyWith<$Res>(_self.after!, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}


/// Adds pattern-matching-related methods to [ReplanChange].
extension ReplanChangePatterns on ReplanChange {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReplanChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReplanChange() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReplanChange value)  $default,){
final _that = this;
switch (_that) {
case _ReplanChange():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReplanChange value)?  $default,){
final _that = this;
switch (_that) {
case _ReplanChange() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String runId,  ChangeType type,  String blockId, @JsonKey(includeIfNull: true)  ScheduleBlock? before, @JsonKey(includeIfNull: true)  ScheduleBlock? after)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReplanChange() when $default != null:
return $default(_that.id,_that.userId,_that.runId,_that.type,_that.blockId,_that.before,_that.after);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String runId,  ChangeType type,  String blockId, @JsonKey(includeIfNull: true)  ScheduleBlock? before, @JsonKey(includeIfNull: true)  ScheduleBlock? after)  $default,) {final _that = this;
switch (_that) {
case _ReplanChange():
return $default(_that.id,_that.userId,_that.runId,_that.type,_that.blockId,_that.before,_that.after);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String runId,  ChangeType type,  String blockId, @JsonKey(includeIfNull: true)  ScheduleBlock? before, @JsonKey(includeIfNull: true)  ScheduleBlock? after)?  $default,) {final _that = this;
switch (_that) {
case _ReplanChange() when $default != null:
return $default(_that.id,_that.userId,_that.runId,_that.type,_that.blockId,_that.before,_that.after);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReplanChange implements ReplanChange {
  const _ReplanChange({required this.id, required this.userId, required this.runId, required this.type, required this.blockId, @JsonKey(includeIfNull: true) required this.before, @JsonKey(includeIfNull: true) required this.after});
  factory _ReplanChange.fromJson(Map<String, dynamic> json) => _$ReplanChangeFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String runId;
@override final  ChangeType type;
@override final  String blockId;
@override@JsonKey(includeIfNull: true) final  ScheduleBlock? before;
@override@JsonKey(includeIfNull: true) final  ScheduleBlock? after;

/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReplanChangeCopyWith<_ReplanChange> get copyWith => __$ReplanChangeCopyWithImpl<_ReplanChange>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReplanChangeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReplanChange&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.runId, runId) || other.runId == runId)&&(identical(other.type, type) || other.type == type)&&(identical(other.blockId, blockId) || other.blockId == blockId)&&(identical(other.before, before) || other.before == before)&&(identical(other.after, after) || other.after == after));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,runId,type,blockId,before,after);

@override
String toString() {
  return 'ReplanChange(id: $id, userId: $userId, runId: $runId, type: $type, blockId: $blockId, before: $before, after: $after)';
}


}

/// @nodoc
abstract mixin class _$ReplanChangeCopyWith<$Res> implements $ReplanChangeCopyWith<$Res> {
  factory _$ReplanChangeCopyWith(_ReplanChange value, $Res Function(_ReplanChange) _then) = __$ReplanChangeCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String runId, ChangeType type, String blockId,@JsonKey(includeIfNull: true) ScheduleBlock? before,@JsonKey(includeIfNull: true) ScheduleBlock? after
});


@override $ScheduleBlockCopyWith<$Res>? get before;@override $ScheduleBlockCopyWith<$Res>? get after;

}
/// @nodoc
class __$ReplanChangeCopyWithImpl<$Res>
    implements _$ReplanChangeCopyWith<$Res> {
  __$ReplanChangeCopyWithImpl(this._self, this._then);

  final _ReplanChange _self;
  final $Res Function(_ReplanChange) _then;

/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? runId = null,Object? type = null,Object? blockId = null,Object? before = freezed,Object? after = freezed,}) {
  return _then(_ReplanChange(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,runId: null == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String,type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as ChangeType,blockId: null == blockId ? _self.blockId : blockId // ignore: cast_nullable_to_non_nullable
as String,before: freezed == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as ScheduleBlock?,after: freezed == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as ScheduleBlock?,
  ));
}

/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ScheduleBlockCopyWith<$Res>? get before {
    if (_self.before == null) {
    return null;
  }

  return $ScheduleBlockCopyWith<$Res>(_self.before!, (value) {
    return _then(_self.copyWith(before: value));
  });
}/// Create a copy of ReplanChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ScheduleBlockCopyWith<$Res>? get after {
    if (_self.after == null) {
    return null;
  }

  return $ScheduleBlockCopyWith<$Res>(_self.after!, (value) {
    return _then(_self.copyWith(after: value));
  });
}
}


/// @nodoc
mixin _$Conflict {

 String get taskId; String get title; int get minutes; String get reason;
/// Create a copy of Conflict
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConflictCopyWith<Conflict> get copyWith => _$ConflictCopyWithImpl<Conflict>(this as Conflict, _$identity);

  /// Serializes this Conflict to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Conflict&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.title, title) || other.title == title)&&(identical(other.minutes, minutes) || other.minutes == minutes)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,taskId,title,minutes,reason);

@override
String toString() {
  return 'Conflict(taskId: $taskId, title: $title, minutes: $minutes, reason: $reason)';
}


}

/// @nodoc
abstract mixin class $ConflictCopyWith<$Res>  {
  factory $ConflictCopyWith(Conflict value, $Res Function(Conflict) _then) = _$ConflictCopyWithImpl;
@useResult
$Res call({
 String taskId, String title, int minutes, String reason
});




}
/// @nodoc
class _$ConflictCopyWithImpl<$Res>
    implements $ConflictCopyWith<$Res> {
  _$ConflictCopyWithImpl(this._self, this._then);

  final Conflict _self;
  final $Res Function(Conflict) _then;

/// Create a copy of Conflict
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? taskId = null,Object? title = null,Object? minutes = null,Object? reason = null,}) {
  return _then(_self.copyWith(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,minutes: null == minutes ? _self.minutes : minutes // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Conflict].
extension ConflictPatterns on Conflict {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Conflict value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Conflict() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Conflict value)  $default,){
final _that = this;
switch (_that) {
case _Conflict():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Conflict value)?  $default,){
final _that = this;
switch (_that) {
case _Conflict() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String taskId,  String title,  int minutes,  String reason)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Conflict() when $default != null:
return $default(_that.taskId,_that.title,_that.minutes,_that.reason);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String taskId,  String title,  int minutes,  String reason)  $default,) {final _that = this;
switch (_that) {
case _Conflict():
return $default(_that.taskId,_that.title,_that.minutes,_that.reason);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String taskId,  String title,  int minutes,  String reason)?  $default,) {final _that = this;
switch (_that) {
case _Conflict() when $default != null:
return $default(_that.taskId,_that.title,_that.minutes,_that.reason);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _Conflict implements Conflict {
  const _Conflict({required this.taskId, required this.title, required this.minutes, required this.reason});
  factory _Conflict.fromJson(Map<String, dynamic> json) => _$ConflictFromJson(json);

@override final  String taskId;
@override final  String title;
@override final  int minutes;
@override final  String reason;

/// Create a copy of Conflict
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConflictCopyWith<_Conflict> get copyWith => __$ConflictCopyWithImpl<_Conflict>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ConflictToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _Conflict&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.title, title) || other.title == title)&&(identical(other.minutes, minutes) || other.minutes == minutes)&&(identical(other.reason, reason) || other.reason == reason));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,taskId,title,minutes,reason);

@override
String toString() {
  return 'Conflict(taskId: $taskId, title: $title, minutes: $minutes, reason: $reason)';
}


}

/// @nodoc
abstract mixin class _$ConflictCopyWith<$Res> implements $ConflictCopyWith<$Res> {
  factory _$ConflictCopyWith(_Conflict value, $Res Function(_Conflict) _then) = __$ConflictCopyWithImpl;
@override @useResult
$Res call({
 String taskId, String title, int minutes, String reason
});




}
/// @nodoc
class __$ConflictCopyWithImpl<$Res>
    implements _$ConflictCopyWith<$Res> {
  __$ConflictCopyWithImpl(this._self, this._then);

  final _Conflict _self;
  final $Res Function(_Conflict) _then;

/// Create a copy of Conflict
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? title = null,Object? minutes = null,Object? reason = null,}) {
  return _then(_Conflict(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,minutes: null == minutes ? _self.minutes : minutes // ignore: cast_nullable_to_non_nullable
as int,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$DayChange {

 String get date; int get beforeMinutes; int get afterMinutes;
/// Create a copy of DayChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DayChangeCopyWith<DayChange> get copyWith => _$DayChangeCopyWithImpl<DayChange>(this as DayChange, _$identity);

  /// Serializes this DayChange to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DayChange&&(identical(other.date, date) || other.date == date)&&(identical(other.beforeMinutes, beforeMinutes) || other.beforeMinutes == beforeMinutes)&&(identical(other.afterMinutes, afterMinutes) || other.afterMinutes == afterMinutes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,date,beforeMinutes,afterMinutes);

@override
String toString() {
  return 'DayChange(date: $date, beforeMinutes: $beforeMinutes, afterMinutes: $afterMinutes)';
}


}

/// @nodoc
abstract mixin class $DayChangeCopyWith<$Res>  {
  factory $DayChangeCopyWith(DayChange value, $Res Function(DayChange) _then) = _$DayChangeCopyWithImpl;
@useResult
$Res call({
 String date, int beforeMinutes, int afterMinutes
});




}
/// @nodoc
class _$DayChangeCopyWithImpl<$Res>
    implements $DayChangeCopyWith<$Res> {
  _$DayChangeCopyWithImpl(this._self, this._then);

  final DayChange _self;
  final $Res Function(DayChange) _then;

/// Create a copy of DayChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? date = null,Object? beforeMinutes = null,Object? afterMinutes = null,}) {
  return _then(_self.copyWith(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,beforeMinutes: null == beforeMinutes ? _self.beforeMinutes : beforeMinutes // ignore: cast_nullable_to_non_nullable
as int,afterMinutes: null == afterMinutes ? _self.afterMinutes : afterMinutes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [DayChange].
extension DayChangePatterns on DayChange {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DayChange value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DayChange() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DayChange value)  $default,){
final _that = this;
switch (_that) {
case _DayChange():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DayChange value)?  $default,){
final _that = this;
switch (_that) {
case _DayChange() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String date,  int beforeMinutes,  int afterMinutes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DayChange() when $default != null:
return $default(_that.date,_that.beforeMinutes,_that.afterMinutes);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String date,  int beforeMinutes,  int afterMinutes)  $default,) {final _that = this;
switch (_that) {
case _DayChange():
return $default(_that.date,_that.beforeMinutes,_that.afterMinutes);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String date,  int beforeMinutes,  int afterMinutes)?  $default,) {final _that = this;
switch (_that) {
case _DayChange() when $default != null:
return $default(_that.date,_that.beforeMinutes,_that.afterMinutes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DayChange implements DayChange {
  const _DayChange({required this.date, required this.beforeMinutes, required this.afterMinutes});
  factory _DayChange.fromJson(Map<String, dynamic> json) => _$DayChangeFromJson(json);

@override final  String date;
@override final  int beforeMinutes;
@override final  int afterMinutes;

/// Create a copy of DayChange
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DayChangeCopyWith<_DayChange> get copyWith => __$DayChangeCopyWithImpl<_DayChange>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DayChangeToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DayChange&&(identical(other.date, date) || other.date == date)&&(identical(other.beforeMinutes, beforeMinutes) || other.beforeMinutes == beforeMinutes)&&(identical(other.afterMinutes, afterMinutes) || other.afterMinutes == afterMinutes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,date,beforeMinutes,afterMinutes);

@override
String toString() {
  return 'DayChange(date: $date, beforeMinutes: $beforeMinutes, afterMinutes: $afterMinutes)';
}


}

/// @nodoc
abstract mixin class _$DayChangeCopyWith<$Res> implements $DayChangeCopyWith<$Res> {
  factory _$DayChangeCopyWith(_DayChange value, $Res Function(_DayChange) _then) = __$DayChangeCopyWithImpl;
@override @useResult
$Res call({
 String date, int beforeMinutes, int afterMinutes
});




}
/// @nodoc
class __$DayChangeCopyWithImpl<$Res>
    implements _$DayChangeCopyWith<$Res> {
  __$DayChangeCopyWithImpl(this._self, this._then);

  final _DayChange _self;
  final $Res Function(_DayChange) _then;

/// Create a copy of DayChange
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? date = null,Object? beforeMinutes = null,Object? afterMinutes = null,}) {
  return _then(_DayChange(
date: null == date ? _self.date : date // ignore: cast_nullable_to_non_nullable
as String,beforeMinutes: null == beforeMinutes ? _self.beforeMinutes : beforeMinutes // ignore: cast_nullable_to_non_nullable
as int,afterMinutes: null == afterMinutes ? _self.afterMinutes : afterMinutes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$TaskStatusSnapshot {

 String get id; TaskStatus get status;
/// Create a copy of TaskStatusSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TaskStatusSnapshotCopyWith<TaskStatusSnapshot> get copyWith => _$TaskStatusSnapshotCopyWithImpl<TaskStatusSnapshot>(this as TaskStatusSnapshot, _$identity);

  /// Serializes this TaskStatusSnapshot to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TaskStatusSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,status);

@override
String toString() {
  return 'TaskStatusSnapshot(id: $id, status: $status)';
}


}

/// @nodoc
abstract mixin class $TaskStatusSnapshotCopyWith<$Res>  {
  factory $TaskStatusSnapshotCopyWith(TaskStatusSnapshot value, $Res Function(TaskStatusSnapshot) _then) = _$TaskStatusSnapshotCopyWithImpl;
@useResult
$Res call({
 String id, TaskStatus status
});




}
/// @nodoc
class _$TaskStatusSnapshotCopyWithImpl<$Res>
    implements $TaskStatusSnapshotCopyWith<$Res> {
  _$TaskStatusSnapshotCopyWithImpl(this._self, this._then);

  final TaskStatusSnapshot _self;
  final $Res Function(TaskStatusSnapshot) _then;

/// Create a copy of TaskStatusSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? status = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,
  ));
}

}


/// Adds pattern-matching-related methods to [TaskStatusSnapshot].
extension TaskStatusSnapshotPatterns on TaskStatusSnapshot {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TaskStatusSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TaskStatusSnapshot() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TaskStatusSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _TaskStatusSnapshot():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TaskStatusSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _TaskStatusSnapshot() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  TaskStatus status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TaskStatusSnapshot() when $default != null:
return $default(_that.id,_that.status);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  TaskStatus status)  $default,) {final _that = this;
switch (_that) {
case _TaskStatusSnapshot():
return $default(_that.id,_that.status);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  TaskStatus status)?  $default,) {final _that = this;
switch (_that) {
case _TaskStatusSnapshot() when $default != null:
return $default(_that.id,_that.status);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _TaskStatusSnapshot implements TaskStatusSnapshot {
  const _TaskStatusSnapshot({required this.id, required this.status});
  factory _TaskStatusSnapshot.fromJson(Map<String, dynamic> json) => _$TaskStatusSnapshotFromJson(json);

@override final  String id;
@override final  TaskStatus status;

/// Create a copy of TaskStatusSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TaskStatusSnapshotCopyWith<_TaskStatusSnapshot> get copyWith => __$TaskStatusSnapshotCopyWithImpl<_TaskStatusSnapshot>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$TaskStatusSnapshotToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _TaskStatusSnapshot&&(identical(other.id, id) || other.id == id)&&(identical(other.status, status) || other.status == status));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,status);

@override
String toString() {
  return 'TaskStatusSnapshot(id: $id, status: $status)';
}


}

/// @nodoc
abstract mixin class _$TaskStatusSnapshotCopyWith<$Res> implements $TaskStatusSnapshotCopyWith<$Res> {
  factory _$TaskStatusSnapshotCopyWith(_TaskStatusSnapshot value, $Res Function(_TaskStatusSnapshot) _then) = __$TaskStatusSnapshotCopyWithImpl;
@override @useResult
$Res call({
 String id, TaskStatus status
});




}
/// @nodoc
class __$TaskStatusSnapshotCopyWithImpl<$Res>
    implements _$TaskStatusSnapshotCopyWith<$Res> {
  __$TaskStatusSnapshotCopyWithImpl(this._self, this._then);

  final _TaskStatusSnapshot _self;
  final $Res Function(_TaskStatusSnapshot) _then;

/// Create a copy of TaskStatusSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? status = null,}) {
  return _then(_TaskStatusSnapshot(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as TaskStatus,
  ));
}


}


/// @nodoc
mixin _$ReplanPreview {

 String get id; String get userId; String get createdAt; List<ScheduleBlock> get before; List<ScheduleBlock> get after; List<ReplanChange> get changes; List<String> get postponed; List<String> get advanced; List<Conflict> get conflicts; List<DayChange> get dailyChanges;
/// Create a copy of ReplanPreview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplanPreviewCopyWith<ReplanPreview> get copyWith => _$ReplanPreviewCopyWithImpl<ReplanPreview>(this as ReplanPreview, _$identity);

  /// Serializes this ReplanPreview to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplanPreview&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.before, before)&&const DeepCollectionEquality().equals(other.after, after)&&const DeepCollectionEquality().equals(other.changes, changes)&&const DeepCollectionEquality().equals(other.postponed, postponed)&&const DeepCollectionEquality().equals(other.advanced, advanced)&&const DeepCollectionEquality().equals(other.conflicts, conflicts)&&const DeepCollectionEquality().equals(other.dailyChanges, dailyChanges));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,createdAt,const DeepCollectionEquality().hash(before),const DeepCollectionEquality().hash(after),const DeepCollectionEquality().hash(changes),const DeepCollectionEquality().hash(postponed),const DeepCollectionEquality().hash(advanced),const DeepCollectionEquality().hash(conflicts),const DeepCollectionEquality().hash(dailyChanges));

@override
String toString() {
  return 'ReplanPreview(id: $id, userId: $userId, createdAt: $createdAt, before: $before, after: $after, changes: $changes, postponed: $postponed, advanced: $advanced, conflicts: $conflicts, dailyChanges: $dailyChanges)';
}


}

/// @nodoc
abstract mixin class $ReplanPreviewCopyWith<$Res>  {
  factory $ReplanPreviewCopyWith(ReplanPreview value, $Res Function(ReplanPreview) _then) = _$ReplanPreviewCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String createdAt, List<ScheduleBlock> before, List<ScheduleBlock> after, List<ReplanChange> changes, List<String> postponed, List<String> advanced, List<Conflict> conflicts, List<DayChange> dailyChanges
});




}
/// @nodoc
class _$ReplanPreviewCopyWithImpl<$Res>
    implements $ReplanPreviewCopyWith<$Res> {
  _$ReplanPreviewCopyWithImpl(this._self, this._then);

  final ReplanPreview _self;
  final $Res Function(ReplanPreview) _then;

/// Create a copy of ReplanPreview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? createdAt = null,Object? before = null,Object? after = null,Object? changes = null,Object? postponed = null,Object? advanced = null,Object? conflicts = null,Object? dailyChanges = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,before: null == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as List<ReplanChange>,postponed: null == postponed ? _self.postponed : postponed // ignore: cast_nullable_to_non_nullable
as List<String>,advanced: null == advanced ? _self.advanced : advanced // ignore: cast_nullable_to_non_nullable
as List<String>,conflicts: null == conflicts ? _self.conflicts : conflicts // ignore: cast_nullable_to_non_nullable
as List<Conflict>,dailyChanges: null == dailyChanges ? _self.dailyChanges : dailyChanges // ignore: cast_nullable_to_non_nullable
as List<DayChange>,
  ));
}

}


/// Adds pattern-matching-related methods to [ReplanPreview].
extension ReplanPreviewPatterns on ReplanPreview {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReplanPreview value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReplanPreview() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReplanPreview value)  $default,){
final _that = this;
switch (_that) {
case _ReplanPreview():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReplanPreview value)?  $default,){
final _that = this;
switch (_that) {
case _ReplanPreview() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String createdAt,  List<ScheduleBlock> before,  List<ScheduleBlock> after,  List<ReplanChange> changes,  List<String> postponed,  List<String> advanced,  List<Conflict> conflicts,  List<DayChange> dailyChanges)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReplanPreview() when $default != null:
return $default(_that.id,_that.userId,_that.createdAt,_that.before,_that.after,_that.changes,_that.postponed,_that.advanced,_that.conflicts,_that.dailyChanges);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String createdAt,  List<ScheduleBlock> before,  List<ScheduleBlock> after,  List<ReplanChange> changes,  List<String> postponed,  List<String> advanced,  List<Conflict> conflicts,  List<DayChange> dailyChanges)  $default,) {final _that = this;
switch (_that) {
case _ReplanPreview():
return $default(_that.id,_that.userId,_that.createdAt,_that.before,_that.after,_that.changes,_that.postponed,_that.advanced,_that.conflicts,_that.dailyChanges);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String createdAt,  List<ScheduleBlock> before,  List<ScheduleBlock> after,  List<ReplanChange> changes,  List<String> postponed,  List<String> advanced,  List<Conflict> conflicts,  List<DayChange> dailyChanges)?  $default,) {final _that = this;
switch (_that) {
case _ReplanPreview() when $default != null:
return $default(_that.id,_that.userId,_that.createdAt,_that.before,_that.after,_that.changes,_that.postponed,_that.advanced,_that.conflicts,_that.dailyChanges);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReplanPreview implements ReplanPreview {
  const _ReplanPreview({required this.id, required this.userId, required this.createdAt, required final  List<ScheduleBlock> before, required final  List<ScheduleBlock> after, required final  List<ReplanChange> changes, required final  List<String> postponed, required final  List<String> advanced, required final  List<Conflict> conflicts, required final  List<DayChange> dailyChanges}): _before = before,_after = after,_changes = changes,_postponed = postponed,_advanced = advanced,_conflicts = conflicts,_dailyChanges = dailyChanges;
  factory _ReplanPreview.fromJson(Map<String, dynamic> json) => _$ReplanPreviewFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String createdAt;
 final  List<ScheduleBlock> _before;
@override List<ScheduleBlock> get before {
  if (_before is EqualUnmodifiableListView) return _before;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_before);
}

 final  List<ScheduleBlock> _after;
@override List<ScheduleBlock> get after {
  if (_after is EqualUnmodifiableListView) return _after;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_after);
}

 final  List<ReplanChange> _changes;
@override List<ReplanChange> get changes {
  if (_changes is EqualUnmodifiableListView) return _changes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changes);
}

 final  List<String> _postponed;
@override List<String> get postponed {
  if (_postponed is EqualUnmodifiableListView) return _postponed;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_postponed);
}

 final  List<String> _advanced;
@override List<String> get advanced {
  if (_advanced is EqualUnmodifiableListView) return _advanced;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_advanced);
}

 final  List<Conflict> _conflicts;
@override List<Conflict> get conflicts {
  if (_conflicts is EqualUnmodifiableListView) return _conflicts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_conflicts);
}

 final  List<DayChange> _dailyChanges;
@override List<DayChange> get dailyChanges {
  if (_dailyChanges is EqualUnmodifiableListView) return _dailyChanges;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dailyChanges);
}


/// Create a copy of ReplanPreview
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReplanPreviewCopyWith<_ReplanPreview> get copyWith => __$ReplanPreviewCopyWithImpl<_ReplanPreview>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReplanPreviewToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReplanPreview&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._before, _before)&&const DeepCollectionEquality().equals(other._after, _after)&&const DeepCollectionEquality().equals(other._changes, _changes)&&const DeepCollectionEquality().equals(other._postponed, _postponed)&&const DeepCollectionEquality().equals(other._advanced, _advanced)&&const DeepCollectionEquality().equals(other._conflicts, _conflicts)&&const DeepCollectionEquality().equals(other._dailyChanges, _dailyChanges));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,createdAt,const DeepCollectionEquality().hash(_before),const DeepCollectionEquality().hash(_after),const DeepCollectionEquality().hash(_changes),const DeepCollectionEquality().hash(_postponed),const DeepCollectionEquality().hash(_advanced),const DeepCollectionEquality().hash(_conflicts),const DeepCollectionEquality().hash(_dailyChanges));

@override
String toString() {
  return 'ReplanPreview(id: $id, userId: $userId, createdAt: $createdAt, before: $before, after: $after, changes: $changes, postponed: $postponed, advanced: $advanced, conflicts: $conflicts, dailyChanges: $dailyChanges)';
}


}

/// @nodoc
abstract mixin class _$ReplanPreviewCopyWith<$Res> implements $ReplanPreviewCopyWith<$Res> {
  factory _$ReplanPreviewCopyWith(_ReplanPreview value, $Res Function(_ReplanPreview) _then) = __$ReplanPreviewCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String createdAt, List<ScheduleBlock> before, List<ScheduleBlock> after, List<ReplanChange> changes, List<String> postponed, List<String> advanced, List<Conflict> conflicts, List<DayChange> dailyChanges
});




}
/// @nodoc
class __$ReplanPreviewCopyWithImpl<$Res>
    implements _$ReplanPreviewCopyWith<$Res> {
  __$ReplanPreviewCopyWithImpl(this._self, this._then);

  final _ReplanPreview _self;
  final $Res Function(_ReplanPreview) _then;

/// Create a copy of ReplanPreview
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? createdAt = null,Object? before = null,Object? after = null,Object? changes = null,Object? postponed = null,Object? advanced = null,Object? conflicts = null,Object? dailyChanges = null,}) {
  return _then(_ReplanPreview(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,before: null == before ? _self._before : before // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,after: null == after ? _self._after : after // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,changes: null == changes ? _self._changes : changes // ignore: cast_nullable_to_non_nullable
as List<ReplanChange>,postponed: null == postponed ? _self._postponed : postponed // ignore: cast_nullable_to_non_nullable
as List<String>,advanced: null == advanced ? _self._advanced : advanced // ignore: cast_nullable_to_non_nullable
as List<String>,conflicts: null == conflicts ? _self._conflicts : conflicts // ignore: cast_nullable_to_non_nullable
as List<Conflict>,dailyChanges: null == dailyChanges ? _self._dailyChanges : dailyChanges // ignore: cast_nullable_to_non_nullable
as List<DayChange>,
  ));
}


}


/// @nodoc
mixin _$ReplanRun {

 String get id; String get userId; String get createdAt; List<ScheduleBlock> get before; List<ScheduleBlock> get after; List<ReplanChange> get changes; List<String> get postponed; List<String> get advanced; List<Conflict> get conflicts; List<DayChange> get dailyChanges; ReplanStatus get status; List<TaskStatusSnapshot>? get taskStatusBefore; List<TaskStatusSnapshot>? get taskStatusAfter;/// Local application guard; old TypeScript runs omit it and use block protection.
 JsonMap? get localUndoGuard;
/// Create a copy of ReplanRun
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplanRunCopyWith<ReplanRun> get copyWith => _$ReplanRunCopyWithImpl<ReplanRun>(this as ReplanRun, _$identity);

  /// Serializes this ReplanRun to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplanRun&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.before, before)&&const DeepCollectionEquality().equals(other.after, after)&&const DeepCollectionEquality().equals(other.changes, changes)&&const DeepCollectionEquality().equals(other.postponed, postponed)&&const DeepCollectionEquality().equals(other.advanced, advanced)&&const DeepCollectionEquality().equals(other.conflicts, conflicts)&&const DeepCollectionEquality().equals(other.dailyChanges, dailyChanges)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other.taskStatusBefore, taskStatusBefore)&&const DeepCollectionEquality().equals(other.taskStatusAfter, taskStatusAfter)&&const DeepCollectionEquality().equals(other.localUndoGuard, localUndoGuard));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,createdAt,const DeepCollectionEquality().hash(before),const DeepCollectionEquality().hash(after),const DeepCollectionEquality().hash(changes),const DeepCollectionEquality().hash(postponed),const DeepCollectionEquality().hash(advanced),const DeepCollectionEquality().hash(conflicts),const DeepCollectionEquality().hash(dailyChanges),status,const DeepCollectionEquality().hash(taskStatusBefore),const DeepCollectionEquality().hash(taskStatusAfter),const DeepCollectionEquality().hash(localUndoGuard));

@override
String toString() {
  return 'ReplanRun(id: $id, userId: $userId, createdAt: $createdAt, before: $before, after: $after, changes: $changes, postponed: $postponed, advanced: $advanced, conflicts: $conflicts, dailyChanges: $dailyChanges, status: $status, taskStatusBefore: $taskStatusBefore, taskStatusAfter: $taskStatusAfter, localUndoGuard: $localUndoGuard)';
}


}

/// @nodoc
abstract mixin class $ReplanRunCopyWith<$Res>  {
  factory $ReplanRunCopyWith(ReplanRun value, $Res Function(ReplanRun) _then) = _$ReplanRunCopyWithImpl;
@useResult
$Res call({
 String id, String userId, String createdAt, List<ScheduleBlock> before, List<ScheduleBlock> after, List<ReplanChange> changes, List<String> postponed, List<String> advanced, List<Conflict> conflicts, List<DayChange> dailyChanges, ReplanStatus status, List<TaskStatusSnapshot>? taskStatusBefore, List<TaskStatusSnapshot>? taskStatusAfter, JsonMap? localUndoGuard
});




}
/// @nodoc
class _$ReplanRunCopyWithImpl<$Res>
    implements $ReplanRunCopyWith<$Res> {
  _$ReplanRunCopyWithImpl(this._self, this._then);

  final ReplanRun _self;
  final $Res Function(ReplanRun) _then;

/// Create a copy of ReplanRun
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? userId = null,Object? createdAt = null,Object? before = null,Object? after = null,Object? changes = null,Object? postponed = null,Object? advanced = null,Object? conflicts = null,Object? dailyChanges = null,Object? status = null,Object? taskStatusBefore = freezed,Object? taskStatusAfter = freezed,Object? localUndoGuard = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,before: null == before ? _self.before : before // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,after: null == after ? _self.after : after // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,changes: null == changes ? _self.changes : changes // ignore: cast_nullable_to_non_nullable
as List<ReplanChange>,postponed: null == postponed ? _self.postponed : postponed // ignore: cast_nullable_to_non_nullable
as List<String>,advanced: null == advanced ? _self.advanced : advanced // ignore: cast_nullable_to_non_nullable
as List<String>,conflicts: null == conflicts ? _self.conflicts : conflicts // ignore: cast_nullable_to_non_nullable
as List<Conflict>,dailyChanges: null == dailyChanges ? _self.dailyChanges : dailyChanges // ignore: cast_nullable_to_non_nullable
as List<DayChange>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ReplanStatus,taskStatusBefore: freezed == taskStatusBefore ? _self.taskStatusBefore : taskStatusBefore // ignore: cast_nullable_to_non_nullable
as List<TaskStatusSnapshot>?,taskStatusAfter: freezed == taskStatusAfter ? _self.taskStatusAfter : taskStatusAfter // ignore: cast_nullable_to_non_nullable
as List<TaskStatusSnapshot>?,localUndoGuard: freezed == localUndoGuard ? _self.localUndoGuard : localUndoGuard // ignore: cast_nullable_to_non_nullable
as JsonMap?,
  ));
}

}


/// Adds pattern-matching-related methods to [ReplanRun].
extension ReplanRunPatterns on ReplanRun {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReplanRun value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReplanRun() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReplanRun value)  $default,){
final _that = this;
switch (_that) {
case _ReplanRun():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReplanRun value)?  $default,){
final _that = this;
switch (_that) {
case _ReplanRun() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String userId,  String createdAt,  List<ScheduleBlock> before,  List<ScheduleBlock> after,  List<ReplanChange> changes,  List<String> postponed,  List<String> advanced,  List<Conflict> conflicts,  List<DayChange> dailyChanges,  ReplanStatus status,  List<TaskStatusSnapshot>? taskStatusBefore,  List<TaskStatusSnapshot>? taskStatusAfter,  JsonMap? localUndoGuard)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReplanRun() when $default != null:
return $default(_that.id,_that.userId,_that.createdAt,_that.before,_that.after,_that.changes,_that.postponed,_that.advanced,_that.conflicts,_that.dailyChanges,_that.status,_that.taskStatusBefore,_that.taskStatusAfter,_that.localUndoGuard);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String userId,  String createdAt,  List<ScheduleBlock> before,  List<ScheduleBlock> after,  List<ReplanChange> changes,  List<String> postponed,  List<String> advanced,  List<Conflict> conflicts,  List<DayChange> dailyChanges,  ReplanStatus status,  List<TaskStatusSnapshot>? taskStatusBefore,  List<TaskStatusSnapshot>? taskStatusAfter,  JsonMap? localUndoGuard)  $default,) {final _that = this;
switch (_that) {
case _ReplanRun():
return $default(_that.id,_that.userId,_that.createdAt,_that.before,_that.after,_that.changes,_that.postponed,_that.advanced,_that.conflicts,_that.dailyChanges,_that.status,_that.taskStatusBefore,_that.taskStatusAfter,_that.localUndoGuard);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String userId,  String createdAt,  List<ScheduleBlock> before,  List<ScheduleBlock> after,  List<ReplanChange> changes,  List<String> postponed,  List<String> advanced,  List<Conflict> conflicts,  List<DayChange> dailyChanges,  ReplanStatus status,  List<TaskStatusSnapshot>? taskStatusBefore,  List<TaskStatusSnapshot>? taskStatusAfter,  JsonMap? localUndoGuard)?  $default,) {final _that = this;
switch (_that) {
case _ReplanRun() when $default != null:
return $default(_that.id,_that.userId,_that.createdAt,_that.before,_that.after,_that.changes,_that.postponed,_that.advanced,_that.conflicts,_that.dailyChanges,_that.status,_that.taskStatusBefore,_that.taskStatusAfter,_that.localUndoGuard);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReplanRun implements ReplanRun {
  const _ReplanRun({required this.id, required this.userId, required this.createdAt, required final  List<ScheduleBlock> before, required final  List<ScheduleBlock> after, required final  List<ReplanChange> changes, required final  List<String> postponed, required final  List<String> advanced, required final  List<Conflict> conflicts, required final  List<DayChange> dailyChanges, required this.status, final  List<TaskStatusSnapshot>? taskStatusBefore, final  List<TaskStatusSnapshot>? taskStatusAfter, final  JsonMap? localUndoGuard}): _before = before,_after = after,_changes = changes,_postponed = postponed,_advanced = advanced,_conflicts = conflicts,_dailyChanges = dailyChanges,_taskStatusBefore = taskStatusBefore,_taskStatusAfter = taskStatusAfter,_localUndoGuard = localUndoGuard;
  factory _ReplanRun.fromJson(Map<String, dynamic> json) => _$ReplanRunFromJson(json);

@override final  String id;
@override final  String userId;
@override final  String createdAt;
 final  List<ScheduleBlock> _before;
@override List<ScheduleBlock> get before {
  if (_before is EqualUnmodifiableListView) return _before;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_before);
}

 final  List<ScheduleBlock> _after;
@override List<ScheduleBlock> get after {
  if (_after is EqualUnmodifiableListView) return _after;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_after);
}

 final  List<ReplanChange> _changes;
@override List<ReplanChange> get changes {
  if (_changes is EqualUnmodifiableListView) return _changes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_changes);
}

 final  List<String> _postponed;
@override List<String> get postponed {
  if (_postponed is EqualUnmodifiableListView) return _postponed;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_postponed);
}

 final  List<String> _advanced;
@override List<String> get advanced {
  if (_advanced is EqualUnmodifiableListView) return _advanced;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_advanced);
}

 final  List<Conflict> _conflicts;
@override List<Conflict> get conflicts {
  if (_conflicts is EqualUnmodifiableListView) return _conflicts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_conflicts);
}

 final  List<DayChange> _dailyChanges;
@override List<DayChange> get dailyChanges {
  if (_dailyChanges is EqualUnmodifiableListView) return _dailyChanges;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_dailyChanges);
}

@override final  ReplanStatus status;
 final  List<TaskStatusSnapshot>? _taskStatusBefore;
@override List<TaskStatusSnapshot>? get taskStatusBefore {
  final value = _taskStatusBefore;
  if (value == null) return null;
  if (_taskStatusBefore is EqualUnmodifiableListView) return _taskStatusBefore;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<TaskStatusSnapshot>? _taskStatusAfter;
@override List<TaskStatusSnapshot>? get taskStatusAfter {
  final value = _taskStatusAfter;
  if (value == null) return null;
  if (_taskStatusAfter is EqualUnmodifiableListView) return _taskStatusAfter;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

/// Local application guard; old TypeScript runs omit it and use block protection.
 final  JsonMap? _localUndoGuard;
/// Local application guard; old TypeScript runs omit it and use block protection.
@override JsonMap? get localUndoGuard {
  final value = _localUndoGuard;
  if (value == null) return null;
  if (_localUndoGuard is EqualUnmodifiableMapView) return _localUndoGuard;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of ReplanRun
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReplanRunCopyWith<_ReplanRun> get copyWith => __$ReplanRunCopyWithImpl<_ReplanRun>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReplanRunToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReplanRun&&(identical(other.id, id) || other.id == id)&&(identical(other.userId, userId) || other.userId == userId)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._before, _before)&&const DeepCollectionEquality().equals(other._after, _after)&&const DeepCollectionEquality().equals(other._changes, _changes)&&const DeepCollectionEquality().equals(other._postponed, _postponed)&&const DeepCollectionEquality().equals(other._advanced, _advanced)&&const DeepCollectionEquality().equals(other._conflicts, _conflicts)&&const DeepCollectionEquality().equals(other._dailyChanges, _dailyChanges)&&(identical(other.status, status) || other.status == status)&&const DeepCollectionEquality().equals(other._taskStatusBefore, _taskStatusBefore)&&const DeepCollectionEquality().equals(other._taskStatusAfter, _taskStatusAfter)&&const DeepCollectionEquality().equals(other._localUndoGuard, _localUndoGuard));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,userId,createdAt,const DeepCollectionEquality().hash(_before),const DeepCollectionEquality().hash(_after),const DeepCollectionEquality().hash(_changes),const DeepCollectionEquality().hash(_postponed),const DeepCollectionEquality().hash(_advanced),const DeepCollectionEquality().hash(_conflicts),const DeepCollectionEquality().hash(_dailyChanges),status,const DeepCollectionEquality().hash(_taskStatusBefore),const DeepCollectionEquality().hash(_taskStatusAfter),const DeepCollectionEquality().hash(_localUndoGuard));

@override
String toString() {
  return 'ReplanRun(id: $id, userId: $userId, createdAt: $createdAt, before: $before, after: $after, changes: $changes, postponed: $postponed, advanced: $advanced, conflicts: $conflicts, dailyChanges: $dailyChanges, status: $status, taskStatusBefore: $taskStatusBefore, taskStatusAfter: $taskStatusAfter, localUndoGuard: $localUndoGuard)';
}


}

/// @nodoc
abstract mixin class _$ReplanRunCopyWith<$Res> implements $ReplanRunCopyWith<$Res> {
  factory _$ReplanRunCopyWith(_ReplanRun value, $Res Function(_ReplanRun) _then) = __$ReplanRunCopyWithImpl;
@override @useResult
$Res call({
 String id, String userId, String createdAt, List<ScheduleBlock> before, List<ScheduleBlock> after, List<ReplanChange> changes, List<String> postponed, List<String> advanced, List<Conflict> conflicts, List<DayChange> dailyChanges, ReplanStatus status, List<TaskStatusSnapshot>? taskStatusBefore, List<TaskStatusSnapshot>? taskStatusAfter, JsonMap? localUndoGuard
});




}
/// @nodoc
class __$ReplanRunCopyWithImpl<$Res>
    implements _$ReplanRunCopyWith<$Res> {
  __$ReplanRunCopyWithImpl(this._self, this._then);

  final _ReplanRun _self;
  final $Res Function(_ReplanRun) _then;

/// Create a copy of ReplanRun
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? userId = null,Object? createdAt = null,Object? before = null,Object? after = null,Object? changes = null,Object? postponed = null,Object? advanced = null,Object? conflicts = null,Object? dailyChanges = null,Object? status = null,Object? taskStatusBefore = freezed,Object? taskStatusAfter = freezed,Object? localUndoGuard = freezed,}) {
  return _then(_ReplanRun(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,userId: null == userId ? _self.userId : userId // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as String,before: null == before ? _self._before : before // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,after: null == after ? _self._after : after // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,changes: null == changes ? _self._changes : changes // ignore: cast_nullable_to_non_nullable
as List<ReplanChange>,postponed: null == postponed ? _self._postponed : postponed // ignore: cast_nullable_to_non_nullable
as List<String>,advanced: null == advanced ? _self._advanced : advanced // ignore: cast_nullable_to_non_nullable
as List<String>,conflicts: null == conflicts ? _self._conflicts : conflicts // ignore: cast_nullable_to_non_nullable
as List<Conflict>,dailyChanges: null == dailyChanges ? _self._dailyChanges : dailyChanges // ignore: cast_nullable_to_non_nullable
as List<DayChange>,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ReplanStatus,taskStatusBefore: freezed == taskStatusBefore ? _self._taskStatusBefore : taskStatusBefore // ignore: cast_nullable_to_non_nullable
as List<TaskStatusSnapshot>?,taskStatusAfter: freezed == taskStatusAfter ? _self._taskStatusAfter : taskStatusAfter // ignore: cast_nullable_to_non_nullable
as List<TaskStatusSnapshot>?,localUndoGuard: freezed == localUndoGuard ? _self._localUndoGuard : localUndoGuard // ignore: cast_nullable_to_non_nullable
as JsonMap?,
  ));
}


}


/// @nodoc
mixin _$ReplanInput {

 List<Task> get tasks; List<ScheduleBlock> get blocks; List<TimeLog> get logs; List<FixedEvent> get fixedEvents; Profile get profile; String get today; ReplanMode get mode; int? get excessMinutes;
/// Create a copy of ReplanInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReplanInputCopyWith<ReplanInput> get copyWith => _$ReplanInputCopyWithImpl<ReplanInput>(this as ReplanInput, _$identity);

  /// Serializes this ReplanInput to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReplanInput&&const DeepCollectionEquality().equals(other.tasks, tasks)&&const DeepCollectionEquality().equals(other.blocks, blocks)&&const DeepCollectionEquality().equals(other.logs, logs)&&const DeepCollectionEquality().equals(other.fixedEvents, fixedEvents)&&(identical(other.profile, profile) || other.profile == profile)&&(identical(other.today, today) || other.today == today)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.excessMinutes, excessMinutes) || other.excessMinutes == excessMinutes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(tasks),const DeepCollectionEquality().hash(blocks),const DeepCollectionEquality().hash(logs),const DeepCollectionEquality().hash(fixedEvents),profile,today,mode,excessMinutes);

@override
String toString() {
  return 'ReplanInput(tasks: $tasks, blocks: $blocks, logs: $logs, fixedEvents: $fixedEvents, profile: $profile, today: $today, mode: $mode, excessMinutes: $excessMinutes)';
}


}

/// @nodoc
abstract mixin class $ReplanInputCopyWith<$Res>  {
  factory $ReplanInputCopyWith(ReplanInput value, $Res Function(ReplanInput) _then) = _$ReplanInputCopyWithImpl;
@useResult
$Res call({
 List<Task> tasks, List<ScheduleBlock> blocks, List<TimeLog> logs, List<FixedEvent> fixedEvents, Profile profile, String today, ReplanMode mode, int? excessMinutes
});


$ProfileCopyWith<$Res> get profile;

}
/// @nodoc
class _$ReplanInputCopyWithImpl<$Res>
    implements $ReplanInputCopyWith<$Res> {
  _$ReplanInputCopyWithImpl(this._self, this._then);

  final ReplanInput _self;
  final $Res Function(ReplanInput) _then;

/// Create a copy of ReplanInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? tasks = null,Object? blocks = null,Object? logs = null,Object? fixedEvents = null,Object? profile = null,Object? today = null,Object? mode = null,Object? excessMinutes = freezed,}) {
  return _then(_self.copyWith(
tasks: null == tasks ? _self.tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<Task>,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,logs: null == logs ? _self.logs : logs // ignore: cast_nullable_to_non_nullable
as List<TimeLog>,fixedEvents: null == fixedEvents ? _self.fixedEvents : fixedEvents // ignore: cast_nullable_to_non_nullable
as List<FixedEvent>,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as Profile,today: null == today ? _self.today : today // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ReplanMode,excessMinutes: freezed == excessMinutes ? _self.excessMinutes : excessMinutes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of ReplanInput
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res> get profile {
  
  return $ProfileCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// Adds pattern-matching-related methods to [ReplanInput].
extension ReplanInputPatterns on ReplanInput {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReplanInput value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReplanInput() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReplanInput value)  $default,){
final _that = this;
switch (_that) {
case _ReplanInput():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReplanInput value)?  $default,){
final _that = this;
switch (_that) {
case _ReplanInput() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<Task> tasks,  List<ScheduleBlock> blocks,  List<TimeLog> logs,  List<FixedEvent> fixedEvents,  Profile profile,  String today,  ReplanMode mode,  int? excessMinutes)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReplanInput() when $default != null:
return $default(_that.tasks,_that.blocks,_that.logs,_that.fixedEvents,_that.profile,_that.today,_that.mode,_that.excessMinutes);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<Task> tasks,  List<ScheduleBlock> blocks,  List<TimeLog> logs,  List<FixedEvent> fixedEvents,  Profile profile,  String today,  ReplanMode mode,  int? excessMinutes)  $default,) {final _that = this;
switch (_that) {
case _ReplanInput():
return $default(_that.tasks,_that.blocks,_that.logs,_that.fixedEvents,_that.profile,_that.today,_that.mode,_that.excessMinutes);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<Task> tasks,  List<ScheduleBlock> blocks,  List<TimeLog> logs,  List<FixedEvent> fixedEvents,  Profile profile,  String today,  ReplanMode mode,  int? excessMinutes)?  $default,) {final _that = this;
switch (_that) {
case _ReplanInput() when $default != null:
return $default(_that.tasks,_that.blocks,_that.logs,_that.fixedEvents,_that.profile,_that.today,_that.mode,_that.excessMinutes);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ReplanInput implements ReplanInput {
  const _ReplanInput({required final  List<Task> tasks, required final  List<ScheduleBlock> blocks, required final  List<TimeLog> logs, required final  List<FixedEvent> fixedEvents, required this.profile, required this.today, required this.mode, this.excessMinutes}): _tasks = tasks,_blocks = blocks,_logs = logs,_fixedEvents = fixedEvents;
  factory _ReplanInput.fromJson(Map<String, dynamic> json) => _$ReplanInputFromJson(json);

 final  List<Task> _tasks;
@override List<Task> get tasks {
  if (_tasks is EqualUnmodifiableListView) return _tasks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_tasks);
}

 final  List<ScheduleBlock> _blocks;
@override List<ScheduleBlock> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}

 final  List<TimeLog> _logs;
@override List<TimeLog> get logs {
  if (_logs is EqualUnmodifiableListView) return _logs;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_logs);
}

 final  List<FixedEvent> _fixedEvents;
@override List<FixedEvent> get fixedEvents {
  if (_fixedEvents is EqualUnmodifiableListView) return _fixedEvents;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_fixedEvents);
}

@override final  Profile profile;
@override final  String today;
@override final  ReplanMode mode;
@override final  int? excessMinutes;

/// Create a copy of ReplanInput
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReplanInputCopyWith<_ReplanInput> get copyWith => __$ReplanInputCopyWithImpl<_ReplanInput>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ReplanInputToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReplanInput&&const DeepCollectionEquality().equals(other._tasks, _tasks)&&const DeepCollectionEquality().equals(other._blocks, _blocks)&&const DeepCollectionEquality().equals(other._logs, _logs)&&const DeepCollectionEquality().equals(other._fixedEvents, _fixedEvents)&&(identical(other.profile, profile) || other.profile == profile)&&(identical(other.today, today) || other.today == today)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.excessMinutes, excessMinutes) || other.excessMinutes == excessMinutes));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_tasks),const DeepCollectionEquality().hash(_blocks),const DeepCollectionEquality().hash(_logs),const DeepCollectionEquality().hash(_fixedEvents),profile,today,mode,excessMinutes);

@override
String toString() {
  return 'ReplanInput(tasks: $tasks, blocks: $blocks, logs: $logs, fixedEvents: $fixedEvents, profile: $profile, today: $today, mode: $mode, excessMinutes: $excessMinutes)';
}


}

/// @nodoc
abstract mixin class _$ReplanInputCopyWith<$Res> implements $ReplanInputCopyWith<$Res> {
  factory _$ReplanInputCopyWith(_ReplanInput value, $Res Function(_ReplanInput) _then) = __$ReplanInputCopyWithImpl;
@override @useResult
$Res call({
 List<Task> tasks, List<ScheduleBlock> blocks, List<TimeLog> logs, List<FixedEvent> fixedEvents, Profile profile, String today, ReplanMode mode, int? excessMinutes
});


@override $ProfileCopyWith<$Res> get profile;

}
/// @nodoc
class __$ReplanInputCopyWithImpl<$Res>
    implements _$ReplanInputCopyWith<$Res> {
  __$ReplanInputCopyWithImpl(this._self, this._then);

  final _ReplanInput _self;
  final $Res Function(_ReplanInput) _then;

/// Create a copy of ReplanInput
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? tasks = null,Object? blocks = null,Object? logs = null,Object? fixedEvents = null,Object? profile = null,Object? today = null,Object? mode = null,Object? excessMinutes = freezed,}) {
  return _then(_ReplanInput(
tasks: null == tasks ? _self._tasks : tasks // ignore: cast_nullable_to_non_nullable
as List<Task>,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<ScheduleBlock>,logs: null == logs ? _self._logs : logs // ignore: cast_nullable_to_non_nullable
as List<TimeLog>,fixedEvents: null == fixedEvents ? _self._fixedEvents : fixedEvents // ignore: cast_nullable_to_non_nullable
as List<FixedEvent>,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as Profile,today: null == today ? _self.today : today // ignore: cast_nullable_to_non_nullable
as String,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ReplanMode,excessMinutes: freezed == excessMinutes ? _self.excessMinutes : excessMinutes // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of ReplanInput
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProfileCopyWith<$Res> get profile {
  
  return $ProfileCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// @nodoc
mixin _$SyncMetadata {

@JsonKey(fromJson: _versionOne) int get version;@JsonKey(fromJson: _revision) int get revision; bool get pending;@JsonKey(includeIfNull: true) PlannerData? get base;@JsonKey(name: 'updatedAt', includeIfNull: true) DateTime? get updatedAt;
/// Create a copy of SyncMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncMetadataCopyWith<SyncMetadata> get copyWith => _$SyncMetadataCopyWithImpl<SyncMetadata>(this as SyncMetadata, _$identity);

  /// Serializes this SyncMetadata to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncMetadata&&(identical(other.version, version) || other.version == version)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.base, base) || other.base == base)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,version,revision,pending,base,updatedAt);

@override
String toString() {
  return 'SyncMetadata(version: $version, revision: $revision, pending: $pending, base: $base, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SyncMetadataCopyWith<$Res>  {
  factory $SyncMetadataCopyWith(SyncMetadata value, $Res Function(SyncMetadata) _then) = _$SyncMetadataCopyWithImpl;
@useResult
$Res call({
@JsonKey(fromJson: _versionOne) int version,@JsonKey(fromJson: _revision) int revision, bool pending,@JsonKey(includeIfNull: true) PlannerData? base,@JsonKey(name: 'updatedAt', includeIfNull: true) DateTime? updatedAt
});


$PlannerDataCopyWith<$Res>? get base;

}
/// @nodoc
class _$SyncMetadataCopyWithImpl<$Res>
    implements $SyncMetadataCopyWith<$Res> {
  _$SyncMetadataCopyWithImpl(this._self, this._then);

  final SyncMetadata _self;
  final $Res Function(SyncMetadata) _then;

/// Create a copy of SyncMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? revision = null,Object? pending = null,Object? base = freezed,Object? updatedAt = freezed,}) {
  return _then(_self.copyWith(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,base: freezed == base ? _self.base : base // ignore: cast_nullable_to_non_nullable
as PlannerData?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}
/// Create a copy of SyncMetadata
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlannerDataCopyWith<$Res>? get base {
    if (_self.base == null) {
    return null;
  }

  return $PlannerDataCopyWith<$Res>(_self.base!, (value) {
    return _then(_self.copyWith(base: value));
  });
}
}


/// Adds pattern-matching-related methods to [SyncMetadata].
extension SyncMetadataPatterns on SyncMetadata {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SyncMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SyncMetadata() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SyncMetadata value)  $default,){
final _that = this;
switch (_that) {
case _SyncMetadata():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SyncMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _SyncMetadata() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function(@JsonKey(fromJson: _versionOne)  int version, @JsonKey(fromJson: _revision)  int revision,  bool pending, @JsonKey(includeIfNull: true)  PlannerData? base, @JsonKey(name: 'updatedAt', includeIfNull: true)  DateTime? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SyncMetadata() when $default != null:
return $default(_that.version,_that.revision,_that.pending,_that.base,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function(@JsonKey(fromJson: _versionOne)  int version, @JsonKey(fromJson: _revision)  int revision,  bool pending, @JsonKey(includeIfNull: true)  PlannerData? base, @JsonKey(name: 'updatedAt', includeIfNull: true)  DateTime? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _SyncMetadata():
return $default(_that.version,_that.revision,_that.pending,_that.base,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function(@JsonKey(fromJson: _versionOne)  int version, @JsonKey(fromJson: _revision)  int revision,  bool pending, @JsonKey(includeIfNull: true)  PlannerData? base, @JsonKey(name: 'updatedAt', includeIfNull: true)  DateTime? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _SyncMetadata() when $default != null:
return $default(_that.version,_that.revision,_that.pending,_that.base,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _SyncMetadata implements SyncMetadata {
  const _SyncMetadata({@JsonKey(fromJson: _versionOne) this.version = 1, @JsonKey(fromJson: _revision) this.revision = 0, this.pending = false, @JsonKey(includeIfNull: true) this.base, @JsonKey(name: 'updatedAt', includeIfNull: true) this.updatedAt});
  factory _SyncMetadata.fromJson(Map<String, dynamic> json) => _$SyncMetadataFromJson(json);

@override@JsonKey(fromJson: _versionOne) final  int version;
@override@JsonKey(fromJson: _revision) final  int revision;
@override@JsonKey() final  bool pending;
@override@JsonKey(includeIfNull: true) final  PlannerData? base;
@override@JsonKey(name: 'updatedAt', includeIfNull: true) final  DateTime? updatedAt;

/// Create a copy of SyncMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SyncMetadataCopyWith<_SyncMetadata> get copyWith => __$SyncMetadataCopyWithImpl<_SyncMetadata>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$SyncMetadataToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _SyncMetadata&&(identical(other.version, version) || other.version == version)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.pending, pending) || other.pending == pending)&&(identical(other.base, base) || other.base == base)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,version,revision,pending,base,updatedAt);

@override
String toString() {
  return 'SyncMetadata(version: $version, revision: $revision, pending: $pending, base: $base, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SyncMetadataCopyWith<$Res> implements $SyncMetadataCopyWith<$Res> {
  factory _$SyncMetadataCopyWith(_SyncMetadata value, $Res Function(_SyncMetadata) _then) = __$SyncMetadataCopyWithImpl;
@override @useResult
$Res call({
@JsonKey(fromJson: _versionOne) int version,@JsonKey(fromJson: _revision) int revision, bool pending,@JsonKey(includeIfNull: true) PlannerData? base,@JsonKey(name: 'updatedAt', includeIfNull: true) DateTime? updatedAt
});


@override $PlannerDataCopyWith<$Res>? get base;

}
/// @nodoc
class __$SyncMetadataCopyWithImpl<$Res>
    implements _$SyncMetadataCopyWith<$Res> {
  __$SyncMetadataCopyWithImpl(this._self, this._then);

  final _SyncMetadata _self;
  final $Res Function(_SyncMetadata) _then;

/// Create a copy of SyncMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? revision = null,Object? pending = null,Object? base = freezed,Object? updatedAt = freezed,}) {
  return _then(_SyncMetadata(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,pending: null == pending ? _self.pending : pending // ignore: cast_nullable_to_non_nullable
as bool,base: freezed == base ? _self.base : base // ignore: cast_nullable_to_non_nullable
as PlannerData?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,
  ));
}

/// Create a copy of SyncMetadata
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlannerDataCopyWith<$Res>? get base {
    if (_self.base == null) {
    return null;
  }

  return $PlannerDataCopyWith<$Res>(_self.base!, (value) {
    return _then(_self.copyWith(base: value));
  });
}
}

// dart format on
