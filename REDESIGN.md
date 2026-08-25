# BurlMD visual redesign journal

This journal records the completed visual-parity redesign on
`feat/visual-parity-redesign`. The V33 audit accepts all 22 authoritative
surfaces with strict thresholds. No visual failures remain.

## Scope and design system

The Flutter application implements the prototype's Washi light palette and
Sumi dark palette across the workspace, editor, and overlays. The theme
preference offers System, Light, and Dark. System maps to Flutter's
`ThemeMode.system`, so the application follows the operating system setting.

`BurlColors` supplies the application, sidebar, editor, surface, border,
text, review, sync, and diff tokens. The main design components include tabs,
metadata, directory navigation, search, preferences, history, sync, recovery,
destructive-action dialogs, block editing, and inline links.

The fixture uses embedded `BurlPrototypeSans` and `BurlPrototypeMono` font
families to make the reference comparison deterministic. The production theme
continues to use its platform typography and user-selected font scale and
measure.

Microinteractions include 120 ms overlay entrances, 150 ms chrome, theme, and
link feedback, 200 ms focus dimming, and 100 ms row feedback. When
`MediaQuery.disableAnimationsOf(context)` is true, transitions use a zero
duration and the sync spinner is static. These paths are covered by widget
tests.

The design-system specimen page provides implementation surfaces only. It is
not an authoritative screenshot surface and is excluded from the 22-surface
comparison matrix.

## Responsive layout

The layout has three tiers:

- Wide viewports at 1040 px and wider use a 288 px navigator.
- Medium viewports from 720 px to 1039 px use a 48 px rail with an overlay
  navigator.
- Compact viewports below 720 px use compact navigation. The audited compact
  viewport is 480x820.

The final compact raster keeps the footer, utility row, metadata, directory
tree, tabs, editor viewport, typography, and wrapping at the prototype's
measured geometry. The compact post-search gap is 25 px; `Spacer` keeps the
footer fixed while the directory tree aligns to its reference lanes.

## Authoritative references

The reference archive is
`/mnt/new-learning/grok/burlmd-design-language-prototype.zip`. Its SHA-256 is
`a31e36c7092b4012140dcd426d93910cca1ab2c71147d3d2c8ade2fbcfee05e9`.
The extracted prototype and reference images are in
`/tmp/burlmd-reference-proof`.

The reference manifest is
`/tmp/burlmd-reference-proof/reference-manifest.json`, with SHA-256
`d03a67e3678c4f5d5f906b56765a96a26f2a0df261a8a6dc75845114a18bf1ed`.
It records 21 `1440x900` surfaces and one `480x820` surface. The raw-code
reference was captured with Chromium spellchecking disabled and records zero
spellcheck-squiggle pixels in its raw-header region.

The Flutter V33 manifest is `/tmp/burlmd-proof/flutter-manifest.json`, with
SHA-256 `5235ec846458ea96776924813b1d42ae6068aba16154d8494c690a7cd04ce75b`.
The manifest, capture ledger, images, and audit artifacts remain in
`/tmp/burlmd-proof`.

## Audited surfaces

The V33 matrix contains these authoritative surfaces:

1. `reference-wide-dark-shell`
2. `reference-note-rendered`
3. `reference-wide-light-shell`
4. `reference-search-results`
5. `reference-preferences-dark`
6. `reference-sync-local-only`
7. `reference-sync-connected-idle`
8. `reference-sync-syncing`
9. `reference-sync-offline`
10. `reference-sync-pending-suggestions`
11. `reference-sync-auth-required`
12. `reference-sync-sync-error`
13. `reference-sync-external-changed`
14. `reference-history`
15. `reference-delete-confirmation`
16. `reference-note-raw`
17. `reference-suggestion`
18. `reference-code-rendered`
19. `reference-code-raw`
20. `reference-link-hover`
21. `reference-recovery-badge-note`
22. `reference-narrow-dark-shell`

The search surface has the prototype's two-match state. Anchored suggestion,
rendered-code, raw-code, and link-popover surfaces use controller telemetry
and stable geometry before capture.

## Normal-app capture protocol

The normal application target is `lib/visual_capture_main.dart`. It exposes a
`FixtureCaptureController` through `FlutterDriver.requestData`; it does not
use a widget-test binding as the capture target.

For each state, `test_driver/visual_capture_driver.dart` publishes a
resize-ready handshake, waits for the controller to report the exact viewport,
and requires three stable telemetry responses. It then publishes a
capture-ready handshake only after the frame is presented. The capture worker
uses `hyprctl` to focus, float, and resize one exact Linux client, verifies
`floating: true`, captures with `grim`, and writes a matching acknowledgement.
The client is chromeless, has no border, shadow, or compositor animation, and
uses atomic ready and acknowledgement files.

The V33 manifest records one floating Hyprland client with exact dimensions and
decorations. The capture protocol rejects stale acknowledgements, dimension
mismatches, missing presentation markers, and unstable controller geometry.

## V33 visual evidence

The V33 audit accepts 22 of 22 surfaces. Every hard gate passes, and every
surface meets the exact and Gaussian-blur thresholds. The practical epsilon is
unused.

The strict thresholds are:

- Exact: RMSE at most 0.150, MAE at most 0.060, and AE5 at most 25%.
- Gaussian sigma 1: RMSE at most 0.108, MAE at most 0.060, and AE5 at most
  30%.

The compact surface passes strictly with exact RMSE 0.148562, MAE 0.043839,
and AE5 13.139%. Its Gaussian sigma 1 metrics are RMSE 0.080844, MAE 0.028154,
and AE5 20.250%.

The final artifacts are:

- `/tmp/burlmd-proof/v33-summary.json`
- `/tmp/burlmd-proof/v33-capture-ledger.tsv`
- `/tmp/burlmd-proof/v33-perceptual-metrics.tsv`
- `/tmp/burlmd-proof/v33-visual-audit.json`
- `/tmp/burlmd-proof/v33-visual-audit.tsv`
- `/tmp/burlmd-proof/v33-visual-audit.md`
- `/tmp/burlmd-proof/v33-audit-pairs/`
- `/tmp/burlmd-proof/v33-audit-diffs/`

Captures 1 through 21 are byte-identical to the accepted V32 captures. V33
replaces intermediate visual claims and rejected capture directories as the
final visual verdict.

## Final engineering evidence

The V33 exact-worktree regression passed:

- Dart MCP `analyze_files`: no errors.
- `flutter analyze`: no issues.
- `dart format --output=none --set-exit-if-changed`: no changes.
- `git diff --check`: exit 0.
- `flutter test --concurrency=1`: 344 of 344 tests passed.
- Production Linux driver: 2 of 2 tests passed.
- Fixture Linux driver with `BURLMD_VISUAL_FIXTURE=true`: 2 of 2 tests passed
  across all 22 states.
- Host protocol tests: 6 of 6 tests passed.
- Process audit: no residual Flutter test, driver, or Linux application
  process remained.

## Deferred logic and Core boundaries

The parity fixture supplies deterministic presentation data. It does not
extend product logic beyond the capture contract. The following work remains
outside this redesign:

- Persist preferences.
- Route active-tab close through the lifecycle-aware close and flush path.
- Complete multi-tab lifecycle behavior.
- Expose remote sync status from Core.
- Expose snapshots, diffs, and a lifecycle-safe restore operation from Core.
- Add Core data and lifecycle support for remote suggestion review.

These boundaries preserve the existing selection, rescan, recovery,
write-tier, and editor-geometry seams while the product logic is planned
separately.
