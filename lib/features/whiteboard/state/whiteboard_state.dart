import 'package:flutter/material.dart';
import '../models/project_model.dart';
import '../models/tool_type.dart';
import '../pdf/pdf_text_index.dart';
import '../recognition/handwriting_math_engine.dart';
import '../recognition/math_evaluator.dart';
import '../recognition/shape_detector.dart';

class WhiteboardState {
  final ProjectModel project;
  final ToolType currentTool;
  final ShapeType selectedShapeType;
  final int selectedColorValue;
  final double selectedStrokeWidth;
  final bool isShapeFilled;
  final double selectedFontSize;
  final Set<String> selectedObjectIds;
  final bool canUndo;
  final bool canRedo;
  final bool isLeftHanded;
  final bool isSaving;
  final double zoomScale;
  final Offset panOffset;
  final ShapeDetectionResult? shapeSuggestion;
  final MathEvaluationResult? detectedMathResult;
  final HandwritingMathResult? handwritingMathResult;
  final bool isCalculatingMath;

  /// User-facing message from the last failed AI request (null = no error).
  final String? aiErrorMessage;

  /// Text just highlighted on a PDF page, offered for look-up (null = none).
  final HighlightedText? pdfLookup;
  final bool isAutoShapeEnabled;
  final bool isAutoMathEnabled;
  final bool isInfiniteCanvas;
  final Map<ToolType, ToolPreset> toolPresets;

  const WhiteboardState({
    required this.project,
    this.currentTool = ToolType.pen,
    this.selectedShapeType = ShapeType.rectangle,
    this.selectedColorValue = 0xFF111827, // Authentic Indian Ink Black
    this.selectedStrokeWidth = 3.5,
    this.isShapeFilled = false,
    this.selectedFontSize = 22.0,
    this.selectedObjectIds = const {},
    this.canUndo = false,
    this.canRedo = false,
    this.isLeftHanded = false,
    this.isSaving = false,
    this.isCalculatingMath = false,
    this.aiErrorMessage,
    this.pdfLookup,
    this.isAutoShapeEnabled = true,
    this.isAutoMathEnabled = true,
    this.isInfiniteCanvas = false,
    this.zoomScale = 1.0,
    this.panOffset = Offset.zero,
    this.shapeSuggestion,
    this.detectedMathResult,
    this.handwritingMathResult,
    this.toolPresets = defaultPresets,
  });

  Color get selectedColor => Color(selectedColorValue);

  WhiteboardState copyWith({
    ProjectModel? project,
    ToolType? currentTool,
    ShapeType? selectedShapeType,
    int? selectedColorValue,
    double? selectedStrokeWidth,
    bool? isShapeFilled,
    double? selectedFontSize,
    Set<String>? selectedObjectIds,
    bool? canUndo,
    bool? canRedo,
    bool? isLeftHanded,
    bool? isSaving,
    bool? isCalculatingMath,
    String? Function()? aiErrorMessage,
    HighlightedText? Function()? pdfLookup,
    bool? isAutoShapeEnabled,
    bool? isAutoMathEnabled,
    bool? isInfiniteCanvas,
    double? zoomScale,
    Offset? panOffset,
    ShapeDetectionResult? Function()? shapeSuggestion,
    MathEvaluationResult? Function()? detectedMathResult,
    HandwritingMathResult? Function()? handwritingMathResult,
    Map<ToolType, ToolPreset>? toolPresets,
  }) {
    return WhiteboardState(
      project: project ?? this.project,
      currentTool: currentTool ?? this.currentTool,
      selectedShapeType: selectedShapeType ?? this.selectedShapeType,
      selectedColorValue: selectedColorValue ?? this.selectedColorValue,
      selectedStrokeWidth: selectedStrokeWidth ?? this.selectedStrokeWidth,
      isShapeFilled: isShapeFilled ?? this.isShapeFilled,
      selectedFontSize: selectedFontSize ?? this.selectedFontSize,
      selectedObjectIds: selectedObjectIds ?? this.selectedObjectIds,
      canUndo: canUndo ?? this.canUndo,
      canRedo: canRedo ?? this.canRedo,
      isLeftHanded: isLeftHanded ?? this.isLeftHanded,
      isSaving: isSaving ?? this.isSaving,
      isCalculatingMath: isCalculatingMath ?? this.isCalculatingMath,
      aiErrorMessage: aiErrorMessage != null
          ? aiErrorMessage()
          : this.aiErrorMessage,
      pdfLookup: pdfLookup != null ? pdfLookup() : this.pdfLookup,
      isAutoShapeEnabled: isAutoShapeEnabled ?? this.isAutoShapeEnabled,
      isAutoMathEnabled: isAutoMathEnabled ?? this.isAutoMathEnabled,
      isInfiniteCanvas: isInfiniteCanvas ?? this.isInfiniteCanvas,
      zoomScale: zoomScale ?? this.zoomScale,
      panOffset: panOffset ?? this.panOffset,
      shapeSuggestion: shapeSuggestion != null
          ? shapeSuggestion()
          : this.shapeSuggestion,
      detectedMathResult: detectedMathResult != null
          ? detectedMathResult()
          : this.detectedMathResult,
      handwritingMathResult: handwritingMathResult != null
          ? handwritingMathResult()
          : this.handwritingMathResult,
      toolPresets: toolPresets ?? this.toolPresets,
    );
  }

  // Authentic teacher stationery palette (natural, non-synthetic, high-contrast)
  static const List<int> standardPalette = [
    0xFF111827, // Indian Ink / Charcoal Black
    0xFF1E3A8A, // Prussian / Oxford Blue
    0xFFB91C1C, // Classroom Crimson Correction Red
    0xFF047857, // Chalkboard Emerald Green
    0xFF6D28D9, // Deep Violet / Indigo
    0xFFD97706, // Warm Amber Orange
    0xFF059669, // Forest Green
    0xFFF9FAFB, // Chalk White (for dark boards)
  ];

  // Vibrant pastel highlighter palette
  static const List<int> highlighterPalette = [
    0xFFFACC15, // Fluorescent Sunlight Yellow
    0xFF4ADE80, // Fresh Mint Green
    0xFF38BDF8, // Vivid Sky Blue
    0xFFF472B6, // Neon Bubblegum Pink
    0xFFFB923C, // Vivid Tangerine Orange
    0xFFC084FC, // Soft Lavender Purple
  ];

  static const Map<ToolType, ToolPreset> defaultPresets = {
    ToolType.pen: ToolPreset(colorValue: 0xFF111827, strokeWidth: 3.5),
    ToolType.pencil: ToolPreset(colorValue: 0xFF4B5563, strokeWidth: 2.0),
    ToolType.marker: ToolPreset(colorValue: 0xFF1E3A8A, strokeWidth: 8.0),
    ToolType.highlighter: ToolPreset(colorValue: 0xFFFACC15, strokeWidth: 22.0),
  };
}

class ToolPreset {
  final int colorValue;
  final double strokeWidth;

  const ToolPreset({required this.colorValue, required this.strokeWidth});

  Color get color => Color(colorValue);

  ToolPreset copyWith({int? colorValue, double? strokeWidth}) {
    return ToolPreset(
      colorValue: colorValue ?? this.colorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}
