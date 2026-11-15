import 'package:flutter/material.dart';

enum BackgroundStyle {
  plain,
  grid,
  ruled,
  dotted,
  graph,
  isometric,
  polar;

  String get displayName {
    switch (this) {
      case BackgroundStyle.plain:
        return 'Plain';
      case BackgroundStyle.grid:
        return 'Grid';
      case BackgroundStyle.ruled:
        return 'Ruled Lines';
      case BackgroundStyle.dotted:
        return 'Dotted';
      case BackgroundStyle.graph:
        return 'Graph Paper';
      case BackgroundStyle.isometric:
        return 'Isometric 3D';
      case BackgroundStyle.polar:
        return 'Polar Coordinates';
    }
  }
}

class CanvasBackground {
  final BackgroundStyle style;
  final int colorValue; // ARGB int
  final double
  spacing; // Spacing in points (e.g. 28.0 for ruled lines, 32.0 for grid)
  final int patternColorValue; // ARGB int for grid/ruled lines

  const CanvasBackground({
    this.style = BackgroundStyle.plain,
    this.colorValue = 0xFFFFFFFF,
    this.spacing = 32.0,
    this.patternColorValue = 0x26000000, // 15% opacity black
  });

  Color get color => Color(colorValue);
  Color get patternColor => Color(patternColorValue);

  bool get isDark {
    final c = Color(colorValue);
    // Standard relative luminance check
    return c.computeLuminance() < 0.4;
  }

  CanvasBackground copyWith({
    BackgroundStyle? style,
    int? colorValue,
    double? spacing,
    int? patternColorValue,
  }) {
    return CanvasBackground(
      style: style ?? this.style,
      colorValue: colorValue ?? this.colorValue,
      spacing: spacing ?? this.spacing,
      patternColorValue: patternColorValue ?? this.patternColorValue,
    );
  }

  Map<String, dynamic> toJson() => {
    'style': style.name,
    'colorValue': colorValue,
    'spacing': spacing,
    'patternColorValue': patternColorValue,
  };

  factory CanvasBackground.fromJson(Map<String, dynamic> json) {
    return CanvasBackground(
      style: BackgroundStyle.values.firstWhere(
        (e) => e.name == json['style'],
        orElse: () => BackgroundStyle.plain,
      ),
      colorValue: json['colorValue'] as int? ?? 0xFFFFFFFF,
      spacing: (json['spacing'] as num?)?.toDouble() ?? 32.0,
      patternColorValue: json['patternColorValue'] as int? ?? 0x26000000,
    );
  }

  static const List<int> presetColors = [
    0xFFFFFFFF, // Clean White
    0xFFFBF8F2, // Warm Cream
    0xFF1E222B, // Dark Slate
    0xFF16382B, // Blackboard Green
  ];
}
