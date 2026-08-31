import 'dart:async';
import 'dart:math' as math;

import 'package:burlmd/src/components/draft_recovery.dart';
import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/components/search_panel.dart';
import 'package:burlmd/src/components/visual_parity_fixture.dart';
import 'package:burlmd/src/components/workspace_tree.dart';
import 'package:burlmd/src/design/burl_theme.dart';
import 'package:burlmd/src/design/burl_motion.dart';
import 'package:burlmd/src/providers/burl_preferences_provider.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:burlmd/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart' show kMiddleMouseButton;
import 'package:flutter_lucide/flutter_lucide.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart'
    show
        Clipboard,
        ClipboardData,
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        LogicalKeyboardKey;

class _ShellIntent extends Intent {
  const _ShellIntent(this.command);
  final _ShellCommand command;
}

class _TabContextMenuIntent extends Intent {
  const _TabContextMenuIntent();
}

enum _ShellCommand { search, history, preferences, closeTab, dismiss }

const _visualFixture = bool.fromEnvironment('BURLMD_VISUAL_FIXTURE');

/// Desktop workspace chrome. It intentionally hosts the existing navigation
/// and editor widgets rather than duplicating their provider-sensitive logic.
class BurlWorkspaceShell extends ConsumerStatefulWidget {
  const BurlWorkspaceShell({
    super.key,
    required this.workspaceName,
    this.workspacePath,
    required this.rescanButton,
    required this.onRescan,
    this.fixtureCaptureController,
  });

  final String workspaceName;
  final String? workspacePath;
  final Widget rescanButton;
  final VoidCallback onRescan;
  final FixtureCaptureController? fixtureCaptureController;

  @override
  ConsumerState<BurlWorkspaceShell> createState() => _BurlWorkspaceShellState();
}

class _BurlWorkspaceShellState extends ConsumerState<BurlWorkspaceShell> {
  bool _navigatorOpen = false;
  bool _searchOpen = false;
  bool _preferencesOpen = false;
  bool _syncOpen = false;
  bool _historyOpen = false;
  bool _sidebarCollapsed = false;
  var _tabCloseRequest = 0;

