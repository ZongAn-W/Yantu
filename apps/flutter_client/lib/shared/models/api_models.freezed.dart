// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'api_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$OnboardingProfile {

 String get goalText; String get goalType; String get goalSubtype; String get targetDate; bool get targetDateConfirmed; String get planStartDate; String get planEndDate; String get targetSchool; String get targetProgram; String get currentProgress; Map<String, int> get weeklyMinutes; String get constraintsText;
/// Create a copy of OnboardingProfile
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OnboardingProfileCopyWith<OnboardingProfile> get copyWith => _$OnboardingProfileCopyWithImpl<OnboardingProfile>(this as OnboardingProfile, _$identity);

  /// Serializes this OnboardingProfile to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OnboardingProfile&&(identical(other.goalText, goalText) || other.goalText == goalText)&&(identical(other.goalType, goalType) || other.goalType == goalType)&&(identical(other.goalSubtype, goalSubtype) || other.goalSubtype == goalSubtype)&&(identical(other.targetDate, targetDate) || other.targetDate == targetDate)&&(identical(other.targetDateConfirmed, targetDateConfirmed) || other.targetDateConfirmed == targetDateConfirmed)&&(identical(other.planStartDate, planStartDate) || other.planStartDate == planStartDate)&&(identical(other.planEndDate, planEndDate) || other.planEndDate == planEndDate)&&(identical(other.targetSchool, targetSchool) || other.targetSchool == targetSchool)&&(identical(other.targetProgram, targetProgram) || other.targetProgram == targetProgram)&&(identical(other.currentProgress, currentProgress) || other.currentProgress == currentProgress)&&const DeepCollectionEquality().equals(other.weeklyMinutes, weeklyMinutes)&&(identical(other.constraintsText, constraintsText) || other.constraintsText == constraintsText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goalText,goalType,goalSubtype,targetDate,targetDateConfirmed,planStartDate,planEndDate,targetSchool,targetProgram,currentProgress,const DeepCollectionEquality().hash(weeklyMinutes),constraintsText);

@override
String toString() {
  return 'OnboardingProfile(goalText: $goalText, goalType: $goalType, goalSubtype: $goalSubtype, targetDate: $targetDate, targetDateConfirmed: $targetDateConfirmed, planStartDate: $planStartDate, planEndDate: $planEndDate, targetSchool: $targetSchool, targetProgram: $targetProgram, currentProgress: $currentProgress, weeklyMinutes: $weeklyMinutes, constraintsText: $constraintsText)';
}


}

