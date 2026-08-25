import 'package:burlmd/src/components/draft_recovery.dart';
import 'package:burlmd/src/components/editor.dart';
import 'package:burlmd/src/providers/note_providers.dart';
import 'package:burlmd/src/providers/rust_api_provider.dart';
import 'package:burlmd/src/providers/workspace_provider.dart';
import 'package:burlmd/src/rust/draft.dart';
import 'package:burlmd/src/rust/error.dart';
import 'package:burlmd/src/rust/markdown/ast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A [NoteController] whose initial state is fixed at construction, so tests
/// can mount the recovery surfaces against an already-open Note without a
/// real `open_note` FFI round trip (which needs the compiled Rust dylib).
class _FixedNoteController extends NoteController {
  _FixedNoteController(this._initial);

  final NoteState _initial;

  @override
  NoteState? build() => _initial;
}

/// A [RustApi] standing in for the Core at the recovery-surface level:
/// serves [pendingDraftsResult], answers every `note_write_status` poll
/// with [status], records `open:`/`reload:` calls so tests can prove the
/// reload offer drives `reload_note` and never `open_note`, and hands back
/// distinct states per call so drafted vs disk content is observable.
class _RecoveryRustApi extends RustApi {
  _RecoveryRustApi({this.pendingDraftsResult = const []});

  List<NoteMetadata> pendingDraftsResult;

  /// What every write-status poll reports until a test changes it.
  NoteWriteStatus status = const NoteWriteStatus(hasUnwrittenEdits: false);

  /// What `openNote` returns, per concept id.
  final Map<String, NoteState> openStates = {};

  /// When non-null, every write-status poll throws instead of answering —
  /// the "the poll channel itself is down" case.
  Object? throwStatus;

  /// What `reloadNote` returns (the disk state), per concept id.
  final Map<String, NoteState> reloadStates = {};

  /// Every `open:` / `reload:` / `status:` call, in issue order.
  final List<String> calls = [];

  @override
  Future<List<NoteMetadata>> pendingDrafts() async => pendingDraftsResult;

  @override
  NoteWriteStatus noteWriteStatus(String noteId) {
    calls.add('status:$noteId');
    final failure = throwStatus;
    if (failure != null) throw failure;
    return status;
  }

  @override
  Future<NoteState> openNote(String noteId) async {
    calls.add('open:$noteId');
    return openStates[noteId]!;
  }

  @override
  Future<NoteState> reloadNote(String noteId) async {
    calls.add('reload:$noteId');
    // The real Core leaves the failing draft behind and reports clean after
    // a successful reload; mirror that so the post-reload poll clears.
    status = const NoteWriteStatus(hasUnwrittenEdits: false);
    return reloadStates[noteId]!;
  }
}

NoteMetadata _metadata(String id, String title) => NoteMetadata(
  id: id,
  path: '$id.md',
  title: title,
  lastModified: 0,
  okfConformant: true,
);

AstNode _paragraph(String text) => AstNode.paragraph(
  content: [
    InlineElement.text(
      TextRun(
        content: text,
        bold: false,
        italic: false,
        strikethrough: false,
        code: false,
      ),
    ),
  ],
);

NoteState _state(
  String id,
  String paragraphText, {
  bool restoredFromDraft = false,
}) => NoteState(
  ast: [_paragraph(paragraphText)],
  metadata: _metadata(id, id),
  baseRevision: 'head',
  restoredFromDraft: restoredFromDraft,
);

