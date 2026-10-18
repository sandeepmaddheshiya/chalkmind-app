enum ToolType {
  pen,
  pencil,
  marker,
  highlighter,
  strokeEraser,
  areaEraser,
  shape,
  text,
  select,
  laser;

  bool get isDrawingTool =>
      this == ToolType.pen ||
      this == ToolType.pencil ||
      this == ToolType.marker ||
      this == ToolType.highlighter;

  bool get isEraser =>
      this == ToolType.strokeEraser || this == ToolType.areaEraser;

  String get displayName {
    switch (this) {
      case ToolType.pen:
        return 'Pen';
      case ToolType.pencil:
        return 'Pencil';
      case ToolType.marker:
        return 'Marker';
      case ToolType.highlighter:
        return 'Highlighter';
      case ToolType.strokeEraser:
        return 'Stroke Eraser';
      case ToolType.areaEraser:
        return 'Area Eraser';
      case ToolType.shape:
        return 'Shapes';
      case ToolType.text:
        return 'Text';
      case ToolType.select:
        return 'Select';
      case ToolType.laser:
        return 'Laser Pointer';
    }
  }
}

enum ShapeType {
  line,
  arrow,
  rectangle,
  circle,
  triangle,
  star,
  diamond,
  pentagon,
  hexagon,
  heptagon,
  octagon;

  String get displayName {
    switch (this) {
      case ShapeType.line:
        return 'Line';
      case ShapeType.arrow:
        return 'Arrow';
      case ShapeType.rectangle:
        return 'Rectangle';
      case ShapeType.circle:
        return 'Circle / Oval';
      case ShapeType.triangle:
        return 'Triangle';
      case ShapeType.star:
        return 'Star';
      case ShapeType.diamond:
        return 'Diamond';
      case ShapeType.pentagon:
        return 'Pentagon';
      case ShapeType.hexagon:
        return 'Hexagon';
      case ShapeType.heptagon:
        return 'Heptagon';
      case ShapeType.octagon:
        return 'Octagon';
    }
  }
}