/// @nodoc
abstract mixin class $OnboardingProfileCopyWith<$Res>  {
  factory $OnboardingProfileCopyWith(OnboardingProfile value, $Res Function(OnboardingProfile) _then) = _$OnboardingProfileCopyWithImpl;
@useResult
$Res call({
 String goalText, String goalType, String goalSubtype, String targetDate, bool targetDateConfirmed, String planStartDate, String planEndDate, String targetSchool, String targetProgram, String currentProgress, Map<String, int> weeklyMinutes, String constraintsText
});




}
/// @nodoc
class _$OnboardingProfileCopyWithImpl<$Res>
    implements $OnboardingProfileCopyWith<$Res> {
  _$OnboardingProfileCopyWithImpl(this._self, this._then);

  final OnboardingProfile _self;
  final $Res Function(OnboardingProfile) _then;

/// Create a copy of OnboardingProfile
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? goalText = null,Object? goalType = null,Object? goalSubtype = null,Object? targetDate = null,Object? targetDateConfirmed = null,Object? planStartDate = null,Object? planEndDate = null,Object? targetSchool = null,Object? targetProgram = null,Object? currentProgress = null,Object? weeklyMinutes = null,Object? constraintsText = null,}) {
  return _then(_self.copyWith(
goalText: null == goalText ? _self.goalText : goalText // ignore: cast_nullable_to_non_nullable
as String,goalType: null == goalType ? _self.goalType : goalType // ignore: cast_nullable_to_non_nullable
as String,goalSubtype: null == goalSubtype ? _self.goalSubtype : goalSubtype // ignore: cast_nullable_to_non_nullable
as String,targetDate: null == targetDate ? _self.targetDate : targetDate // ignore: cast_nullable_to_non_nullable
as String,targetDateConfirmed: null == targetDateConfirmed ? _self.targetDateConfirmed : targetDateConfirmed // ignore: cast_nullable_to_non_nullable
as bool,planStartDate: null == planStartDate ? _self.planStartDate : planStartDate // ignore: cast_nullable_to_non_nullable
as String,planEndDate: null == planEndDate ? _self.planEndDate : planEndDate // ignore: cast_nullable_to_non_nullable
as String,targetSchool: null == targetSchool ? _self.targetSchool : targetSchool // ignore: cast_nullable_to_non_nullable
as String,targetProgram: null == targetProgram ? _self.targetProgram : targetProgram // ignore: cast_nullable_to_non_nullable
as String,currentProgress: null == currentProgress ? _self.currentProgress : currentProgress // ignore: cast_nullable_to_non_nullable
as String,weeklyMinutes: null == weeklyMinutes ? _self.weeklyMinutes : weeklyMinutes // ignore: cast_nullable_to_non_nullable
as Map<String, int>,constraintsText: null == constraintsText ? _self.constraintsText : constraintsText // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [OnboardingProfile].
extension OnboardingProfilePatterns on OnboardingProfile {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OnboardingProfile value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OnboardingProfile() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OnboardingProfile value)  $default,){
final _that = this;
switch (_that) {
case _OnboardingProfile():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OnboardingProfile value)?  $default,){
final _that = this;
switch (_that) {
case _OnboardingProfile() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String goalText,  String goalType,  String goalSubtype,  String targetDate,  bool targetDateConfirmed,  String planStartDate,  String planEndDate,  String targetSchool,  String targetProgram,  String currentProgress,  Map<String, int> weeklyMinutes,  String constraintsText)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OnboardingProfile() when $default != null:
return $default(_that.goalText,_that.goalType,_that.goalSubtype,_that.targetDate,_that.targetDateConfirmed,_that.planStartDate,_that.planEndDate,_that.targetSchool,_that.targetProgram,_that.currentProgress,_that.weeklyMinutes,_that.constraintsText);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String goalText,  String goalType,  String goalSubtype,  String targetDate,  bool targetDateConfirmed,  String planStartDate,  String planEndDate,  String targetSchool,  String targetProgram,  String currentProgress,  Map<String, int> weeklyMinutes,  String constraintsText)  $default,) {final _that = this;
switch (_that) {
case _OnboardingProfile():
return $default(_that.goalText,_that.goalType,_that.goalSubtype,_that.targetDate,_that.targetDateConfirmed,_that.planStartDate,_that.planEndDate,_that.targetSchool,_that.targetProgram,_that.currentProgress,_that.weeklyMinutes,_that.constraintsText);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String goalText,  String goalType,  String goalSubtype,  String targetDate,  bool targetDateConfirmed,  String planStartDate,  String planEndDate,  String targetSchool,  String targetProgram,  String currentProgress,  Map<String, int> weeklyMinutes,  String constraintsText)?  $default,) {final _that = this;
switch (_that) {
case _OnboardingProfile() when $default != null:
return $default(_that.goalText,_that.goalType,_that.goalSubtype,_that.targetDate,_that.targetDateConfirmed,_that.planStartDate,_that.planEndDate,_that.targetSchool,_that.targetProgram,_that.currentProgress,_that.weeklyMinutes,_that.constraintsText);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _OnboardingProfile extends OnboardingProfile {
  const _OnboardingProfile({this.goalText = '', this.goalType = 'other', this.goalSubtype = '', this.targetDate = '', this.targetDateConfirmed = false, this.planStartDate = '', this.planEndDate = '', this.targetSchool = '', this.targetProgram = '', this.currentProgress = '', final  Map<String, int> weeklyMinutes = const {'0' : 0, '1' : 0, '2' : 0, '3' : 0, '4' : 0, '5' : 0, '6' : 0}, this.constraintsText = ''}): _weeklyMinutes = weeklyMinutes,super._();
  factory _OnboardingProfile.fromJson(Map<String, dynamic> json) => _$OnboardingProfileFromJson(json);

@override@JsonKey() final  String goalText;
@override@JsonKey() final  String goalType;
@override@JsonKey() final  String goalSubtype;
@override@JsonKey() final  String targetDate;
@override@JsonKey() final  bool targetDateConfirmed;
@override@JsonKey() final  String planStartDate;
@override@JsonKey() final  String planEndDate;
@override@JsonKey() final  String targetSchool;
@override@JsonKey() final  String targetProgram;
@override@JsonKey() final  String currentProgress;
 final  Map<String, int> _weeklyMinutes;
@override@JsonKey() Map<String, int> get weeklyMinutes {
  if (_weeklyMinutes is EqualUnmodifiableMapView) return _weeklyMinutes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_weeklyMinutes);
}

@override@JsonKey() final  String constraintsText;

/// Create a copy of OnboardingProfile
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OnboardingProfileCopyWith<_OnboardingProfile> get copyWith => __$OnboardingProfileCopyWithImpl<_OnboardingProfile>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$OnboardingProfileToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _OnboardingProfile&&(identical(other.goalText, goalText) || other.goalText == goalText)&&(identical(other.goalType, goalType) || other.goalType == goalType)&&(identical(other.goalSubtype, goalSubtype) || other.goalSubtype == goalSubtype)&&(identical(other.targetDate, targetDate) || other.targetDate == targetDate)&&(identical(other.targetDateConfirmed, targetDateConfirmed) || other.targetDateConfirmed == targetDateConfirmed)&&(identical(other.planStartDate, planStartDate) || other.planStartDate == planStartDate)&&(identical(other.planEndDate, planEndDate) || other.planEndDate == planEndDate)&&(identical(other.targetSchool, targetSchool) || other.targetSchool == targetSchool)&&(identical(other.targetProgram, targetProgram) || other.targetProgram == targetProgram)&&(identical(other.currentProgress, currentProgress) || other.currentProgress == currentProgress)&&const DeepCollectionEquality().equals(other._weeklyMinutes, _weeklyMinutes)&&(identical(other.constraintsText, constraintsText) || other.constraintsText == constraintsText));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,goalText,goalType,goalSubtype,targetDate,targetDateConfirmed,planStartDate,planEndDate,targetSchool,targetProgram,currentProgress,const DeepCollectionEquality().hash(_weeklyMinutes),constraintsText);

@override
String toString() {
  return 'OnboardingProfile(goalText: $goalText, goalType: $goalType, goalSubtype: $goalSubtype, targetDate: $targetDate, targetDateConfirmed: $targetDateConfirmed, planStartDate: $planStartDate, planEndDate: $planEndDate, targetSchool: $targetSchool, targetProgram: $targetProgram, currentProgress: $currentProgress, weeklyMinutes: $weeklyMinutes, constraintsText: $constraintsText)';
}


}

