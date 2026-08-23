// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'query.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LinkCompletionKind {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkCompletionKind);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LinkCompletionKind()';
}


}

/// @nodoc
class $LinkCompletionKindCopyWith<$Res>  {
$LinkCompletionKindCopyWith(LinkCompletionKind _, $Res Function(LinkCompletionKind) __);
}


/// Adds pattern-matching-related methods to [LinkCompletionKind].
extension LinkCompletionKindPatterns on LinkCompletionKind {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LinkCompletionKind_Existing value)?  existing,TResult Function( LinkCompletionKind_ProspectiveGhost value)?  prospectiveGhost,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LinkCompletionKind_Existing() when existing != null:
return existing(_that);case LinkCompletionKind_ProspectiveGhost() when prospectiveGhost != null:
return prospectiveGhost(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LinkCompletionKind_Existing value)  existing,required TResult Function( LinkCompletionKind_ProspectiveGhost value)  prospectiveGhost,}){
final _that = this;
switch (_that) {
case LinkCompletionKind_Existing():
return existing(_that);case LinkCompletionKind_ProspectiveGhost():
return prospectiveGhost(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LinkCompletionKind_Existing value)?  existing,TResult? Function( LinkCompletionKind_ProspectiveGhost value)?  prospectiveGhost,}){
final _that = this;
switch (_that) {
case LinkCompletionKind_Existing() when existing != null:
return existing(_that);case LinkCompletionKind_ProspectiveGhost() when prospectiveGhost != null:
return prospectiveGhost(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String noteId)?  existing,TResult Function( String targetId)?  prospectiveGhost,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LinkCompletionKind_Existing() when existing != null:
return existing(_that.noteId);case LinkCompletionKind_ProspectiveGhost() when prospectiveGhost != null:
return prospectiveGhost(_that.targetId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String noteId)  existing,required TResult Function( String targetId)  prospectiveGhost,}) {final _that = this;
switch (_that) {
case LinkCompletionKind_Existing():
return existing(_that.noteId);case LinkCompletionKind_ProspectiveGhost():
return prospectiveGhost(_that.targetId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String noteId)?  existing,TResult? Function( String targetId)?  prospectiveGhost,}) {final _that = this;
switch (_that) {
case LinkCompletionKind_Existing() when existing != null:
return existing(_that.noteId);case LinkCompletionKind_ProspectiveGhost() when prospectiveGhost != null:
return prospectiveGhost(_that.targetId);case _:
  return null;

}
}

}

/// @nodoc


class LinkCompletionKind_Existing extends LinkCompletionKind {
  const LinkCompletionKind_Existing({required this.noteId}): super._();
  

 final  String noteId;

/// Create a copy of LinkCompletionKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkCompletionKind_ExistingCopyWith<LinkCompletionKind_Existing> get copyWith => _$LinkCompletionKind_ExistingCopyWithImpl<LinkCompletionKind_Existing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkCompletionKind_Existing&&(identical(other.noteId, noteId) || other.noteId == noteId));
}


@override
int get hashCode => Object.hash(runtimeType,noteId);

@override
String toString() {
  return 'LinkCompletionKind.existing(noteId: $noteId)';
}


}

