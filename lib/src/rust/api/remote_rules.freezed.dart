// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_rules.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RuleStep {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RuleStep()';
}


}

/// @nodoc
class $RuleStepCopyWith<$Res>  {
$RuleStepCopyWith(RuleStep _, $Res Function(RuleStep) __);
}


/// Adds pattern-matching-related methods to [RuleStep].
extension RuleStepPatterns on RuleStep {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RuleStep_Fetch value)?  fetch,TResult Function( RuleStep_RegexExtract value)?  regexExtract,TResult Function( RuleStep_RegexFindAll value)?  regexFindAll,TResult Function( RuleStep_BuildStream value)?  buildStream,TResult Function( RuleStep_SetTitle value)?  setTitle,TResult Function( RuleStep_SetThumbnail value)?  setThumbnail,TResult Function( RuleStep_SetAuthor value)?  setAuthor,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RuleStep_Fetch() when fetch != null:
return fetch(_that);case RuleStep_RegexExtract() when regexExtract != null:
return regexExtract(_that);case RuleStep_RegexFindAll() when regexFindAll != null:
return regexFindAll(_that);case RuleStep_BuildStream() when buildStream != null:
return buildStream(_that);case RuleStep_SetTitle() when setTitle != null:
return setTitle(_that);case RuleStep_SetThumbnail() when setThumbnail != null:
return setThumbnail(_that);case RuleStep_SetAuthor() when setAuthor != null:
return setAuthor(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RuleStep_Fetch value)  fetch,required TResult Function( RuleStep_RegexExtract value)  regexExtract,required TResult Function( RuleStep_RegexFindAll value)  regexFindAll,required TResult Function( RuleStep_BuildStream value)  buildStream,required TResult Function( RuleStep_SetTitle value)  setTitle,required TResult Function( RuleStep_SetThumbnail value)  setThumbnail,required TResult Function( RuleStep_SetAuthor value)  setAuthor,}){
final _that = this;
switch (_that) {
case RuleStep_Fetch():
return fetch(_that);case RuleStep_RegexExtract():
return regexExtract(_that);case RuleStep_RegexFindAll():
return regexFindAll(_that);case RuleStep_BuildStream():
return buildStream(_that);case RuleStep_SetTitle():
return setTitle(_that);case RuleStep_SetThumbnail():
return setThumbnail(_that);case RuleStep_SetAuthor():
return setAuthor(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RuleStep_Fetch value)?  fetch,TResult? Function( RuleStep_RegexExtract value)?  regexExtract,TResult? Function( RuleStep_RegexFindAll value)?  regexFindAll,TResult? Function( RuleStep_BuildStream value)?  buildStream,TResult? Function( RuleStep_SetTitle value)?  setTitle,TResult? Function( RuleStep_SetThumbnail value)?  setThumbnail,TResult? Function( RuleStep_SetAuthor value)?  setAuthor,}){
final _that = this;
switch (_that) {
case RuleStep_Fetch() when fetch != null:
return fetch(_that);case RuleStep_RegexExtract() when regexExtract != null:
return regexExtract(_that);case RuleStep_RegexFindAll() when regexFindAll != null:
return regexFindAll(_that);case RuleStep_BuildStream() when buildStream != null:
return buildStream(_that);case RuleStep_SetTitle() when setTitle != null:
return setTitle(_that);case RuleStep_SetThumbnail() when setThumbnail != null:
return setThumbnail(_that);case RuleStep_SetAuthor() when setAuthor != null:
return setAuthor(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String url,  String asVar)?  fetch,TResult Function( String input,  String pattern,  String asVar)?  regexExtract,TResult Function( String input,  String pattern,  String asVar)?  regexFindAll,TResult Function( String url,  String quality,  String container,  bool isAudioOnly)?  buildStream,TResult Function( String value)?  setTitle,TResult Function( String value)?  setThumbnail,TResult Function( String value)?  setAuthor,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RuleStep_Fetch() when fetch != null:
return fetch(_that.url,_that.asVar);case RuleStep_RegexExtract() when regexExtract != null:
return regexExtract(_that.input,_that.pattern,_that.asVar);case RuleStep_RegexFindAll() when regexFindAll != null:
return regexFindAll(_that.input,_that.pattern,_that.asVar);case RuleStep_BuildStream() when buildStream != null:
return buildStream(_that.url,_that.quality,_that.container,_that.isAudioOnly);case RuleStep_SetTitle() when setTitle != null:
return setTitle(_that.value);case RuleStep_SetThumbnail() when setThumbnail != null:
return setThumbnail(_that.value);case RuleStep_SetAuthor() when setAuthor != null:
return setAuthor(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String url,  String asVar)  fetch,required TResult Function( String input,  String pattern,  String asVar)  regexExtract,required TResult Function( String input,  String pattern,  String asVar)  regexFindAll,required TResult Function( String url,  String quality,  String container,  bool isAudioOnly)  buildStream,required TResult Function( String value)  setTitle,required TResult Function( String value)  setThumbnail,required TResult Function( String value)  setAuthor,}) {final _that = this;
switch (_that) {
case RuleStep_Fetch():
return fetch(_that.url,_that.asVar);case RuleStep_RegexExtract():
return regexExtract(_that.input,_that.pattern,_that.asVar);case RuleStep_RegexFindAll():
return regexFindAll(_that.input,_that.pattern,_that.asVar);case RuleStep_BuildStream():
return buildStream(_that.url,_that.quality,_that.container,_that.isAudioOnly);case RuleStep_SetTitle():
return setTitle(_that.value);case RuleStep_SetThumbnail():
return setThumbnail(_that.value);case RuleStep_SetAuthor():
return setAuthor(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String url,  String asVar)?  fetch,TResult? Function( String input,  String pattern,  String asVar)?  regexExtract,TResult? Function( String input,  String pattern,  String asVar)?  regexFindAll,TResult? Function( String url,  String quality,  String container,  bool isAudioOnly)?  buildStream,TResult? Function( String value)?  setTitle,TResult? Function( String value)?  setThumbnail,TResult? Function( String value)?  setAuthor,}) {final _that = this;
switch (_that) {
case RuleStep_Fetch() when fetch != null:
return fetch(_that.url,_that.asVar);case RuleStep_RegexExtract() when regexExtract != null:
return regexExtract(_that.input,_that.pattern,_that.asVar);case RuleStep_RegexFindAll() when regexFindAll != null:
return regexFindAll(_that.input,_that.pattern,_that.asVar);case RuleStep_BuildStream() when buildStream != null:
return buildStream(_that.url,_that.quality,_that.container,_that.isAudioOnly);case RuleStep_SetTitle() when setTitle != null:
return setTitle(_that.value);case RuleStep_SetThumbnail() when setThumbnail != null:
return setThumbnail(_that.value);case RuleStep_SetAuthor() when setAuthor != null:
return setAuthor(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class RuleStep_Fetch extends RuleStep {
  const RuleStep_Fetch({required this.url, required this.asVar}): super._();
  

 final  String url;
 final  String asVar;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_FetchCopyWith<RuleStep_Fetch> get copyWith => _$RuleStep_FetchCopyWithImpl<RuleStep_Fetch>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_Fetch&&(identical(other.url, url) || other.url == url)&&(identical(other.asVar, asVar) || other.asVar == asVar));
}


@override
int get hashCode => Object.hash(runtimeType,url,asVar);

@override
String toString() {
  return 'RuleStep.fetch(url: $url, asVar: $asVar)';
}


}

/// @nodoc
abstract mixin class $RuleStep_FetchCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_FetchCopyWith(RuleStep_Fetch value, $Res Function(RuleStep_Fetch) _then) = _$RuleStep_FetchCopyWithImpl;
@useResult
$Res call({
 String url, String asVar
});




}
/// @nodoc
class _$RuleStep_FetchCopyWithImpl<$Res>
    implements $RuleStep_FetchCopyWith<$Res> {
  _$RuleStep_FetchCopyWithImpl(this._self, this._then);

  final RuleStep_Fetch _self;
  final $Res Function(RuleStep_Fetch) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? asVar = null,}) {
  return _then(RuleStep_Fetch(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,asVar: null == asVar ? _self.asVar : asVar // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RuleStep_RegexExtract extends RuleStep {
  const RuleStep_RegexExtract({required this.input, required this.pattern, required this.asVar}): super._();
  

 final  String input;
 final  String pattern;
 final  String asVar;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_RegexExtractCopyWith<RuleStep_RegexExtract> get copyWith => _$RuleStep_RegexExtractCopyWithImpl<RuleStep_RegexExtract>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_RegexExtract&&(identical(other.input, input) || other.input == input)&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.asVar, asVar) || other.asVar == asVar));
}