/// @nodoc
abstract mixin class _$OnboardingProfileCopyWith<$Res> implements $OnboardingProfileCopyWith<$Res> {
  factory _$OnboardingProfileCopyWith(_OnboardingProfile value, $Res Function(_OnboardingProfile) _then) = __$OnboardingProfileCopyWithImpl;
@override @useResult
$Res call({
 String goalText, String goalType, String goalSubtype, String targetDate, bool targetDateConfirmed, String planStartDate, String planEndDate, String targetSchool, String targetProgram, String currentProgress, Map<String, int> weeklyMinutes, String constraintsText
});




}
/// @nodoc
class __$OnboardingProfileCopyWithImpl<$Res>
    implements _$OnboardingProfileCopyWith<$Res> {
  __$OnboardingProfileCopyWithImpl(this._self, this._then);

  final _OnboardingProfile _self;
  final $Res Function(_OnboardingProfile) _then;

/// Create a copy of OnboardingProfile
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? goalText = null,Object? goalType = null,Object? goalSubtype = null,Object? targetDate = null,Object? targetDateConfirmed = null,Object? planStartDate = null,Object? planEndDate = null,Object? targetSchool = null,Object? targetProgram = null,Object? currentProgress = null,Object? weeklyMinutes = null,Object? constraintsText = null,}) {
  return _then(_OnboardingProfile(
goalText: null == goalText ? _self.goalText : goalText // ignore: cast_nullable_to_non_nullable
as String,goalType: null == goalType ? _self.goalType : goalType // ignore: cast_nullable_to_non_nullable
as String,goalSubtype: null == goalSubtype ? _self.goalSubtype : goalSubtype // ignore: cast_nullable_to_non_nullable
as String,targetDate: null == targetDate ? _self.targetDate : targetDate // ignore: cast_nullable_to_non_nullable
as String,targetDateConfirmed: null == targetDateConfirmed ? _self.targetDateConfirmed : targetDateConfirmed // ignore: cast_nullable_to_non_nullable
as bool,planStartDate: null == planStartDate ? _self.planStartDate : planStartDate // ignore: cast_nullable_to_non_nullable
as String,planEndDate: null == planEndDate ? _self.planEndDate : planEndDate // ignore: cast_nullable_to_non_nullable
as String,targetSchool: null == targetSchool ? _self.targetSchool : targetSchool // ignore: cast_nullable_to_non_nullable
as String,targetProgram: null == targetProgram ? _self.targetProgram : targetProgram // ignore: cast_nullable_to_non_nullable
as String,currentProgress: null == currentProgress ? _self.currentProgress : currentProgress // ignore: cast_nullable_to_non_nullable
as String,weeklyMinutes: null == weeklyMinutes ? _self._weeklyMinutes : weeklyMinutes // ignore: cast_nullable_to_non_nullable
as Map<String, int>,constraintsText: null == constraintsText ? _self.constraintsText : constraintsText // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$CourseDraft {

 String get id; String get name; String get description; int get priority;
/// Create a copy of CourseDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CourseDraftCopyWith<CourseDraft> get copyWith => _$CourseDraftCopyWithImpl<CourseDraft>(this as CourseDraft, _$identity);

  /// Serializes this CourseDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CourseDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.priority, priority) || other.priority == priority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,priority);

@override
String toString() {
  return 'CourseDraft(id: $id, name: $name, description: $description, priority: $priority)';
}


}

/// @nodoc
abstract mixin class $CourseDraftCopyWith<$Res>  {
  factory $CourseDraftCopyWith(CourseDraft value, $Res Function(CourseDraft) _then) = _$CourseDraftCopyWithImpl;
@useResult
$Res call({
 String id, String name, String description, int priority
});




}
/// @nodoc
class _$CourseDraftCopyWithImpl<$Res>
    implements $CourseDraftCopyWith<$Res> {
  _$CourseDraftCopyWithImpl(this._self, this._then);

  final CourseDraft _self;
  final $Res Function(CourseDraft) _then;

/// Create a copy of CourseDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = null,Object? priority = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [CourseDraft].
extension CourseDraftPatterns on CourseDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CourseDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CourseDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CourseDraft value)  $default,){
final _that = this;
switch (_that) {
case _CourseDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CourseDraft value)?  $default,){
final _that = this;
switch (_that) {
case _CourseDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String description,  int priority)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CourseDraft() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.priority);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String description,  int priority)  $default,) {final _that = this;
switch (_that) {
case _CourseDraft():
return $default(_that.id,_that.name,_that.description,_that.priority);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String description,  int priority)?  $default,) {final _that = this;
switch (_that) {
case _CourseDraft() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.priority);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _CourseDraft implements CourseDraft {
  const _CourseDraft({required this.id, required this.name, this.description = '', this.priority = 2});
  factory _CourseDraft.fromJson(Map<String, dynamic> json) => _$CourseDraftFromJson(json);

@override final  String id;
@override final  String name;
@override@JsonKey() final  String description;
@override@JsonKey() final  int priority;

/// Create a copy of CourseDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CourseDraftCopyWith<_CourseDraft> get copyWith => __$CourseDraftCopyWithImpl<_CourseDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$CourseDraftToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _CourseDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.priority, priority) || other.priority == priority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description,priority);

@override
String toString() {
  return 'CourseDraft(id: $id, name: $name, description: $description, priority: $priority)';
}


}

/// @nodoc
abstract mixin class _$CourseDraftCopyWith<$Res> implements $CourseDraftCopyWith<$Res> {
  factory _$CourseDraftCopyWith(_CourseDraft value, $Res Function(_CourseDraft) _then) = __$CourseDraftCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String description, int priority
});




}
/// @nodoc
class __$CourseDraftCopyWithImpl<$Res>
    implements _$CourseDraftCopyWith<$Res> {
  __$CourseDraftCopyWithImpl(this._self, this._then);

  final _CourseDraft _self;
  final $Res Function(_CourseDraft) _then;

/// Create a copy of CourseDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = null,Object? priority = null,}) {
  return _then(_CourseDraft(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$ItemDraft {

 String get id; String get courseId; String get title; String get description; String get completionCriteria; int get estimatedMinutes; String? get earliestDate; String get deadline; ItemDateKind get deadlineKind; int get priority;
/// Create a copy of ItemDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ItemDraftCopyWith<ItemDraft> get copyWith => _$ItemDraftCopyWithImpl<ItemDraft>(this as ItemDraft, _$identity);

  /// Serializes this ItemDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ItemDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.courseId, courseId) || other.courseId == courseId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.completionCriteria, completionCriteria) || other.completionCriteria == completionCriteria)&&(identical(other.estimatedMinutes, estimatedMinutes) || other.estimatedMinutes == estimatedMinutes)&&(identical(other.earliestDate, earliestDate) || other.earliestDate == earliestDate)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.deadlineKind, deadlineKind) || other.deadlineKind == deadlineKind)&&(identical(other.priority, priority) || other.priority == priority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,courseId,title,description,completionCriteria,estimatedMinutes,earliestDate,deadline,deadlineKind,priority);

@override
String toString() {
  return 'ItemDraft(id: $id, courseId: $courseId, title: $title, description: $description, completionCriteria: $completionCriteria, estimatedMinutes: $estimatedMinutes, earliestDate: $earliestDate, deadline: $deadline, deadlineKind: $deadlineKind, priority: $priority)';
}


}

/// @nodoc
abstract mixin class $ItemDraftCopyWith<$Res>  {
  factory $ItemDraftCopyWith(ItemDraft value, $Res Function(ItemDraft) _then) = _$ItemDraftCopyWithImpl;
@useResult
$Res call({
 String id, String courseId, String title, String description, String completionCriteria, int estimatedMinutes, String? earliestDate, String deadline, ItemDateKind deadlineKind, int priority
});




}
/// @nodoc
class _$ItemDraftCopyWithImpl<$Res>
    implements $ItemDraftCopyWith<$Res> {
  _$ItemDraftCopyWithImpl(this._self, this._then);

  final ItemDraft _self;
  final $Res Function(ItemDraft) _then;

/// Create a copy of ItemDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? courseId = null,Object? title = null,Object? description = null,Object? completionCriteria = null,Object? estimatedMinutes = null,Object? earliestDate = freezed,Object? deadline = null,Object? deadlineKind = null,Object? priority = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,courseId: null == courseId ? _self.courseId : courseId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,completionCriteria: null == completionCriteria ? _self.completionCriteria : completionCriteria // ignore: cast_nullable_to_non_nullable
as String,estimatedMinutes: null == estimatedMinutes ? _self.estimatedMinutes : estimatedMinutes // ignore: cast_nullable_to_non_nullable
as int,earliestDate: freezed == earliestDate ? _self.earliestDate : earliestDate // ignore: cast_nullable_to_non_nullable
as String?,deadline: null == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as String,deadlineKind: null == deadlineKind ? _self.deadlineKind : deadlineKind // ignore: cast_nullable_to_non_nullable
as ItemDateKind,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ItemDraft].
extension ItemDraftPatterns on ItemDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ItemDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ItemDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ItemDraft value)  $default,){
final _that = this;
switch (_that) {
case _ItemDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ItemDraft value)?  $default,){
final _that = this;
switch (_that) {
case _ItemDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String courseId,  String title,  String description,  String completionCriteria,  int estimatedMinutes,  String? earliestDate,  String deadline,  ItemDateKind deadlineKind,  int priority)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ItemDraft() when $default != null:
return $default(_that.id,_that.courseId,_that.title,_that.description,_that.completionCriteria,_that.estimatedMinutes,_that.earliestDate,_that.deadline,_that.deadlineKind,_that.priority);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String courseId,  String title,  String description,  String completionCriteria,  int estimatedMinutes,  String? earliestDate,  String deadline,  ItemDateKind deadlineKind,  int priority)  $default,) {final _that = this;
switch (_that) {
case _ItemDraft():
return $default(_that.id,_that.courseId,_that.title,_that.description,_that.completionCriteria,_that.estimatedMinutes,_that.earliestDate,_that.deadline,_that.deadlineKind,_that.priority);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String courseId,  String title,  String description,  String completionCriteria,  int estimatedMinutes,  String? earliestDate,  String deadline,  ItemDateKind deadlineKind,  int priority)?  $default,) {final _that = this;
switch (_that) {
case _ItemDraft() when $default != null:
return $default(_that.id,_that.courseId,_that.title,_that.description,_that.completionCriteria,_that.estimatedMinutes,_that.earliestDate,_that.deadline,_that.deadlineKind,_that.priority);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _ItemDraft implements ItemDraft {
  const _ItemDraft({required this.id, required this.courseId, required this.title, this.description = '', this.completionCriteria = '', required this.estimatedMinutes, this.earliestDate, required this.deadline, this.deadlineKind = ItemDateKind.deadline, this.priority = 2});
  factory _ItemDraft.fromJson(Map<String, dynamic> json) => _$ItemDraftFromJson(json);

@override final  String id;
@override final  String courseId;
@override final  String title;
@override@JsonKey() final  String description;
@override@JsonKey() final  String completionCriteria;
@override final  int estimatedMinutes;
@override final  String? earliestDate;
@override final  String deadline;
@override@JsonKey() final  ItemDateKind deadlineKind;
@override@JsonKey() final  int priority;

/// Create a copy of ItemDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ItemDraftCopyWith<_ItemDraft> get copyWith => __$ItemDraftCopyWithImpl<_ItemDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$ItemDraftToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _ItemDraft&&(identical(other.id, id) || other.id == id)&&(identical(other.courseId, courseId) || other.courseId == courseId)&&(identical(other.title, title) || other.title == title)&&(identical(other.description, description) || other.description == description)&&(identical(other.completionCriteria, completionCriteria) || other.completionCriteria == completionCriteria)&&(identical(other.estimatedMinutes, estimatedMinutes) || other.estimatedMinutes == estimatedMinutes)&&(identical(other.earliestDate, earliestDate) || other.earliestDate == earliestDate)&&(identical(other.deadline, deadline) || other.deadline == deadline)&&(identical(other.deadlineKind, deadlineKind) || other.deadlineKind == deadlineKind)&&(identical(other.priority, priority) || other.priority == priority));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,courseId,title,description,completionCriteria,estimatedMinutes,earliestDate,deadline,deadlineKind,priority);

@override
String toString() {
  return 'ItemDraft(id: $id, courseId: $courseId, title: $title, description: $description, completionCriteria: $completionCriteria, estimatedMinutes: $estimatedMinutes, earliestDate: $earliestDate, deadline: $deadline, deadlineKind: $deadlineKind, priority: $priority)';
}


}

/// @nodoc
abstract mixin class _$ItemDraftCopyWith<$Res> implements $ItemDraftCopyWith<$Res> {
  factory _$ItemDraftCopyWith(_ItemDraft value, $Res Function(_ItemDraft) _then) = __$ItemDraftCopyWithImpl;
@override @useResult
$Res call({
 String id, String courseId, String title, String description, String completionCriteria, int estimatedMinutes, String? earliestDate, String deadline, ItemDateKind deadlineKind, int priority
});




}
/// @nodoc
class __$ItemDraftCopyWithImpl<$Res>
    implements _$ItemDraftCopyWith<$Res> {
  __$ItemDraftCopyWithImpl(this._self, this._then);

  final _ItemDraft _self;
  final $Res Function(_ItemDraft) _then;

/// Create a copy of ItemDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? courseId = null,Object? title = null,Object? description = null,Object? completionCriteria = null,Object? estimatedMinutes = null,Object? earliestDate = freezed,Object? deadline = null,Object? deadlineKind = null,Object? priority = null,}) {
  return _then(_ItemDraft(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,courseId: null == courseId ? _self.courseId : courseId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,completionCriteria: null == completionCriteria ? _self.completionCriteria : completionCriteria // ignore: cast_nullable_to_non_nullable
as String,estimatedMinutes: null == estimatedMinutes ? _self.estimatedMinutes : estimatedMinutes // ignore: cast_nullable_to_non_nullable
as int,earliestDate: freezed == earliestDate ? _self.earliestDate : earliestDate // ignore: cast_nullable_to_non_nullable
as String?,deadline: null == deadline ? _self.deadline : deadline // ignore: cast_nullable_to_non_nullable
as String,deadlineKind: null == deadlineKind ? _self.deadlineKind : deadlineKind // ignore: cast_nullable_to_non_nullable
as ItemDateKind,priority: null == priority ? _self.priority : priority // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}


/// @nodoc
mixin _$PlanDraft {

 List<CourseDraft> get courses; List<ItemDraft> get items; String get analysisSummary; List<String> get assumptions; List<String> get warnings;
/// Create a copy of PlanDraft
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PlanDraftCopyWith<PlanDraft> get copyWith => _$PlanDraftCopyWithImpl<PlanDraft>(this as PlanDraft, _$identity);

  /// Serializes this PlanDraft to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PlanDraft&&const DeepCollectionEquality().equals(other.courses, courses)&&const DeepCollectionEquality().equals(other.items, items)&&(identical(other.analysisSummary, analysisSummary) || other.analysisSummary == analysisSummary)&&const DeepCollectionEquality().equals(other.assumptions, assumptions)&&const DeepCollectionEquality().equals(other.warnings, warnings));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(courses),const DeepCollectionEquality().hash(items),analysisSummary,const DeepCollectionEquality().hash(assumptions),const DeepCollectionEquality().hash(warnings));

@override
String toString() {
  return 'PlanDraft(courses: $courses, items: $items, analysisSummary: $analysisSummary, assumptions: $assumptions, warnings: $warnings)';
}


}

/// @nodoc
abstract mixin class $PlanDraftCopyWith<$Res>  {
  factory $PlanDraftCopyWith(PlanDraft value, $Res Function(PlanDraft) _then) = _$PlanDraftCopyWithImpl;
@useResult
$Res call({
 List<CourseDraft> courses, List<ItemDraft> items, String analysisSummary, List<String> assumptions, List<String> warnings
});




}
/// @nodoc
class _$PlanDraftCopyWithImpl<$Res>
    implements $PlanDraftCopyWith<$Res> {
  _$PlanDraftCopyWithImpl(this._self, this._then);

  final PlanDraft _self;
  final $Res Function(PlanDraft) _then;

/// Create a copy of PlanDraft
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? courses = null,Object? items = null,Object? analysisSummary = null,Object? assumptions = null,Object? warnings = null,}) {
  return _then(_self.copyWith(
courses: null == courses ? _self.courses : courses // ignore: cast_nullable_to_non_nullable
as List<CourseDraft>,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ItemDraft>,analysisSummary: null == analysisSummary ? _self.analysisSummary : analysisSummary // ignore: cast_nullable_to_non_nullable
as String,assumptions: null == assumptions ? _self.assumptions : assumptions // ignore: cast_nullable_to_non_nullable
as List<String>,warnings: null == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [PlanDraft].
extension PlanDraftPatterns on PlanDraft {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PlanDraft value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PlanDraft() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PlanDraft value)  $default,){
final _that = this;
switch (_that) {
case _PlanDraft():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PlanDraft value)?  $default,){
final _that = this;
switch (_that) {
case _PlanDraft() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<CourseDraft> courses,  List<ItemDraft> items,  String analysisSummary,  List<String> assumptions,  List<String> warnings)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PlanDraft() when $default != null:
return $default(_that.courses,_that.items,_that.analysisSummary,_that.assumptions,_that.warnings);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<CourseDraft> courses,  List<ItemDraft> items,  String analysisSummary,  List<String> assumptions,  List<String> warnings)  $default,) {final _that = this;
switch (_that) {
case _PlanDraft():
return $default(_that.courses,_that.items,_that.analysisSummary,_that.assumptions,_that.warnings);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<CourseDraft> courses,  List<ItemDraft> items,  String analysisSummary,  List<String> assumptions,  List<String> warnings)?  $default,) {final _that = this;
switch (_that) {
case _PlanDraft() when $default != null:
return $default(_that.courses,_that.items,_that.analysisSummary,_that.assumptions,_that.warnings);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _PlanDraft implements PlanDraft {
  const _PlanDraft({required final  List<CourseDraft> courses, required final  List<ItemDraft> items, required this.analysisSummary, final  List<String> assumptions = const [], final  List<String> warnings = const []}): _courses = courses,_items = items,_assumptions = assumptions,_warnings = warnings;
  factory _PlanDraft.fromJson(Map<String, dynamic> json) => _$PlanDraftFromJson(json);

 final  List<CourseDraft> _courses;
@override List<CourseDraft> get courses {
  if (_courses is EqualUnmodifiableListView) return _courses;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_courses);
}

 final  List<ItemDraft> _items;
@override List<ItemDraft> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  String analysisSummary;
 final  List<String> _assumptions;
@override@JsonKey() List<String> get assumptions {
  if (_assumptions is EqualUnmodifiableListView) return _assumptions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_assumptions);
}

 final  List<String> _warnings;
@override@JsonKey() List<String> get warnings {
  if (_warnings is EqualUnmodifiableListView) return _warnings;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_warnings);
}


/// Create a copy of PlanDraft
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PlanDraftCopyWith<_PlanDraft> get copyWith => __$PlanDraftCopyWithImpl<_PlanDraft>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$PlanDraftToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _PlanDraft&&const DeepCollectionEquality().equals(other._courses, _courses)&&const DeepCollectionEquality().equals(other._items, _items)&&(identical(other.analysisSummary, analysisSummary) || other.analysisSummary == analysisSummary)&&const DeepCollectionEquality().equals(other._assumptions, _assumptions)&&const DeepCollectionEquality().equals(other._warnings, _warnings));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_courses),const DeepCollectionEquality().hash(_items),analysisSummary,const DeepCollectionEquality().hash(_assumptions),const DeepCollectionEquality().hash(_warnings));

@override
String toString() {
  return 'PlanDraft(courses: $courses, items: $items, analysisSummary: $analysisSummary, assumptions: $assumptions, warnings: $warnings)';
}


}

/// @nodoc
abstract mixin class _$PlanDraftCopyWith<$Res> implements $PlanDraftCopyWith<$Res> {
  factory _$PlanDraftCopyWith(_PlanDraft value, $Res Function(_PlanDraft) _then) = __$PlanDraftCopyWithImpl;
@override @useResult
$Res call({
 List<CourseDraft> courses, List<ItemDraft> items, String analysisSummary, List<String> assumptions, List<String> warnings
});




}
/// @nodoc
class __$PlanDraftCopyWithImpl<$Res>
    implements _$PlanDraftCopyWith<$Res> {
  __$PlanDraftCopyWithImpl(this._self, this._then);

  final _PlanDraft _self;
  final $Res Function(_PlanDraft) _then;

/// Create a copy of PlanDraft
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? courses = null,Object? items = null,Object? analysisSummary = null,Object? assumptions = null,Object? warnings = null,}) {
  return _then(_PlanDraft(
courses: null == courses ? _self._courses : courses // ignore: cast_nullable_to_non_nullable
as List<CourseDraft>,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ItemDraft>,analysisSummary: null == analysisSummary ? _self.analysisSummary : analysisSummary // ignore: cast_nullable_to_non_nullable
as String,assumptions: null == assumptions ? _self._assumptions : assumptions // ignore: cast_nullable_to_non_nullable
as List<String>,warnings: null == warnings ? _self._warnings : warnings // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}


}


/// @nodoc
mixin _$DraftResponse {

 String get id; PlanDraft get draft;
/// Create a copy of DraftResponse
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DraftResponseCopyWith<DraftResponse> get copyWith => _$DraftResponseCopyWithImpl<DraftResponse>(this as DraftResponse, _$identity);

  /// Serializes this DraftResponse to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftResponse&&(identical(other.id, id) || other.id == id)&&(identical(other.draft, draft) || other.draft == draft));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,draft);

@override
String toString() {
  return 'DraftResponse(id: $id, draft: $draft)';
}


}

/// @nodoc
abstract mixin class $DraftResponseCopyWith<$Res>  {
  factory $DraftResponseCopyWith(DraftResponse value, $Res Function(DraftResponse) _then) = _$DraftResponseCopyWithImpl;
@useResult
$Res call({
 String id, PlanDraft draft
});


$PlanDraftCopyWith<$Res> get draft;

}
/// @nodoc
class _$DraftResponseCopyWithImpl<$Res>
    implements $DraftResponseCopyWith<$Res> {
  _$DraftResponseCopyWithImpl(this._self, this._then);

  final DraftResponse _self;
  final $Res Function(DraftResponse) _then;

/// Create a copy of DraftResponse
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? draft = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as PlanDraft,
  ));
}
/// Create a copy of DraftResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanDraftCopyWith<$Res> get draft {
  
  return $PlanDraftCopyWith<$Res>(_self.draft, (value) {
    return _then(_self.copyWith(draft: value));
  });
}
}