/// @nodoc
abstract mixin class $LinkCompletionKind_ExistingCopyWith<$Res> implements $LinkCompletionKindCopyWith<$Res> {
  factory $LinkCompletionKind_ExistingCopyWith(LinkCompletionKind_Existing value, $Res Function(LinkCompletionKind_Existing) _then) = _$LinkCompletionKind_ExistingCopyWithImpl;
@useResult
$Res call({
 String noteId
});




}
/// @nodoc
class _$LinkCompletionKind_ExistingCopyWithImpl<$Res>
    implements $LinkCompletionKind_ExistingCopyWith<$Res> {
  _$LinkCompletionKind_ExistingCopyWithImpl(this._self, this._then);

  final LinkCompletionKind_Existing _self;
  final $Res Function(LinkCompletionKind_Existing) _then;

/// Create a copy of LinkCompletionKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? noteId = null,}) {
  return _then(LinkCompletionKind_Existing(
noteId: null == noteId ? _self.noteId : noteId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class LinkCompletionKind_ProspectiveGhost extends LinkCompletionKind {
  const LinkCompletionKind_ProspectiveGhost({required this.targetId}): super._();
  

 final  String targetId;

/// Create a copy of LinkCompletionKind
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkCompletionKind_ProspectiveGhostCopyWith<LinkCompletionKind_ProspectiveGhost> get copyWith => _$LinkCompletionKind_ProspectiveGhostCopyWithImpl<LinkCompletionKind_ProspectiveGhost>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkCompletionKind_ProspectiveGhost&&(identical(other.targetId, targetId) || other.targetId == targetId));
}


@override
int get hashCode => Object.hash(runtimeType,targetId);

@override
String toString() {
  return 'LinkCompletionKind.prospectiveGhost(targetId: $targetId)';
}


}

/// @nodoc
abstract mixin class $LinkCompletionKind_ProspectiveGhostCopyWith<$Res> implements $LinkCompletionKindCopyWith<$Res> {
  factory $LinkCompletionKind_ProspectiveGhostCopyWith(LinkCompletionKind_ProspectiveGhost value, $Res Function(LinkCompletionKind_ProspectiveGhost) _then) = _$LinkCompletionKind_ProspectiveGhostCopyWithImpl;
@useResult
$Res call({
 String targetId
});




}
/// @nodoc
class _$LinkCompletionKind_ProspectiveGhostCopyWithImpl<$Res>
    implements $LinkCompletionKind_ProspectiveGhostCopyWith<$Res> {
  _$LinkCompletionKind_ProspectiveGhostCopyWithImpl(this._self, this._then);

  final LinkCompletionKind_ProspectiveGhost _self;
  final $Res Function(LinkCompletionKind_ProspectiveGhost) _then;

/// Create a copy of LinkCompletionKind
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetId = null,}) {
  return _then(LinkCompletionKind_ProspectiveGhost(
targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$LinkTargetResolution {





@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkTargetResolution);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
  return 'LinkTargetResolution()';
}


}

/// @nodoc
class $LinkTargetResolutionCopyWith<$Res>  {
$LinkTargetResolutionCopyWith(LinkTargetResolution _, $Res Function(LinkTargetResolution) __);
}


/// Adds pattern-matching-related methods to [LinkTargetResolution].
extension LinkTargetResolutionPatterns on LinkTargetResolution {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LinkTargetResolution_Existing value)?  existing,TResult Function( LinkTargetResolution_Missing value)?  missing,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LinkTargetResolution_Existing() when existing != null:
return existing(_that);case LinkTargetResolution_Missing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LinkTargetResolution_Existing value)  existing,required TResult Function( LinkTargetResolution_Missing value)  missing,}){
final _that = this;
switch (_that) {
case LinkTargetResolution_Existing():
return existing(_that);case LinkTargetResolution_Missing():
return missing(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LinkTargetResolution_Existing value)?  existing,TResult? Function( LinkTargetResolution_Missing value)?  missing,}){
final _that = this;
switch (_that) {
case LinkTargetResolution_Existing() when existing != null:
return existing(_that);case LinkTargetResolution_Missing() when missing != null:
return missing(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String noteId)?  existing,TResult Function( String targetId,  String directoryPath,  String title)?  missing,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LinkTargetResolution_Existing() when existing != null:
return existing(_that.noteId);case LinkTargetResolution_Missing() when missing != null:
return missing(_that.targetId,_that.directoryPath,_that.title);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String noteId)  existing,required TResult Function( String targetId,  String directoryPath,  String title)  missing,}) {final _that = this;
switch (_that) {
case LinkTargetResolution_Existing():
return existing(_that.noteId);case LinkTargetResolution_Missing():
return missing(_that.targetId,_that.directoryPath,_that.title);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String noteId)?  existing,TResult? Function( String targetId,  String directoryPath,  String title)?  missing,}) {final _that = this;
switch (_that) {
case LinkTargetResolution_Existing() when existing != null:
return existing(_that.noteId);case LinkTargetResolution_Missing() when missing != null:
return missing(_that.targetId,_that.directoryPath,_that.title);case _:
  return null;

}
}

}

/// @nodoc


class LinkTargetResolution_Existing extends LinkTargetResolution {
  const LinkTargetResolution_Existing({required this.noteId}): super._();
  

 final  String noteId;

/// Create a copy of LinkTargetResolution
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkTargetResolution_ExistingCopyWith<LinkTargetResolution_Existing> get copyWith => _$LinkTargetResolution_ExistingCopyWithImpl<LinkTargetResolution_Existing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkTargetResolution_Existing&&(identical(other.noteId, noteId) || other.noteId == noteId));
}


@override
int get hashCode => Object.hash(runtimeType,noteId);

@override
String toString() {
  return 'LinkTargetResolution.existing(noteId: $noteId)';
}


}