@override
int get hashCode => Object.hash(runtimeType,input,pattern,asVar);

@override
String toString() {
  return 'RuleStep.regexExtract(input: $input, pattern: $pattern, asVar: $asVar)';
}


}

/// @nodoc
abstract mixin class $RuleStep_RegexExtractCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_RegexExtractCopyWith(RuleStep_RegexExtract value, $Res Function(RuleStep_RegexExtract) _then) = _$RuleStep_RegexExtractCopyWithImpl;
@useResult
$Res call({
 String input, String pattern, String asVar
});




}
/// @nodoc
class _$RuleStep_RegexExtractCopyWithImpl<$Res>
    implements $RuleStep_RegexExtractCopyWith<$Res> {
  _$RuleStep_RegexExtractCopyWithImpl(this._self, this._then);

  final RuleStep_RegexExtract _self;
  final $Res Function(RuleStep_RegexExtract) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? input = null,Object? pattern = null,Object? asVar = null,}) {
  return _then(RuleStep_RegexExtract(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as String,pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,asVar: null == asVar ? _self.asVar : asVar // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RuleStep_RegexFindAll extends RuleStep {
  const RuleStep_RegexFindAll({required this.input, required this.pattern, required this.asVar}): super._();
  

 final  String input;
 final  String pattern;
 final  String asVar;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_RegexFindAllCopyWith<RuleStep_RegexFindAll> get copyWith => _$RuleStep_RegexFindAllCopyWithImpl<RuleStep_RegexFindAll>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_RegexFindAll&&(identical(other.input, input) || other.input == input)&&(identical(other.pattern, pattern) || other.pattern == pattern)&&(identical(other.asVar, asVar) || other.asVar == asVar));
}


@override
int get hashCode => Object.hash(runtimeType,input,pattern,asVar);

@override
String toString() {
  return 'RuleStep.regexFindAll(input: $input, pattern: $pattern, asVar: $asVar)';
}


}

