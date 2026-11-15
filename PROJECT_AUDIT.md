# Project Audit — Chalkwise (formerly BoardFlow)

_Audit date: 2026-11-15. Scope: full repository at commit `ff75d3b` plus the uncommitted function-plotter work present in the working tree._

## 1. What the application is

A **local-first Flutter whiteboard** (package `boardflow`) for teachers and students, targeting Android, Linux desktop and web folders (only `dart:io` storage is implemented, so web is not a functional target today).

| Area | Implementation |
|---|---|
| State | Riverpod 3 `Notifier` (`WhiteboardNotifier`), immutable `WhiteboardState` / `ProjectModel` / `PageModel` |
| Engine | `Listener`-based pointer handling + `TransformationController` (pan / zoom), `CustomPainter` layers |
| History | Command pattern (`BoardCommand`, `HistoryManager`) |
| Persistence | JSON files in app documents dir (`.bf`), atomic temp-file rename, debounced crash-recovery draft |
| Export | PNG / multi-page PDF (`pdf` package), share sheet |
| Recognition | On-device shape detection, handwritten-equation detection & solving, formula catalog, function parser/plotter |
| AI | OpenRouter multimodal API (vision math solving); after this work also the AI Assistant |

**Not present in the codebase** (verified by searching the repository, not assumed): backend server, database, user accounts / authentication, authorization, real-time collaboration, WebSockets, cloud sync. "Private boards cannot be accessed by unauthorized users" is satisfied today only in the sense that boards never leave the device except via explicit export/share and AI requests.

## 2. Critical findings (all fixed)