/// @nodoc
abstract mixin class $LinkTargetResolution_ExistingCopyWith<$Res> implements $LinkTargetResolutionCopyWith<$Res> {
  factory $LinkTargetResolution_ExistingCopyWith(LinkTargetResolution_Existing value, $Res Function(LinkTargetResolution_Existing) _then) = _$LinkTargetResolution_ExistingCopyWithImpl;
@useResult
$Res call({
 String noteId
});




}
/// @nodoc
class _$LinkTargetResolution_ExistingCopyWithImpl<$Res>
    implements $LinkTargetResolution_ExistingCopyWith<$Res> {
  _$LinkTargetResolution_ExistingCopyWithImpl(this._self, this._then);

  final LinkTargetResolution_Existing _self;
  final $Res Function(LinkTargetResolution_Existing) _then;

/// Create a copy of LinkTargetResolution
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? noteId = null,}) {
  return _then(LinkTargetResolution_Existing(
noteId: null == noteId ? _self.noteId : noteId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class LinkTargetResolution_Missing extends LinkTargetResolution {
  const LinkTargetResolution_Missing({required this.targetId, required this.directoryPath, required this.title}): super._();
  

 final  String targetId;
 final  String directoryPath;
 final  String title;

/// Create a copy of LinkTargetResolution
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LinkTargetResolution_MissingCopyWith<LinkTargetResolution_Missing> get copyWith => _$LinkTargetResolution_MissingCopyWithImpl<LinkTargetResolution_Missing>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LinkTargetResolution_Missing&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.directoryPath, directoryPath) || other.directoryPath == directoryPath)&&(identical(other.title, title) || other.title == title));
}


@override
int get hashCode => Object.hash(runtimeType,targetId,directoryPath,title);

@override
String toString() {
  return 'LinkTargetResolution.missing(targetId: $targetId, directoryPath: $directoryPath, title: $title)';
}


}

/// @nodoc
abstract mixin class $LinkTargetResolution_MissingCopyWith<$Res> implements $LinkTargetResolutionCopyWith<$Res> {
  factory $LinkTargetResolution_MissingCopyWith(LinkTargetResolution_Missing value, $Res Function(LinkTargetResolution_Missing) _then) = _$LinkTargetResolution_MissingCopyWithImpl;
@useResult
$Res call({
 String targetId, String directoryPath, String title
});




}
/// @nodoc
class _$LinkTargetResolution_MissingCopyWithImpl<$Res>
    implements $LinkTargetResolution_MissingCopyWith<$Res> {
  _$LinkTargetResolution_MissingCopyWithImpl(this._self, this._then);

  final LinkTargetResolution_Missing _self;
  final $Res Function(LinkTargetResolution_Missing) _then;

/// Create a copy of LinkTargetResolution
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? targetId = null,Object? directoryPath = null,Object? title = null,}) {
  return _then(LinkTargetResolution_Missing(
targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,directoryPath: null == directoryPath ? _self.directoryPath : directoryPath // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$TreeNode {

 String get path;
/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreeNodeCopyWith<TreeNode> get copyWith => _$TreeNodeCopyWithImpl<TreeNode>(this as TreeNode, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreeNode&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,path);

@override
String toString() {
  return 'TreeNode(path: $path)';
}


}

/// @nodoc
abstract mixin class $TreeNodeCopyWith<$Res>  {
  factory $TreeNodeCopyWith(TreeNode value, $Res Function(TreeNode) _then) = _$TreeNodeCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$TreeNodeCopyWithImpl<$Res>
    implements $TreeNodeCopyWith<$Res> {
  _$TreeNodeCopyWithImpl(this._self, this._then);

  final TreeNode _self;
  final $Res Function(TreeNode) _then;

/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? path = null,}) {
  return _then(_self.copyWith(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [TreeNode].
extension TreeNodePatterns on TreeNode {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( TreeNode_Directory value)?  directory,TResult Function( TreeNode_Note value)?  note,required TResult orElse(),}){
final _that = this;
switch (_that) {
case TreeNode_Directory() when directory != null:
return directory(_that);case TreeNode_Note() when note != null:
return note(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( TreeNode_Directory value)  directory,required TResult Function( TreeNode_Note value)  note,}){
final _that = this;
switch (_that) {
case TreeNode_Directory():
return directory(_that);case TreeNode_Note():
return note(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( TreeNode_Directory value)?  directory,TResult? Function( TreeNode_Note value)?  note,}){
final _that = this;
switch (_that) {
case TreeNode_Directory() when directory != null:
return directory(_that);case TreeNode_Note() when note != null:
return note(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String name,  String path,  List<TreeNode> children)?  directory,TResult Function( String id,  String title,  String path)?  note,required TResult orElse(),}) {final _that = this;
switch (_that) {
case TreeNode_Directory() when directory != null:
return directory(_that.name,_that.path,_that.children);case TreeNode_Note() when note != null:
return note(_that.id,_that.title,_that.path);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String name,  String path,  List<TreeNode> children)  directory,required TResult Function( String id,  String title,  String path)  note,}) {final _that = this;
switch (_that) {
case TreeNode_Directory():
return directory(_that.name,_that.path,_that.children);case TreeNode_Note():
return note(_that.id,_that.title,_that.path);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String name,  String path,  List<TreeNode> children)?  directory,TResult? Function( String id,  String title,  String path)?  note,}) {final _that = this;
switch (_that) {
case TreeNode_Directory() when directory != null:
return directory(_that.name,_that.path,_that.children);case TreeNode_Note() when note != null:
return note(_that.id,_that.title,_that.path);case _:
  return null;

}
}

}

/// @nodoc


class TreeNode_Directory extends TreeNode {
  const TreeNode_Directory({required this.name, required this.path, required final  List<TreeNode> children}): _children = children,super._();
  

 final  String name;
@override final  String path;
 final  List<TreeNode> _children;
 List<TreeNode> get children {
  if (_children is EqualUnmodifiableListView) return _children;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_children);
}


/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreeNode_DirectoryCopyWith<TreeNode_Directory> get copyWith => _$TreeNode_DirectoryCopyWithImpl<TreeNode_Directory>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreeNode_Directory&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&const DeepCollectionEquality().equals(other._children, _children));
}


@override
int get hashCode => Object.hash(runtimeType,name,path,const DeepCollectionEquality().hash(_children));

@override
String toString() {
  return 'TreeNode.directory(name: $name, path: $path, children: $children)';
}


}

