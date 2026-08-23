import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'
    show Actions, intentForMacOSSelector, primaryFocus;

/// Ephemeral platform-input proxy for one rendered, cross-Block selection.
///
/// This deliberately holds neither a Note id nor document text. Its empty
/// [TextEditingValue] is only the platform's IME/clipboard handshake; Core
/// owns the frozen [range], source splice, parse, and resulting caret.
class RangeTextInputClient<T> implements TextInputClient {
  RangeTextInputClient({
    required this.range,
    required this.onReplace,
    required this.onDelete,
    required this.copyMarkdown,
    required this.onError,
  });

  final T range;
  final Future<void> Function(String replacement) onReplace;
  final Future<void> Function() onDelete;
  final Future<String> Function() copyMarkdown;
  final void Function(Object error) onError;

  TextInputConnection? _connection;
  TextEditingValue _value = TextEditingValue.empty;
  int _generation = 0;
  bool _operationInFlight = false;

  bool get isAttached => _connection?.attached ?? false;

  @override
  TextEditingValue get currentTextEditingValue => _value;

  @override
  AutofillScope? get currentAutofillScope => null;

  /// Attaches exactly one connection, establishing the empty state before the
  /// platform is allowed to show its input UI (Flutter 3.44.3 protocol).
  void attach() {
    close();
    final connection = TextInput.attach(
      this,
      const TextInputConfiguration(
        inputType: TextInputType.multiline,
        enableDeltaModel: false,
      ),
    );
    _connection = connection;
    _value = TextEditingValue.empty;
    connection.setEditingState(_value);
    connection.show();
  }

  /// Revokes all callbacks before releasing the platform connection.
  void close() {
    _generation++;
    _operationInFlight = false;
    final connection = _connection;
    _connection = null;
    _value = TextEditingValue.empty;
    connection?.close();
  }

  bool _isLive(int generation) =>
      generation == _generation && _connection?.attached == true;

  @override
  void updateEditingValue(TextEditingValue value) {
    if (!isAttached || _operationInFlight) return;
    _value = value;
    // A valid nonempty composing range is owned exclusively by the IME.
    if (value.isComposingRangeValid && !value.composing.isCollapsed) return;
    // Selection-only/cancel notifications on our deliberately empty proxy do
    // not describe a replacement.
    if (value.text.isEmpty) return;
    unawaited(_replace(value.text));
  }

  Future<void> replaceWith(String replacement) => _replace(replacement);

  Future<void> deleteSelection() => _runMutation(onDelete);

  Future<void> copySelection() async {
    if (!isAttached) return;
    try {
      final markdown = await copyMarkdown();
      if (!isAttached) return;
      await Clipboard.setData(ClipboardData(text: markdown));
    } catch (error) {
      if (isAttached) onError(error);
    }
  }

  Future<void> cutSelection() async {
    if (!isAttached) return;
    try {
      // Clipboard completion is the cut boundary: no deletion follows a
      // failed copy, and the deletion itself is one Core operation.
      final markdown = await copyMarkdown();
      if (!isAttached) return;
      await Clipboard.setData(ClipboardData(text: markdown));
      if (!isAttached) return;
      await deleteSelection();
    } catch (error) {
      if (isAttached) onError(error);
    }
  }

  Future<void> pasteSelection() async {
    if (!isAttached) return;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text;
      if (!isAttached || text == null) return;
      await _replace(text);
    } catch (error) {
      if (isAttached) onError(error);
    }
  }

  Future<void> _replace(String replacement) =>
      _runMutation(() => onReplace(replacement));

  Future<void> _runMutation(Future<void> Function() mutation) async {
    if (!isAttached || _operationInFlight) return;
    final generation = _generation;
    _operationInFlight = true;
    try {
      await mutation();
      // Do not clear an active composition or a replacement connection. A
      // successful Core result is the only point that may reset this value.
      if (_isLive(generation)) {
        _value = TextEditingValue.empty;
        _connection!.setEditingState(_value);
      }
    } catch (error) {
      if (_isLive(generation)) onError(error);
    } finally {
      if (_isLive(generation)) _operationInFlight = false;
    }
  }

  @override
  void performAction(TextInputAction action) {}

  @override
  void insertContent(KeyboardInsertedContent content) {}

  @override
  void performPrivateCommand(String action, Map<String, dynamic> data) {}

  @override
  void updateFloatingCursor(RawFloatingCursorPoint point) {}

  @override
  void showAutocorrectionPromptRect(int start, int end) {}

  @override
  bool onFocusReceived() => false;

  @override
  void didChangeInputControl(
    TextInputControl? oldControl,
    TextInputControl? newControl,
  ) {}

  @override
  void showToolbar() {}

  @override
  void insertTextPlaceholder(Size size) {}

  @override
  void removeTextPlaceholder() {}

  @override
  void performSelector(String selectorName) {
    if (!isAttached) return;
    final intent = intentForMacOSSelector(selectorName);
    final primaryContext = primaryFocus?.context;
    if (intent != null && primaryContext != null) {
      Actions.invoke(primaryContext, intent);
    }
  }

  @override
  void connectionClosed() {
    // The engine has already detached this connection. Do not call close()
    // back into it; just invalidate any asynchronous mutation continuation.
    _generation++;
    _operationInFlight = false;
    _connection = null;
    _value = TextEditingValue.empty;
  }
}
