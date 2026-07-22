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
mixin _$AppError {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppError()';
}


}

/// @nodoc
class $AppErrorCopyWith<$Res>  {
$AppErrorCopyWith(AppError _, $Res Function(AppError) __);
}


/// Adds pattern-matching-related methods to [AppError].
extension AppErrorPatterns on AppError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AppError_DiskFull value)?  diskFull,TResult Function( AppError_AuthExpired value)?  authExpired,TResult Function( AppError_GitConflict value)?  gitConflict,TResult Function( AppError_DatabaseError value)?  databaseError,TResult Function( AppError_CryptoError value)?  cryptoError,TResult Function( AppError_NetworkError value)?  networkError,TResult Function( AppError_OAuthError value)?  oAuthError,TResult Function( AppError_IoError value)?  ioError,TResult Function( AppError_ParseError value)?  parseError,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AppError_DiskFull() when diskFull != null:
return diskFull(_that);case AppError_AuthExpired() when authExpired != null:
return authExpired(_that);case AppError_GitConflict() when gitConflict != null:
return gitConflict(_that);case AppError_DatabaseError() when databaseError != null:
return databaseError(_that);case AppError_CryptoError() when cryptoError != null:
return cryptoError(_that);case AppError_NetworkError() when networkError != null:
return networkError(_that);case AppError_OAuthError() when oAuthError != null:
return oAuthError(_that);case AppError_IoError() when ioError != null:
return ioError(_that);case AppError_ParseError() when parseError != null:
return parseError(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AppError_DiskFull value)  diskFull,required TResult Function( AppError_AuthExpired value)  authExpired,required TResult Function( AppError_GitConflict value)  gitConflict,required TResult Function( AppError_DatabaseError value)  databaseError,required TResult Function( AppError_CryptoError value)  cryptoError,required TResult Function( AppError_NetworkError value)  networkError,required TResult Function( AppError_OAuthError value)  oAuthError,required TResult Function( AppError_IoError value)  ioError,required TResult Function( AppError_ParseError value)  parseError,}){
final _that = this;
switch (_that) {
case AppError_DiskFull():
return diskFull(_that);case AppError_AuthExpired():
return authExpired(_that);case AppError_GitConflict():
return gitConflict(_that);case AppError_DatabaseError():
return databaseError(_that);case AppError_CryptoError():
return cryptoError(_that);case AppError_NetworkError():
return networkError(_that);case AppError_OAuthError():
return oAuthError(_that);case AppError_IoError():
return ioError(_that);case AppError_ParseError():
return parseError(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AppError_DiskFull value)?  diskFull,TResult? Function( AppError_AuthExpired value)?  authExpired,TResult? Function( AppError_GitConflict value)?  gitConflict,TResult? Function( AppError_DatabaseError value)?  databaseError,TResult? Function( AppError_CryptoError value)?  cryptoError,TResult? Function( AppError_NetworkError value)?  networkError,TResult? Function( AppError_OAuthError value)?  oAuthError,TResult? Function( AppError_IoError value)?  ioError,TResult? Function( AppError_ParseError value)?  parseError,}){
final _that = this;
switch (_that) {
case AppError_DiskFull() when diskFull != null:
return diskFull(_that);case AppError_AuthExpired() when authExpired != null:
return authExpired(_that);case AppError_GitConflict() when gitConflict != null:
return gitConflict(_that);case AppError_DatabaseError() when databaseError != null:
return databaseError(_that);case AppError_CryptoError() when cryptoError != null:
return cryptoError(_that);case AppError_NetworkError() when networkError != null:
return networkError(_that);case AppError_OAuthError() when oAuthError != null:
return oAuthError(_that);case AppError_IoError() when ioError != null:
return ioError(_that);case AppError_ParseError() when parseError != null:
return parseError(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  diskFull,TResult Function()?  authExpired,TResult Function()?  gitConflict,TResult Function( String field0)?  databaseError,TResult Function( String field0)?  cryptoError,TResult Function( String field0)?  networkError,TResult Function( String field0)?  oAuthError,TResult Function( String field0)?  ioError,TResult Function( String field0)?  parseError,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AppError_DiskFull() when diskFull != null:
return diskFull();case AppError_AuthExpired() when authExpired != null:
return authExpired();case AppError_GitConflict() when gitConflict != null:
return gitConflict();case AppError_DatabaseError() when databaseError != null:
return databaseError(_that.field0);case AppError_CryptoError() when cryptoError != null:
return cryptoError(_that.field0);case AppError_NetworkError() when networkError != null:
return networkError(_that.field0);case AppError_OAuthError() when oAuthError != null:
return oAuthError(_that.field0);case AppError_IoError() when ioError != null:
return ioError(_that.field0);case AppError_ParseError() when parseError != null:
return parseError(_that.field0);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  diskFull,required TResult Function()  authExpired,required TResult Function()  gitConflict,required TResult Function( String field0)  databaseError,required TResult Function( String field0)  cryptoError,required TResult Function( String field0)  networkError,required TResult Function( String field0)  oAuthError,required TResult Function( String field0)  ioError,required TResult Function( String field0)  parseError,}) {final _that = this;
switch (_that) {
case AppError_DiskFull():
return diskFull();case AppError_AuthExpired():
return authExpired();case AppError_GitConflict():
return gitConflict();case AppError_DatabaseError():
return databaseError(_that.field0);case AppError_CryptoError():
return cryptoError(_that.field0);case AppError_NetworkError():
return networkError(_that.field0);case AppError_OAuthError():
return oAuthError(_that.field0);case AppError_IoError():
return ioError(_that.field0);case AppError_ParseError():
return parseError(_that.field0);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  diskFull,TResult? Function()?  authExpired,TResult? Function()?  gitConflict,TResult? Function( String field0)?  databaseError,TResult? Function( String field0)?  cryptoError,TResult? Function( String field0)?  networkError,TResult? Function( String field0)?  oAuthError,TResult? Function( String field0)?  ioError,TResult? Function( String field0)?  parseError,}) {final _that = this;
switch (_that) {
case AppError_DiskFull() when diskFull != null:
return diskFull();case AppError_AuthExpired() when authExpired != null:
return authExpired();case AppError_GitConflict() when gitConflict != null:
return gitConflict();case AppError_DatabaseError() when databaseError != null:
return databaseError(_that.field0);case AppError_CryptoError() when cryptoError != null:
return cryptoError(_that.field0);case AppError_NetworkError() when networkError != null:
return networkError(_that.field0);case AppError_OAuthError() when oAuthError != null:
return oAuthError(_that.field0);case AppError_IoError() when ioError != null:
return ioError(_that.field0);case AppError_ParseError() when parseError != null:
return parseError(_that.field0);case _:
  return null;

}
}

}

