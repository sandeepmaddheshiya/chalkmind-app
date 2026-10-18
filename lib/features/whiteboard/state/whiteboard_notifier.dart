import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../core/storage/project_storage_service.dart';
import '../../../core/storage/recovery_service.dart';
import '../history/board_command.dart';
import '../history/history_manager.dart';
import '../models/background_style.dart';
import '../models/page_model.dart';
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
  final HistoryManager _historyManager = HistoryManager(maxHistoryDepth: 60);
  Timer? _visionAiDebounceTimer;
  int _visionAiRequestId = 0;

  @override
  WhiteboardState build() {
    _storageService = ref.watch(projectStorageProvider);
    _recoveryService = ref.watch(recoveryServiceProvider);

    final initialProject = ProjectModel.createEmpty();
    return WhiteboardState(project: initialProject);
  }

  void loadProject(ProjectModel project) {
    _historyManager.clear();
    state = state.copyWith(
      project: project,
      canUndo: false,
      canRedo: false,
      selectedObjectIds: {},
    );
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
      state = state.copyWith(
        currentTool: tool,
        selectedObjectIds: {},
      );
    }
  }

  void setColor(int colorValue) {
    final updatedPresets = Map<ToolType, ToolPreset>.from(state.toolPresets);
    if (updatedPresets.containsKey(state.currentTool)) {
      updatedPresets[state.currentTool] =
          updatedPresets[state.currentTool]!.copyWith(colorValue: colorValue);
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
      updatedPresets[state.currentTool] =
          updatedPresets[state.currentTool]!.copyWith(strokeWidth: clamped);
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
    state = state.copyWith(
      zoomScale: zoom.clamp(0.25, 5.0),
      panOffset: pan,
    );
  }

  void resetZoom() {
    state = state.copyWith(zoomScale: 1.0, panOffset: Offset.zero);
  }

  // --- Drawing & Content Mutations ---

  void addStroke(Stroke stroke) {
    final command = AddStrokeCommand(stroke);
    _executeCommand(command);

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
          // Debounce Vision AI by 500ms to avoid flooding upstream workers on every pen touch
          _visionAiDebounceTimer?.cancel();
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
        final detection = ShapeDetector.detectShape(stroke) ??
            ShapeDetector.detectMultiStrokeShape(state.project.currentPage.strokes);

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

  void _triggerVisionAiMath(List<Stroke> strokes) async {
    if (strokes.isEmpty) {
      state = state.copyWith(isCalculatingMath: false);
      return;
    }
    final pageId = state.project.currentPage.id;
    final requestId = ++_visionAiRequestId;

    debugPrint('WhiteboardNotifier: triggering Vision AI on ${strokes.length} strokes (req #$requestId)');

    try {
      final aiResult = await AiMathService.solveWithVisionAI(strokes: strokes);
      if (requestId != _visionAiRequestId) {
        debugPrint('WhiteboardNotifier: ignoring stale Vision AI response for req #$requestId');
        return;
      }

      debugPrint('WhiteboardNotifier: Vision AI result = ${aiResult?.expression} ${aiResult?.answer}');
      if (aiResult != null) {
        if (state.project.currentPage.id == pageId) {
          state = state.copyWith(
            handwritingMathResult: () => aiResult,
            isCalculatingMath: false,
            shapeSuggestion: () => null,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('WhiteboardNotifier: Vision AI error: $e');
    }

    if (requestId == _visionAiRequestId) {
      state = state.copyWith(isCalculatingMath: false);
    }
  }

  void acceptShapeSuggestion() {
    final suggestion = state.shapeSuggestion;
    if (suggestion == null) return;

    if (suggestion.originalStrokes != null && suggestion.originalStrokes!.isNotEmpty) {
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

    final generatedStrokes = HandwritingStrokeGenerator.generateHandwrittenStrokes(
      text: mathResult.answer,
      startPosition: mathResult.insertPosition,
      characterHeight: mathResult.characterHeight,
      colorValue: mathResult.strokeColorValue,
      strokeWidth: mathResult.strokeWidth,
      direction: mathResult.direction,
      normal: mathResult.normal,
      toolType: state.currentTool,
    );

    for (final s in generatedStrokes) {
      final cmd = AddStrokeCommand(s);
      _executeCommand(cmd);
    }

    _visionAiDebounceTimer?.cancel();
    state = state.copyWith(
      handwritingMathResult: () => null,
      isCalculatingMath: false,
    );
  }

  void dismissHandwrittenMath() {
    _visionAiDebounceTimer?.cancel();
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
    final localResult = HandwritingMathEngine.detectHandwrittenEquation(selectedStrokes);
    if (localResult != null) {
      state = state.copyWith(
        handwritingMathResult: () => localResult,
        isCalculatingMath: false,
        shapeSuggestion: () => null,
      );
      return;
    }

    // 2. Multimodal AI solving for selected strokes
    _triggerVisionAiMath(selectedStrokes);
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

  void eraseAtPoint(Offset point, {double radius = 20.0}) {
    final currentPage = state.project.currentPage;

    // 1. Check stroke collisions
    final hitStrokes = <Stroke>[];
    final hitIndices = <int>[];

    for (int i = 0; i < currentPage.strokes.length; i++) {
      final s = currentPage.strokes[i];
      if (s.hitTest(point, threshold: radius)) {
        hitStrokes.add(s);
        hitIndices.add(i);
      }
    }

    // 2. Check shape collisions
    final hitShapes = <ShapeObject>[];
    for (final shape in currentPage.shapes) {
      if (shape.hitTest(point, threshold: radius)) {
        hitShapes.add(shape);
      }
    }

    // 3. Check text collisions
    final hitTexts = <TextObject>[];
    for (final text in currentPage.texts) {
      if (text.hitTest(point)) {
        hitTexts.add(text);
      }
    }

    if (hitStrokes.isNotEmpty || hitShapes.isNotEmpty || hitTexts.isNotEmpty) {
      final command = DeleteElementsCommand(
        strokes: hitStrokes,
        shapes: hitShapes,
        texts: hitTexts,
      );
      _executeCommand(command);
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

  void clearCurrentPage() {
    final page = state.project.currentPage;
    if (page.isEmpty) return;

    final command = ClearPageCommand(
      previousStrokes: page.strokes,
      previousShapes: page.shapes,
      previousTexts: page.texts,
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

    final command = DeleteElementsCommand(
      strokes: strokesToDelete,
      shapes: shapesToDelete,
      texts: textsToDelete,
    );
    _executeCommand(command);
    state = state.copyWith(selectedObjectIds: {});
  }

  void translateSelected(Offset delta) {
    if (state.selectedObjectIds.isEmpty) return;
    final page = state.project.currentPage;

    final updatedStrokes = page.strokes.map((s) {
      return state.selectedObjectIds.contains(s.id) ? s.translate(delta) : s;
    }).toList();

    final updatedShapes = page.shapes.map((s) {
      return state.selectedObjectIds.contains(s.id) ? s.translate(delta) : s;
    }).toList();

    final updatedTexts = page.texts.map((t) {
      return state.selectedObjectIds.contains(t.id) ? t.translate(delta) : t;
    }).toList();

    final newPage = page.copyWith(
      strokes: updatedStrokes,
      shapes: updatedShapes,
      texts: updatedTexts,
    );
    _updateCurrentPage(newPage);
  }

  void undo() {
    if (!_historyManager.canUndo) return;
    final newPage = _historyManager.undo(state.project.currentPage);
    _updateCurrentPage(newPage);
  }

  void redo() {
    if (!_historyManager.canRedo) return;
    final newPage = _historyManager.redo(state.project.currentPage);
    _updateCurrentPage(newPage);
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

    _historyManager.clear();
    state = state.copyWith(
      project: updatedProject,
      canUndo: false,
      canRedo: false,
      selectedObjectIds: {},
    );
    _recoveryService.scheduleRecoverySave(updatedProject);
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
        updatedPages[i].copyWith(pageNumber: i + 1)
    ];

    final updatedProject = state.project.copyWith(
      pages: reindexed,
      currentPageIndex: insertIdx,
      updatedAt: DateTime.now(),
    );

    _historyManager.clear();
    state = state.copyWith(
      project: updatedProject,
      canUndo: false,
      canRedo: false,
      selectedObjectIds: {},
    );
    _recoveryService.scheduleRecoverySave(updatedProject);
  }

  void deleteCurrentPage() {
    if (state.project.pages.length <= 1) {
      // Don't delete only page; clear it instead
      clearCurrentPage();
      return;
    }

    final updatedPages = List<PageModel>.from(state.project.pages)
      ..removeAt(state.project.currentPageIndex);

    // Re-index
    final reindexed = [
      for (int i = 0; i < updatedPages.length; i++)
        updatedPages[i].copyWith(pageNumber: i + 1)
    ];

    final newIndex = (state.project.currentPageIndex >= reindexed.length)
        ? reindexed.length - 1
        : state.project.currentPageIndex;

    final updatedProject = state.project.copyWith(
      pages: reindexed,
      currentPageIndex: newIndex,
      updatedAt: DateTime.now(),
    );

    _historyManager.clear();
    state = state.copyWith(
      project: updatedProject,
      canUndo: false,
      canRedo: false,
      selectedObjectIds: {},
    );
    _recoveryService.scheduleRecoverySave(updatedProject);
  }

  void selectPage(int index) {
    if (index < 0 || index >= state.project.pages.length) return;
    if (index == state.project.currentPageIndex) return;

    _historyManager.clear();
    state = state.copyWith(
      project: state.project.copyWith(currentPageIndex: index),
      canUndo: false,
      canRedo: false,
      selectedObjectIds: {},
    );
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
    _storageService.saveProject(updated);
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
    _recoveryService.scheduleRecoverySave(updatedProject);
  }
}
