# Performance Report

## Method

`test/perf/engine_benchmark_test.dart` — headless benchmark of UI-thread (Dart) cost on a large board: **2,000 strokes × 60 points + 200 text objects**. Median of 15 runs after warm-up (5 runs for serialization). Machine: the development Linux workstation, `flutter test` (JIT, debug-mode VM), so absolute numbers are pessimistic versus a release build; the *ratios* are what matter.

Run it: `flutter test test/perf/engine_benchmark_test.dart` (prints `BENCH name: value` lines).

**Not measured here:** GPU rasterization, on-device frame times, network latency of AI calls. These need `flutter run --profile` with DevTools on a target tablet, and a configured API key. No claims are made about them.

## Results

| Operation | Baseline | After | Change | Target |
|---|---:|---:|---:|---:|
| Full board repaint (record picture) | 13.62 ms | **1.16 ms** | 11.7× faster | < 16 ms/frame ✅ |
| Bounds of all 200 texts | 7.70 ms | **0.007 ms** | ~1000× | — |
| One eraser pointer sample (scan board) | 6.22 ms | **0.12 ms** | 52× | < 16 ms ✅ |
| Marquee select whole board | 6.23 ms | **0.15 ms** | 41× | < 50 ms ✅ |
| Commit stroke (incl. auto-shape + auto-math checks) | 0.20 ms | 0.22 ms | ≈ | < 16 ms ✅ |
| Undo + redo pair | 0.24 ms | 0.49 ms | slower, still tiny* | < 50 ms ✅ |
| Build save map (`toJson`) | 118.9 ms | **8.6 ms** | 14× | — |
| Full JSON encode | 255.2 ms on UI thread | 107 ms **in background isolate**; ~15–18 ms on UI thread (map build + isolate hand-off, measured separately) | UI-thread cost ~15× lower | no jank |
| Saved file size | 6.55 MB | **2.77 MB** | 2.4× smaller | — |
| Load / decode project | 148.0 ms on UI thread | 38.4 ms, **in background isolate** | 3.9× faster, off UI thread | < 1 s ✅ |

\* Undo/redo is slightly slower because commands now restore exact z-order (index capture). 0.5 ms is two orders of magnitude under the 50 ms target.

## Structural changes behind the numbers

1. **Text layout caching.** `TextObject.bounds` and painting reused a cached `TextPainter` instead of laying out text on every call (Expando cache, carried over on translate).
2. **No widget rebuilds for gesture frames.** Active ink, shape preview, eraser/laser cursor, marquee and drag offset live in a `ChangeNotifier` that drives `CustomPainter(repaint:)` directly. Previously each pointer event called `setState` on the whole canvas subtree (including every plot widget).
3. **Selection drag preview.** Dragged elements are hidden in the board layer and painted by a light overlay at the drag offset; the page is updated once, on release. Previously the page (and board layer) was rewritten every pointer move.
4. **Narrow state subscriptions.** Canvas and screen watch `select()`ed slices; pinch/pan frames no longer rebuild the screen/app bar/canvas. Background repaints from the `TransformationController` listenable.
5. **Board layer repaint only when content changes.** `shouldRepaint` uses identity checks and ignores selection changes (selection is drawn by its own layer).
6. **Serialization.** Flat numeric point arrays (`pts`) instead of per-point maps with string-formatted numbers; encoding/decoding via `compute` (background isolate); writes serialized to avoid temp-file races.
7. **Eraser.** One gesture = one history entry and one snapshot; segment sampling so fast swipes don't skip strokes; bounds pre-filter per segment.
8. **Sub-pixel jitter filter** on pointer samples (< 0.35 px) keeps stroke data lean.

## AI latency design (not measured — no key in this environment)

- AI never runs on the drawing path: auto-solve is debounced 500 ms and skipped entirely without a key; the assistant is non-modal.
- Streaming (SSE) for all assistant text so first tokens render as soon as the provider sends them.
- Cancellation (`AiCancelToken` closes the HTTP client) for stale solves, page switches and the Stop button.
- Bounded context: image downscaled to ≤1024 px (board) / ≤1600 px (uploads); typed text capped at 4,000 chars; last 4 conversation turns; per-action `max_tokens`; image omitted for text-only selections.
- Fallback only on retryable failures (404/408/429/5xx/timeouts). Auth failures fail fast (previously up to ~48 s of retries).

## Next profiling steps (recommended)

1. `flutter run --profile` on a mid-range Android tablet with a 5k-stroke board: check raster thread time during pan/zoom (the board layer is a single picture; if raster > 8 ms, add tiling or `RepaintBoundary` raster caching per region).
2. Measure first-token latency for `google/gemini-2.5-flash` vs `-lite` from the target region once a key is configured.

## Round 2 (PDF import, home screen, app size)

| Area | Before | After | How measured |
|---|---|---|---|
| PDF import | Every page rendered, PNG-encoded and text-indexed up front (cost grows with page count; ~0.5 s+ per page on a mid-range tablet) | Opens the file, reads page sizes, stores one copy of the PDF; time no longer depends on page count | Structural; on-device timings are logged as `PdfImportService: imported N pages in X ms` and `PdfPageRenderer: page N rendered in X ms` |
| Viewing a PDF page | Already rendered at import | Rendered on first view (white page + spinner, drawing still works), cached to disk; next/previous pages prefetched in the background | — |
| PDF page render size | 1800 px wide (~18 MB decoded) | 1500 px (~10 MB decoded), ~25% less work per page | — |
| Home screen list (20 boards × 300 strokes) | 94 ms (full decode of every board) | **2 ms** (small `.meta` summaries) | `test/board_listing_test.dart` |
| Shape recognition per stroke | — | 0.2–1.4 ms (desktop) | ad-hoc benchmark; well under one frame |
| App download for the tablet (arm64) | 78.5 MB universal APK | **27.6 MB** (`--split-per-abi`) | build output |
