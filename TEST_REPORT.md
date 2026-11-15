# Test Report

_Run 2026-11-15, Flutter 3.44.8 stable, Linux._

## Summary

| Check | Before | After |
|---|---|---|
| `flutter analyze` | 10 issues (2 warnings, 8 infos) | **0 issues** |
| `flutter test` | 90 passed | **147 passed, 0 failed** |
| `flutter build apk --release` | not run | ✅ `app-release.apk` (60.3 MB) |
| `flutter build web --release` | not run | ✅ builds (note: storage uses `dart:io`, so boards don't persist on web) |
| `flutter build linux` | — | ⚠️ not possible here: clang, ninja, GTK dev libraries missing on this machine |
| Live AI calls | — | ⚠️ not run: no API key in this environment; AI verified against a mock HTTP server |
| On-device profiling | — | ⚠️ not run: no device attached; see `PERFORMANCE_REPORT.md` |

## New test suites (57 tests)

### `test/engine_reliability_test.dart` — 16 tests
Undo restores deleted elements at original z-order · move strokes/texts/plots and undo · selection move = one undo step · fast eraser swipe across 6 strokes (2 samples) erases all and is one undo step · partial eraser splits a stroke, removes ink under the cursor, undoes · history is kept per page across page switches · plots in add/undo/clear/delete-selection · copy/paste cascades offsets, duplicate, undo prunes selection · cut/paste · select all covers every element type · load resets transient state · Solve Selected without key gives a clear error · compact point format round-trip **and legacy v1 files still load** · document version written · export region includes content below the fold and plots · page with plot renders to PNG.

### `test/ai_integration_test.dart` — 23 tests (mock HTTP)
No key ships with the app · model fallback list · not-configured sends nothing · bearer auth + model in body · fallback on 404/5xx · **no retry on 401** · rate-limit error · timeout instead of hang · pre-cancelled token sends nothing · SSE parser (keep-alives, empty deltas, `[DONE]`, UTF-8) · streaming through transport · vision math solver needs config, sends image, parses answer · board context reading order / selection scoping / no image for text-only · message building (system prompt, last-4-turn history, context, image) · lesson plan does not leak board content · markdown stripping · diagram end-to-end: invalid edges dropped, diamond node, arrows, **no overlapping nodes**, title, origin · mind-map radial layout with no overlaps · invalid diagram → bad-response error · upload rejects scripts/empty files by signature, oversized files, undecodable PNG.

### `test/whiteboard_interaction_test.dart` — 11 widget tests (real gestures and keys through `WhiteboardScreen`)
Pen draw → Ctrl+Z / Ctrl+Shift+Z · select-drag moves on release and undoes · eraser swipe removes 4 strokes as one undo step · Ctrl+A / Ctrl+D / Delete · text tool add, tap-to-edit, undo edit · single-letter shortcuts ignored while typing · assistant without key shows setup message · E toggles eraser modes · **no layout overflow at 390×844, 820×1180, 1400×900** (with and without assistant panel).

### `test/perf/engine_benchmark_test.dart` — 7 benchmarks
See `PERFORMANCE_REPORT.md`.

## Regressions found and fixed during testing

1. **Text dialog controller used after dispose** (introduced in this round): the controller was disposed when the dialog's future completed, while the closing animation still built the `TextField`. Fixed by moving the dialog into a `StatefulWidget` that owns its controller.
2. **App bar overflow on phones** (pre-existing): 102 px overflow at 390 px width. Fixed with a responsive overflow menu.
3. Test-only issue: mock HTTP responses defaulted to Latin-1; the client correctly decodes UTF-8 JSON. Mocks now send UTF-8 bytes like the real API.

## Not covered (recommended next)

- Live provider smoke test (one `Explain` + one `Flowchart`) once a key is configured.
- Integration tests on a physical tablet with a stylus (palm rejection, pressure).
- Collaboration / auth / API tests: no such systems exist yet.