/// Adds pattern-matching-related methods to [DraftResponse].
extension DraftResponsePatterns on DraftResponse {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DraftResponse value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DraftResponse() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DraftResponse value)  $default,){
final _that = this;
switch (_that) {
case _DraftResponse():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DraftResponse value)?  $default,){
final _that = this;
switch (_that) {
case _DraftResponse() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  PlanDraft draft)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DraftResponse() when $default != null:
return $default(_that.id,_that.draft);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  PlanDraft draft)  $default,) {final _that = this;
switch (_that) {
case _DraftResponse():
return $default(_that.id,_that.draft);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  PlanDraft draft)?  $default,) {final _that = this;
switch (_that) {
case _DraftResponse() when $default != null:
return $default(_that.id,_that.draft);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DraftResponse implements DraftResponse {
  const _DraftResponse({required this.id, required this.draft});
  factory _DraftResponse.fromJson(Map<String, dynamic> json) => _$DraftResponseFromJson(json);

@override final  String id;
@override final  PlanDraft draft;

/// Create a copy of DraftResponse
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DraftResponseCopyWith<_DraftResponse> get copyWith => __$DraftResponseCopyWithImpl<_DraftResponse>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DraftResponseToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DraftResponse&&(identical(other.id, id) || other.id == id)&&(identical(other.draft, draft) || other.draft == draft));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,draft);

@override
String toString() {
  return 'DraftResponse(id: $id, draft: $draft)';
}


}