/// @nodoc
abstract mixin class $RuleStep_RegexFindAllCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_RegexFindAllCopyWith(RuleStep_RegexFindAll value, $Res Function(RuleStep_RegexFindAll) _then) = _$RuleStep_RegexFindAllCopyWithImpl;
@useResult
$Res call({
 String input, String pattern, String asVar
});




}
/// @nodoc
class _$RuleStep_RegexFindAllCopyWithImpl<$Res>
    implements $RuleStep_RegexFindAllCopyWith<$Res> {
  _$RuleStep_RegexFindAllCopyWithImpl(this._self, this._then);

  final RuleStep_RegexFindAll _self;
  final $Res Function(RuleStep_RegexFindAll) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? input = null,Object? pattern = null,Object? asVar = null,}) {
  return _then(RuleStep_RegexFindAll(
input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as String,pattern: null == pattern ? _self.pattern : pattern // ignore: cast_nullable_to_non_nullable
as String,asVar: null == asVar ? _self.asVar : asVar // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RuleStep_BuildStream extends RuleStep {
  const RuleStep_BuildStream({required this.url, required this.quality, required this.container, required this.isAudioOnly}): super._();
  

 final  String url;
 final  String quality;
 final  String container;
 final  bool isAudioOnly;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_BuildStreamCopyWith<RuleStep_BuildStream> get copyWith => _$RuleStep_BuildStreamCopyWithImpl<RuleStep_BuildStream>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_BuildStream&&(identical(other.url, url) || other.url == url)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.container, container) || other.container == container)&&(identical(other.isAudioOnly, isAudioOnly) || other.isAudioOnly == isAudioOnly));
}


@override
int get hashCode => Object.hash(runtimeType,url,quality,container,isAudioOnly);

@override
String toString() {
  return 'RuleStep.buildStream(url: $url, quality: $quality, container: $container, isAudioOnly: $isAudioOnly)';
}


}