/// @nodoc


class AppError_DiskFull extends AppError {
  const AppError_DiskFull(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_DiskFull);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppError.diskFull()';
}


}




/// @nodoc


class AppError_AuthExpired extends AppError {
  const AppError_AuthExpired(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_AuthExpired);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppError.authExpired()';
}


}




/// @nodoc


class AppError_GitConflict extends AppError {
  const AppError_GitConflict(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_GitConflict);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AppError.gitConflict()';
}


}




/// @nodoc


class AppError_DatabaseError extends AppError {
  const AppError_DatabaseError(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_DatabaseErrorCopyWith<AppError_DatabaseError> get copyWith => _$AppError_DatabaseErrorCopyWithImpl<AppError_DatabaseError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_DatabaseError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.databaseError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_DatabaseErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_DatabaseErrorCopyWith(AppError_DatabaseError value, $Res Function(AppError_DatabaseError) _then) = _$AppError_DatabaseErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_DatabaseErrorCopyWithImpl<$Res>
    implements $AppError_DatabaseErrorCopyWith<$Res> {
  _$AppError_DatabaseErrorCopyWithImpl(this._self, this._then);

  final AppError_DatabaseError _self;
  final $Res Function(AppError_DatabaseError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_DatabaseError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_CryptoError extends AppError {
  const AppError_CryptoError(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_CryptoErrorCopyWith<AppError_CryptoError> get copyWith => _$AppError_CryptoErrorCopyWithImpl<AppError_CryptoError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_CryptoError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.cryptoError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_CryptoErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_CryptoErrorCopyWith(AppError_CryptoError value, $Res Function(AppError_CryptoError) _then) = _$AppError_CryptoErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_CryptoErrorCopyWithImpl<$Res>
    implements $AppError_CryptoErrorCopyWith<$Res> {
  _$AppError_CryptoErrorCopyWithImpl(this._self, this._then);

  final AppError_CryptoError _self;
  final $Res Function(AppError_CryptoError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_CryptoError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_NetworkError extends AppError {
  const AppError_NetworkError(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_NetworkErrorCopyWith<AppError_NetworkError> get copyWith => _$AppError_NetworkErrorCopyWithImpl<AppError_NetworkError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_NetworkError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.networkError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_NetworkErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_NetworkErrorCopyWith(AppError_NetworkError value, $Res Function(AppError_NetworkError) _then) = _$AppError_NetworkErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_NetworkErrorCopyWithImpl<$Res>
    implements $AppError_NetworkErrorCopyWith<$Res> {
  _$AppError_NetworkErrorCopyWithImpl(this._self, this._then);

  final AppError_NetworkError _self;
  final $Res Function(AppError_NetworkError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_NetworkError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_OAuthError extends AppError {
  const AppError_OAuthError(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_OAuthErrorCopyWith<AppError_OAuthError> get copyWith => _$AppError_OAuthErrorCopyWithImpl<AppError_OAuthError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_OAuthError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.oAuthError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_OAuthErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_OAuthErrorCopyWith(AppError_OAuthError value, $Res Function(AppError_OAuthError) _then) = _$AppError_OAuthErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_OAuthErrorCopyWithImpl<$Res>
    implements $AppError_OAuthErrorCopyWith<$Res> {
  _$AppError_OAuthErrorCopyWithImpl(this._self, this._then);

  final AppError_OAuthError _self;
  final $Res Function(AppError_OAuthError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_OAuthError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_IoError extends AppError {
  const AppError_IoError(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_IoErrorCopyWith<AppError_IoError> get copyWith => _$AppError_IoErrorCopyWithImpl<AppError_IoError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_IoError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.ioError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_IoErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_IoErrorCopyWith(AppError_IoError value, $Res Function(AppError_IoError) _then) = _$AppError_IoErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_IoErrorCopyWithImpl<$Res>
    implements $AppError_IoErrorCopyWith<$Res> {
  _$AppError_IoErrorCopyWithImpl(this._self, this._then);

  final AppError_IoError _self;
  final $Res Function(AppError_IoError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_IoError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AppError_ParseError extends AppError {
  const AppError_ParseError(this.field0): super._();
  

 final  String field0;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AppError_ParseErrorCopyWith<AppError_ParseError> get copyWith => _$AppError_ParseErrorCopyWithImpl<AppError_ParseError>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AppError_ParseError&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'AppError.parseError(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $AppError_ParseErrorCopyWith<$Res> implements $AppErrorCopyWith<$Res> {
  factory $AppError_ParseErrorCopyWith(AppError_ParseError value, $Res Function(AppError_ParseError) _then) = _$AppError_ParseErrorCopyWithImpl;
@useResult
$Res call({
 String field0
});




}
/// @nodoc
class _$AppError_ParseErrorCopyWithImpl<$Res>
    implements $AppError_ParseErrorCopyWith<$Res> {
  _$AppError_ParseErrorCopyWithImpl(this._self, this._then);

  final AppError_ParseError _self;
  final $Res Function(AppError_ParseError) _then;

/// Create a copy of AppError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(AppError_ParseError(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AstNode {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AstNode()';
}


}

/// @nodoc
class $AstNodeCopyWith<$Res>  {
$AstNodeCopyWith(AstNode _, $Res Function(AstNode) __);
}


/// Adds pattern-matching-related methods to [AstNode].
extension AstNodePatterns on AstNode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AstNode_Heading value)?  heading,TResult Function( AstNode_Paragraph value)?  paragraph,TResult Function( AstNode_List value)?  list,TResult Function( AstNode_ListItem value)?  listItem,TResult Function( AstNode_Blockquote value)?  blockquote,TResult Function( AstNode_CodeBlock value)?  codeBlock,TResult Function( AstNode_ThematicBreak value)?  thematicBreak,TResult Function( AstNode_Image value)?  image,TResult Function( AstNode_Suggestion value)?  suggestion,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AstNode_Heading() when heading != null:
return heading(_that);case AstNode_Paragraph() when paragraph != null:
return paragraph(_that);case AstNode_List() when list != null:
return list(_that);case AstNode_ListItem() when listItem != null:
return listItem(_that);case AstNode_Blockquote() when blockquote != null:
return blockquote(_that);case AstNode_CodeBlock() when codeBlock != null:
return codeBlock(_that);case AstNode_ThematicBreak() when thematicBreak != null:
return thematicBreak(_that);case AstNode_Image() when image != null:
return image(_that);case AstNode_Suggestion() when suggestion != null:
return suggestion(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AstNode_Heading value)  heading,required TResult Function( AstNode_Paragraph value)  paragraph,required TResult Function( AstNode_List value)  list,required TResult Function( AstNode_ListItem value)  listItem,required TResult Function( AstNode_Blockquote value)  blockquote,required TResult Function( AstNode_CodeBlock value)  codeBlock,required TResult Function( AstNode_ThematicBreak value)  thematicBreak,required TResult Function( AstNode_Image value)  image,required TResult Function( AstNode_Suggestion value)  suggestion,}){
final _that = this;
switch (_that) {
case AstNode_Heading():
return heading(_that);case AstNode_Paragraph():
return paragraph(_that);case AstNode_List():
return list(_that);case AstNode_ListItem():
return listItem(_that);case AstNode_Blockquote():
return blockquote(_that);case AstNode_CodeBlock():
return codeBlock(_that);case AstNode_ThematicBreak():
return thematicBreak(_that);case AstNode_Image():
return image(_that);case AstNode_Suggestion():
return suggestion(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AstNode_Heading value)?  heading,TResult? Function( AstNode_Paragraph value)?  paragraph,TResult? Function( AstNode_List value)?  list,TResult? Function( AstNode_ListItem value)?  listItem,TResult? Function( AstNode_Blockquote value)?  blockquote,TResult? Function( AstNode_CodeBlock value)?  codeBlock,TResult? Function( AstNode_ThematicBreak value)?  thematicBreak,TResult? Function( AstNode_Image value)?  image,TResult? Function( AstNode_Suggestion value)?  suggestion,}){
final _that = this;
switch (_that) {
case AstNode_Heading() when heading != null:
return heading(_that);case AstNode_Paragraph() when paragraph != null:
return paragraph(_that);case AstNode_List() when list != null:
return list(_that);case AstNode_ListItem() when listItem != null:
return listItem(_that);case AstNode_Blockquote() when blockquote != null:
return blockquote(_that);case AstNode_CodeBlock() when codeBlock != null:
return codeBlock(_that);case AstNode_ThematicBreak() when thematicBreak != null:
return thematicBreak(_that);case AstNode_Image() when image != null:
return image(_that);case AstNode_Suggestion() when suggestion != null:
return suggestion(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int level,  List<InlineElement> content)?  heading,TResult Function( List<InlineElement> content)?  paragraph,TResult Function( bool ordered,  List<AstNode> items)?  list,TResult Function( List<AstNode> content,  bool? checked)?  listItem,TResult Function( List<AstNode> nodes)?  blockquote,TResult Function( String? language,  String code)?  codeBlock,TResult Function()?  thematicBreak,TResult Function( String altText,  String urlOrPath)?  image,TResult Function( List<AstNode>? baseContent,  List<AstNode> localContent,  List<AstNode> incomingContent)?  suggestion,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AstNode_Heading() when heading != null:
return heading(_that.level,_that.content);case AstNode_Paragraph() when paragraph != null:
return paragraph(_that.content);case AstNode_List() when list != null:
return list(_that.ordered,_that.items);case AstNode_ListItem() when listItem != null:
return listItem(_that.content,_that.checked);case AstNode_Blockquote() when blockquote != null:
return blockquote(_that.nodes);case AstNode_CodeBlock() when codeBlock != null:
return codeBlock(_that.language,_that.code);case AstNode_ThematicBreak() when thematicBreak != null:
return thematicBreak();case AstNode_Image() when image != null:
return image(_that.altText,_that.urlOrPath);case AstNode_Suggestion() when suggestion != null:
return suggestion(_that.baseContent,_that.localContent,_that.incomingContent);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int level,  List<InlineElement> content)  heading,required TResult Function( List<InlineElement> content)  paragraph,required TResult Function( bool ordered,  List<AstNode> items)  list,required TResult Function( List<AstNode> content,  bool? checked)  listItem,required TResult Function( List<AstNode> nodes)  blockquote,required TResult Function( String? language,  String code)  codeBlock,required TResult Function()  thematicBreak,required TResult Function( String altText,  String urlOrPath)  image,required TResult Function( List<AstNode>? baseContent,  List<AstNode> localContent,  List<AstNode> incomingContent)  suggestion,}) {final _that = this;
switch (_that) {
case AstNode_Heading():
return heading(_that.level,_that.content);case AstNode_Paragraph():
return paragraph(_that.content);case AstNode_List():
return list(_that.ordered,_that.items);case AstNode_ListItem():
return listItem(_that.content,_that.checked);case AstNode_Blockquote():
return blockquote(_that.nodes);case AstNode_CodeBlock():
return codeBlock(_that.language,_that.code);case AstNode_ThematicBreak():
return thematicBreak();case AstNode_Image():
return image(_that.altText,_that.urlOrPath);case AstNode_Suggestion():
return suggestion(_that.baseContent,_that.localContent,_that.incomingContent);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int level,  List<InlineElement> content)?  heading,TResult? Function( List<InlineElement> content)?  paragraph,TResult? Function( bool ordered,  List<AstNode> items)?  list,TResult? Function( List<AstNode> content,  bool? checked)?  listItem,TResult? Function( List<AstNode> nodes)?  blockquote,TResult? Function( String? language,  String code)?  codeBlock,TResult? Function()?  thematicBreak,TResult? Function( String altText,  String urlOrPath)?  image,TResult? Function( List<AstNode>? baseContent,  List<AstNode> localContent,  List<AstNode> incomingContent)?  suggestion,}) {final _that = this;
switch (_that) {
case AstNode_Heading() when heading != null:
return heading(_that.level,_that.content);case AstNode_Paragraph() when paragraph != null:
return paragraph(_that.content);case AstNode_List() when list != null:
return list(_that.ordered,_that.items);case AstNode_ListItem() when listItem != null:
return listItem(_that.content,_that.checked);case AstNode_Blockquote() when blockquote != null:
return blockquote(_that.nodes);case AstNode_CodeBlock() when codeBlock != null:
return codeBlock(_that.language,_that.code);case AstNode_ThematicBreak() when thematicBreak != null:
return thematicBreak();case AstNode_Image() when image != null:
return image(_that.altText,_that.urlOrPath);case AstNode_Suggestion() when suggestion != null:
return suggestion(_that.baseContent,_that.localContent,_that.incomingContent);case _:
  return null;

}
}

}

/// @nodoc


class AstNode_Heading extends AstNode {
  const AstNode_Heading({required this.level, required final  List<InlineElement> content}): _content = content,super._();
  

 final  int level;
 final  List<InlineElement> _content;
 List<InlineElement> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}


/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_HeadingCopyWith<AstNode_Heading> get copyWith => _$AstNode_HeadingCopyWithImpl<AstNode_Heading>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_Heading&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other._content, _content));
}


@override
int get hashCode => Object.hash(runtimeType,level,const DeepCollectionEquality().hash(_content));

@override
String toString() {
  return 'AstNode.heading(level: $level, content: $content)';
}


}

/// @nodoc
abstract mixin class $AstNode_HeadingCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_HeadingCopyWith(AstNode_Heading value, $Res Function(AstNode_Heading) _then) = _$AstNode_HeadingCopyWithImpl;
@useResult
$Res call({
 int level, List<InlineElement> content
});




}
/// @nodoc
class _$AstNode_HeadingCopyWithImpl<$Res>
    implements $AstNode_HeadingCopyWith<$Res> {
  _$AstNode_HeadingCopyWithImpl(this._self, this._then);

  final AstNode_Heading _self;
  final $Res Function(AstNode_Heading) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = null,Object? content = null,}) {
  return _then(AstNode_Heading(
level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as int,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<InlineElement>,
  ));
}


}

/// @nodoc


class AstNode_Paragraph extends AstNode {
  const AstNode_Paragraph({required final  List<InlineElement> content}): _content = content,super._();
  

 final  List<InlineElement> _content;
 List<InlineElement> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}


/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_ParagraphCopyWith<AstNode_Paragraph> get copyWith => _$AstNode_ParagraphCopyWithImpl<AstNode_Paragraph>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_Paragraph&&const DeepCollectionEquality().equals(other._content, _content));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_content));

@override
String toString() {
  return 'AstNode.paragraph(content: $content)';
}


}

/// @nodoc
abstract mixin class $AstNode_ParagraphCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_ParagraphCopyWith(AstNode_Paragraph value, $Res Function(AstNode_Paragraph) _then) = _$AstNode_ParagraphCopyWithImpl;
@useResult
$Res call({
 List<InlineElement> content
});




}
/// @nodoc
class _$AstNode_ParagraphCopyWithImpl<$Res>
    implements $AstNode_ParagraphCopyWith<$Res> {
  _$AstNode_ParagraphCopyWithImpl(this._self, this._then);

  final AstNode_Paragraph _self;
  final $Res Function(AstNode_Paragraph) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? content = null,}) {
  return _then(AstNode_Paragraph(
content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<InlineElement>,
  ));
}


}