/// @nodoc
abstract mixin class _$DraftResponseCopyWith<$Res> implements $DraftResponseCopyWith<$Res> {
  factory _$DraftResponseCopyWith(_DraftResponse value, $Res Function(_DraftResponse) _then) = __$DraftResponseCopyWithImpl;
@override @useResult
$Res call({
 String id, PlanDraft draft
});


@override $PlanDraftCopyWith<$Res> get draft;

}
/// @nodoc
class __$DraftResponseCopyWithImpl<$Res>
    implements _$DraftResponseCopyWith<$Res> {
  __$DraftResponseCopyWithImpl(this._self, this._then);

  final _DraftResponse _self;
  final $Res Function(_DraftResponse) _then;

/// Create a copy of DraftResponse
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? draft = null,}) {
  return _then(_DraftResponse(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,draft: null == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as PlanDraft,
  ));
}

/// Create a copy of DraftResponse
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PlanDraftCopyWith<$Res> get draft {
  
  return $PlanDraftCopyWith<$Res>(_self.draft, (value) {
    return _then(_self.copyWith(draft: value));
  });
}
}


/// @nodoc
mixin _$DailyEntry {

 String get itemId; int get actualMinutes; CompletionStatus get completionStatus; String get feedback;
/// Create a copy of DailyEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DailyEntryCopyWith<DailyEntry> get copyWith => _$DailyEntryCopyWithImpl<DailyEntry>(this as DailyEntry, _$identity);

  /// Serializes this DailyEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DailyEntry&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.actualMinutes, actualMinutes) || other.actualMinutes == actualMinutes)&&(identical(other.completionStatus, completionStatus) || other.completionStatus == completionStatus)&&(identical(other.feedback, feedback) || other.feedback == feedback));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,itemId,actualMinutes,completionStatus,feedback);

@override
String toString() {
  return 'DailyEntry(itemId: $itemId, actualMinutes: $actualMinutes, completionStatus: $completionStatus, feedback: $feedback)';
}


}

