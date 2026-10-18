import 'package:flutter/material.dart';
import '../models/project_model.dart';
import '../models/tool_type.dart';
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
    this.zoomScale = 1.0,
    this.panOffset = Offset.zero,
    this.shapeSuggestion,
    this.detectedMathResult,
    this.handwritingMathResult,
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
    double? zoomScale,
    Offset? panOffset,
    ShapeDetectionResult? Function()? shapeSuggestion,
    MathEvaluationResult? Function()? detectedMathResult,
    HandwritingMathResult? Function()? handwritingMathResult,
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
      zoomScale: zoomScale ?? this.zoomScale,
      panOffset: panOffset ?? this.panOffset,
      shapeSuggestion: shapeSuggestion != null ? shapeSuggestion() : this.shapeSuggestion,
      detectedMathResult: detectedMathResult != null ? detectedMathResult() : this.detectedMathResult,
      handwritingMathResult: handwritingMathResult != null ? handwritingMathResult() : this.handwritingMathResult,
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
    0xFFF59E0B, // Highlighter Gold
    0xFFF9FAFB, // Chalk White (for dark boards)
  ];
}