/// @nodoc


class AstNode_List extends AstNode {
  const AstNode_List({required this.ordered, required final  List<AstNode> items}): _items = items,super._();
  

 final  bool ordered;
 final  List<AstNode> _items;
 List<AstNode> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}


/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_ListCopyWith<AstNode_List> get copyWith => _$AstNode_ListCopyWithImpl<AstNode_List>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_List&&(identical(other.ordered, ordered) || other.ordered == ordered)&&const DeepCollectionEquality().equals(other._items, _items));
}


@override
int get hashCode => Object.hash(runtimeType,ordered,const DeepCollectionEquality().hash(_items));

@override
String toString() {
  return 'AstNode.list(ordered: $ordered, items: $items)';
}


}

/// @nodoc
abstract mixin class $AstNode_ListCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_ListCopyWith(AstNode_List value, $Res Function(AstNode_List) _then) = _$AstNode_ListCopyWithImpl;
@useResult
$Res call({
 bool ordered, List<AstNode> items
});




}
/// @nodoc
class _$AstNode_ListCopyWithImpl<$Res>
    implements $AstNode_ListCopyWith<$Res> {
  _$AstNode_ListCopyWithImpl(this._self, this._then);

  final AstNode_List _self;
  final $Res Function(AstNode_List) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? ordered = null,Object? items = null,}) {
  return _then(AstNode_List(
ordered: null == ordered ? _self.ordered : ordered // ignore: cast_nullable_to_non_nullable
as bool,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<AstNode>,
  ));
}


}

