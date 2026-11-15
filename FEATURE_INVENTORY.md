# Feature Inventory

Status key: ✅ fully functional · 🟡 functional, needs improvement · 🟠 partial · 🔴 broken · ⚪ missing · 🐢 implemented but inefficient.
"Before" = state found during the audit; "After" = state after this round of work (verified by tests listed in `TEST_REPORT.md` unless noted).

## Drawing & canvas

| Feature | Before | After | Notes |
|---|---|---|---|
| Pen / pencil / marker / highlighter | 🐢 | ✅ | Whole-canvas rebuild per pointer move removed |
| Per-tool colour & width presets | ✅ | ✅ | |
| Stylus palm rejection | ✅ | ✅ | Logic preserved |
| Pressure-sensitive width | ⚪ | ⚪ | Pressure stored, not rendered |
| Shapes tool (11 shapes, fill) | ✅ | ✅ | |
| Text tool — add | ✅ | ✅ | |
| Text — edit existing | ⚪ | ✅ | Text tool tap / select double-tap |
| Stroke eraser | 🐢🔴 | ✅ | Was 1 undo step per sample, skipped strokes on fast swipes |
| Partial (area) eraser | 🟠 | ✅ | Enum existed, unreachable; now splits strokes |
| Laser pointer | ✅ | ✅ | No trail (gap vs Explain Everything) |
| Selection: tap / marquee | 🐢 | ✅ | Now includes plots; Shift adds/toggles |
| Selection: move | 🔴 | ✅ | Not undoable before; per-frame page rewrites |
| Resize / rotate selection | ⚪ | ⚪ | Handles drawn but not interactive |
| Copy / cut / paste / duplicate | ⚪ | ✅ | Ctrl+C/X/V/D + bottom-bar Duplicate |
| Select all | ⚪ | ✅ | Ctrl+A |
| Undo / redo | 🟠 | ✅ | Per-page, z-order-preserving, moves & plots included |
| Pan (hand tool, two-finger) | ✅ | ✅ | |
| Pinch zoom | 🟡 | ✅ | Focal-point offset fixed; no rebuild per frame |
| Mouse wheel / trackpad pan-zoom | ⚪ | ✅ | Ctrl+wheel zoom, wheel pan, trackpad pinch, middle/right-drag pan |
| Fit to content | ⚪ | ✅ | Bottom bar + Shift+1 |
| Infinite vs paginated canvas | ✅ | ✅ | |
| Backgrounds (plain/grid/lined/dots, dark) | ✅ | ✅ | Now repaints from transform without rebuild |
| Layers | ⚪ | ⚪ | `layerId` field exists, unused |

## Pages & files

| Feature | Before | After | Notes |
|---|---|---|---|
| Multi-page: add / duplicate / delete / navigate | ✅ | ✅ | PageUp/PageDown added |
| Save (manual) | 🟡 | ✅ | Errors now reported; off-UI-thread encoding |
| Save on leave | 🟠 | ✅ | System back now saves; failure dialog |
| Crash-recovery autosave | 🐢 | ✅ | Was 255 ms UI freeze; now atomic & background |
| Restore recovery draft | ✅ | ✅ | |
| Home: recent boards, templates, delete | ✅ | ✅ | List decoding moved off UI thread |
| Rename board | ✅ | ✅ | Save error no longer unhandled |
| Export PNG | 🔴 | ✅ | Cropped below y≈1080; plots missing |
| Export PDF | 🔴 | ✅ | Same + aspect distortion |
| Share sheet | ✅ | ✅ | |
| Import boards / files | ⚪ | ⚪ | |
| File format backward compatibility | — | ✅ | v2 compact points; v1 files still load (tested) |

## Recognition & math (on-device)

| Feature | Before | After |
|---|---|---|
| Auto shape recognition (single & multi-stroke) | ✅ | ✅ |
| Handwritten equation detection + instant local solve | ✅ | ✅ |
| Write answer in handwriting style | 🟡 | ✅ (one undo step instead of one per stroke) |
| Insert steps / explanation on board | ✅ | ✅ |
| Math & equation solver dialog (algebra, geometry, trig, calculus catalog) | ✅ | ✅ |
| Function plotter (interactive graphs) | 🟠 | ✅ (history, selection, export integrated) |

## AI

| Feature | Before | After |
|---|---|---|
| Vision math solver (handwriting → solution) | 🔴 (hard-coded leaked key, silent failures) | ✅ (user key, typed errors, cancellation) |
| Solve selected strokes | 🟡 | ✅ (clear error if not configured / nothing found) |
| AI provider settings (key, model) | ⚪ | ✅ |
| AI assistant panel (board-aware, streaming, stop, follow-ups) | ⚪ | ✅ |
| Explain / hint / check my work (identify first mistake) | ⚪ | ✅ |
| Summarize / revision notes / flashcards | ⚪ | ✅ |
| Practice questions / quiz with answer key | ⚪ | ✅ |
| Lesson plan / worksheet generation | ⚪ | ✅ |
| Flowchart / mind map / concept map → **editable** shapes, arrows, text | ⚪ | ✅ |
| Image upload (textbook question / diagram) analysis | ⚪ | ✅ (signature-checked, decoded, downscaled) |
| Insert AI output on board | ⚪ | ✅ (one undo step, auto-selected) |
| LaTeX rendering | ⚪ | ⚪ (Unicode math instead) |
| UML / science diagram generation | ⚪ | 🟠 (flowchart/concept map cover simple cases; no UML notation) |

> Live AI calls were **not** exercised in this environment (no API key available). The AI layer is verified with a mock HTTP server: request format, streaming parser, fallback/auth/timeout/cancel behaviour, response parsing and diagram layout.

## Platform & UX

| Feature | Before | After |
|---|---|---|
| Light / dark theme (system) | ✅ | ✅ |
| Keyboard shortcuts | ⚪ | ✅ (see `IMPLEMENTATION_PROGRESS.md`) |
| Phone-width layout | 🔴 (app bar overflow) | ✅ |
| Tablet / desktop layout | ✅ | ✅ |
| Left-handed toolbar | ✅ | ✅ |
| Draggable / hideable toolbar | ✅ | ✅ |

## Not present (requires new systems)

Authentication, authorization, cloud sync, database, real-time collaboration, WebSockets, teacher-to-student board push, student board monitoring, session recording / replay. See `COMPETITOR_GAP_ANALYSIS.md`.