/// @nodoc
abstract mixin class $TreeNode_DirectoryCopyWith<$Res> implements $TreeNodeCopyWith<$Res> {
  factory $TreeNode_DirectoryCopyWith(TreeNode_Directory value, $Res Function(TreeNode_Directory) _then) = _$TreeNode_DirectoryCopyWithImpl;
@override @useResult
$Res call({
 String name, String path, List<TreeNode> children
});




}
/// @nodoc
class _$TreeNode_DirectoryCopyWithImpl<$Res>
    implements $TreeNode_DirectoryCopyWith<$Res> {
  _$TreeNode_DirectoryCopyWithImpl(this._self, this._then);

  final TreeNode_Directory _self;
  final $Res Function(TreeNode_Directory) _then;

/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? path = null,Object? children = null,}) {
  return _then(TreeNode_Directory(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,children: null == children ? _self._children : children // ignore: cast_nullable_to_non_nullable
as List<TreeNode>,
  ));
}


}

/// @nodoc


class TreeNode_Note extends TreeNode {
  const TreeNode_Note({required this.id, required this.title, required this.path}): super._();
  

 final  String id;
 final  String title;
@override final  String path;

/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TreeNode_NoteCopyWith<TreeNode_Note> get copyWith => _$TreeNode_NoteCopyWithImpl<TreeNode_Note>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TreeNode_Note&&(identical(other.id, id) || other.id == id)&&(identical(other.title, title) || other.title == title)&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode => Object.hash(runtimeType,id,title,path);

@override
String toString() {
  return 'TreeNode.note(id: $id, title: $title, path: $path)';
}


}

/// @nodoc
abstract mixin class $TreeNode_NoteCopyWith<$Res> implements $TreeNodeCopyWith<$Res> {
  factory $TreeNode_NoteCopyWith(TreeNode_Note value, $Res Function(TreeNode_Note) _then) = _$TreeNode_NoteCopyWithImpl;
@override @useResult
$Res call({
 String id, String title, String path
});




}
/// @nodoc
class _$TreeNode_NoteCopyWithImpl<$Res>
    implements $TreeNode_NoteCopyWith<$Res> {
  _$TreeNode_NoteCopyWithImpl(this._self, this._then);

  final TreeNode_Note _self;
  final $Res Function(TreeNode_Note) _then;

/// Create a copy of TreeNode
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? title = null,Object? path = null,}) {
  return _then(TreeNode_Note(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