/// @nodoc


class AstNode_ListItem extends AstNode {
  const AstNode_ListItem({required final  List<AstNode> content, this.checked}): _content = content,super._();
  

 final  List<AstNode> _content;
 List<AstNode> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}

 final  bool? checked;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_ListItemCopyWith<AstNode_ListItem> get copyWith => _$AstNode_ListItemCopyWithImpl<AstNode_ListItem>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_ListItem&&const DeepCollectionEquality().equals(other._content, _content)&&(identical(other.checked, checked) || other.checked == checked));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_content),checked);

@override
String toString() {
  return 'AstNode.listItem(content: $content, checked: $checked)';
}


}

/// @nodoc
abstract mixin class $AstNode_ListItemCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_ListItemCopyWith(AstNode_ListItem value, $Res Function(AstNode_ListItem) _then) = _$AstNode_ListItemCopyWithImpl;
@useResult
$Res call({
 List<AstNode> content, bool? checked
});




}
/// @nodoc
class _$AstNode_ListItemCopyWithImpl<$Res>
    implements $AstNode_ListItemCopyWith<$Res> {
  _$AstNode_ListItemCopyWithImpl(this._self, this._then);

  final AstNode_ListItem _self;
  final $Res Function(AstNode_ListItem) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? content = null,Object? checked = freezed,}) {
  return _then(AstNode_ListItem(
content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<AstNode>,checked: freezed == checked ? _self.checked : checked // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc


class AstNode_Blockquote extends AstNode {
  const AstNode_Blockquote({required final  List<AstNode> nodes}): _nodes = nodes,super._();
  

 final  List<AstNode> _nodes;
 List<AstNode> get nodes {
  if (_nodes is EqualUnmodifiableListView) return _nodes;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_nodes);
}


/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_BlockquoteCopyWith<AstNode_Blockquote> get copyWith => _$AstNode_BlockquoteCopyWithImpl<AstNode_Blockquote>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_Blockquote&&const DeepCollectionEquality().equals(other._nodes, _nodes));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_nodes));

