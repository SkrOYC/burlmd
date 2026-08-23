// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ffi_api.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RangeEditCaret {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RangeEditCaret);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'RangeEditCaret()';
}


}

/// @nodoc
class $RangeEditCaretCopyWith<$Res>  {
$RangeEditCaretCopyWith(RangeEditCaret _, $Res Function(RangeEditCaret) __);
}


/// Adds pattern-matching-related methods to [RangeEditCaret].
extension RangeEditCaretPatterns on RangeEditCaret {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RangeEditCaret_Block value)?  block,TResult Function( RangeEditCaret_Phantom value)?  phantom,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RangeEditCaret_Block() when block != null:
return block(_that);case RangeEditCaret_Phantom() when phantom != null:
return phantom(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RangeEditCaret_Block value)  block,required TResult Function( RangeEditCaret_Phantom value)  phantom,}){
final _that = this;
switch (_that) {
case RangeEditCaret_Block():
return block(_that);case RangeEditCaret_Phantom():
return phantom(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RangeEditCaret_Block value)?  block,TResult? Function( RangeEditCaret_Phantom value)?  phantom,}){
final _that = this;
switch (_that) {
case RangeEditCaret_Block() when block != null:
return block(_that);case RangeEditCaret_Phantom() when phantom != null:
return phantom(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( Uint64List blockPath,  BigInt sourceOffsetUtf16)?  block,TResult Function( BigInt insertionIndex)?  phantom,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RangeEditCaret_Block() when block != null:
return block(_that.blockPath,_that.sourceOffsetUtf16);case RangeEditCaret_Phantom() when phantom != null:
return phantom(_that.insertionIndex);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( Uint64List blockPath,  BigInt sourceOffsetUtf16)  block,required TResult Function( BigInt insertionIndex)  phantom,}) {final _that = this;
switch (_that) {
case RangeEditCaret_Block():
return block(_that.blockPath,_that.sourceOffsetUtf16);case RangeEditCaret_Phantom():
return phantom(_that.insertionIndex);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( Uint64List blockPath,  BigInt sourceOffsetUtf16)?  block,TResult? Function( BigInt insertionIndex)?  phantom,}) {final _that = this;
switch (_that) {
case RangeEditCaret_Block() when block != null:
return block(_that.blockPath,_that.sourceOffsetUtf16);case RangeEditCaret_Phantom() when phantom != null:
return phantom(_that.insertionIndex);case _:
  return null;

}
}

}

/// @nodoc


class RangeEditCaret_Block extends RangeEditCaret {
  const RangeEditCaret_Block({required this.blockPath, required this.sourceOffsetUtf16}): super._();
  

 final  Uint64List blockPath;
 final  BigInt sourceOffsetUtf16;

/// Create a copy of RangeEditCaret
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RangeEditCaret_BlockCopyWith<RangeEditCaret_Block> get copyWith => _$RangeEditCaret_BlockCopyWithImpl<RangeEditCaret_Block>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RangeEditCaret_Block&&const DeepCollectionEquality().equals(other.blockPath, blockPath)&&(identical(other.sourceOffsetUtf16, sourceOffsetUtf16) || other.sourceOffsetUtf16 == sourceOffsetUtf16));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(blockPath),sourceOffsetUtf16);

@override
String toString() {
  return 'RangeEditCaret.block(blockPath: $blockPath, sourceOffsetUtf16: $sourceOffsetUtf16)';
}


}

/// @nodoc
abstract mixin class $RangeEditCaret_BlockCopyWith<$Res> implements $RangeEditCaretCopyWith<$Res> {
  factory $RangeEditCaret_BlockCopyWith(RangeEditCaret_Block value, $Res Function(RangeEditCaret_Block) _then) = _$RangeEditCaret_BlockCopyWithImpl;
@useResult
$Res call({
 Uint64List blockPath, BigInt sourceOffsetUtf16
});




}
/// @nodoc
class _$RangeEditCaret_BlockCopyWithImpl<$Res>
    implements $RangeEditCaret_BlockCopyWith<$Res> {
  _$RangeEditCaret_BlockCopyWithImpl(this._self, this._then);

  final RangeEditCaret_Block _self;
  final $Res Function(RangeEditCaret_Block) _then;

/// Create a copy of RangeEditCaret
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? blockPath = null,Object? sourceOffsetUtf16 = null,}) {
  return _then(RangeEditCaret_Block(
blockPath: null == blockPath ? _self.blockPath : blockPath // ignore: cast_nullable_to_non_nullable
as Uint64List,sourceOffsetUtf16: null == sourceOffsetUtf16 ? _self.sourceOffsetUtf16 : sourceOffsetUtf16 // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

/// @nodoc


class RangeEditCaret_Phantom extends RangeEditCaret {
  const RangeEditCaret_Phantom({required this.insertionIndex}): super._();
  

 final  BigInt insertionIndex;

/// Create a copy of RangeEditCaret
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RangeEditCaret_PhantomCopyWith<RangeEditCaret_Phantom> get copyWith => _$RangeEditCaret_PhantomCopyWithImpl<RangeEditCaret_Phantom>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RangeEditCaret_Phantom&&(identical(other.insertionIndex, insertionIndex) || other.insertionIndex == insertionIndex));
}


@override
int get hashCode => Object.hash(runtimeType,insertionIndex);

@override
String toString() {
  return 'RangeEditCaret.phantom(insertionIndex: $insertionIndex)';
}


}

/// @nodoc
abstract mixin class $RangeEditCaret_PhantomCopyWith<$Res> implements $RangeEditCaretCopyWith<$Res> {
  factory $RangeEditCaret_PhantomCopyWith(RangeEditCaret_Phantom value, $Res Function(RangeEditCaret_Phantom) _then) = _$RangeEditCaret_PhantomCopyWithImpl;
@useResult
$Res call({
 BigInt insertionIndex
});




}
/// @nodoc
class _$RangeEditCaret_PhantomCopyWithImpl<$Res>
    implements $RangeEditCaret_PhantomCopyWith<$Res> {
  _$RangeEditCaret_PhantomCopyWithImpl(this._self, this._then);

  final RangeEditCaret_Phantom _self;
  final $Res Function(RangeEditCaret_Phantom) _then;

/// Create a copy of RangeEditCaret
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? insertionIndex = null,}) {
  return _then(RangeEditCaret_Phantom(
insertionIndex: null == insertionIndex ? _self.insertionIndex : insertionIndex // ignore: cast_nullable_to_non_nullable
as BigInt,
  ));
}


}

// dart format on
