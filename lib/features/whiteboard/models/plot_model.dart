import 'package:flutter/material.dart';

class PlotObject {
  final String id;
  final String equation;
  final Rect rect; // Canvas bounding box for the plot card
  final double xMin;
  final double xMax;
  final double yMin;
  final double yMax;
  final int colorValue; // ARGB int
  final bool showKeyPoints;
  final bool showGrid;
  final bool isMinimized;

  const PlotObject({
    required this.id,
    required this.equation,
    required this.rect,
    this.xMin = -6.0,
    this.xMax = 6.0,
    this.yMin = -6.0,
    this.yMax = 6.0,
    this.colorValue = 0xFF2563EB, // Primary blue curve
    this.showKeyPoints = true,
    this.showGrid = true,
    this.isMinimized = false,
  });

  Color get curveColor => Color(colorValue);

  PlotObject copyWith({
    String? id,
    String? equation,
    Rect? rect,
    double? xMin,
    double? xMax,
    double? yMin,
    double? yMax,
    int? colorValue,
    bool? showKeyPoints,
    bool? showGrid,
    bool? isMinimized,
  }) {
    return PlotObject(
      id: id ?? this.id,
      equation: equation ?? this.equation,
      rect: rect ?? this.rect,
      xMin: xMin ?? this.xMin,
      xMax: xMax ?? this.xMax,
      yMin: yMin ?? this.yMin,
      yMax: yMax ?? this.yMax,
      colorValue: colorValue ?? this.colorValue,
      showKeyPoints: showKeyPoints ?? this.showKeyPoints,
      showGrid: showGrid ?? this.showGrid,
      isMinimized: isMinimized ?? this.isMinimized,
    );
  }

  /// Zooms the coordinate plane centered around the origin or current center.
  PlotObject zoom(double factor) {
    final centerX = (xMin + xMax) / 2;
    final centerY = (yMin + yMax) / 2;
    final halfSpanX = ((xMax - xMin) / 2) * factor;
    final halfSpanY = ((yMax - yMin) / 2) * factor;

    // Clamp zoom bounds so it doesn't underflow or overflow
    if (halfSpanX < 0.5 || halfSpanX > 200.0) return this;

    return copyWith(
      xMin: centerX - halfSpanX,
      xMax: centerX + halfSpanX,
      yMin: centerY - halfSpanY,
      yMax: centerY + halfSpanY,
    );
  }

  /// Pans the coordinate plane in mathematical coordinates.
  PlotObject pan(double dxMath, double dyMath) {
    return copyWith(
      xMin: xMin + dxMath,
      xMax: xMax + dxMath,
      yMin: yMin + dyMath,
      yMax: yMax + dyMath,
    );
  }

  /// Resets the coordinate plane to default standard range.
  PlotObject resetView() {
    return copyWith(xMin: -6.0, xMax: 6.0, yMin: -6.0, yMax: 6.0);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'equation': equation,
    'left': rect.left,
    'top': rect.top,
    'width': rect.width,
    'height': rect.height,
    'xMin': xMin,
    'xMax': xMax,
    'yMin': yMin,
    'yMax': yMax,
    'colorValue': colorValue,
    'showKeyPoints': showKeyPoints,
    'showGrid': showGrid,
    'isMinimized': isMinimized,
  };

  factory PlotObject.fromJson(Map<String, dynamic> json) {
    return PlotObject(
      id: json['id'] as String,
      equation: json['equation'] as String? ?? 'y = x^2 - 4',
      rect: Rect.fromLTWH(
        (json['left'] as num?)?.toDouble() ?? 100.0,
        (json['top'] as num?)?.toDouble() ?? 200.0,
        (json['width'] as num?)?.toDouble() ?? 420.0,
        (json['height'] as num?)?.toDouble() ?? 360.0,
      ),
      xMin: (json['xMin'] as num?)?.toDouble() ?? -6.0,
      xMax: (json['xMax'] as num?)?.toDouble() ?? 6.0,
      yMin: (json['yMin'] as num?)?.toDouble() ?? -6.0,
      yMax: (json['yMax'] as num?)?.toDouble() ?? 6.0,
      colorValue: json['colorValue'] as int? ?? 0xFF2563EB,
      showKeyPoints: json['showKeyPoints'] as bool? ?? true,
      showGrid: json['showGrid'] as bool? ?? true,
      isMinimized: json['isMinimized'] as bool? ?? false,
    );
  }
}
