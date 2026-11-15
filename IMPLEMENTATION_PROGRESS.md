# Implementation Progress

## Stage status

| Stage | Status |
|---|---|
| 1. Repository inspection & feature inventory | ✅ `PROJECT_AUDIT.md`, `FEATURE_INVENTORY.md` |
| 2. Bugs, incomplete functionality, weaknesses | ✅ `PROJECT_AUDIT.md` §2–3 |
| 3. Performance baselines | ✅ `test/perf/engine_benchmark_test.dart`, `PERFORMANCE_REPORT.md` |
| 4. Competitor research | ✅ `COMPETITOR_GAP_ANALYSIS.md` |
| 5. Critical bugs & reliability | ✅ (leaked key, history, export, save, recovery, AI errors, overflow) |
| 6. Engine optimization | ✅ (see performance report) |
| 7. AI improvements & new capabilities | ✅ shared client, settings, assistant, diagrams, image upload |
| 8. Teacher / student workflows | ✅ for single-device use (assistant actions, editing, shortcuts) |
| 9. Collaboration, responsiveness, UI/UX | 🟡 responsiveness/UI done; **collaboration not started (needs backend)** |
| 10. Tests & regressions | ✅ 147 tests passing, analyzer clean |
| 11. Production-readiness docs | ✅ these documents |

## Required action by the owner

1. **Revoke the OpenRouter key** that was committed in `e4d3443` (`sk-or-v1-f0bb…dbc7`). Removing it from the source does not remove it from git history or from any APK built before this change.
2. Configure AI: Smart Recognition & AI settings → API key; or build with `--dart-define=OPENROUTER_API_KEY=…`.

## Changes by file

### New
- `lib/core/ai/ai_config.dart` — key/model config (user key or build define), persisted locally.
- `lib/core/ai/openrouter_client.dart` — single shared AI client: completion + SSE streaming, typed errors, retry policy, cancellation, timeouts.
- `lib/features/whiteboard/assistant/board_context.dart` — selection/page → text summary + PNG (with plots).
- `lib/features/whiteboard/assistant/board_assistant.dart` — 14 teaching actions, prompts, message building, upload validation.
- `lib/features/whiteboard/assistant/diagram_builder.dart` — JSON diagram spec parsing, layered & radial layout → editable shapes/arrows/text.
- `lib/features/whiteboard/ui/ai_assistant_panel.dart` — non-modal assistant panel.
- Tests: `engine_reliability_test.dart`, `ai_integration_test.dart`, `whiteboard_interaction_test.dart`, `perf/engine_benchmark_test.dart`.

### Modified (key points)
- `ai_math_service.dart` — hard-coded key and unverifiable models removed; uses shared client; throws typed errors.
- `board_command.dart` / `history_manager.dart` — `ReplaceElementsCommand` (z-order preserving), `AddElementsCommand`, `MoveElementsCommand`, plots in `ClearPageCommand`, `push()` for already-applied gestures. Existing command APIs kept.
- `whiteboard_notifier.dart` — per-page history; gesture erasing (stroke/partial); undoable moves; clipboard; select all; plots via history; AI cancellation & errors; transient-state reset on load/page switch.
- `whiteboard_state.dart` — `aiErrorMessage`.
- `stroke_model.dart` — compact `pts` encoding (reads legacy `points`), `eraseCircle` splitting.
- `text_model.dart` — cached layout/bounds.
- `project_model.dart` — `documentVersion` 2.
- `project_storage_service.dart`, `recovery_service.dart` — background encoding/decoding, serialized atomic writes, generation guard.
- `export_service.dart` — content-sized export region, plots rendered, PDF aspect preserved.
- `board_painter.dart` — static `paintElements`, `hiddenIds`, identity-based repaint.
- `background_painter.dart` — repaint from transform listenable.
- `whiteboard_canvas.dart` — gesture `ChangeNotifier`, drag preview, interpolated erasing, wheel/trackpad/middle-drag pan-zoom, fit-to-content, text editing, shift-selection, focal-point fix.
- `whiteboard_screen.dart` — shortcuts, Space-to-pan, save/leave error handling, `PopScope`, assistant panel, responsive app bar.
- `toolbar_widget.dart` — eraser mode toggle, shortcut hints.
- `unified_bottom_bar.dart` — Duplicate, Fit buttons.
- `math_suggestion_overlay.dart` — AI error pill with Settings link.
- `ai_recognition_settings_dialog.dart` — provider/key/model section.
- `interactive_plot_widget.dart` — drag preview offset.
- `math_calculator_dialog.dart`, `universal_math_engine.dart`, `function_plotter_and_graph_test.dart` — analyzer fixes.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Ctrl/Cmd+Z · Ctrl+Shift+Z / Ctrl+Y | Undo · Redo |
| Ctrl+C / X / V / D | Copy / Cut / Paste / Duplicate |
| Ctrl+A · Delete/Backspace · Esc | Select all · Delete selection · Clear selection & dismiss suggestions |
| Ctrl+S | Save |
| Ctrl+K | Toggle AI Assistant |
| Ctrl + / − / 0 · Shift+1 | Zoom in / out / reset · Fit content |
| Ctrl+wheel · wheel · Shift+wheel · middle/right drag | Zoom · Pan vertical · Pan horizontal · Pan |
| Hold Space | Temporary pan |
| P M H E (E again = partial) S T V L | Pen, Marker, Highlighter, Eraser, Shapes, Text, Select, Laser |
| PageUp / PageDown | Previous / next page |

Single-letter shortcuts are ignored while a text field has focus (tested).

## Not done (and why)

- **Collaboration, auth, authorization, cloud** — no backend exists; this is a new system requiring infrastructure and product decisions (hosting, identity provider, data residency for minors). Design sketch in `COMPETITOR_GAP_ANALYSIS.md` §4.
- **Live AI verification** — no API key available in this environment; AI layer verified against a mock server only.
- **On-device profiling** — benchmarks are headless; see `PERFORMANCE_REPORT.md` for the recommended device run.
- **Resize/rotate handles, pressure ink, image objects, LaTeX, recording** — tracked as roadmap items.