  @override
  void initState() {
    super.initState();
    // A raw [EditableText] owns primary focus while a block is promoted.
    // FocusManager's early stage is the Flutter 3.44.3 boundary before that
    // field's text shortcuts, so shell commands cannot be swallowed by the
    // editor. The handler is registered per mounted shell and removed in
    // dispose to keep independent windows/tests isolated.
    FocusManager.instance.addEarlyKeyEventHandler(_handleEarlyKeyEvent);
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleEarlyKeyEvent);
    super.dispose();
  }

  KeyEventResult _handleEarlyKeyEvent(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final usesMetaPrimary = defaultTargetPlatform == TargetPlatform.macOS;
    final primaryPressed = usesMetaPrimary
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    final otherPrimaryPressed = usesMetaPrimary
        ? keyboard.isControlPressed
        : keyboard.isMetaPressed;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      final hasOverlay =
          _navigatorOpen ||
          _searchOpen ||
          _preferencesOpen ||
          _syncOpen ||
          _historyOpen;
      if (!hasOverlay) return KeyEventResult.ignored;
      _dismissTop();
      return KeyEventResult.handled;
    }
    // Plain typing, alternate-layout input, repeats, and competing platform
    // modifiers remain entirely with the focused control/IME.
    if (!primaryPressed || otherPrimaryPressed || keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final command = switch (event.logicalKey) {
      LogicalKeyboardKey.keyK => _ShellCommand.search,
      LogicalKeyboardKey.keyH => _ShellCommand.history,
      LogicalKeyboardKey.comma => _ShellCommand.preferences,
      LogicalKeyboardKey.keyW => _ShellCommand.closeTab,
      _ => null,
    };
    if (command == null) return KeyEventResult.ignored;
    _perform(command);
    return KeyEventResult.handled;
  }

  void _dismissTop() {
    setState(() {
      if (_searchOpen) {
        _searchOpen = false;
      } else if (_preferencesOpen) {
        _preferencesOpen = false;
      } else if (_syncOpen) {
        _syncOpen = false;
      } else if (_historyOpen) {
        _historyOpen = false;
      } else if (_navigatorOpen) {
        _navigatorOpen = false;
      }
    });
  }

  void _perform(_ShellCommand command) {
    switch (command) {
      case _ShellCommand.search:
        setState(() => _searchOpen = true);
      case _ShellCommand.history:
        setState(() => _historyOpen = true);
      case _ShellCommand.preferences:
        setState(() => _preferencesOpen = true);
      case _ShellCommand.closeTab:
        setState(() => _tabCloseRequest++);
      case _ShellCommand.dismiss:
        _dismissTop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_visualFixture) {
      return FixtureReferenceShell(
        captureController: widget.fixtureCaptureController,
      );
    }
    final colors = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.keyK, control: true): _ShellIntent(
          _ShellCommand.search,
        ),
        SingleActivator(LogicalKeyboardKey.keyK, meta: true): _ShellIntent(
          _ShellCommand.search,
        ),
        SingleActivator(LogicalKeyboardKey.keyH, control: true): _ShellIntent(
          _ShellCommand.history,
        ),
        SingleActivator(LogicalKeyboardKey.keyH, meta: true): _ShellIntent(
          _ShellCommand.history,
        ),
        SingleActivator(LogicalKeyboardKey.comma, control: true): _ShellIntent(
          _ShellCommand.preferences,
        ),
        SingleActivator(LogicalKeyboardKey.comma, meta: true): _ShellIntent(
          _ShellCommand.preferences,
        ),
        SingleActivator(LogicalKeyboardKey.keyW, control: true): _ShellIntent(
          _ShellCommand.closeTab,
        ),
        SingleActivator(LogicalKeyboardKey.keyW, meta: true): _ShellIntent(
          _ShellCommand.closeTab,
        ),
        SingleActivator(LogicalKeyboardKey.escape): _ShellIntent(
          _ShellCommand.dismiss,
        ),
      },
      child: Actions(
        actions: {
          _ShellIntent: CallbackAction<_ShellIntent>(
            onInvoke: (intent) {
              _perform(intent.command);
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _dismissTop();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final tier = constraints.maxWidth >= 1040
                  ? _ShellTier.wide
                  : constraints.maxWidth >= 720
                  ? _ShellTier.rail
                  : _ShellTier.compact;
              return ColoredBox(
                key: const ValueKey('shell-root'),
                color: colors.app,
                child: Stack(
                  children: [
                    Row(
                      children: [
                        if (tier == _ShellTier.wide && !_sidebarCollapsed)
                          SizedBox(
                            width: 288,
                            child: _NavigatorPane(
                              workspaceName: widget.workspaceName,
                              onSearch: () =>
                                  setState(() => _searchOpen = true),
                              onPreferences: () =>
                                  setState(() => _preferencesOpen = true),
                              onSync: () => setState(() => _syncOpen = true),
                              rescanButton: widget.rescanButton,
                              onNoteSelected: () {},
                            ),
                          ),
                        if (tier == _ShellTier.rail ||
                            (tier == _ShellTier.wide && _sidebarCollapsed))
                          _Rail(
                            openKey: tier == _ShellTier.wide
                                ? const ValueKey('shell-sidebar-expand')
                                : const Key('shell-open-navigator'),
                            onOpen: () => setState(
                              () => tier == _ShellTier.wide
                                  ? _sidebarCollapsed = false
                                  : _navigatorOpen = true,
                            ),
                            onSearch: () => setState(() => _searchOpen = true),
                            onPreferences: () =>
                                setState(() => _preferencesOpen = true),
                          ),
                        Expanded(
                          child: _EditorPane(
                            compact: tier == _ShellTier.compact,
                            onOpenNavigator: () =>
                                setState(() => _navigatorOpen = true),
                            onHistory: () =>
                                setState(() => _historyOpen = true),
                            closeRequest: _tabCloseRequest,
                          ),
                        ),
                      ],
                    ),
                    if (tier == _ShellTier.wide && !_sidebarCollapsed)
                      Positioned(
                        top: 12,
                        left: 258,
                        child: IconButton(
                          key: const ValueKey('shell-sidebar-collapse'),
                          tooltip: l10n.workspaceCollapseSidebar,
                          onPressed: () =>
                              setState(() => _sidebarCollapsed = true),
                          icon: const Icon(
                            LucideIcons.panel_left_close,
                            size: 15,
                          ),
                        ),
                      ),
                    if (_navigatorOpen && tier != _ShellTier.wide)
                      _NavigatorOverlay(
                        workspaceName: widget.workspaceName,
                        onClose: () => setState(() => _navigatorOpen = false),
                        onSearch: () => setState(() => _searchOpen = true),
                        onPreferences: () =>
                            setState(() => _preferencesOpen = true),
                        onSync: () => setState(() => _syncOpen = true),
                        rescanButton: widget.rescanButton,
                      ),
                    if (_searchOpen)
                      _SearchPalette(
                        onClose: () => setState(() => _searchOpen = false),
                      ),
                    if (_preferencesOpen)
                      _PreferencesDrawer(
                        onClose: () => setState(() => _preferencesOpen = false),
                      ),
                    if (_syncOpen)
                      _SyncInspector(
                        onClose: () => setState(() => _syncOpen = false),
                        onRescan: widget.onRescan,
                        workspacePath: widget.workspacePath,
                      ),
                    if (_historyOpen)
                      _HistoryDrawer(
                        onClose: () => setState(() => _historyOpen = false),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

enum _ShellTier { wide, rail, compact }

class _NavigatorPane extends StatelessWidget {
  const _NavigatorPane({
    required this.workspaceName,
    required this.onSearch,
    required this.onPreferences,
    required this.onSync,
    required this.rescanButton,
    required this.onNoteSelected,
  });
  final String workspaceName;
  final VoidCallback onSearch, onPreferences, onSync, onNoteSelected;
  final Widget rescanButton;
  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.borderSubtle)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      workspaceName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(width: 128, child: rescanButton),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: _QuietButton(
              key: const Key('shell-search'),
              icon: LucideIcons.search,
              label: l10n.workspaceSearchNotes,
              tooltip: l10n.workspaceSearchNotesTooltip,
              trailing: _searchShortcutLabel(l10n),
              onPressed: onSearch,
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: WorkspaceTree(onNoteSelected: (_) => onNoteSelected()),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                _QuietButton(
                  key: const Key('shell-sync'),
                  icon: LucideIcons.git_pull_request,
                  label: l10n.workspaceLocalWorkspace,
                  tooltip: l10n.workspaceLocalWorkspace,
                  onPressed: onSync,
                  tint: c.accent,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    TextButton.icon(
                      key: const ValueKey('shell-preferences'),
                      onPressed: onPreferences,
                      icon: const Icon(LucideIcons.settings, size: 15),
                      label: Text(l10n.workspacePreferences),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l10n.workspacePreferences,
                      onPressed: onPreferences,
                      icon: const Icon(LucideIcons.sun, size: 15),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.onOpen,
    required this.onSearch,
    required this.onPreferences,
    this.openKey = const Key('shell-open-navigator'),
  });
  final VoidCallback onOpen, onSearch, onPreferences;
  final Key openKey;
  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.sidebar,
        border: Border(right: BorderSide(color: c.borderSubtle)),
      ),
      child: SizedBox(
        width: 48,
        child: Column(
          children: [
            const SizedBox(height: 8),
            IconButton(
              key: openKey,
              tooltip: l10n.workspaceOpenNavigator,
              onPressed: onOpen,
              icon: const Icon(LucideIcons.panel_left, size: 18),
            ),
            IconButton(
              key: const ValueKey('shell-rail-search'),
              tooltip: l10n.workspaceSearchNotesTooltip,
              onPressed: onSearch,
              icon: const Icon(LucideIcons.search, size: 18),
            ),
            const Spacer(),
            IconButton(
              key: const ValueKey('shell-rail-preferences'),
              tooltip: l10n.workspacePreferences,
              onPressed: onPreferences,
              icon: const Icon(LucideIcons.settings, size: 18),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _NavigatorOverlay extends StatelessWidget {
  const _NavigatorOverlay({
    required this.workspaceName,
    required this.onClose,
    required this.onSearch,
    required this.onPreferences,
    required this.onSync,
    required this.rescanButton,
  });
  final String workspaceName;
  final VoidCallback onClose, onSearch, onPreferences, onSync;
  final Widget rescanButton;
  @override
  Widget build(BuildContext context) => _ShellModalOverlay(
    key: const ValueKey('shell-navigator-overlay'),
    onClose: onClose,
    barrierDuration: BurlMotion.drawer,
    child: Align(
      alignment: Alignment.centerLeft,
      child: BurlScaleFadeEntrance(
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            key: const ValueKey('navigator-pane'),
            width: 320,
            child: _NavigatorPane(
              workspaceName: workspaceName,
              onSearch: () {
                onClose();
                onSearch();
              },
              onPreferences: onPreferences,
              onSync: onSync,
              rescanButton: rescanButton,
              onNoteSelected: onClose,
            ),
          ),
        ),
      ),
    ),
  );
}

class _EditorPane extends ConsumerStatefulWidget {
  const _EditorPane({
    required this.compact,
    required this.onOpenNavigator,
    required this.onHistory,
    required this.closeRequest,
  });
  final bool compact;
  final VoidCallback onOpenNavigator, onHistory;
  final int closeRequest;
  @override
  ConsumerState<_EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends ConsumerState<_EditorPane> {
  late final List<_VisualTab> _tabs;
  var _tabsInitialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabsInitialized) return;
    _tabsInitialized = true;
    _tabs = [
      _VisualTab.visual(
        AppLocalizations.of(context)!.workspaceWelcomeTab,
        id: 'visual-welcome',
      ),
    ];
  }

  void _syncActiveTab(NoteState? active) {
    if (active == null) return;
    _tabs.removeWhere((tab) => tab.id == 'visual-welcome');
    final id = active.metadata.id;
    final index = _tabs.indexWhere((tab) => tab.id == id);
    final tab = _VisualTab.note(
      id,
      _filename(active.metadata.path),
      recovered: active.restoredFromDraft,
    );
    if (index == -1) {
      _tabs.add(tab);
    } else {
      _tabs[index] = tab;
    }
  }

  void _addVisualTab() => setState(() {
    _tabs.add(
      _VisualTab.visual(
        AppLocalizations.of(context)!.workspaceUntitledTab(_tabs.length),
      ),
    );
  });

  // A visual close may remove an inactive/local tab. Closing the active Note
  // is intentionally deferred: it must eventually use the lifecycle-aware
  // provider path (including Core close/flush), rather than silently clearing
  // UI state here. Until that surface exists, the active provider state
  // repopulates its tab on rebuild.
  void _closeVisualTab(_VisualTab tab) => setState(() => _tabs.remove(tab));

  void _closeOtherVisualTabs(_VisualTab tab) => setState(
    () => _tabs.removeWhere(
      (candidate) => candidate != tab && candidate.noteId == null,
    ),
  );

  void _closeAllVisualTabs() =>
      setState(() => _tabs.removeWhere((tab) => tab.noteId == null));

  @override
  void didUpdateWidget(covariant _EditorPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.closeRequest == oldWidget.closeRequest) return;
    final active = ref.read(activeNoteProvider);
    final tab = _tabs
        .where((tab) => tab.noteId == active?.metadata.id)
        .firstOrNull;
    if (tab != null) _closeVisualTab(tab);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    ref.listen<String?>(selectedNoteIdProvider, (_, next) {
      if (next != null) ref.read(activeNoteProvider.notifier).open(next);
    });
    final selected = ref.watch(selectedNoteIdProvider);
    final active = ref.watch(activeNoteProvider);
    _syncActiveTab(active);
    return DecoratedBox(
      decoration: BoxDecoration(color: c.editor),
      child: Column(
        children: [
          _VisualTabStrip(
            compact: widget.compact,
            tabs: _tabs,
            activeId: active?.metadata.id,
            onOpenNavigator: widget.onOpenNavigator,
            onSelect: (tab) {
              if (tab.noteId case final noteId?) {
                ref.read(selectedNoteIdProvider.notifier).select(noteId);
              }
            },
            onClose: _closeVisualTab,
            onCloseOthers: _closeOtherVisualTabs,
            onCloseAll: _closeAllVisualTabs,
            onAdd: _addVisualTab,
          ),
          _MetadataHeader(
            compact: widget.compact,
            onHistory: widget.onHistory,
            note: active,
          ),
          const RecoveredDraftsPanel(),
          if (selected == null)
            const Expanded(child: _EmptyEditor())
          else
            const Expanded(
              child: Column(
                children: [
                  WriteTierNotice(),
                  Expanded(child: Editor()),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _VisualTab {
  const _VisualTab._({
    required this.id,
    required this.label,
    this.noteId,
    this.recovered = false,
  });

  factory _VisualTab.note(
    String noteId,
    String label, {
    bool recovered = false,
  }) => _VisualTab._(
    id: noteId,
    label: label,
    noteId: noteId,
    recovered: recovered,
  );

  factory _VisualTab.visual(String label, {String? id}) =>
      _VisualTab._(id: id ?? 'visual-$label', label: label);

  final String id;
  final String label;
  final String? noteId;
  final bool recovered;
}

class _VisualTabStrip extends StatelessWidget {
  const _VisualTabStrip({
    required this.compact,
    required this.tabs,
    required this.activeId,
    required this.onOpenNavigator,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseAll,
    required this.onAdd,
  });

  final bool compact;
  final List<_VisualTab> tabs;
  final String? activeId;
  final VoidCallback onOpenNavigator;
  final ValueChanged<_VisualTab> onSelect;
  final ValueChanged<_VisualTab> onClose;
  final ValueChanged<_VisualTab> onCloseOthers;
  final VoidCallback onCloseAll;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      key: const Key('shell-tab-strip'),
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.app,
          border: Border(bottom: BorderSide(color: c.borderSubtle)),
        ),
        child: Row(
          children: [
            if (compact)
              IconButton(
                key: const Key('shell-open-navigator'),
                tooltip: l10n.workspaceOpenNavigator,
                constraints: const BoxConstraints.tightFor(
                  width: 36,
                  height: 36,
                ),
                padding: EdgeInsets.zero,
                iconSize: 16,
                onPressed: onOpenNavigator,
                icon: const Icon(LucideIcons.menu),
              ),
            Expanded(
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 4),
                itemCount: tabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 3),
                itemBuilder: (context, index) {
                  final tab = tabs[index];
                  final active = tab.noteId == activeId;
                  return _WorkspaceTab(
                    tab: tab,
                    active: active,
                    onSelect: () => onSelect(tab),
                    onClose: () => onClose(tab),
                    onCloseOthers: () => onCloseOthers(tab),
                    onCloseAll: onCloseAll,
                  );
                },
              ),
            ),
            IconButton(
              key: const Key('shell-add-tab'),
              tooltip: l10n.workspaceAddVisualTab,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              padding: EdgeInsets.zero,
              iconSize: 16,
              onPressed: onAdd,
              icon: const Icon(LucideIcons.plus),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceTab extends StatefulWidget {
  const _WorkspaceTab({
    required this.tab,
    required this.active,
    required this.onSelect,
    required this.onClose,
    required this.onCloseOthers,
    required this.onCloseAll,
  });

  final _VisualTab tab;
  final bool active;
  final VoidCallback onSelect, onClose, onCloseOthers, onCloseAll;

  @override
  State<_WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<_WorkspaceTab> {
  var _hovered = false;
  final _focusNode = FocusNode(debugLabel: 'workspace tab');

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Offset _keyboardMenuPosition() {
    final box = context.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset(0, box.size.height));
  }

  Future<void> _showMenuAt(Offset globalPosition) async {
    final l10n = AppLocalizations.of(context)!;
    final result = await showMenu<_TabMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        0,
        0,
      ),
      items: [
        PopupMenuItem(
          key: ValueKey('tab-menu-close'),
          value: _TabMenuAction.close,
          child: Text(l10n.workspaceCloseTab),
        ),
        PopupMenuItem(
          key: ValueKey('tab-menu-close-others'),
          value: _TabMenuAction.closeOthers,
          child: Text(l10n.workspaceCloseOtherTabs),
        ),
        PopupMenuItem(
          key: ValueKey('tab-menu-close-all'),
          value: _TabMenuAction.closeAll,
          child: Text(l10n.workspaceCloseAllVisualTabs),
        ),
      ],
    );
    switch (result) {
      case _TabMenuAction.close:
        widget.onClose();
      case _TabMenuAction.closeOthers:
        widget.onCloseOthers();
      case _TabMenuAction.closeAll:
        widget.onCloseAll();
      case null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return FocusableActionDetector(
      focusNode: _focusNode,
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.contextMenu):
            _TabContextMenuIntent(),
        SingleActivator(LogicalKeyboardKey.f10, shift: true):
            _TabContextMenuIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: {
        _TabContextMenuIntent: CallbackAction<_TabContextMenuIntent>(
          onInvoke: (_) {
            unawaited(_showMenuAt(_keyboardMenuPosition()));
            return null;
          },
        ),
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onSelect();
            return null;
          },
        ),
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Semantics(
          selected: widget.active,
          button: true,
          label: l10n.workspaceTabLabel(widget.tab.label),
          child: Listener(
            onPointerDown: (event) {
              if (event.buttons == kMiddleMouseButton) widget.onClose();
            },
            child: GestureDetector(
              onSecondaryTapDown: (details) {
                _focusNode.requestFocus();
                unawaited(_showMenuAt(details.globalPosition));
              },
              child: SizedBox(
                width: 224,
                child: AnimatedContainer(
                  duration: BurlMotion.duration(context, BurlMotion.chrome),
                  curve: BurlMotion.enterCurve,
                  decoration: BoxDecoration(
                    color: widget.active ? c.surfaceRaised : c.sidebar,
                    border: Border(
                      top: BorderSide(
                        color: widget.active ? c.accent : Colors.transparent,
                        width: 2,
                      ),
                      left: BorderSide(color: c.borderSubtle),
                      right: BorderSide(color: c.borderSubtle),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          key: Key('shell-tab-${widget.tab.id}'),
                          canRequestFocus: false,
                          hoverDuration: BurlMotion.duration(
                            context,
                            BurlMotion.chrome,
                          ),
                          onTap: () {
                            _focusNode.requestFocus();
                            widget.onSelect();
                          },
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 2),
                            child: Row(
                              children: [
                                Icon(
                                  LucideIcons.file_text,
                                  size: 13,
                                  color: widget.active ? c.accent : c.textMuted,
                                ),
                                if (widget.tab.recovered) ...[
                                  const SizedBox(width: 5),
                                  Container(
                                    key: ValueKey(
                                      'shell-tab-status-${widget.tab.id}',
                                    ),
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: c.review,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    widget.tab.label,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 10,
                                      fontWeight: widget.active
                                          ? FontWeight.w600
                                          : null,
                                      color: widget.active
                                          ? c.textPrimary
                                          : c.textSecondary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        ignoring: !(_hovered || widget.active),
                        child: AnimatedOpacity(
                          opacity: _hovered
                              ? 1
                              : widget.active
                              ? .8
                              : 0,
                          duration: BurlMotion.duration(
                            context,
                            BurlMotion.chrome,
                          ),
                          child: IconButton(
                            key: ValueKey('shell-tab-close-${widget.tab.id}'),
                            tooltip: l10n.workspaceCloseNamedTab(
                              widget.tab.label,
                            ),
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 34,
                            ),
                            padding: EdgeInsets.zero,
                            iconSize: 13,
                            onPressed: widget.onClose,
                            icon: const Icon(LucideIcons.x),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _TabMenuAction { close, closeOthers, closeAll }

class _MetadataHeader extends StatefulWidget {
  const _MetadataHeader({
    required this.compact,
    required this.onHistory,
    required this.note,
  });
  final bool compact;
  final VoidCallback onHistory;
  final NoteState? note;

  @override
  State<_MetadataHeader> createState() => _MetadataHeaderState();
}

class _MetadataHeaderState extends State<_MetadataHeader> {
  bool _copied = false;
  Timer? _copyReset;

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (!mounted) return;
    _copyReset?.cancel();
    setState(() => _copied = true);
    _copyReset = Timer(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  void dispose() {
    _copyReset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    final metadata = widget.note?.metadata;
    final path = metadata?.path ?? l10n.workspaceDefaultPath;
    final filename = _filename(path);
    final breadcrumb = _breadcrumb(path, l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showBreadcrumb = !widget.compact && constraints.maxWidth >= 680;
        final showSummary = !widget.compact && constraints.maxWidth >= 520;
        return Container(
          height: 45,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: c.surfaceRaised.withValues(alpha: .96),
            border: Border(bottom: BorderSide(color: c.borderSubtle)),
          ),
          child: Row(
            children: [
              if (showBreadcrumb)
                Expanded(
                  child: Text(
                    breadcrumb,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: c.textSecondary,
                    ),
                  ),
                )
              else
                const Icon(LucideIcons.folder, size: 14),
              if (!showBreadcrumb) const SizedBox(width: 7),
              Flexible(
                child: _FilenameChip(
                  filename: filename,
                  active: metadata != null,
                ),
              ),
              IconButton(
                key: const Key('shell-copy-path'),
                tooltip: _copied
                    ? l10n.workspaceCopiedPath
                    : l10n.workspaceCopyPath,
                constraints: const BoxConstraints.tightFor(
                  width: 32,
                  height: 32,
                ),
                padding: EdgeInsets.zero,
                iconSize: 14,
                onPressed: () => _copyPath(path),
                icon: Icon(_copied ? LucideIcons.check : LucideIcons.copy),
              ),
              if (showSummary)
                Flexible(
                  child: Text(
                    _noteSummary(widget.note, l10n),
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: c.textMuted),
                  ),
                ),
              if (showSummary) const SizedBox(width: 8),
              if (constraints.maxWidth >= 470)
                OutlinedButton.icon(
                  key: const Key('shell-history'),
                  onPressed: widget.onHistory,
                  icon: const Icon(LucideIcons.rotate_ccw_clock, size: 14),
                  label: Text(l10n.workspaceHistory),
                )
              else
                IconButton(
                  key: const Key('shell-history'),
                  tooltip: l10n.workspaceHistory,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  padding: EdgeInsets.zero,
                  iconSize: 15,
                  onPressed: widget.onHistory,
                  icon: const Icon(LucideIcons.rotate_ccw_clock),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _FilenameChip extends StatelessWidget {
  const _FilenameChip({required this.filename, required this.active});

  final String filename;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return Container(
      key: const Key('shell-filename-chip'),
      constraints: const BoxConstraints(maxWidth: 220),
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: active ? c.accentSubtle : c.surface,
        border: Border.all(color: active ? c.accentBorder : c.borderSubtle),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        filename,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: active ? c.textPrimary : c.textSecondary,
        ),
      ),
    );
  }
}

String _filename(String path) => path.split('/').last;

String _searchShortcutLabel(AppLocalizations l10n) =>
    defaultTargetPlatform == TargetPlatform.macOS
    ? l10n.workspaceSearchShortcutMacos
    : l10n.workspaceSearchShortcutControl;

String _breadcrumb(String path, AppLocalizations l10n) {
  final parts = path.split('/');
  return parts.length > 1
      ? parts.join('  ›  ')
      : l10n.workspaceBreadcrumb(path);
}

String _modifiedLabel(Object? timestamp, AppLocalizations l10n) {
  if (timestamp is! int || timestamp <= 0) {
    return l10n.workspaceModifiedRecently;
  }
  final elapsed = DateTime.now().difference(
    DateTime.fromMillisecondsSinceEpoch(timestamp * 1000),
  );
  return switch (elapsed.inMinutes) {
    < 2 => l10n.workspaceModifiedJustNow,
    < 60 => l10n.workspaceModifiedMinutesAgo(elapsed.inMinutes),
    < 1440 => l10n.workspaceModifiedHoursAgo(elapsed.inHours),
    _ => l10n.workspaceModifiedDaysAgo(elapsed.inDays),
  };
}

String _noteSummary(NoteState? note, AppLocalizations l10n) {
  final modified = _modifiedLabel(note?.metadata.lastModified, l10n);
  if (note == null) return modified;
  final words = _wordCount(note.ast);
  if (words == 0) return modified;
  return l10n.workspaceNoteSummary(
    modified,
    words,
    words == 1 ? l10n.workspaceWordSingular : l10n.workspaceWordPlural,
  );
}

int _wordCount(Iterable<AstNode> nodes) =>
    nodes.fold(0, (total, node) => total + _nodeWordCount(node));

int _nodeWordCount(AstNode node) => switch (node) {
  AstNode_Heading(content: final content) ||
  AstNode_Paragraph(content: final content) => _inlineWordCount(content),
  AstNode_List(items: final items) ||
  AstNode_ListItem(content: final items) ||
  AstNode_Blockquote(nodes: final items) => _wordCount(items),
  AstNode_CodeBlock(code: final code) => _wordsIn(code),
  AstNode_Image(altText: final altText) => _wordsIn(altText),
  AstNode_Suggestion(
    localContent: final local,
    incomingContent: final incoming,
  ) =>
    _wordCount(local) + _wordCount(incoming),
  AstNode_ThematicBreak() => 0,
};

int _inlineWordCount(Iterable<InlineElement> elements) => elements.fold(
  0,
  (total, element) =>
      total +
      switch (element) {
        InlineElement_Text(field0: final text) => _wordsIn(text.content),
        InlineElement_Link(content: final content) ||
        InlineElement_ExternalLink(
          content: final content,
        ) => _inlineWordCount(content),
      },
);

int _wordsIn(String text) =>
    text.trim().isEmpty ? 0 : text.trim().split(RegExp(r'\s+')).length;

class _EmptyEditor extends StatelessWidget {
  const _EmptyEditor();
  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.borderStrong),
            ),
            child: Icon(LucideIcons.folder, size: 23, color: c.textMuted),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.workspaceSelectNoteTitle,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.workspaceSelectNoteBody,
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _QuietButton extends StatelessWidget {
  const _QuietButton({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    this.trailing,
    required this.onPressed,
    this.tint,
  });
  final IconData icon;
  final String label, tooltip;
  final String? trailing;
  final VoidCallback onPressed;
  final Color? tint;
  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            animationDuration: BurlMotion.duration(context, BurlMotion.chrome),
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            side: BorderSide(color: c.borderSubtle),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: tint ?? c.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label, style: const TextStyle(fontSize: 12)),
              ),
              if (trailing case final trailingText?)
                Text(
                  trailingText,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: c.textMuted,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchPalette extends StatelessWidget {
  const _SearchPalette({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return _ShellModalOverlay(
      key: const ValueKey('shell-search-overlay'),
      onClose: onClose,
      barrierColor: const Color(0x88000000),
      child: Align(
        alignment: const Alignment(0, -.68),
        child: BurlScaleFadeEntrance(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 672),
            child: Container(
              key: const Key('search-palette'),
              margin: const EdgeInsets.all(16),
              height: 480,
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.borderStrong),
                boxShadow: const [
                  BoxShadow(color: Color(0x55000000), blurRadius: 28),
                ],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: SearchPanel(
                      resultLimit: 25,
                      onResultSelected: onClose,
                      onDismiss: onClose,
                    ),
                  ),
                  Positioned(
                    top: 3,
                    right: 3,
                    child: IconButton(
                      key: const ValueKey('search-close'),
                      tooltip: l10n.workspaceCloseSearch,
                      onPressed: onClose,
                      icon: const Icon(LucideIcons.x, size: 15),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PreferencesDrawer extends ConsumerWidget {
  const _PreferencesDrawer({required this.onClose});
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(burlPreferencesProvider);
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    Widget section(String label, Widget child) => Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              color: c.textMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
    Widget options<T extends Enum>(
      String keyPrefix,
      Iterable<T> values,
      T selected,
      String Function(T) label,
      void Function(T) set,
    ) => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.borderSubtle),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final value in values)
            OutlinedButton(
              key: ValueKey('preferences-$keyPrefix-${value.name}'),
              style: OutlinedButton.styleFrom(
                animationDuration: BurlMotion.duration(
                  context,
                  BurlMotion.chrome,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                backgroundColor: value == selected ? c.active : c.surface,
                foregroundColor: value == selected ? c.app : c.textPrimary,
                side: BorderSide(
                  color: value == selected ? c.active : c.borderSubtle,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              onPressed: () => set(value),
              child: Text(label(value), style: const TextStyle(fontSize: 11)),
            ),
        ],
      ),
    );
    return _ShellModalOverlay(
      key: const ValueKey('preferences-overlay'),
      onClose: onClose,
      barrierDuration: BurlMotion.drawer,
      child: Align(
        alignment: Alignment.centerRight,
        child: BurlScaleFadeEntrance(
          child: Material(
            key: const ValueKey('preferences-drawer'),
            color: c.surfaceRaised,
            child: SizedBox(
              width: math.min(448, MediaQuery.sizeOf(context).width),
              child: SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          const Icon(LucideIcons.settings, size: 17),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.workspaceEditorPreferences,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const ValueKey('preferences-close'),
                            tooltip: l10n.workspacePreferences,
                            onPressed: onClose,
                            icon: const Icon(LucideIcons.x, size: 17),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: c.borderSubtle),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          section(
                            l10n.workspaceAppearanceTheme,
                            options(
                              'theme',
                              BurlThemePreference.values,
                              p.theme,
                              (v) => _themePreferenceLabel(v, l10n),
                              ref
                                  .read(burlPreferencesProvider.notifier)
                                  .setTheme,
                            ),
                          ),
                          section(
                            l10n.workspaceBaseReadingSize,
                            options(
                              'font-scale',
                              BurlFontScale.values,
                              p.fontScale,
                              (v) => _fontScaleLabel(v, l10n),
                              ref
                                  .read(burlPreferencesProvider.notifier)
                                  .setFontScale,
                            ),
                          ),
                          section(
                            l10n.workspaceProseLineMeasure,
                            options(
                              'measure',
                              BurlMeasure.values,
                              p.measure,
                              (v) => _measureLabel(v, l10n),
                              ref
                                  .read(burlPreferencesProvider.notifier)
                                  .setMeasure,
                            ),
                          ),
                          SwitchListTile(
                            key: const ValueKey('preferences-focus-mode'),
                            contentPadding: EdgeInsets.zero,
                            value: p.focusMode,
                            onChanged: ref
                                .read(burlPreferencesProvider.notifier)
                                .setFocusMode,
                            title: Text(l10n.workspaceFocusMode),
                            subtitle: Text(l10n.workspaceFocusModeDescription),
                          ),
                          SwitchListTile(
                            key: const ValueKey(
                              'preferences-update-notifications',
                            ),
                            contentPadding: EdgeInsets.zero,
                            value: p.updateNotifications,
                            onChanged: ref
                                .read(burlPreferencesProvider.notifier)
                                .setUpdateNotifications,
                            title: Text(l10n.workspaceUpdateNotifications),
                            subtitle: Text(
                              l10n.workspaceUpdateNotificationsDescription,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton(
                          key: const ValueKey('preferences-done'),
                          onPressed: onClose,
                          child: Text(l10n.workspaceDone),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _themePreferenceLabel(
  BurlThemePreference preference,
  AppLocalizations l10n,
) => switch (preference) {
  BurlThemePreference.system => l10n.themePreferenceSystem,
  BurlThemePreference.light => l10n.themePreferenceLight,
  BurlThemePreference.dark => l10n.themePreferenceDark,
};

String _fontScaleLabel(BurlFontScale scale, AppLocalizations l10n) =>
    switch (scale) {
      BurlFontScale.compact => l10n.fontScaleCompact,
      BurlFontScale.standard => l10n.fontScaleStandard,
      BurlFontScale.comfortable => l10n.fontScaleComfortable,
      BurlFontScale.spacious => l10n.fontScaleLarge,
    };

String _measureLabel(BurlMeasure measure, AppLocalizations l10n) =>
    switch (measure) {
      BurlMeasure.narrow => l10n.measureNarrow,
      BurlMeasure.standard => l10n.measureStandard,
      BurlMeasure.wide => l10n.measureWide,
      BurlMeasure.technical => l10n.measureTechnical,
      BurlMeasure.full => l10n.measureFull,
    };

enum _SyncVisualState {
  connectedIdle,
  pendingSuggestions,
  syncing,
  localOnly,
  offline,
  authRequired,
  syncError,
  externalChanged,
}

extension on _SyncVisualState {
  String label(AppLocalizations l10n) => switch (this) {
    _SyncVisualState.connectedIdle => l10n.syncStateInSync,
    _SyncVisualState.pendingSuggestions => l10n.syncStatePendingSuggestion,
    _SyncVisualState.syncing => l10n.syncStateSyncing,
    _SyncVisualState.localOnly => l10n.syncStateLocalOnly,
    _SyncVisualState.offline => l10n.syncStateOffline,
    _SyncVisualState.authRequired => l10n.syncStateAuthRequired,
    _SyncVisualState.syncError => l10n.syncStateUnreachable,
    _SyncVisualState.externalChanged => l10n.syncStateExternalChanges,
  };

  String description(AppLocalizations l10n) => switch (this) {
    _SyncVisualState.connectedIdle => l10n.syncDescriptionInSync,
    _SyncVisualState.pendingSuggestions =>
      l10n.syncDescriptionPendingSuggestion,
    _SyncVisualState.syncing => l10n.syncDescriptionSyncing,
    _SyncVisualState.localOnly => l10n.syncDescriptionLocalOnly,
    _SyncVisualState.offline => l10n.syncDescriptionOffline,
    _SyncVisualState.authRequired => l10n.syncDescriptionAuthRequired,
    _SyncVisualState.syncError => l10n.syncDescriptionUnreachable,
    _SyncVisualState.externalChanged => l10n.syncDescriptionExternalChanges,
  };

  IconData get icon => switch (this) {
    _SyncVisualState.connectedIdle => LucideIcons.check,
    _SyncVisualState.pendingSuggestions => LucideIcons.git_pull_request,
    _SyncVisualState.syncing => LucideIcons.refresh_cw,
    _SyncVisualState.localOnly => LucideIcons.hard_drive,
    _SyncVisualState.offline => LucideIcons.wifi_off,
    _SyncVisualState.authRequired => LucideIcons.lock,
    _SyncVisualState.syncError => LucideIcons.circle_alert,
    _SyncVisualState.externalChanged => LucideIcons.file_code,
  };
}

class _SyncInspector extends StatefulWidget {
  const _SyncInspector({
    required this.onClose,
    required this.onRescan,
    required this.workspacePath,
  });
  final VoidCallback onClose, onRescan;
  final String? workspacePath;

  @override
  State<_SyncInspector> createState() => _SyncInspectorState();
}

class _SyncInspectorState extends State<_SyncInspector>
    with SingleTickerProviderStateMixin {
  var _state = _SyncVisualState.localOnly;
  late final AnimationController _spinner;

  @override
  void initState() {
    super.initState();
    _spinner = AnimationController(vsync: this, duration: BurlMotion.spinner);
  }

  @override
  void dispose() {
    _spinner.dispose();
    super.dispose();
  }

  void _setState(_SyncVisualState value) {
    setState(() => _state = value);
    if (value == _SyncVisualState.syncing &&
        !MediaQuery.disableAnimationsOf(context)) {
      _spinner.repeat();
    } else {
      _spinner.stop();
      _spinner.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    return _CenteredOverlay(
      key: const ValueKey('sync-inspector'),
      onClose: widget.onClose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: _state == _SyncVisualState.connectedIdle
                      ? c.syncConnected
                      : c.textMuted,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.syncInspectorTitle,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                key: const ValueKey('sync-close'),
                tooltip: l10n.syncCloseInspector,
                onPressed: widget.onClose,
                icon: const Icon(LucideIcons.x, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            key: const ValueKey('sync-status-card'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.surface,
              border: Border.all(color: c.borderSubtle),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                _state == _SyncVisualState.syncing
                    ? BurlSyncSpinner(
                        turns: _spinner,
                        child: Icon(_state.icon, size: 16, color: c.accent),
                      )
                    : Icon(_state.icon, size: 16, color: c.accent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _state.label(l10n),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _state.description(l10n),
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          const SizedBox(height: 12),
          if (widget.workspacePath case final path?)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border.all(color: c.borderSubtle),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                '${l10n.syncInspectorPath(path)}\n${l10n.syncRemoteNotConfigured}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: c.textSecondary,
                ),
              ),
            ),
          if (widget.workspacePath != null) const SizedBox(height: 12),
          if (_visualFixture) ...[
            Text(
              'SIMULATION STATE',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                color: c.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<_SyncVisualState>(
              key: const ValueKey('sync-state-select'),
              initialValue: _state,
              isDense: true,
              decoration: const InputDecoration(isDense: true),
              items: [
                for (final state in _SyncVisualState.values)
                  DropdownMenuItem(
                    key: ValueKey('sync-state-${state.name}'),
                    value: state,
                    child: Text(state.label(l10n)),
                  ),
              ],
              onChanged: (state) {
                if (state != null) _setState(state);
              },
            ),
          ] else
            Text(
              l10n.syncStatusUnavailable,
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('sync-now'),
                onPressed: () {
                  widget.onRescan();
                  widget.onClose();
                },
                icon: const Icon(LucideIcons.refresh_cw, size: 14),
                label: Text(l10n.syncRescanWorkspace),
              ),
              FilledButton(
                key: const ValueKey('sync-done'),
                onPressed: widget.onClose,
                child: Text(l10n.workspaceDone),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HistorySnapshot {
  const _HistorySnapshot(
    this.hash,
    this.message,
    this.timestamp,
    this.author,
    this.current,
  );
  final String hash, message, timestamp, author;
  final bool current;
}

class _HistoryDrawer extends StatefulWidget {
  const _HistoryDrawer({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<_HistoryDrawer> {
  static const _snapshots = [
    _HistorySnapshot(
      'a9e31c2',
      'Polish manuscript opening',
      'Today, 10:42',
      'Oscar',
      true,
    ),
    _HistorySnapshot(
      '7d42f10',
      'Clarify supporting argument',
      'Yesterday, 16:08',
      'Oscar',
      false,
    ),
    _HistorySnapshot(
      'd3b67aa',
      'Create first working draft',
      'Aug 20, 09:15',
      'Oscar',
      false,
    ),
  ];
  var _selected = 0;
  var _confirmRestore = false;
  var _fixtureCount = 3;
  var _restored = false;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    final l10n = AppLocalizations.of(context)!;
    final snapshots = _snapshots.take(_fixtureCount).toList();
    final selected = snapshots.isEmpty
        ? 0
        : _selected.clamp(0, snapshots.length - 1);
    final snapshot = snapshots.isEmpty ? _snapshots.first : snapshots[selected];
    return _ShellModalOverlay(
      key: const ValueKey('history-overlay'),
      onClose: widget.onClose,
      barrierDuration: BurlMotion.drawer,
      child: Align(
        alignment: Alignment.centerRight,
        child: BurlScaleFadeEntrance(
          child: Container(
            key: const ValueKey('history-drawer'),
            width: math.min(576, MediaQuery.sizeOf(context).width),
            color: c.surfaceRaised,
            child: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      children: [
                        const Icon(LucideIcons.rotate_ccw_clock, size: 17),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.historyTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                l10n.workspaceBreadcrumb(
                                  l10n.workspaceDefaultPath,
                                ),
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 10,
                                  color: c.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          key: const ValueKey('history-close'),
                          tooltip: l10n.workspaceHistory,
                          onPressed: widget.onClose,
                          icon: const Icon(LucideIcons.x, size: 17),
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: c.borderSubtle),
                  Expanded(
                    child: _visualFixture && snapshots.isEmpty
                        ? const Center(
                            child: Text(
                              'No snapshots in this fixture state.',
                              key: ValueKey('history-fixture-empty'),
                            ),
                          )
                        : _visualFixture
                        ? Row(
                            children: [
                              SizedBox(
                                width: 190,
                                child: ListView(
                                  padding: const EdgeInsets.all(8),
                                  children: [
                                    if (_visualFixture)
                                      Wrap(
                                        children: [
                                          for (final entry in const [
                                            (0, 'zero'),
                                            (1, 'one'),
                                            (3, 'many'),
                                          ])
                                            TextButton(
                                              key: ValueKey(
                                                'history-fixture-${entry.$2}',
                                              ),
                                              onPressed: () => setState(() {
                                                _fixtureCount = entry.$1;
                                                _selected = 0;
                                                _confirmRestore = false;
                                                _restored = false;
                                              }),
                                              child: Text(entry.$2),
                                            ),
                                        ],
                                      ),
                                    Text(
                                      '${snapshots.length} SNAPSHOTS',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1,
                                        color: c.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    for (
                                      var index = 0;
                                      index < snapshots.length;
                                      index++
                                    )
                                      _HistorySnapshotTile(
                                        snapshot: snapshots[index],
                                        selected: index == selected,
                                        onTap: () => setState(() {
                                          _selected = index;
                                          _confirmRestore = false;
                                          _restored = false;
                                        }),
                                      ),
                                  ],
                                ),
                              ),
                              VerticalDivider(width: 1, color: c.borderSubtle),
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.all(16),
                                  children: [
                                    _HistoryMetadataCard(snapshot: snapshot),
                                    const SizedBox(height: 16),
                                    Text(
                                      'WORKING TREE COMPARISON',
                                      style: TextStyle(
                                        fontSize: 10,
                                        letterSpacing: 1,
                                        color: c.textMuted,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    _HistoryDiffCard(snapshot: snapshot),
                                    const SizedBox(height: 16),
                                    if (_restored)
                                      Column(
                                        key: const ValueKey(
                                          'history-restore-resolved',
                                        ),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('Restored ${snapshot.hash}'),
                                          TextButton(
                                            key: const ValueKey(
                                              'history-restore-reset',
                                            ),
                                            onPressed: () => setState(
                                              () => _restored = false,
                                            ),
                                            child: const Text('Reset'),
                                          ),
                                        ],
                                      )
                                    else if (_confirmRestore)
                                      _RestoreConfirmation(
                                        snapshot: snapshot,
                                        onCancel: () => setState(
                                          () => _confirmRestore = false,
                                        ),
                                        onConfirm: () => setState(() {
                                          _confirmRestore = false;
                                          _restored = true;
                                        }),
                                      )
                                    else
                                      OutlinedButton.icon(
                                        key: const ValueKey(
                                          'history-restore-request',
                                        ),
                                        onPressed: () => setState(() {
                                          _confirmRestore = true;
                                          _restored = false;
                                        }),
                                        icon: const Icon(
                                          LucideIcons.rotate_ccw,
                                          size: 15,
                                        ),
                                        label: Text(
                                          'Restore note to ${snapshot.hash}',
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Padding(
                              padding: const EdgeInsets.all(28),
                              child: Text(
                                l10n.historyNoSnapshotsAvailable,
                                key: const ValueKey('history-unavailable'),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: c.textSecondary,
                                ),
                              ),
                            ),
                          ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Text(
                          l10n.historyStoredInGit,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: c.textMuted,
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          key: const ValueKey('history-done'),
                          onPressed: widget.onClose,
                          child: Text(l10n.workspaceDone),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HistorySnapshotTile extends StatelessWidget {
  const _HistorySnapshotTile({
    required this.snapshot,
    required this.selected,
    required this.onTap,
  });
  final _HistorySnapshot snapshot;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        key: ValueKey('history-snapshot-${snapshot.hash}'),
        hoverDuration: BurlMotion.duration(context, BurlMotion.chrome),
        onTap: onTap,
        child: AnimatedContainer(
          duration: BurlMotion.duration(context, BurlMotion.chrome),
          curve: BurlMotion.enterCurve,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: selected ? c.surface : c.surfaceRaised,
            border: Border.all(
              color: selected ? c.borderStrong : c.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    snapshot.hash,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: c.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (snapshot.current)
                    Text(
                      'HEAD',
                      style: TextStyle(fontSize: 9, color: c.accent),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                snapshot.message,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                snapshot.timestamp,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistoryMetadataCard extends StatelessWidget {
  const _HistoryMetadataCard({required this.snapshot});
  final _HistorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return Container(
      key: const ValueKey('history-snapshot-metadata'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.borderSubtle),
        borderRadius: BorderRadius.circular(7),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: c.textSecondary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Commit: ${snapshot.hash}'),
            const SizedBox(height: 5),
            Text('Author: ${snapshot.author}'),
            const SizedBox(height: 5),
            Text('Date: ${snapshot.timestamp}'),
            Divider(height: 18, color: c.borderSubtle),
            Text(
              '“${snapshot.message}”',
              style: TextStyle(fontFamily: null, color: c.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDiffCard extends StatelessWidget {
  const _HistoryDiffCard({required this.snapshot});
  final _HistorySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return Container(
      key: const ValueKey('history-diff'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.borderSubtle),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            color: c.diffDeleteBackground,
            child: Text(
              '- 1 revised block since ${snapshot.hash}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: c.diffDeleteBorder,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(8),
            color: c.diffAddBackground,
            child: Text(
              '+ 2 saved blocks in local Git tree',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: c.diffAddBorder,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestoreConfirmation extends StatelessWidget {
  const _RestoreConfirmation({
    required this.snapshot,
    required this.onCancel,
    required this.onConfirm,
  });
  final _HistorySnapshot snapshot;
  final VoidCallback onCancel, onConfirm;

  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return Container(
      key: const ValueKey('history-restore-confirmation'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.reviewSubtle,
        border: Border.all(color: c.borderStrong),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restore snapshot to disk?',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            'This visual confirmation records no Core restore. The lifecycle-safe restore operation remains separate.',
            style: TextStyle(fontSize: 11, color: c.textSecondary),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('history-restore-confirm'),
                onPressed: onConfirm,
                icon: const Icon(LucideIcons.check, size: 14),
                label: Text('Restore ${snapshot.hash}'),
              ),
              OutlinedButton(
                key: const ValueKey('history-restore-cancel'),
                onPressed: onCancel,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShellModalOverlay extends StatefulWidget {
  const _ShellModalOverlay({
    super.key,
    required this.onClose,
    required this.child,
    this.barrierColor = const Color(0x66000000),
    this.barrierDuration,
  });

  final VoidCallback onClose;
  final Widget child;
  final Color barrierColor;
  final Duration? barrierDuration;

  @override
  State<_ShellModalOverlay> createState() => _ShellModalOverlayState();
}

class _ShellModalOverlayState extends State<_ShellModalOverlay> {
  late final FocusScopeNode _focusScope = FocusScopeNode(
    debugLabel: 'workspace modal',
    traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
  );

  @override
  void dispose() {
    _focusScope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Positioned.fill(
      child: BlockSemantics(
        child: FocusScope.withExternalFocusNode(
          key: const ValueKey('workspace-modal-focus-scope'),
          focusScopeNode: _focusScope,
          autofocus: true,
          child: FocusTraversalGroup(
            child: Focus(
              autofocus: true,
              skipTraversal: true,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: BurlFadeEntrance(
                      duration: widget.barrierDuration ?? BurlMotion.overlay,
                      child: ModalBarrier(
                        color: widget.barrierColor,
                        onDismiss: widget.onClose,
                        semanticsLabel: l10n.workspaceDismissOverlay,
                        barrierSemanticsDismissible: true,
                      ),
                    ),
                  ),
                  widget.child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CenteredOverlay extends StatelessWidget {
  const _CenteredOverlay({
    super.key,
    required this.onClose,
    required this.child,
  });
  final VoidCallback onClose;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final c = context.burlColors;
    return _ShellModalOverlay(
      key: key,
      onClose: onClose,
      child: Center(
        child: BurlScaleFadeEntrance(
          child: Container(
            width: 384,
            margin: const EdgeInsets.all(20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.borderStrong),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