@override
String toString() {
  return 'AstNode.blockquote(nodes: $nodes)';
}


}

/// @nodoc
abstract mixin class $AstNode_BlockquoteCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_BlockquoteCopyWith(AstNode_Blockquote value, $Res Function(AstNode_Blockquote) _then) = _$AstNode_BlockquoteCopyWithImpl;
@useResult
$Res call({
 List<AstNode> nodes
});




}
/// @nodoc
class _$AstNode_BlockquoteCopyWithImpl<$Res>
    implements $AstNode_BlockquoteCopyWith<$Res> {
  _$AstNode_BlockquoteCopyWithImpl(this._self, this._then);

  final AstNode_Blockquote _self;
  final $Res Function(AstNode_Blockquote) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nodes = null,}) {
  return _then(AstNode_Blockquote(
nodes: null == nodes ? _self._nodes : nodes // ignore: cast_nullable_to_non_nullable
as List<AstNode>,
  ));
}


}

/// @nodoc


class AstNode_CodeBlock extends AstNode {
  const AstNode_CodeBlock({this.language, required this.code}): super._();
  

 final  String? language;
 final  String code;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_CodeBlockCopyWith<AstNode_CodeBlock> get copyWith => _$AstNode_CodeBlockCopyWithImpl<AstNode_CodeBlock>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_CodeBlock&&(identical(other.language, language) || other.language == language)&&(identical(other.code, code) || other.code == code));
}