/// @nodoc
abstract mixin class $DailyEntryCopyWith<$Res>  {
  factory $DailyEntryCopyWith(DailyEntry value, $Res Function(DailyEntry) _then) = _$DailyEntryCopyWithImpl;
@useResult
$Res call({
 String itemId, int actualMinutes, CompletionStatus completionStatus, String feedback
});




}
/// @nodoc
class _$DailyEntryCopyWithImpl<$Res>
    implements $DailyEntryCopyWith<$Res> {
  _$DailyEntryCopyWithImpl(this._self, this._then);

  final DailyEntry _self;
  final $Res Function(DailyEntry) _then;

/// Create a copy of DailyEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? itemId = null,Object? actualMinutes = null,Object? completionStatus = null,Object? feedback = null,}) {
  return _then(_self.copyWith(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,actualMinutes: null == actualMinutes ? _self.actualMinutes : actualMinutes // ignore: cast_nullable_to_non_nullable
as int,completionStatus: null == completionStatus ? _self.completionStatus : completionStatus // ignore: cast_nullable_to_non_nullable
as CompletionStatus,feedback: null == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [DailyEntry].
extension DailyEntryPatterns on DailyEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DailyEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DailyEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DailyEntry value)  $default,){
final _that = this;
switch (_that) {
case _DailyEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DailyEntry value)?  $default,){
final _that = this;
switch (_that) {
case _DailyEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String itemId,  int actualMinutes,  CompletionStatus completionStatus,  String feedback)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DailyEntry() when $default != null:
return $default(_that.itemId,_that.actualMinutes,_that.completionStatus,_that.feedback);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String itemId,  int actualMinutes,  CompletionStatus completionStatus,  String feedback)  $default,) {final _that = this;
switch (_that) {
case _DailyEntry():
return $default(_that.itemId,_that.actualMinutes,_that.completionStatus,_that.feedback);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String itemId,  int actualMinutes,  CompletionStatus completionStatus,  String feedback)?  $default,) {final _that = this;
switch (_that) {
case _DailyEntry() when $default != null:
return $default(_that.itemId,_that.actualMinutes,_that.completionStatus,_that.feedback);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DailyEntry implements DailyEntry {
  const _DailyEntry({required this.itemId, required this.actualMinutes, required this.completionStatus, this.feedback = ''});
  factory _DailyEntry.fromJson(Map<String, dynamic> json) => _$DailyEntryFromJson(json);

@override final  String itemId;
@override final  int actualMinutes;
@override final  CompletionStatus completionStatus;
@override@JsonKey() final  String feedback;

/// Create a copy of DailyEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DailyEntryCopyWith<_DailyEntry> get copyWith => __$DailyEntryCopyWithImpl<_DailyEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DailyEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DailyEntry&&(identical(other.itemId, itemId) || other.itemId == itemId)&&(identical(other.actualMinutes, actualMinutes) || other.actualMinutes == actualMinutes)&&(identical(other.completionStatus, completionStatus) || other.completionStatus == completionStatus)&&(identical(other.feedback, feedback) || other.feedback == feedback));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,itemId,actualMinutes,completionStatus,feedback);

@override
String toString() {
  return 'DailyEntry(itemId: $itemId, actualMinutes: $actualMinutes, completionStatus: $completionStatus, feedback: $feedback)';
}


}

/// @nodoc
abstract mixin class _$DailyEntryCopyWith<$Res> implements $DailyEntryCopyWith<$Res> {
  factory _$DailyEntryCopyWith(_DailyEntry value, $Res Function(_DailyEntry) _then) = __$DailyEntryCopyWithImpl;
@override @useResult
$Res call({
 String itemId, int actualMinutes, CompletionStatus completionStatus, String feedback
});




}
/// @nodoc
class __$DailyEntryCopyWithImpl<$Res>
    implements _$DailyEntryCopyWith<$Res> {
  __$DailyEntryCopyWithImpl(this._self, this._then);

  final _DailyEntry _self;
  final $Res Function(_DailyEntry) _then;

/// Create a copy of DailyEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? itemId = null,Object? actualMinutes = null,Object? completionStatus = null,Object? feedback = null,}) {
  return _then(_DailyEntry(
itemId: null == itemId ? _self.itemId : itemId // ignore: cast_nullable_to_non_nullable
as String,actualMinutes: null == actualMinutes ? _self.actualMinutes : actualMinutes // ignore: cast_nullable_to_non_nullable
as int,completionStatus: null == completionStatus ? _self.completionStatus : completionStatus // ignore: cast_nullable_to_non_nullable
as CompletionStatus,feedback: null == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$DailyReview {

 String get feedback; List<DailyEntry> get entries;
/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DailyReviewCopyWith<DailyReview> get copyWith => _$DailyReviewCopyWithImpl<DailyReview>(this as DailyReview, _$identity);

  /// Serializes this DailyReview to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is DailyReview&&(identical(other.feedback, feedback) || other.feedback == feedback)&&const DeepCollectionEquality().equals(other.entries, entries));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,feedback,const DeepCollectionEquality().hash(entries));

@override
String toString() {
  return 'DailyReview(feedback: $feedback, entries: $entries)';
}


}

/// @nodoc
abstract mixin class $DailyReviewCopyWith<$Res>  {
  factory $DailyReviewCopyWith(DailyReview value, $Res Function(DailyReview) _then) = _$DailyReviewCopyWithImpl;
@useResult
$Res call({
 String feedback, List<DailyEntry> entries
});




}
/// @nodoc
class _$DailyReviewCopyWithImpl<$Res>
    implements $DailyReviewCopyWith<$Res> {
  _$DailyReviewCopyWithImpl(this._self, this._then);

  final DailyReview _self;
  final $Res Function(DailyReview) _then;

/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? feedback = null,Object? entries = null,}) {
  return _then(_self.copyWith(
feedback: null == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String,entries: null == entries ? _self.entries : entries // ignore: cast_nullable_to_non_nullable
as List<DailyEntry>,
  ));
}

}


/// Adds pattern-matching-related methods to [DailyReview].
extension DailyReviewPatterns on DailyReview {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _DailyReview value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _DailyReview value)  $default,){
final _that = this;
switch (_that) {
case _DailyReview():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _DailyReview value)?  $default,){
final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String feedback,  List<DailyEntry> entries)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
return $default(_that.feedback,_that.entries);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String feedback,  List<DailyEntry> entries)  $default,) {final _that = this;
switch (_that) {
case _DailyReview():
return $default(_that.feedback,_that.entries);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String feedback,  List<DailyEntry> entries)?  $default,) {final _that = this;
switch (_that) {
case _DailyReview() when $default != null:
return $default(_that.feedback,_that.entries);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _DailyReview implements DailyReview {
  const _DailyReview({this.feedback = '', final  List<DailyEntry> entries = const []}): _entries = entries;
  factory _DailyReview.fromJson(Map<String, dynamic> json) => _$DailyReviewFromJson(json);

@override@JsonKey() final  String feedback;
 final  List<DailyEntry> _entries;
@override@JsonKey() List<DailyEntry> get entries {
  if (_entries is EqualUnmodifiableListView) return _entries;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_entries);
}


/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$DailyReviewCopyWith<_DailyReview> get copyWith => __$DailyReviewCopyWithImpl<_DailyReview>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$DailyReviewToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _DailyReview&&(identical(other.feedback, feedback) || other.feedback == feedback)&&const DeepCollectionEquality().equals(other._entries, _entries));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,feedback,const DeepCollectionEquality().hash(_entries));

@override
String toString() {
  return 'DailyReview(feedback: $feedback, entries: $entries)';
}


}

/// @nodoc
abstract mixin class _$DailyReviewCopyWith<$Res> implements $DailyReviewCopyWith<$Res> {
  factory _$DailyReviewCopyWith(_DailyReview value, $Res Function(_DailyReview) _then) = __$DailyReviewCopyWithImpl;
@override @useResult
$Res call({
 String feedback, List<DailyEntry> entries
});




}
/// @nodoc
class __$DailyReviewCopyWithImpl<$Res>
    implements _$DailyReviewCopyWith<$Res> {
  __$DailyReviewCopyWithImpl(this._self, this._then);

  final _DailyReview _self;
  final $Res Function(_DailyReview) _then;

/// Create a copy of DailyReview
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? feedback = null,Object? entries = null,}) {
  return _then(_DailyReview(
feedback: null == feedback ? _self.feedback : feedback // ignore: cast_nullable_to_non_nullable
as String,entries: null == entries ? _self._entries : entries // ignore: cast_nullable_to_non_nullable
as List<DailyEntry>,
  ));
}


}

// dart format on
