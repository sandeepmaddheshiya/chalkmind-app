import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/ai/ai_config.dart';
import '../../../core/ai/openrouter_client.dart';
import '../../../core/backend/backend.dart';
import '../../../core/storage/project_storage_service.dart';
import '../../../core/storage/recovery_service.dart';
import '../history/board_command.dart';
import '../history/history_manager.dart';
import '../models/background_style.dart';
import '../models/page_model.dart';
import '../models/pdf_page_attachment.dart';
import '../models/plot_model.dart';
import '../models/project_model.dart';
import '../models/shape_model.dart';
import '../models/stroke_model.dart';
import '../models/text_model.dart';
import '../models/tool_type.dart';
import 'whiteboard_state.dart';

import '../recognition/ai_math_service.dart';
import '../recognition/handwriting_math_engine.dart';
import '../recognition/handwriting_stroke_generator.dart';
import '../recognition/math_evaluator.dart';
import '../recognition/shape_detector.dart';
import '../pdf/pdf_text_index.dart';

final projectStorageProvider = Provider<ProjectStorageService>((ref) {
  return ProjectStorageService();
});

final recoveryServiceProvider = Provider<RecoveryService>((ref) {
  return RecoveryService();
});

final whiteboardControllerProvider =
    NotifierProvider<WhiteboardNotifier, WhiteboardState>(() {
      return WhiteboardNotifier();
    });

class WhiteboardNotifier extends Notifier<WhiteboardState> {
  late final ProjectStorageService _storageService;
  late final RecoveryService _recoveryService;

  /// Undo history is kept per page so switching pages no longer wipes it.
  final Map<String, HistoryManager> _histories = {};
  HistoryManager get _historyManager => _histories.putIfAbsent(
    state.project.currentPage.id,
    () => HistoryManager(maxHistoryDepth: 60),
  );
  Timer? _visionAiDebounceTimer;
  int _visionAiRequestId = 0;
  AiCancelToken? _aiCancelToken;
  bool _shownMissingKeyHint = false;

  // Live eraser gesture: page snapshot taken at gesture start; the whole
  // gesture is recorded as one undo step at the end.
  PageModel? _eraseSnapshot;

  // Internal clipboard for copy / cut / paste / duplicate.
  _ClipboardContent? _clipboard;
  int _pasteCount = 0;

  static const _uuid = Uuid();

  @override
  WhiteboardState build() {
    _storageService = ref.watch(projectStorageProvider);
    _recoveryService = ref.watch(recoveryServiceProvider);

    ref.onDispose(() {
      _autosaveTimer?.cancel();
      _visionAiDebounceTimer?.cancel();
      _aiCancelToken?.cancel();
    });

    final initialProject = ProjectModel.createEmpty();
    return WhiteboardState(project: initialProject);
  }

  void loadProject(ProjectModel project) {
    // Summaries (home screen listing) have no drawing; editing and autosaving
    // one would wipe the board. Callers must load the full board first.
    if (project.isSummary) {
      throw ArgumentError('Load the full board (not its listing summary) before opening it');
    }
    _histories.clear();
    _cancelPendingAi();
    _eraseSnapshot = null;
    state = state.copyWith(
      project: project,
      canUndo: false,
      canRedo: false,
      selectedObjectIds: {},
      zoomScale: 1.0,
      panOffset: Offset.zero,
      isCalculatingMath: false,
      shapeSuggestion: () => null,
      handwritingMathResult: () => null,
      aiErrorMessage: () => null,
      pdfLookup: () => null,
    );
  }

  void _cancelPendingAi() {
    _visionAiDebounceTimer?.cancel();
    _aiCancelToken?.cancel();
    _aiCancelToken = null;
    _visionAiRequestId++;
  }

  void dismissAiError() {
    state = state.copyWith(aiErrorMessage: () => null);
  }

  void setTool(ToolType tool) {
    final preset = state.toolPresets[tool];
    if (preset != null) {
      state = state.copyWith(
        currentTool: tool,
        selectedColorValue: preset.colorValue,
        selectedStrokeWidth: preset.strokeWidth,
        selectedObjectIds: {},
      );
    } else {
      state = state.copyWith(currentTool: tool, selectedObjectIds: {});
    }
  }

  void setColor(int colorValue) {
    final updatedPresets = Map<ToolType, ToolPreset>.from(state.toolPresets);
    if (updatedPresets.containsKey(state.currentTool)) {
      updatedPresets[state.currentTool] = updatedPresets[state.currentTool]!
          .copyWith(colorValue: colorValue);
    }
    state = state.copyWith(
      selectedColorValue: colorValue,
      toolPresets: updatedPresets,
    );
  }

  void setStrokeWidth(double width) {
    final clamped = width.clamp(1.0, 48.0);
    final updatedPresets = Map<ToolType, ToolPreset>.from(state.toolPresets);
    if (updatedPresets.containsKey(state.currentTool)) {
      updatedPresets[state.currentTool] = updatedPresets[state.currentTool]!
          .copyWith(strokeWidth: clamped);
    }
    state = state.copyWith(
      selectedStrokeWidth: clamped,
      toolPresets: updatedPresets,
    );
  }