@override
int get hashCode => Object.hash(runtimeType,language,code);

@override
String toString() {
  return 'AstNode.codeBlock(language: $language, code: $code)';
}


}

/// @nodoc
abstract mixin class $AstNode_CodeBlockCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_CodeBlockCopyWith(AstNode_CodeBlock value, $Res Function(AstNode_CodeBlock) _then) = _$AstNode_CodeBlockCopyWithImpl;
@useResult
$Res call({
 String? language, String code
});




}
/// @nodoc
class _$AstNode_CodeBlockCopyWithImpl<$Res>
    implements $AstNode_CodeBlockCopyWith<$Res> {
  _$AstNode_CodeBlockCopyWithImpl(this._self, this._then);

  final AstNode_CodeBlock _self;
  final $Res Function(AstNode_CodeBlock) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? language = freezed,Object? code = null,}) {
  return _then(AstNode_CodeBlock(
language: freezed == language ? _self.language : language // ignore: cast_nullable_to_non_nullable
as String?,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AstNode_ThematicBreak extends AstNode {
  const AstNode_ThematicBreak(): super._();
  






@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_ThematicBreak);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'AstNode.thematicBreak()';
}


}




/// @nodoc


class AstNode_Image extends AstNode {
  const AstNode_Image({required this.altText, required this.urlOrPath}): super._();
  

 final  String altText;
 final  String urlOrPath;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_ImageCopyWith<AstNode_Image> get copyWith => _$AstNode_ImageCopyWithImpl<AstNode_Image>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_Image&&(identical(other.altText, altText) || other.altText == altText)&&(identical(other.urlOrPath, urlOrPath) || other.urlOrPath == urlOrPath));
}


@override
int get hashCode => Object.hash(runtimeType,altText,urlOrPath);

@override
String toString() {
  return 'AstNode.image(altText: $altText, urlOrPath: $urlOrPath)';
}


}

/// @nodoc
abstract mixin class $AstNode_ImageCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_ImageCopyWith(AstNode_Image value, $Res Function(AstNode_Image) _then) = _$AstNode_ImageCopyWithImpl;
@useResult
$Res call({
 String altText, String urlOrPath
});




}
/// @nodoc
class _$AstNode_ImageCopyWithImpl<$Res>
    implements $AstNode_ImageCopyWith<$Res> {
  _$AstNode_ImageCopyWithImpl(this._self, this._then);

  final AstNode_Image _self;
  final $Res Function(AstNode_Image) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? altText = null,Object? urlOrPath = null,}) {
  return _then(AstNode_Image(
altText: null == altText ? _self.altText : altText // ignore: cast_nullable_to_non_nullable
as String,urlOrPath: null == urlOrPath ? _self.urlOrPath : urlOrPath // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AstNode_Suggestion extends AstNode {
  const AstNode_Suggestion({final  List<AstNode>? baseContent, required final  List<AstNode> localContent, required final  List<AstNode> incomingContent}): _baseContent = baseContent,_localContent = localContent,_incomingContent = incomingContent,super._();
  

 final  List<AstNode>? _baseContent;
 List<AstNode>? get baseContent {
  final value = _baseContent;
  if (value == null) return null;
  if (_baseContent is EqualUnmodifiableListView) return _baseContent;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(value);
}

 final  List<AstNode> _localContent;
 List<AstNode> get localContent {
  if (_localContent is EqualUnmodifiableListView) return _localContent;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_localContent);
}

 final  List<AstNode> _incomingContent;
 List<AstNode> get incomingContent {
  if (_incomingContent is EqualUnmodifiableListView) return _incomingContent;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_incomingContent);
}


/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AstNode_SuggestionCopyWith<AstNode_Suggestion> get copyWith => _$AstNode_SuggestionCopyWithImpl<AstNode_Suggestion>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AstNode_Suggestion&&const DeepCollectionEquality().equals(other._baseContent, _baseContent)&&const DeepCollectionEquality().equals(other._localContent, _localContent)&&const DeepCollectionEquality().equals(other._incomingContent, _incomingContent));
}


