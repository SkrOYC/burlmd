// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'ast.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( TextRun field0)?  text,TResult Function( String targetId,  bool exists,  List<InlineElement> content)?  link,TResult Function( String url,  List<InlineElement> content)?  externalLink,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InlineElement_Text() when text != null:
return text(_that.field0);case InlineElement_Link() when link != null:
return link(_that.targetId,_that.exists,_that.content);case InlineElement_ExternalLink() when externalLink != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( TextRun field0)  text,required TResult Function( String targetId,  bool exists,  List<InlineElement> content)  link,required TResult Function( String url,  List<InlineElement> content)  externalLink,}) {final _that = this;
switch (_that) {
case InlineElement_Text():
return text(_that.field0);case InlineElement_Link():
return link(_that.targetId,_that.exists,_that.content);case InlineElement_ExternalLink():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( TextRun field0)?  text,TResult? Function( String targetId,  bool exists,  List<InlineElement> content)?  link,TResult? Function( String url,  List<InlineElement> content)?  externalLink,}) {final _that = this;
switch (_that) {
case InlineElement_Text() when text != null:
return text(_that.field0);case InlineElement_Link() when link != null:
return link(_that.targetId,_that.exists,_that.content);case InlineElement_ExternalLink() when externalLink != null:
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
  const InlineElement_Link({required this.targetId, required this.exists, required final  List<InlineElement> content}): _content = content,super._();
  

/// The target's OKF concept id, as `okf::links::classify` derived it
/// from the parsed destination. Always present, even when nothing
/// matches it.
 final  String targetId;
/// False for a ghost Link — a Link to a Note not yet created, which
/// OKF §6.1 requires consumers to tolerate and which CAP-GRAPH-04
/// makes a feature.
///
/// Resolving this requires the index, not the parser: it is whether
/// `target_id` matches a `notes` row. `WSPC-D003` declares the field
/// and sits upstream of the indexer, so it leaves the field `false`
/// and `WSPC-D005` populates it.
///
/// **Advisory, and only as fresh as the state it came from.** Creating
/// or deleting a Note flips it for every inbound Link in every other
/// Note, so the follow path must re-resolve against the index rather
/// than trust the flag; what it is *for* is rendering.
 final  bool exists;
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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InlineElement_Link&&(identical(other.targetId, targetId) || other.targetId == targetId)&&(identical(other.exists, exists) || other.exists == exists)&&const DeepCollectionEquality().equals(other._content, _content));
}


@override
int get hashCode => Object.hash(runtimeType,targetId,exists,const DeepCollectionEquality().hash(_content));

@override
String toString() {
  return 'InlineElement.link(targetId: $targetId, exists: $exists, content: $content)';
}


}

/// @nodoc
abstract mixin class $InlineElement_LinkCopyWith<$Res> implements $InlineElementCopyWith<$Res> {
  factory $InlineElement_LinkCopyWith(InlineElement_Link value, $Res Function(InlineElement_Link) _then) = _$InlineElement_LinkCopyWithImpl;
@useResult
$Res call({
 String targetId, bool exists, List<InlineElement> content
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
@pragma('vm:prefer-inline') $Res call({Object? targetId = null,Object? exists = null,Object? content = null,}) {
  return _then(InlineElement_Link(
targetId: null == targetId ? _self.targetId : targetId // ignore: cast_nullable_to_non_nullable
as String,exists: null == exists ? _self.exists : exists // ignore: cast_nullable_to_non_nullable
as bool,content: null == content ? _self._content : content // ignore: cast_nullable_to_non_nullable
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
