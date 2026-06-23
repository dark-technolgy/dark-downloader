// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ExtractionResult {

 Object get field0;



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionResult&&const DeepCollectionEquality().equals(other.field0, field0));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(field0));

@override
String toString() {
  return 'ExtractionResult(field0: $field0)';
}


}

/// @nodoc
class $ExtractionResultCopyWith<$Res>  {
$ExtractionResultCopyWith(ExtractionResult _, $Res Function(ExtractionResult) __);
}


/// Adds pattern-matching-related methods to [ExtractionResult].
extension ExtractionResultPatterns on ExtractionResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExtractionResult_Video value)?  video,TResult Function( ExtractionResult_Playlist value)?  playlist,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExtractionResult_Video() when video != null:
return video(_that);case ExtractionResult_Playlist() when playlist != null:
return playlist(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExtractionResult_Video value)  video,required TResult Function( ExtractionResult_Playlist value)  playlist,}){
final _that = this;
switch (_that) {
case ExtractionResult_Video():
return video(_that);case ExtractionResult_Playlist():
return playlist(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExtractionResult_Video value)?  video,TResult? Function( ExtractionResult_Playlist value)?  playlist,}){
final _that = this;
switch (_that) {
case ExtractionResult_Video() when video != null:
return video(_that);case ExtractionResult_Playlist() when playlist != null:
return playlist(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( VideoInfoResult field0)?  video,TResult Function( PlaylistResult field0)?  playlist,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExtractionResult_Video() when video != null:
return video(_that.field0);case ExtractionResult_Playlist() when playlist != null:
return playlist(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( VideoInfoResult field0)  video,required TResult Function( PlaylistResult field0)  playlist,}) {final _that = this;
switch (_that) {
case ExtractionResult_Video():
return video(_that.field0);case ExtractionResult_Playlist():
return playlist(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( VideoInfoResult field0)?  video,TResult? Function( PlaylistResult field0)?  playlist,}) {final _that = this;
switch (_that) {
case ExtractionResult_Video() when video != null:
return video(_that.field0);case ExtractionResult_Playlist() when playlist != null:
return playlist(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class ExtractionResult_Video extends ExtractionResult {
  const ExtractionResult_Video(this.field0): super._();
  

@override final  VideoInfoResult field0;

/// Create a copy of ExtractionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionResult_VideoCopyWith<ExtractionResult_Video> get copyWith => _$ExtractionResult_VideoCopyWithImpl<ExtractionResult_Video>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionResult_Video&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ExtractionResult.video(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ExtractionResult_VideoCopyWith<$Res> implements $ExtractionResultCopyWith<$Res> {
  factory $ExtractionResult_VideoCopyWith(ExtractionResult_Video value, $Res Function(ExtractionResult_Video) _then) = _$ExtractionResult_VideoCopyWithImpl;
@useResult
$Res call({
 VideoInfoResult field0
});




}
/// @nodoc
class _$ExtractionResult_VideoCopyWithImpl<$Res>
    implements $ExtractionResult_VideoCopyWith<$Res> {
  _$ExtractionResult_VideoCopyWithImpl(this._self, this._then);

  final ExtractionResult_Video _self;
  final $Res Function(ExtractionResult_Video) _then;

/// Create a copy of ExtractionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ExtractionResult_Video(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as VideoInfoResult,
  ));
}


}

/// @nodoc


class ExtractionResult_Playlist extends ExtractionResult {
  const ExtractionResult_Playlist(this.field0): super._();
  

@override final  PlaylistResult field0;

/// Create a copy of ExtractionResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExtractionResult_PlaylistCopyWith<ExtractionResult_Playlist> get copyWith => _$ExtractionResult_PlaylistCopyWithImpl<ExtractionResult_Playlist>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ExtractionResult_Playlist&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'ExtractionResult.playlist(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $ExtractionResult_PlaylistCopyWith<$Res> implements $ExtractionResultCopyWith<$Res> {
  factory $ExtractionResult_PlaylistCopyWith(ExtractionResult_Playlist value, $Res Function(ExtractionResult_Playlist) _then) = _$ExtractionResult_PlaylistCopyWithImpl;
@useResult
$Res call({
 PlaylistResult field0
});




}
/// @nodoc
class _$ExtractionResult_PlaylistCopyWithImpl<$Res>
    implements $ExtractionResult_PlaylistCopyWith<$Res> {
  _$ExtractionResult_PlaylistCopyWithImpl(this._self, this._then);

  final ExtractionResult_Playlist _self;
  final $Res Function(ExtractionResult_Playlist) _then;

/// Create a copy of ExtractionResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(ExtractionResult_Playlist(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as PlaylistResult,
  ));
}


}

// dart format on