  void setShapeType(ShapeType shapeType) {
    state = state.copyWith(selectedShapeType: shapeType);
  }

  void toggleShapeFilled() {
    state = state.copyWith(isShapeFilled: !state.isShapeFilled);
  }

  void setFontSize(double size) {
    state = state.copyWith(selectedFontSize: size.clamp(12.0, 72.0));
  }

  void toggleLeftHanded() {
    state = state.copyWith(isLeftHanded: !state.isLeftHanded);
  }

  void setZoomAndPan(double zoom, Offset pan) {
    final z = zoom.clamp(0.10, 6.0);
    if (z == state.zoomScale && pan == state.panOffset) return;
    state = state.copyWith(zoomScale: z, panOffset: pan);
  }

  void resetZoom() {
    state = state.copyWith(zoomScale: 1.0, panOffset: Offset.zero);
  }

  // --- Drawing & Content Mutations ---

  void addStroke(Stroke stroke) {
    final command = AddStrokeCommand(stroke);
    _executeCommand(command);

    // Any new ink replaces a pending PDF look-up offer.
    if (state.pdfLookup != null) state = state.copyWith(pdfLookup: () => null);

    // Highlighter strokes are for marking text, never shapes or equations.
    // On an imported PDF page they offer a meaning / explanation look-up.
    if (stroke.toolType == ToolType.highlighter) {
      final pdf = state.project.currentPage.pdf;
      if (pdf != null) _offerLookup(pdf, stroke);
      return;
    }

    if (stroke.toolType.isDrawingTool) {
      // 1. Check if the latest strokes form an equation ending with '=' (if Auto Math is enabled)
      if (state.isAutoMathEnabled) {
        final equationStrokes = HandwritingMathEngine.getEquationStrokes(
          state.project.currentPage.strokes,
        );

        if (equationStrokes != null && equationStrokes.length >= 2) {
          // Teacher is writing a math equation!
          // Suppress any geometric shape suggestion
          if (state.shapeSuggestion != null) {
            state = state.copyWith(shapeSuggestion: () => null);
          }

          // STEP 1: Fast real-time local evaluation (0ms latency!)
          final localResult = HandwritingMathEngine.detectHandwrittenEquation(
            state.project.currentPage.strokes,
          );

          if (localResult != null) {
            _visionAiDebounceTimer?.cancel();
            // Solved instantly in real time (0ms)!
            state = state.copyWith(
              handwritingMathResult: () => localResult,
              isCalculatingMath: false,
              shapeSuggestion: () => null,
            );
            return;
          }

          // STEP 2: If local evaluation didn't resolve (e.g. geometry diagram, triangle with unknown x):
          // Debounce Vision AI by 500ms to avoid flooding upstream workers on every pen touch.
          // Signed out: say so once per session (with a Sign in shortcut)
          // instead of failing silently, then stay quiet.
          _visionAiDebounceTimer?.cancel();
          if (!ref.read(aiConfigProvider).isConfigured) {
            if (!_shownMissingKeyHint) {
              _shownMissingKeyHint = true;
              state = state.copyWith(
                aiErrorMessage: () =>
                    'This needs the AI solver (geometry, word problems, chemistry...). '
                    'Sign in with Google to turn it on.',
              );
            }
            return;
          }
          state = state.copyWith(isCalculatingMath: true);
          _visionAiDebounceTimer = Timer(const Duration(milliseconds: 500), () {
            final problemStrokes = HandwritingMathEngine.getProblemStrokes(
              state.project.currentPage.strokes,
            );
            _triggerVisionAiMath(problemStrokes);
          });
          return;
        }
      }

      // 2. Geometric Shape Recognition (if Auto Shape is enabled)
      if (state.isAutoShapeEnabled) {
        final detection =
            ShapeDetector.detectShape(stroke) ??
            ShapeDetector.detectMultiStrokeShape(
              state.project.currentPage.strokes,
            );

        if (detection != null) {
          state = state.copyWith(
            shapeSuggestion: () => detection,
            handwritingMathResult: () => null,
          );
        } else {
          if (state.shapeSuggestion != null) {
            state = state.copyWith(shapeSuggestion: () => null);
          }
          if (state.handwritingMathResult != null) {
            state = state.copyWith(handwritingMathResult: () => null);
          }
        }
      }
    }
  }

