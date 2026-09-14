import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/search_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Keyboard navigation for a title-prefix jump and inbound Links.
///
/// Both lists are Core-backed. Selecting a candidate publishes only its
/// concept id through [selectedNoteIdProvider], so the mounted workspace shell
/// retains responsibility for the guarded, authoritative tab open.
class NoteNavigationPanel extends ConsumerStatefulWidget {
  const NoteNavigationPanel({
    super.key,
    this.titleResultLimit = 25,
    this.backlinksForNoteId,
    this.onResultSelected,
    this.onDismiss,
  });

  final int titleResultLimit;

  /// Test and embedded callers can name the displayed Note directly.
  /// Production leaves this null and follows the authoritative active session.
  final String? backlinksForNoteId;
  final ValueChanged<String>? onResultSelected;
  final VoidCallback? onDismiss;

  @override
  ConsumerState<NoteNavigationPanel> createState() =>
      _NoteNavigationPanelState();
}

class _NoteNavigationPanelState extends ConsumerState<NoteNavigationPanel> {
  final _inputFocusNode = FocusNode(debugLabel: 'note-navigation-input');
  var _query = '';
  var _selectedIndex = 0;
  int? _selectedBacklinkIndex;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputFocusNode.dispose();
    super.dispose();
  }

  bool _select(NoteMetadata note) {
    if (ref.read(noteSelectionBlockedProvider)) return false;
    final selected = ref.read(selectedNoteIdProvider.notifier).select(note.id);
    if (selected) widget.onResultSelected?.call(note.id);
    return selected;
  }

  KeyEventResult _handleTitleKey(
    KeyEvent event,
    List<NoteMetadata> hits,
    List<NoteMetadata> backlinks,
  ) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (hits.isEmpty && backlinks.isEmpty) return KeyEventResult.ignored;
    if (hits.isEmpty) {
      final selectedBacklink = _selectedBacklinkIndex ?? 0;
      switch (event.logicalKey) {
        case LogicalKeyboardKey.arrowDown:
          setState(
            () => _selectedBacklinkIndex =
                (selectedBacklink + 1) % backlinks.length,
          );
          return KeyEventResult.handled;
        case LogicalKeyboardKey.arrowUp:
          setState(
            () => _selectedBacklinkIndex =
                (selectedBacklink - 1 + backlinks.length) % backlinks.length,
          );
          return KeyEventResult.handled;
        case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
          _select(backlinks[selectedBacklink]);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          widget.onDismiss?.call();
          return widget.onDismiss == null
              ? KeyEventResult.ignored
              : KeyEventResult.handled;
        default:
          return KeyEventResult.ignored;
      }
    }
    final selectedIndex = _selectedIndex.clamp(0, hits.length - 1);
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        setState(() => _selectedIndex = (selectedIndex + 1) % hits.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        setState(
          () =>
              _selectedIndex = (selectedIndex - 1 + hits.length) % hits.length,
        );
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter:
        _select(hits[selectedIndex]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        widget.onDismiss?.call();
        return widget.onDismiss == null
            ? KeyEventResult.ignored
            : KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    final titleResults = ref.watch(
      titleJumpResultsProvider((query: _query, limit: widget.titleResultLimit)),
    );
    final activeNoteId =
        widget.backlinksForNoteId ?? ref.watch(activeNoteProvider)?.metadata.id;
    final backlinks = activeNoteId == null
        ? const AsyncData<List<NoteMetadata>>([])
        : ref.watch(backlinksProvider(activeNoteId));
    final titleHits = titleResults.value ?? const <NoteMetadata>[];
    final backlinkHits = backlinks.value ?? const <NoteMetadata>[];
    final selectedIndex = _selectedIndex.clamp(
      0,
      titleHits.isEmpty ? 0 : titleHits.length - 1,
    );

    return Material(
      color: colors.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            child: Text(
              l10n.noteNavigationTitle,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Focus(
              onKeyEvent: (_, event) =>
                  _handleTitleKey(event, titleHits, backlinkHits),
              child: TextField(
                key: const ValueKey('note-navigation-input'),
                autofocus: true,
                focusNode: _inputFocusNode,
                style: TextStyle(color: colors.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: Icon(
                    LucideIcons.arrow_right_to_line,
                    size: 16,
                    color: colors.textMuted,
                  ),
                  hintText: l10n.noteNavigationHint,
                  isDense: true,
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
                onChanged: (query) => setState(() {
                  _query = query;
                  _selectedIndex = 0;
                  _selectedBacklinkIndex = null;
                }),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              key: const ValueKey('note-navigation-results'),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              children: [
                _TitleResults(
                  query: _query,
                  results: titleResults,
                  selectedIndex: selectedIndex,
                  onSelect: _select,
                ),
                if (activeNoteId != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    l10n.noteNavigationBacklinks,
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  _BacklinkResults(
                    results: backlinks,
                    selectedIndex: _selectedBacklinkIndex,
                    onSelect: _select,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleResults extends StatelessWidget {
  const _TitleResults({
    required this.query,
    required this.results,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String query;
  final AsyncValue<List<NoteMetadata>> results;
  final int selectedIndex;
  final ValueChanged<NoteMetadata> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _NavigationFailure(error: error),
      data: (hits) {
        if (query.isEmpty) {
          return _NavigationEmpty(l10n.noteNavigationTypePrompt);
        }
        if (hits.isEmpty) return _NavigationEmpty(l10n.noteNavigationNoMatches);
        return Column(
          children: [
            for (var index = 0; index < hits.length; index++)
              _NavigationResultRow(
                note: hits[index],
                selected: index == selectedIndex,
                onSelect: () => onSelect(hits[index]),
              ),
          ],
        );
      },
    );
  }
}

class _BacklinkResults extends StatelessWidget {
  const _BacklinkResults({
    required this.results,
    required this.selectedIndex,
    required this.onSelect,
  });

  final AsyncValue<List<NoteMetadata>> results;
  final int? selectedIndex;
  final ValueChanged<NoteMetadata> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return results.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _NavigationFailure(error: error),
      data: (notes) => notes.isEmpty
          ? _NavigationEmpty(l10n.noteNavigationNoBacklinks)
          : Column(
              children: [
                for (var index = 0; index < notes.length; index++)
                  _NavigationResultRow(
                    key: ValueKey(
                      'note-navigation-backlink-${notes[index].id}',
                    ),
                    note: notes[index],
                    selected: index == selectedIndex,
                    onSelect: () => onSelect(notes[index]),
                  ),
              ],
            ),
    );
  }
}

class _NavigationResultRow extends StatelessWidget {
  const _NavigationResultRow({
    super.key,
    required this.note,
    this.selected = false,
    required this.onSelect,
  });

  final NoteMetadata note;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.burlColors;
    return FocusableActionDetector(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            onSelect();
            return null;
          },
        ),
      },
      child: ListTile(
        selected: selected,
        selectedTileColor: colors.surface,
        dense: true,
        title: Text(note.title, overflow: TextOverflow.ellipsis),
        subtitle: Text(note.path, overflow: TextOverflow.ellipsis),
        onTap: onSelect,
      ),
    );
  }
}

class _NavigationEmpty extends StatelessWidget {
  const _NavigationEmpty(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: TextStyle(color: context.burlColors.textMuted, fontSize: 12),
    ),
  );
}

class _NavigationFailure extends StatelessWidget {
  const _NavigationFailure({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final colors = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            l10n.noteNavigationFailed,
            style: TextStyle(color: colors.syncError, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            '$error',
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