/// Pumps both recovery surfaces above a real [Editor], against one
/// [ProviderContainer] the test owns (so its disposal in teardown cancels
/// the write-status poller's periodic timer before the test framework
/// checks for pending timers).
///
/// [seededNote] pre-opens a Note through a fixed controller, standing in
/// for "the user has a recovered Note on screen".
Future<ProviderContainer> _pumpSurface(
  WidgetTester tester,
  _RecoveryRustApi api, {
  NoteState? seededNote,
}) async {
  final container = ProviderContainer(
    overrides: [
      rustApiProvider.overrideWithValue(api),
      // No periodic timer in tests (there is no fake clock to fire it): the
      // monitor is driven by explicit poll() calls, which also makes the
      // persistence criteria deterministically testable.
      writeStatusPollIntervalProvider.overrideWithValue(null),
      if (seededNote != null)
        activeNoteProvider.overrideWith(() => _FixedNoteController(seededNote)),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              // Mirrors the shell's editor pane: the selection seam drives
              // `NoteController.open`, exactly as production navigation
              // does — the recovery surface itself only publishes.
              ref.listen<String?>(selectedNoteIdProvider, (_, next) {
                if (next != null) {
                  ref.read(activeNoteProvider.notifier).open(next);
                }
              });
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  RecoveredDraftsPanel(),
                  WriteTierNotice(),
                  Expanded(child: Editor()),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets('a draft left unflushed by a previous session is surfaced as '
      'recovered work on startup', (tester) async {
    final api = _RecoveryRustApi(
      pendingDraftsResult: [_metadata('n-crash', 'Crash Journal')],
    );

    await _pumpSurface(tester, api);

    expect(find.text('Recovered drafts'), findsOneWidget);
    expect(find.text('Crash Journal'), findsOneWidget);
    expect(
      find.textContaining('recovered from a previous session'),
      findsOneWidget,
    );
  });

  testWidgets('opening a recovered note renders the drafted content, and '
      'the open state carries that it came from a draft', (tester) async {
    final api = _RecoveryRustApi(
      pendingDraftsResult: [_metadata('n-crash', 'Crash Journal')],
    );
    // `open_note` restores the draft in preference to disk: the returned
    // state holds the drafted line and says where it came from.
    api.openStates['n-crash'] = _state(
      'n-crash',
      'Drafted line',
      restoredFromDraft: true,
    );

    final container = await _pumpSurface(tester, api);

    expect(container.read(activeNoteProvider), isNull);
    await tester.tap(find.text('Crash Journal'));
    await tester.pumpAndSettle();

    // The drafted content renders — not some other "last-on-disk" text.
    expect(find.text('Drafted line'), findsOneWidget);
    // And the state carries the fact that it came from a draft.
    expect(container.read(activeNoteProvider)!.restoredFromDraft, isTrue);
    expect(api.calls.contains('open:n-crash'), isTrue);
  });

  testWidgets(
    'lifecycle admission disables recovered-draft selection and allows it again after settlement',
    (tester) async {
      final api = _RecoveryRustApi(
        pendingDraftsResult: [_metadata('n-crash', 'Crash Journal')],
      );
      api.openStates['n-crash'] = _state(
        'n-crash',
        'Drafted line',
        restoredFromDraft: true,
      );
      final container = await _pumpSurface(tester, api);

      container.read(lifecycleEditingProvider.notifier).begin();
      await tester.pump();
      final blockedRow = tester.widget<ListTile>(
        find.byKey(const ValueKey('recovered-n-crash')),
      );
      expect(blockedRow.onTap, isNull);
      await tester.tap(find.text('Crash Journal'));
      await tester.pump();
      expect(container.read(selectedNoteIdProvider), isNull);
      expect(container.read(activeNoteProvider), isNull);
      expect(api.calls.where((call) => call == 'open:n-crash'), isEmpty);

      container.read(lifecycleEditingProvider.notifier).end();
      await tester.pump();
      await tester.tap(find.text('Crash Journal'));
      await tester.pumpAndSettle();
      expect(container.read(selectedNoteIdProvider), 'n-crash');
      expect(container.read(activeNoteProvider)!.metadata.id, 'n-crash');
      expect(find.text('Drafted line'), findsOneWidget);
    },
  );

  testWidgets('dismissing the recovery notice hides only the notice — the '
      'recovered content stays present', (tester) async {
    final api = _RecoveryRustApi(
      pendingDraftsResult: [_metadata('n-crash', 'Crash Journal')],
    );
    api.openStates['n-crash'] = _state(
      'n-crash',
      'Drafted line',
      restoredFromDraft: true,
    );

    final container = await _pumpSurface(tester, api);
    await tester.tap(find.text('Crash Journal'));
    await tester.pumpAndSettle();
    expect(find.text('Recovered drafts'), findsOneWidget);

    final coreCallsBeforeDismiss = api.calls
        .where((c) => !c.startsWith('status:'))
        .toList();
    await tester.tap(find.byTooltip('Dismiss notice'));
    await tester.pumpAndSettle();

    // The notice is gone…
    expect(find.text('Recovered drafts'), findsNothing);
    expect(find.text('Crash Journal'), findsNothing);
    // …and the recovered content is exactly as it was. Dismissal touched
    // nothing Core-side — no close, no reopen, no draft-row discard.
    expect(find.text('Drafted line'), findsOneWidget);
    expect(container.read(activeNoteProvider)!.restoredFromDraft, isTrue);
    expect(
      api.calls.where((c) => !c.startsWith('status:')),
      coreCallsBeforeDismiss,
    );
  });

  testWidgets('a revision mismatch surfaces the failure and offers a reload '
      'that drives reload_note, never open_note', (tester) async {
    final api = _RecoveryRustApi();
    api.status = const NoteWriteStatus(
      lastError: AppError.revisionMismatch('rev-2'),
      hasUnwrittenEdits: true,
    );
    api.reloadStates['n-open'] = _state('n-open', 'Reloaded from disk');

    final container = await _pumpSurface(
      tester,
      api,
      seededNote: _state('n-open', 'Buffered line', restoredFromDraft: true),
    );

    // The failure is shown…
    expect(find.textContaining('revision mismatch'), findsOneWidget);
    // …with a reload offered rather than a retry.
    expect(find.text('Reload from disk'), findsOneWidget);

    await tester.tap(find.text('Reload from disk'));
    await tester.pumpAndSettle();

    // The confirmation says plainly that reloading discards buffered text —
    // the only prompt in the application that destroys unwritten work.
    expect(find.textContaining('discards your buffered text'), findsOneWidget);

    await tester.tap(find.text('Discard and reload'));
    await tester.pumpAndSettle();

    // The offer called reload_note — and never open_note, which would have
    // restored the surviving draft and reproduced the mismatch on the next
    // tick.
    expect(api.calls.contains('reload:n-open'), isTrue);
    expect(api.calls.where((c) => c.startsWith('open:')), isEmpty);

    // The note re-rendered from disk…
    expect(find.text('Reloaded from disk'), findsOneWidget);
    expect(find.text('Buffered line'), findsNothing);
    expect(container.read(activeNoteProvider)!.restoredFromDraft, isFalse);
    // …and the write status cleared.
    expect(find.textContaining('revision mismatch'), findsNothing);
    expect(container.read(writeTierMonitorProvider).status?.lastError, isNull);
  });

  testWidgets('declining the reload keeps the buffered text reachable and '
      'the failure surfaced', (tester) async {
    final api = _RecoveryRustApi();
    api.status = const NoteWriteStatus(
      lastError: AppError.revisionMismatch('rev-2'),
      hasUnwrittenEdits: true,
    );
    api.reloadStates['n-open'] = _state('n-open', 'Reloaded from disk');

    await _pumpSurface(
      tester,
      api,
      seededNote: _state('n-open', 'Buffered line', restoredFromDraft: true),
    );

    await tester.tap(find.text('Reload from disk'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();

    // Nothing was destroyed: the buffered content is still on screen, the
    // failure is still surfaced, and the Core was never asked to reload.
    expect(find.text('Buffered line'), findsOneWidget);
    expect(find.textContaining('revision mismatch'), findsOneWidget);
    expect(api.calls.where((c) => c.startsWith('reload:')), isEmpty);
  });

  testWidgets('a disk-full failure persists across polls until it resolves', (
    tester,
  ) async {
    final api = _RecoveryRustApi();
    api.status = const NoteWriteStatus(
      lastError: AppError.diskFull(),
      hasUnwrittenEdits: true,
    );

    final container = await _pumpSurface(
      tester,
      api,
      seededNote: _state('n-open', 'Buffered line'),
    );

    expect(find.textContaining('disk is full'), findsOneWidget);

    // Every subsequent poll fails the same way until space is freed, so the
    // surface keeps showing it — showing it once would hide the condition
    // the user must fix.
    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(find.textContaining('disk is full'), findsOneWidget);

    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(find.textContaining('disk is full'), findsOneWidget);

    // Once it actually resolves, the surface clears.
    api.status = const NoteWriteStatus(hasUnwrittenEdits: false);
    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(find.textContaining('disk is full'), findsNothing);
  });

  testWidgets('a poll that fails once or twice keeps last-known standing, '
      'but persistent failures surface a write-status-unavailable state', (
    tester,
  ) async {
    final api = _RecoveryRustApi()
      ..status = const NoteWriteStatus(hasUnwrittenEdits: false);

    final container = await _pumpSurface(
      tester,
      api,
      seededNote: _state('n-open', 'Buffered line'),
    );

    // The channel goes dark mid-session.
    api.throwStatus = true;

    // One failed poll: transient. The previous clean status keeps standing
    // (clearing it would unsurface a failure that may still be real) and no
    // unavailable claim is made yet.
    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(
      container.read(writeTierMonitorProvider).status?.hasUnwrittenEdits,
      isFalse,
    );
    expect(find.textContaining('cannot be checked'), findsNothing);

    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(find.textContaining('cannot be checked'), findsNothing);

    // A third consecutive failure crosses the threshold: rather than keep
    // presenting an answer nothing can verify, the surface says plainly
    // that the save status is unknown (SHEL-E007's STOP risk).
    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(find.textContaining('cannot be checked'), findsOneWidget);
    expect(container.read(writeTierMonitorProvider).statusUnavailable, isTrue);

    // And when the channel comes back, the unavailable state clears.
    api.throwStatus = null;
    api.status = const NoteWriteStatus(hasUnwrittenEdits: true);
    container.read(writeTierMonitorProvider.notifier).poll();
    await tester.pump();
    expect(find.textContaining('cannot be checked'), findsNothing);
    expect(container.read(writeTierMonitorProvider).statusUnavailable, isFalse);
  });
}