  Future<void> _triggerVisionAiMath(
    List<Stroke> strokes, {
    bool userInitiated = false,
  }) async {
    if (strokes.isEmpty) {
      state = state.copyWith(isCalculatingMath: false);
      return;
    }
    final config = ref.read(aiConfigProvider);
    if (!config.isConfigured) {
      if (userInitiated) AiBackend.requestGate(AiGateReason.signInRequired);
      state = state.copyWith(
        isCalculatingMath: false,
        aiErrorMessage: userInitiated
            ? () => const AiException(AiErrorKind.notConfigured, '').userMessage
            : null,
      );
      return;
    }

    // Only the newest request matters: cancel any in-flight one.
    _aiCancelToken?.cancel();
    final token = _aiCancelToken = AiCancelToken();
    final pageId = state.project.currentPage.id;
    final requestId = ++_visionAiRequestId;
    state = state.copyWith(isCalculatingMath: true, aiErrorMessage: () => null);

    HandwritingMathResult? aiResult;
    String? error;
    try {
      aiResult = await AiMathService.solveWithVisionAI(
        strokes: strokes,
        config: config,
        cancelToken: token,
        interactive: userInitiated,
      );
    } on AiException catch (e) {
      if (e.kind != AiErrorKind.cancelled) {
        debugPrint('WhiteboardNotifier: Vision AI error: $e');
        error = e.userMessage;
      }
    } catch (e) {
      debugPrint('WhiteboardNotifier: Vision AI error: $e');
      error = const AiException(AiErrorKind.badResponse, '').userMessage;
    }

    // Ignore stale responses (newer request, page switch, or disposal).
    if (!ref.mounted || requestId != _visionAiRequestId) return;
    if (identical(_aiCancelToken, token)) _aiCancelToken = null;

    if (aiResult != null && state.project.currentPage.id == pageId) {
      state = state.copyWith(
        handwritingMathResult: () => aiResult,
        isCalculatingMath: false,
        shapeSuggestion: () => null,
      );
      return;
    }
    state = state.copyWith(
      isCalculatingMath: false,
      aiErrorMessage: (error != null || userInitiated)
          ? () => error ?? 'No solvable math found in the selection.'
          : null,
    );
  }

  Future<void> _offerLookup(PdfPageAttachment pdf, Stroke stroke) async {
    final pageId = state.project.currentPage.id;
    final found = await PdfTextIndex.forStroke(pdf, stroke);
    // Ignore if the user moved on (other page, or more ink since).
    if (!ref.mounted || found == null) return;
    final page = state.project.currentPage;
    if (page.id != pageId ||
        page.strokes.isEmpty ||
        page.strokes.last.id != stroke.id) {
      return;
    }
    state = state.copyWith(pdfLookup: () => found, shapeSuggestion: () => null);
  }

  void dismissPdfLookup() => state = state.copyWith(pdfLookup: () => null);

