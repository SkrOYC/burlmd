// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'error.dart';

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

// dart format on