/// @nodoc
abstract mixin class $RuleStep_BuildStreamCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_BuildStreamCopyWith(RuleStep_BuildStream value, $Res Function(RuleStep_BuildStream) _then) = _$RuleStep_BuildStreamCopyWithImpl;
@useResult
$Res call({
 String url, String quality, String container, bool isAudioOnly
});




}
/// @nodoc
class _$RuleStep_BuildStreamCopyWithImpl<$Res>
    implements $RuleStep_BuildStreamCopyWith<$Res> {
  _$RuleStep_BuildStreamCopyWithImpl(this._self, this._then);

  final RuleStep_BuildStream _self;
  final $Res Function(RuleStep_BuildStream) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? quality = null,Object? container = null,Object? isAudioOnly = null,}) {
  return _then(RuleStep_BuildStream(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,quality: null == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as String,container: null == container ? _self.container : container // ignore: cast_nullable_to_non_nullable
as String,isAudioOnly: null == isAudioOnly ? _self.isAudioOnly : isAudioOnly // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class RuleStep_SetTitle extends RuleStep {
  const RuleStep_SetTitle({required this.value}): super._();
  

 final  String value;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_SetTitleCopyWith<RuleStep_SetTitle> get copyWith => _$RuleStep_SetTitleCopyWithImpl<RuleStep_SetTitle>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_SetTitle&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RuleStep.setTitle(value: $value)';
}


}

/// @nodoc
abstract mixin class $RuleStep_SetTitleCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_SetTitleCopyWith(RuleStep_SetTitle value, $Res Function(RuleStep_SetTitle) _then) = _$RuleStep_SetTitleCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$RuleStep_SetTitleCopyWithImpl<$Res>
    implements $RuleStep_SetTitleCopyWith<$Res> {
  _$RuleStep_SetTitleCopyWithImpl(this._self, this._then);

  final RuleStep_SetTitle _self;
  final $Res Function(RuleStep_SetTitle) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RuleStep_SetTitle(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RuleStep_SetThumbnail extends RuleStep {
  const RuleStep_SetThumbnail({required this.value}): super._();
  

 final  String value;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_SetThumbnailCopyWith<RuleStep_SetThumbnail> get copyWith => _$RuleStep_SetThumbnailCopyWithImpl<RuleStep_SetThumbnail>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_SetThumbnail&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RuleStep.setThumbnail(value: $value)';
}


}

/// @nodoc
abstract mixin class $RuleStep_SetThumbnailCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_SetThumbnailCopyWith(RuleStep_SetThumbnail value, $Res Function(RuleStep_SetThumbnail) _then) = _$RuleStep_SetThumbnailCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$RuleStep_SetThumbnailCopyWithImpl<$Res>
    implements $RuleStep_SetThumbnailCopyWith<$Res> {
  _$RuleStep_SetThumbnailCopyWithImpl(this._self, this._then);

  final RuleStep_SetThumbnail _self;
  final $Res Function(RuleStep_SetThumbnail) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RuleStep_SetThumbnail(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RuleStep_SetAuthor extends RuleStep {
  const RuleStep_SetAuthor({required this.value}): super._();
  

 final  String value;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuleStep_SetAuthorCopyWith<RuleStep_SetAuthor> get copyWith => _$RuleStep_SetAuthorCopyWithImpl<RuleStep_SetAuthor>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuleStep_SetAuthor&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode => Object.hash(runtimeType,value);

@override
String toString() {
  return 'RuleStep.setAuthor(value: $value)';
}


}

/// @nodoc
abstract mixin class $RuleStep_SetAuthorCopyWith<$Res> implements $RuleStepCopyWith<$Res> {
  factory $RuleStep_SetAuthorCopyWith(RuleStep_SetAuthor value, $Res Function(RuleStep_SetAuthor) _then) = _$RuleStep_SetAuthorCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$RuleStep_SetAuthorCopyWithImpl<$Res>
    implements $RuleStep_SetAuthorCopyWith<$Res> {
  _$RuleStep_SetAuthorCopyWithImpl(this._self, this._then);

  final RuleStep_SetAuthor _self;
  final $Res Function(RuleStep_SetAuthor) _then;

/// Create a copy of RuleStep
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(RuleStep_SetAuthor(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