  /// Inserts imported PDF pages after the current page and opens the first.
  void insertPages(List<PageModel> newPages) {
    if (newPages.isEmpty) return;
    final at = state.project.currentPageIndex + 1;
    final pages = List<PageModel>.from(state.project.pages)
      ..insertAll(at, newPages);
    _switchToProject(
      state.project.copyWith(
        pages: [
          for (int i = 0; i < pages.length; i++)
            pages[i].copyWith(pageNumber: i + 1),
        ],
        currentPageIndex: at,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void acceptShapeSuggestion() {
    final suggestion = state.shapeSuggestion;
    if (suggestion == null) return;

    if (suggestion.originalStrokes != null &&
        suggestion.originalStrokes!.isNotEmpty) {
      final command = ReplaceStrokesWithShapeCommand(
        originalStrokes: suggestion.originalStrokes!,
        shape: suggestion.suggestedShape,
      );
      _executeCommand(command);
    } else {
      final command = ReplaceStrokeWithShapeCommand(
        originalStroke: suggestion.originalStroke,
        shape: suggestion.suggestedShape,
      );
      _executeCommand(command);
    }
    state = state.copyWith(shapeSuggestion: () => null);
  }

  void dismissShapeSuggestion() {
    state = state.copyWith(shapeSuggestion: () => null);
  }

  void acceptHandwrittenMath() {
    final mathResult = state.handwritingMathResult;
    if (mathResult == null) return;

    // The handwriting writer only knows digits, basic operators and a few
    // letters. Anything else (chemical formulas, units, words) is placed as
    // typed text in the same spot instead of being drawn as scribbles.
    if (!HandwritingStrokeGenerator.canWrite(mathResult.answer)) {
      final height = mathResult.characterHeight.clamp(18.0, 64.0);
      _executeCommand(
        AddElementsCommand(
          description: 'Write Answer',
          texts: [
            TextObject(
              id: _uuid.v4(),
              text: mathResult.answer,
              position: mathResult.insertPosition,
              fontSize: height * 0.8,
              colorValue: mathResult.strokeColorValue,
            ),
          ],
        ),
      );
      _visionAiDebounceTimer?.cancel();
      state = state.copyWith(
        handwritingMathResult: () => null,
        isCalculatingMath: false,
      );
      return;
    }

    final generatedStrokes =
        HandwritingStrokeGenerator.generateHandwrittenStrokes(
          text: mathResult.answer,
          startPosition: mathResult.insertPosition,
          characterHeight: mathResult.characterHeight,
          colorValue: mathResult.strokeColorValue,
          strokeWidth: mathResult.strokeWidth,
          direction: mathResult.direction,
          normal: mathResult.normal,
          toolType: state.currentTool,
        );

    // One undo step for the whole written answer (not one per pen stroke).
    if (generatedStrokes.isNotEmpty) {
      _executeCommand(
        AddElementsCommand(
          description: 'Write Answer',
          strokes: generatedStrokes,
        ),
      );
    }

    _visionAiDebounceTimer?.cancel();
    state = state.copyWith(
      handwritingMathResult: () => null,
      isCalculatingMath: false,
    );
  }

  void dismissHandwrittenMath() {
    _cancelPendingAi();
    state = state.copyWith(
      handwritingMathResult: () => null,
      isCalculatingMath: false,
    );
  }

  void toggleAutoShape() {
    state = state.copyWith(isAutoShapeEnabled: !state.isAutoShapeEnabled);
  }

  void toggleAutoMath() {
    state = state.copyWith(isAutoMathEnabled: !state.isAutoMathEnabled);
  }

  void setAutoShape(bool enabled) {
    state = state.copyWith(isAutoShapeEnabled: enabled);
  }

  void setAutoMath(bool enabled) {
    state = state.copyWith(isAutoMathEnabled: enabled);
  }

  void setInfiniteCanvas(bool isInfinite) {
    state = state.copyWith(isInfiniteCanvas: isInfinite);
  }

  void toggleCanvasMode() {
    state = state.copyWith(isInfiniteCanvas: !state.isInfiniteCanvas);
  }

  /// Solves only the strokes currently selected by the teacher using the selection tool
  Future<void> solveSelectedStrokes() async {
    final selectedIds = state.selectedObjectIds;
    if (selectedIds.isEmpty) return;

    final selectedStrokes = state.project.currentPage.strokes
        .where((s) => selectedIds.contains(s.id))
        .toList();

    if (selectedStrokes.isEmpty) return;

    _visionAiDebounceTimer?.cancel();
    state = state.copyWith(isCalculatingMath: true);

    // 1. Try local 0ms solver on selected strokes first
    final localResult = HandwritingMathEngine.detectHandwrittenEquation(
      selectedStrokes,
    );
    if (localResult != null) {
      state = state.copyWith(
        handwritingMathResult: () => localResult,
        isCalculatingMath: false,
        shapeSuggestion: () => null,
      );
      return;
    }

    // 2. Multimodal AI solving for selected strokes
    await _triggerVisionAiMath(selectedStrokes, userInitiated: true);
  }

  /// Inserts pedagogical step-by-step mathematical reasoning directly onto the whiteboard
  void insertMathSteps(HandwritingMathResult result) {
    final buffer = StringBuffer();
    buffer.writeln('${result.expression} ${result.answer}');
    if (result.steps.isNotEmpty) {
      buffer.writeln('');
      for (int i = 0; i < result.steps.length; i++) {
        buffer.writeln('Step ${i + 1}: ${result.steps[i]}');
      }
    }
    if (result.explanation != null && result.explanation!.isNotEmpty) {
      buffer.writeln('');
      buffer.writeln('Explanation: ${result.explanation}');
    }

    final pos = result.insertPosition + const Offset(0, 35);
    final textObj = TextObject(
      id: const Uuid().v4(),
      text: buffer.toString().trim(),
      position: pos,
      fontSize: 16.0,
      colorValue: result.strokeColorValue,
      isBold: false,
    );
    final cmd = AddTextCommand(textObj);
    _executeCommand(cmd);
    state = state.copyWith(handwritingMathResult: () => null);
  }

  void insertMathCalculation(String equationText, {Offset? position}) {
    final mathResult = MathEvaluator.evaluate(equationText);
    if (mathResult == null) return;

    final pos = position ?? const Offset(100, 150);
    final textObj = TextObject(
      id: const Uuid().v4(),
      text: mathResult.fullEquation,
      position: pos,
      fontSize: state.selectedFontSize,
      colorValue: state.selectedColorValue,
      isBold: true,
    );
    addText(textObj);
  }

  void insertStepByStepWorking(String formattedText, {Offset? position}) {
    if (formattedText.trim().isEmpty) return;
    final pos = position ?? const Offset(80, 120);
    final textObj = TextObject(
      id: const Uuid().v4(),
      text: formattedText,
      position: pos,
      fontSize: 18.0,
      colorValue: state.selectedColorValue,
      isBold: false,
    );
    addText(textObj);
  }

  static const double eraserRadius = 18.0;

  /// Starts an eraser gesture. All erasing until [endEraseGesture] becomes a
  /// single undo step.
  void beginEraseGesture() {
    _eraseSnapshot = state.project.currentPage;
  }

  /// Erases along the pointer path from [from] to [to]. The segment is
  /// sampled so fast swipes don't skip over thin strokes.
  /// Stroke eraser removes whole objects; area eraser splits strokes and
  /// removes only the ink under the eraser.
  void eraseAlong(Offset from, Offset to, {double radius = eraserRadius}) {
    final page = state.project.currentPage;
    final partial = state.currentTool == ToolType.areaEraser;

    final dist = (to - from).distance;
    final steps = math.max(1, (dist / (radius * 0.5)).ceil());
    final samples = <Offset>[
      for (int i = 0; i <= steps; i++) Offset.lerp(from, to, i / steps)!,
    ];
    final sweep = Rect.fromPoints(from, to).inflate(radius);

    bool changed = false;
    final newStrokes = <Stroke>[];
    for (final s in page.strokes) {
      if (!s.bounds.overlaps(sweep)) {
        newStrokes.add(s);
        continue;
      }
      if (partial) {
        var pieces = <Stroke>[s];
        bool hit = false;
        for (final c in samples) {
          final next = <Stroke>[];
          for (final pc in pieces) {
            final r = pc.eraseCircle(c, radius, _uuid.v4);
            if (r == null) {
              next.add(pc);
            } else {
              hit = true;
              next.addAll(r);
            }
          }
          pieces = next;
          if (pieces.isEmpty) break;
        }
        if (hit) {
          changed = true;
          newStrokes.addAll(pieces);
        } else {
          newStrokes.add(s);
        }
      } else if (samples.any((c) => s.hitTest(c, threshold: radius))) {
        changed = true;
      } else {
        newStrokes.add(s);
      }
    }

    final newShapes = <ShapeObject>[];
    for (final sh in page.shapes) {
      if (sh.bounds.inflate(radius).overlaps(sweep) &&
          samples.any((c) => sh.hitTest(c, threshold: radius))) {
        changed = true;
      } else {
        newShapes.add(sh);
      }
    }

    final newTexts = <TextObject>[];
    for (final t in page.texts) {
      final b = t.bounds;
      if (b.inflate(radius).overlaps(sweep) && samples.any(b.contains)) {
        changed = true;
      } else {
        newTexts.add(t);
      }
    }

    if (!changed) return;
    final newPage = page.copyWith(
      strokes: newStrokes,
      shapes: newShapes,
      texts: newTexts,
    );
    if (_eraseSnapshot == null) {
      // Not inside a gesture: record immediately as its own undo step.
      _recordDiff(page, newPage, 'Erase');
    } else {
      _setCurrentPageLive(newPage);
    }
  }

  /// Ends the eraser gesture and records everything erased as one undo step.
  void endEraseGesture() {
    final before = _eraseSnapshot;
    _eraseSnapshot = null;
    if (before == null) return;
    final after = state.project.currentPage;
    if (identical(before, after) || before.id != after.id) return;
    _recordDiff(before, after, 'Erase', alreadyApplied: true);
  }

  /// Single-point erase (kept for compatibility; one undo step per call).
  void eraseAtPoint(Offset point, {double radius = eraserRadius}) =>
      eraseAlong(point, point, radius: radius);

  /// Records the difference between two versions of the current page as one
  /// order-preserving undoable command.
  void _recordDiff(
    PageModel before,
    PageModel after,
    String description, {
    bool alreadyApplied = false,
  }) {
    List<T> missing<T>(List<T> a, List<T> b, String Function(T) id) {
      final ids = b.map(id).toSet();
      return [
        for (final e in a)
          if (!ids.contains(id(e))) e,
      ];
    }

    final cmd = ReplaceElementsCommand(
      description: description,
      removedStrokes: missing(before.strokes, after.strokes, (e) => e.id),
      removedShapes: missing(before.shapes, after.shapes, (e) => e.id),
      removedTexts: missing(before.texts, after.texts, (e) => e.id),
      removedPlots: missing(before.plots, after.plots, (e) => e.id),
      addedStrokes: missing(after.strokes, before.strokes, (e) => e.id),
      addedShapes: missing(after.shapes, before.shapes, (e) => e.id),
      addedTexts: missing(after.texts, before.texts, (e) => e.id),
      addedPlots: missing(after.plots, before.plots, (e) => e.id),
    );
    if (cmd.isEmpty) return;
    if (alreadyApplied) {
      cmd.captureOrder(before);
      _historyManager.push(cmd);
      _updateCurrentPage(after);
    } else {
      _executeCommand(cmd);
    }
  }

  void addShape(ShapeObject shape) {
    final command = AddShapeCommand(shape);
    _executeCommand(command);
  }

  void addText(TextObject text) {
    final command = AddTextCommand(text);
    _executeCommand(command);
  }

  void updateText(TextObject oldText, TextObject newText) {
    final command = UpdateTextCommand(oldText: oldText, newText: newText);
    _executeCommand(command);
  }

  void setBackground(CanvasBackground newBg) {
    final command = ChangeBackgroundCommand(
      oldBackground: state.project.currentPage.background,
      newBackground: newBg,
    );
    _executeCommand(command);
  }

  void addPlot(PlotObject plot) {
    _executeCommand(
      AddElementsCommand(description: 'Add Graph', plots: [plot]),
    );
  }

  /// Live plot edits (pan / zoom of the coordinate plane, dragging the card)
  /// update continuously during gestures, so they are not individual undo
  /// steps. They are still autosaved.
  void updatePlot(PlotObject updatedPlot) {
    final page = state.project.currentPage;
    final updatedPlots = page.plots
        .map((p) => p.id == updatedPlot.id ? updatedPlot : p)
        .toList();
    _setCurrentPageLive(page.copyWith(plots: updatedPlots));
  }

  void deletePlot(String plotId) {
    final page = state.project.currentPage;
    final victims = page.plots.where((p) => p.id == plotId).toList();
    if (victims.isEmpty) return;
    _executeCommand(DeleteElementsCommand(plots: victims));
  }

  void plotEquation(String equation, {Offset? position}) {
    final pos = position ?? const Offset(80, 160);
    final top = math.max(64.0, pos.dy);
    final plot = PlotObject(
      id: const Uuid().v4(),
      equation: equation,
      rect: Rect.fromLTWH(pos.dx, top, 420, 360),
    );
    addPlot(plot);
  }

  void clearCurrentPage() {
    final page = state.project.currentPage;
    if (page.isEmpty) return;

    final command = ClearPageCommand(
      previousStrokes: page.strokes,
      previousShapes: page.shapes,
      previousTexts: page.texts,
      previousPlots: page.plots,
    );
    _executeCommand(command);
  }

  void setSelectedObjects(Set<String> ids) {
    state = state.copyWith(selectedObjectIds: ids);
  }

  void clearSelection() {
    setSelectedObjects({});
  }

  void deleteSelected() {
    if (state.selectedObjectIds.isEmpty) return;
    final page = state.project.currentPage;

    final strokesToDelete = page.strokes
        .where((s) => state.selectedObjectIds.contains(s.id))
        .toList();
    final shapesToDelete = page.shapes
        .where((s) => state.selectedObjectIds.contains(s.id))
        .toList();
    final textsToDelete = page.texts
        .where((t) => state.selectedObjectIds.contains(t.id))
        .toList();
    final plotsToDelete = page.plots
        .where((p) => state.selectedObjectIds.contains(p.id))
        .toList();

    final command = DeleteElementsCommand(
      strokes: strokesToDelete,
      shapes: shapesToDelete,
      texts: textsToDelete,
      plots: plotsToDelete,
    );
    _executeCommand(command);
    state = state.copyWith(selectedObjectIds: {});
  }

  /// Moves the selection by [delta] as one undoable step. The canvas shows a
  /// live preview during the drag and calls this once on release.
  void translateSelected(Offset delta) {
    if (state.selectedObjectIds.isEmpty || delta == Offset.zero) return;
    _executeCommand(
      MoveElementsCommand(Set.of(state.selectedObjectIds), delta),
    );
  }

  void selectAll() {
    final page = state.project.currentPage;
    state = state.copyWith(
      currentTool: ToolType.select,
      selectedObjectIds: {
        for (final s in page.strokes) s.id,
        for (final s in page.shapes) s.id,
        for (final t in page.texts) t.id,
        for (final p in page.plots) p.id,
      },
    );
  }

  _ClipboardContent? _selectionContent() {
    final ids = state.selectedObjectIds;
    if (ids.isEmpty) return null;
    final page = state.project.currentPage;
    final c = _ClipboardContent(
      strokes: page.strokes.where((e) => ids.contains(e.id)).toList(),
      shapes: page.shapes.where((e) => ids.contains(e.id)).toList(),
      texts: page.texts.where((e) => ids.contains(e.id)).toList(),
      plots: page.plots.where((e) => ids.contains(e.id)).toList(),
    );
    return c.isEmpty ? null : c;
  }

  bool get hasClipboard => _clipboard != null;

  void copySelected() {
    final c = _selectionContent();
    if (c == null) return;
    _clipboard = c;
    _pasteCount = 0;
  }

  void cutSelected() {
    copySelected();
    deleteSelected();
  }

  /// Pastes clipboard content offset from the original (cascading on repeated
  /// pastes), selects it, and records one undo step.
  void pasteClipboard() {
    final c = _clipboard;
    if (c == null) return;
    _pasteCount++;
    _insertCopies(c, Offset(24.0 * _pasteCount, 24.0 * _pasteCount), 'Paste');
  }

  void duplicateSelected() {
    final c = _selectionContent();
    if (c == null) return;
    _insertCopies(c, const Offset(24, 24), 'Duplicate');
  }

  void _insertCopies(_ClipboardContent c, Offset d, String description) {
    final strokes = [
      for (final s in c.strokes) s.translate(d).copyWith(id: _uuid.v4()),
    ];
    final shapes = [
      for (final s in c.shapes) s.translate(d).copyWith(id: _uuid.v4()),
    ];
    final texts = [
      for (final t in c.texts) t.translate(d).copyWith(id: _uuid.v4()),
    ];
    final plots = [
      for (final p in c.plots)
        p.copyWith(id: _uuid.v4(), rect: p.rect.shift(d)),
    ];
    _executeCommand(
      AddElementsCommand(
        description: description,
        strokes: strokes,
        shapes: shapes,
        texts: texts,
        plots: plots,
      ),
    );
    state = state.copyWith(
      currentTool: ToolType.select,
      selectedObjectIds: {
        ...strokes.map((e) => e.id),
        ...shapes.map((e) => e.id),
        ...texts.map((e) => e.id),
        ...plots.map((e) => e.id),
      },
    );
  }

  /// Inserts a group of new elements (e.g. an AI-generated diagram) as one
  /// undoable step and selects it so it can be moved immediately.
  void insertElements({
    List<Stroke> strokes = const [],
    List<ShapeObject> shapes = const [],
    List<TextObject> texts = const [],
    List<PlotObject> plots = const [],
    String description = 'Insert',
    bool select = true,
  }) {
    if (strokes.isEmpty && shapes.isEmpty && texts.isEmpty && plots.isEmpty) {
      return;
    }
    _executeCommand(
      AddElementsCommand(
        description: description,
        strokes: strokes,
        shapes: shapes,
        texts: texts,
        plots: plots,
      ),
    );
    if (select) {
      state = state.copyWith(
        currentTool: ToolType.select,
        selectedObjectIds: {
          ...strokes.map((e) => e.id),
          ...shapes.map((e) => e.id),
          ...texts.map((e) => e.id),
          ...plots.map((e) => e.id),
        },
      );
    }
  }

  void undo() {
    if (_eraseSnapshot != null) endEraseGesture();
    if (!_historyManager.canUndo) return;
    final newPage = _historyManager.undo(state.project.currentPage);
    _updateCurrentPage(newPage);
    _pruneSelection();
  }

  void redo() {
    if (!_historyManager.canRedo) return;
    final newPage = _historyManager.redo(state.project.currentPage);
    _updateCurrentPage(newPage);
    _pruneSelection();
  }

  /// Drops selected ids that no longer exist on the page (after undo / redo).
  void _pruneSelection() {
    if (state.selectedObjectIds.isEmpty) return;
    final page = state.project.currentPage;
    final alive = <String>{
      for (final s in page.strokes) s.id,
      for (final s in page.shapes) s.id,
      for (final t in page.texts) t.id,
      for (final p in page.plots) p.id,
    };
    final kept = state.selectedObjectIds.where(alive.contains).toSet();
    if (kept.length != state.selectedObjectIds.length) {
      state = state.copyWith(selectedObjectIds: kept);
    }
  }

  // --- Page Navigation & Management ---

  void addNewPage() {
    const uuid = Uuid();
    final newPage = PageModel(
      id: uuid.v4(),
      pageNumber: state.project.pages.length + 1,
      background: state.project.currentPage.background,
    );

    final updatedPages = [...state.project.pages, newPage];
    final updatedProject = state.project.copyWith(
      pages: updatedPages,
      currentPageIndex: updatedPages.length - 1,
      updatedAt: DateTime.now(),
    );

    _switchToProject(updatedProject);
  }

  void duplicateCurrentPage() {
    const uuid = Uuid();
    final current = state.project.currentPage;
    final duplicate = current.copyWith(
      id: uuid.v4(),
      pageNumber: state.project.pages.length + 1,
    );

    final updatedPages = List<PageModel>.from(state.project.pages);
    final insertIdx = state.project.currentPageIndex + 1;
    updatedPages.insert(insertIdx, duplicate);

    // Re-index page numbers
    final reindexed = [
      for (int i = 0; i < updatedPages.length; i++)
        updatedPages[i].copyWith(pageNumber: i + 1),
    ];

    final updatedProject = state.project.copyWith(
      pages: reindexed,
      currentPageIndex: insertIdx,
      updatedAt: DateTime.now(),
    );

    _switchToProject(updatedProject);
  }

  void deleteCurrentPage() {
    if (state.project.pages.length <= 1) {
      // Don't delete only page; clear it instead
      clearCurrentPage();
      return;
    }

    _histories.remove(state.project.currentPage.id);
    final updatedPages = List<PageModel>.from(state.project.pages)
      ..removeAt(state.project.currentPageIndex);

    // Re-index
    final reindexed = [
      for (int i = 0; i < updatedPages.length; i++)
        updatedPages[i].copyWith(pageNumber: i + 1),
    ];

    final newIndex = (state.project.currentPageIndex >= reindexed.length)
        ? reindexed.length - 1
        : state.project.currentPageIndex;

    final updatedProject = state.project.copyWith(
      pages: reindexed,
      currentPageIndex: newIndex,
      updatedAt: DateTime.now(),
    );

    _switchToProject(updatedProject);
  }

  void deletePage(int index) {
    if (state.project.pages.length <= 1) {
      clearCurrentPage();
      return;
    }
    if (index < 0 || index >= state.project.pages.length) return;

    _histories.remove(state.project.pages[index].id);
    final updatedPages = List<PageModel>.from(state.project.pages)
      ..removeAt(index);

    final reindexed = [
      for (int i = 0; i < updatedPages.length; i++)
        updatedPages[i].copyWith(pageNumber: i + 1),
    ];

    int newIndex = state.project.currentPageIndex;
    if (index < newIndex) {
      newIndex--;
    } else if (newIndex >= reindexed.length) {
      newIndex = reindexed.length - 1;
    }

    final updatedProject = state.project.copyWith(
      pages: reindexed,
      currentPageIndex: newIndex,
      updatedAt: DateTime.now(),
    );

    _switchToProject(updatedProject);
  }

  void selectPage(int index) {
    if (index < 0 || index >= state.project.pages.length) return;
    if (index == state.project.currentPageIndex) return;

    _cancelPendingAi();
    final updated = state.project.copyWith(currentPageIndex: index);
    final h = _histories[updated.currentPage.id];
    state = state.copyWith(
      project: updated,
      canUndo: h?.canUndo ?? false,
      canRedo: h?.canRedo ?? false,
      selectedObjectIds: {},
      isCalculatingMath: false,
      shapeSuggestion: () => null,
      handwritingMathResult: () => null,
      pdfLookup: () => null,
    );
    // Persist the page change so recovery reopens on the right page.
    _scheduleAutosave(updated);
  }

  void nextPage() {
    if (state.project.currentPageIndex < state.project.pages.length - 1) {
      selectPage(state.project.currentPageIndex + 1);
    }
  }

  void previousPage() {
    if (state.project.currentPageIndex > 0) {
      selectPage(state.project.currentPageIndex - 1);
    }
  }

  void renameProject(String title) {
    final updated = state.project.copyWith(
      title: title.trim().isEmpty ? 'Untitled Whiteboard' : title.trim(),
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(project: updated);
    _storageService.saveProject(updated).catchError((Object e) {
      debugPrint('WhiteboardNotifier: rename save failed: $e');
    });
  }

  Future<void> saveProject() async {
    state = state.copyWith(isSaving: true);
    try {
      final updated = state.project.copyWith(
        updatedAt: DateTime.now(),
        recoveryStatus: false,
      );
      await _storageService.saveProject(updated);
      await _recoveryService.clearRecoveryDraft();
      state = state.copyWith(project: updated, isSaving: false);
    } catch (e) {
      state = state.copyWith(isSaving: false);
      rethrow;
    }
  }

  // --- Private Helpers ---

  void _executeCommand(BoardCommand command) {
    final newPage = _historyManager.execute(command, state.project.currentPage);
    _updateCurrentPage(newPage);
  }

  /// Switches to a project with a different page set/index (page add,
  /// duplicate, delete) while keeping each page's own undo history.
  void _switchToProject(ProjectModel updatedProject) {
    _cancelPendingAi();
    final h = _histories[updatedProject.currentPage.id];
    state = state.copyWith(
      project: updatedProject,
      canUndo: h?.canUndo ?? false,
      canRedo: h?.canRedo ?? false,
      selectedObjectIds: {},
      isCalculatingMath: false,
      shapeSuggestion: () => null,
      handwritingMathResult: () => null,
      pdfLookup: () => null,
    );
    _scheduleAutosave(updatedProject);
  }

  Timer? _autosaveTimer;

  /// Saves the board to its project file shortly after every change, as well
  /// as to the crash-recovery draft. Boards then always appear in the home
  /// list, even if the app is closed without pressing Back or Save (the
  /// single recovery slot used to be overwritten by the next board).
  void _scheduleAutosave(ProjectModel project) {
    _recoveryService.scheduleRecoverySave(project);
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 800), () {
      _storageService.saveProject(project).catchError((Object e) {
        debugPrint('WhiteboardNotifier: autosave failed: $e');
      });
    });
  }

  /// Applies a page change that is not its own undo step (live gesture
  /// previews, plot viewport changes). Still autosaved.
  void _setCurrentPageLive(PageModel newPage) {
    final pages = List<PageModel>.from(state.project.pages);
    pages[state.project.currentPageIndex] = newPage;
    final updatedProject = state.project.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );
    state = state.copyWith(project: updatedProject);
    _scheduleAutosave(updatedProject);
  }

  void _updateCurrentPage(PageModel newPage) {
    final pages = List<PageModel>.from(state.project.pages);
    pages[state.project.currentPageIndex] = newPage;

    final updatedProject = state.project.copyWith(
      pages: pages,
      updatedAt: DateTime.now(),
    );

    state = state.copyWith(
      project: updatedProject,
      canUndo: _historyManager.canUndo,
      canRedo: _historyManager.canRedo,
    );

    // Continuous autosave to crash recovery draft
    _scheduleAutosave(updatedProject);
  }
}

class _ClipboardContent {
  final List<Stroke> strokes;
  final List<ShapeObject> shapes;
  final List<TextObject> texts;
  final List<PlotObject> plots;
  const _ClipboardContent({
    required this.strokes,
    required this.shapes,
    required this.texts,
    required this.plots,
  });
  bool get isEmpty =>
      strokes.isEmpty && shapes.isEmpty && texts.isEmpty && plots.isEmpty;
}