@override
int get hashCode => Object.hash(runtimeType,const DeepCollectionEquality().hash(_baseContent),const DeepCollectionEquality().hash(_localContent),const DeepCollectionEquality().hash(_incomingContent));

@override
String toString() {
  return 'AstNode.suggestion(baseContent: $baseContent, localContent: $localContent, incomingContent: $incomingContent)';
}


}

/// @nodoc
abstract mixin class $AstNode_SuggestionCopyWith<$Res> implements $AstNodeCopyWith<$Res> {
  factory $AstNode_SuggestionCopyWith(AstNode_Suggestion value, $Res Function(AstNode_Suggestion) _then) = _$AstNode_SuggestionCopyWithImpl;
@useResult
$Res call({
 List<AstNode>? baseContent, List<AstNode> localContent, List<AstNode> incomingContent
});




}
/// @nodoc
class _$AstNode_SuggestionCopyWithImpl<$Res>
    implements $AstNode_SuggestionCopyWith<$Res> {
  _$AstNode_SuggestionCopyWithImpl(this._self, this._then);

  final AstNode_Suggestion _self;
  final $Res Function(AstNode_Suggestion) _then;

/// Create a copy of AstNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? baseContent = freezed,Object? localContent = null,Object? incomingContent = null,}) {
  return _then(AstNode_Suggestion(
baseContent: freezed == baseContent ? _self._baseContent : baseContent // ignore: cast_nullable_to_non_nullable
as List<AstNode>?,localContent: null == localContent ? _self._localContent : localContent // ignore: cast_nullable_to_non_nullable
as List<AstNode>,incomingContent: null == incomingContent ? _self._incomingContent : incomingContent // ignore: cast_nullable_to_non_nullable
as List<AstNode>,
  ));
}


}

/// @nodoc
mixin _$InlineElement {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InlineElement);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'InlineElement()';
}


}

/// @nodoc
class $InlineElementCopyWith<$Res>  {
$InlineElementCopyWith(InlineElement _, $Res Function(InlineElement) __);
}


/// Adds pattern-matching-related methods to [InlineElement].
extension InlineElementPatterns on InlineElement {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( InlineElement_Text value)?  text,TResult Function( InlineElement_Link value)?  link,TResult Function( InlineElement_ExternalLink value)?  externalLink,required TResult orElse(),}){
final _that = this;
switch (_that) {
case InlineElement_Text() when text != null:
return text(_that);case InlineElement_Link() when link != null:
return link(_that);case InlineElement_ExternalLink() when externalLink != null:
return externalLink(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( InlineElement_Text value)  text,required TResult Function( InlineElement_Link value)  link,required TResult Function( InlineElement_ExternalLink value)  externalLink,}){
final _that = this;
switch (_that) {
case InlineElement_Text():
return text(_that);case InlineElement_Link():
return link(_that);case InlineElement_ExternalLink():
return externalLink(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( InlineElement_Text value)?  text,TResult? Function( InlineElement_Link value)?  link,TResult? Function( InlineElement_ExternalLink value)?  externalLink,}){
final _that = this;
switch (_that) {
case InlineElement_Text() when text != null:
return text(_that);case InlineElement_Link() when link != null:
return link(_that);case InlineElement_ExternalLink() when externalLink != null:
return externalLink(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( TextRun field0)?  text,TResult Function( String targetTitle,  String? resolvedNoteId,  List<InlineElement> content)?  link,TResult Function( String url,  List<InlineElement> content)?  externalLink,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InlineElement_Text() when text != null:
return text(_that.field0);case InlineElement_Link() when link != null:
return link(_that.targetTitle,_that.resolvedNoteId,_that.content);case InlineElement_ExternalLink() when externalLink != null:
return externalLink(_that.url,_that.content);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( TextRun field0)  text,required TResult Function( String targetTitle,  String? resolvedNoteId,  List<InlineElement> content)  link,required TResult Function( String url,  List<InlineElement> content)  externalLink,}) {final _that = this;
switch (_that) {
case InlineElement_Text():
return text(_that.field0);case InlineElement_Link():
return link(_that.targetTitle,_that.resolvedNoteId,_that.content);case InlineElement_ExternalLink():
return externalLink(_that.url,_that.content);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( TextRun field0)?  text,TResult? Function( String targetTitle,  String? resolvedNoteId,  List<InlineElement> content)?  link,TResult? Function( String url,  List<InlineElement> content)?  externalLink,}) {final _that = this;
switch (_that) {
case InlineElement_Text() when text != null:
return text(_that.field0);case InlineElement_Link() when link != null:
return link(_that.targetTitle,_that.resolvedNoteId,_that.content);case InlineElement_ExternalLink() when externalLink != null:
return externalLink(_that.url,_that.content);case _:
  return null;

}
}

}

/// @nodoc


class InlineElement_Text extends InlineElement {
  const InlineElement_Text(this.field0): super._();
  

 final  TextRun field0;

/// Create a copy of InlineElement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InlineElement_TextCopyWith<InlineElement_Text> get copyWith => _$InlineElement_TextCopyWithImpl<InlineElement_Text>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InlineElement_Text&&(identical(other.field0, field0) || other.field0 == field0));
}


@override
int get hashCode => Object.hash(runtimeType,field0);

@override
String toString() {
  return 'InlineElement.text(field0: $field0)';
}


}

/// @nodoc
abstract mixin class $InlineElement_TextCopyWith<$Res> implements $InlineElementCopyWith<$Res> {
  factory $InlineElement_TextCopyWith(InlineElement_Text value, $Res Function(InlineElement_Text) _then) = _$InlineElement_TextCopyWithImpl;
@useResult
$Res call({
 TextRun field0
});




}
/// @nodoc
class _$InlineElement_TextCopyWithImpl<$Res>
    implements $InlineElement_TextCopyWith<$Res> {
  _$InlineElement_TextCopyWithImpl(this._self, this._then);

  final InlineElement_Text _self;
  final $Res Function(InlineElement_Text) _then;

/// Create a copy of InlineElement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? field0 = null,}) {
  return _then(InlineElement_Text(
null == field0 ? _self.field0 : field0 // ignore: cast_nullable_to_non_nullable
as TextRun,
  ));
}


}