| # | Severity | Finding | Root cause | Fix |
|---|---|---|---|---|
| S1 | **Critical (security)** | A live OpenRouter API key was hard-coded in `ai_math_service.dart` and committed in `e4d3443`. Anyone with the source or the compiled app could use it. | Key embedded as a default constant. | Key removed. New `AiConfig` reads a user-entered key (device-local) or `--dart-define=OPENROUTER_API_KEY`. **The key is still in git history — it must be revoked at openrouter.ai.** |
| P1 | High (perf) | Autosave serialized the entire project on the UI thread 800 ms after every edit: **255 ms freeze** on a 2,000-stroke board, i.e. visible stutter while drawing. | `jsonEncode` + per-coordinate `double.parse(toStringAsFixed())` on main isolate. | Compact point encoding (14× faster map build), encoding moved to a background isolate (`compute`). |
| P2 | High (perf) | Each eraser move scanned all text objects with a fresh text layout: 6.2 ms per pointer sample. Marquee select likewise. | `TextObject.bounds` ran `TextPainter.layout()` on every call. | Cached layout per instance (Expando). 0.12 ms. |
| P3 | High (perf) | Full board repaint cost 13.6 ms (most of a 60 fps frame) and happened on every commit; drags rewrote the page every frame. | Text laid out on every paint; selection drag mutated state per move. | Cached text painters (1.2 ms repaint); drag preview layer, single commit on release. |
| P4 | Medium (perf) | Every pointer move called `setState` on the whole canvas; every pinch/pan frame pushed zoom into global state and rebuilt the screen, app bar and canvas. | Coarse `ref.watch` of the entire state; gesture data in widget state. | `ChangeNotifier`-driven painters; `select()`-narrowed watches; background repaints from the transform listenable. |
| B1 | High (data) | Moving a selection could not be undone. | `translateSelected` bypassed history. | `MoveElementsCommand`, one step per drag. |
| B2 | High (data) | Every eraser pointer sample was its own undo entry — one swipe could fill the 60-step history and evict real work. Fast swipes skipped strokes. | Per-sample commands, no segment interpolation. | Gesture-batched erase (one undo step), interpolated sampling. |
| B3 | High (data) | Switching pages wiped undo history for all pages. | Single global `HistoryManager` cleared on page change. | Per-page history map. |
| B4 | Medium (data) | Graph plots: add/delete not undoable, not removed by Clear Page, not selectable/deletable/movable with selection, not autosaved on edit, **missing from PNG/PDF export**. | Plots added later without integrating with commands/selection/export. | Plots routed through commands, selection, clear, export rendering. |
| B5 | Medium (data) | Undo of a delete re-added elements on top (z-order changed). | `DeleteElementsCommand.undo` appended. | `ReplaceElementsCommand` captures and restores original indices. |
| B6 | High (export) | PNG/PDF export rendered a fixed 1920×1080 area from the origin, but the page sheet is portrait 1100×1550: **everything below y≈1080 was cut off**; infinite-canvas content outside the area was lost. PDF stretched with `BoxFit.fill`. | Hard-coded target size. | Export region = page sheet ∪ content bounds; orientation follows content; aspect preserved. |
| B7 | Medium | Saving errors escaped as unhandled exceptions; on failure the back button did nothing and the user got no message. System back (Android gesture) left without saving. | `await saveProject()` with no catch; no `PopScope`. | Error snackbar, "leave anyway?" dialog (recovery draft kept), `PopScope`. |
| B8 | Medium | Recovery draft written non-atomically (crash mid-write corrupts the very file meant for crash recovery); an in-flight draft write could re-create the draft after a clean save. | Direct `writeAsString`; no generation guard. | Temp-file + rename; generation counter; serialized writes. |
| B9 | Medium (AI) | AI failures were silent: spinner disappeared with no explanation. Bad key → retried 4 models × 12 s (~48 s). Two of the fallback model IDs could not be verified to exist. Stale requests not cancelled. | Catch-all `debugPrint`; retry on every error. | Typed `AiException` with user messages; retry only on retryable statuses; cancellation; error pill with "Settings" shortcut. |
| B10 | Medium (UI) | App bar overflowed by 102 px on phones (390 px wide) — some actions were unreachable. | 11 fixed action buttons. | Secondary actions collapse into an overflow menu below 760 px. |
| B11 | Low | Text objects could not be edited after creation (`updateText` existed but had no UI). | Missing UI path. | Tap with Text tool / double-tap with Select tool opens an edit dialog (empty = delete). |
| B12 | Low | Area eraser existed in the model but was unreachable and behaved identically to the stroke eraser. | Never wired up. | Partial erase (splits strokes) reachable by tapping the eraser again or pressing E twice. |
| B13 | Low | Pinch-zoom focal point used global coordinates, so zoom drifted by the app-bar height. | `event.position` vs `localPosition`. | Local coordinates. |
| B14 | Low | Zoom % display clamped to 25–500 % while the canvas allowed 10–600 %. | Mismatched clamps. | Aligned. |

## 3. Remaining weaknesses (not fixed — need product decisions or larger work)

1. **No collaboration / accounts / cloud.** Real-time classroom sessions require a backend (sync service, auth, authorization, conflict resolution). This is a new system, not an improvement of an existing one; see `COMPETITOR_GAP_ANALYSIS.md` for a recommended approach.
2. **API key storage** uses `shared_preferences` (plain text on device). For shared classroom devices, `flutter_secure_storage` or a server-side proxy (preferable: keeps keys off student devices entirely) is recommended.
3. **AI requests go directly from the device to OpenRouter.** A small backend proxy would enable usage limits per class, key protection, logging and content filtering for minors.
4. **Pressure is captured but not rendered** (strokes are constant width).
5. **No image objects on the board** — uploaded photos can be analysed by AI but not placed on the canvas.
6. **No LaTeX rendering** — AI is instructed to output Unicode math (x², √, π) so it renders as board text; true typeset math would need a dependency such as `flutter_math_fork`.
7. **Dead code:** `SelectionActionOverlay`, `PageStripWidget`, `CanvasZoomControls` widgets are unused (superseded by `UnifiedBottomBar`). Left in place pending owner decision.
8. **Plot viewport edits** (pan/zoom inside a graph, dragging a graph card) are live and autosaved but are not individual undo steps.
9. **Web target**: storage uses `dart:io`; a web build will not persist boards.
10. **Very large boards** (>10k strokes): repaint is O(n) on change; spatial indexing/tiling would be the next step if profiling on device shows need.