/// @nodoc


class InlineElement_Link extends InlineElement {
  const InlineElement_Link({required this.targetTitle, this.resolvedNoteId, required final  List<InlineElement> content}): _content = content,super._();
  

 final  String targetTitle;
 final  String? resolvedNoteId;
 final  List<InlineElement> _content;
 List<InlineElement> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}


/// Create a copy of InlineElement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InlineElement_LinkCopyWith<InlineElement_Link> get copyWith => _$InlineElement_LinkCopyWithImpl<InlineElement_Link>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InlineElement_Link&&(identical(other.targetTitle, targetTitle) || other.targetTitle == targetTitle)&&(identical(other.resolvedNoteId, resolvedNoteId) || other.resolvedNoteId == resolvedNoteId)&&const DeepCollectionEquality().equals(other._content, _content));
}


@override
int get hashCode => Object.hash(runtimeType,targetTitle,resolvedNoteId,const DeepCollectionEquality().hash(_content));

@override
String toString() {
  return 'InlineElement.link(targetTitle: $targetTitle, resolvedNoteId: $resolvedNoteId, content: $content)';
}


}

/// @nodoc
abstract mixin class $InlineElement_LinkCopyWith<$Res> implements $InlineElementCopyWith<$Res> {
  factory $InlineElement_LinkCopyWith(InlineElement_Link value, $Res Function(InlineElement_Link) _then) = _$InlineElement_LinkCopyWithImpl;
@useResult
$Res call({
 String targetTitle, String? resolvedNoteId, List<InlineElement> content
});




}
/// @nodoc
class _$InlineElement_LinkCopyWithImpl<$Res>
    implements $InlineElement_LinkCopyWith<$Res> {
  _$InlineElement_LinkCopyWithImpl(this._self, this._then);

  final InlineElement_Link _self;
  final $Res Function(InlineElement_Link) _then;

/// Create a copy of InlineElement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetTitle = null,Object? resolvedNoteId = freezed,Object? content = null,}) {
  return _then(InlineElement_Link(
targetTitle: null == targetTitle ? _self.targetTitle : targetTitle // ignore: cast_nullable_to_non_nullable
as String,resolvedNoteId: freezed == resolvedNoteId ? _self.resolvedNoteId : resolvedNoteId // ignore: cast_nullable_to_non_nullable
as String?,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<InlineElement>,
  ));
}


}

/// @nodoc


class InlineElement_ExternalLink extends InlineElement {
  const InlineElement_ExternalLink({required this.url, required final  List<InlineElement> content}): _content = content,super._();
  

 final  String url;
 final  List<InlineElement> _content;
 List<InlineElement> get content {
  if (_content is EqualUnmodifiableListView) return _content;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_content);
}


/// Create a copy of InlineElement
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InlineElement_ExternalLinkCopyWith<InlineElement_ExternalLink> get copyWith => _$InlineElement_ExternalLinkCopyWithImpl<InlineElement_ExternalLink>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InlineElement_ExternalLink&&(identical(other.url, url) || other.url == url)&&const DeepCollectionEquality().equals(other._content, _content));
}


@override
int get hashCode => Object.hash(runtimeType,url,const DeepCollectionEquality().hash(_content));

@override
String toString() {
  return 'InlineElement.externalLink(url: $url, content: $content)';
}


}

/// @nodoc
abstract mixin class $InlineElement_ExternalLinkCopyWith<$Res> implements $InlineElementCopyWith<$Res> {
  factory $InlineElement_ExternalLinkCopyWith(InlineElement_ExternalLink value, $Res Function(InlineElement_ExternalLink) _then) = _$InlineElement_ExternalLinkCopyWithImpl;
@useResult
$Res call({
 String url, List<InlineElement> content
});




}
/// @nodoc
class _$InlineElement_ExternalLinkCopyWithImpl<$Res>
    implements $InlineElement_ExternalLinkCopyWith<$Res> {
  _$InlineElement_ExternalLinkCopyWithImpl(this._self, this._then);

  final InlineElement_ExternalLink _self;
  final $Res Function(InlineElement_ExternalLink) _then;

/// Create a copy of InlineElement
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? content = null,}) {
  return _then(InlineElement_ExternalLink(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
as List<InlineElement>,
  ));
}


}

// dart format on
