import '../models/background_style.dart';
import '../models/page_model.dart';
import '../models/shape_model.dart';
import '../models/stroke_model.dart';
import '../models/text_model.dart';

abstract class BoardCommand {
  String get description;
  PageModel apply(PageModel page);
  PageModel undo(PageModel page);
}

class AddStrokeCommand extends BoardCommand {
  final Stroke stroke;
  AddStrokeCommand(this.stroke);

  @override
  String get description => 'Add Stroke';

  @override
  PageModel apply(PageModel page) {
    return page.copyWith(strokes: [...page.strokes, stroke]);
  }

  @override
  PageModel undo(PageModel page) {
    final updated = page.strokes.where((s) => s.id != stroke.id).toList();
    return page.copyWith(strokes: updated);
  }
}

class DeleteStrokesCommand extends BoardCommand {
  final List<Stroke> deletedStrokes;
  final List<int> originalIndices;

  DeleteStrokesCommand(this.deletedStrokes, this.originalIndices);

  @override
  String get description => 'Erase Strokes (${deletedStrokes.length})';

  @override
  PageModel apply(PageModel page) {
    final idsToRemove = deletedStrokes.map((s) => s.id).toSet();
    final updated =
        page.strokes.where((s) => !idsToRemove.contains(s.id)).toList();
    return page.copyWith(strokes: updated);
  }

  @override
  PageModel undo(PageModel page) {
    final currentStrokes = List<Stroke>.from(page.strokes);
    for (int i = 0; i < deletedStrokes.length; i++) {
      final stroke = deletedStrokes[i];
      final targetIdx = originalIndices[i];
      if (targetIdx <= currentStrokes.length) {
        currentStrokes.insert(targetIdx, stroke);
      } else {
        currentStrokes.add(stroke);
      }
    }
    return page.copyWith(strokes: currentStrokes);
  }
}

class AddShapeCommand extends BoardCommand {
  final ShapeObject shape;
  AddShapeCommand(this.shape);

  @override
  String get description => 'Add ${shape.shapeType.displayName}';

  @override
  PageModel apply(PageModel page) {
    return page.copyWith(shapes: [...page.shapes, shape]);
  }

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(
      shapes: page.shapes.where((s) => s.id != shape.id).toList(),
    );
  }
}

class AddTextCommand extends BoardCommand {
  final TextObject text;
  AddTextCommand(this.text);

  @override
  String get description => 'Add Text';

  @override
  PageModel apply(PageModel page) {
    return page.copyWith(texts: [...page.texts, text]);
  }

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(
      texts: page.texts.where((t) => t.id != text.id).toList(),
    );
  }
}

class UpdateTextCommand extends BoardCommand {
  final TextObject oldText;
  final TextObject newText;

  UpdateTextCommand({required this.oldText, required this.newText});

  @override
  String get description => 'Update Text';

  @override
  PageModel apply(PageModel page) {
    final updated = page.texts.map((t) {
      return t.id == newText.id ? newText : t;
    }).toList();
    return page.copyWith(texts: updated);
  }

  @override
  PageModel undo(PageModel page) {
    final updated = page.texts.map((t) {
      return t.id == oldText.id ? oldText : t;
    }).toList();
    return page.copyWith(texts: updated);
  }
}

class DeleteElementsCommand extends BoardCommand {
  final List<Stroke> strokes;
  final List<ShapeObject> shapes;
  final List<TextObject> texts;

  DeleteElementsCommand({
    this.strokes = const [],
    this.shapes = const [],
    this.texts = const [],
  });

  @override
  String get description => 'Delete Elements';

  @override
  PageModel apply(PageModel page) {
    final strokeIds = strokes.map((s) => s.id).toSet();
    final shapeIds = shapes.map((s) => s.id).toSet();
    final textIds = texts.map((t) => t.id).toSet();

    return page.copyWith(
      strokes: page.strokes.where((s) => !strokeIds.contains(s.id)).toList(),
      shapes: page.shapes.where((s) => !shapeIds.contains(s.id)).toList(),
      texts: page.texts.where((t) => !textIds.contains(t.id)).toList(),
    );
  }

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(
      strokes: [...page.strokes, ...strokes],
      shapes: [...page.shapes, ...shapes],
      texts: [...page.texts, ...texts],
    );
  }
}

class ClearPageCommand extends BoardCommand {
  final List<Stroke> previousStrokes;
  final List<ShapeObject> previousShapes;
  final List<TextObject> previousTexts;

  ClearPageCommand({
    required this.previousStrokes,
    required this.previousShapes,
    required this.previousTexts,
  });

  @override
  String get description => 'Clear Page';

  @override
  PageModel apply(PageModel page) {
    return page.copyWith(strokes: [], shapes: [], texts: []);
  }

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(
      strokes: previousStrokes,
      shapes: previousShapes,
      texts: previousTexts,
    );
  }
}

class ChangeBackgroundCommand extends BoardCommand {
  final CanvasBackground oldBackground;
  final CanvasBackground newBackground;

  ChangeBackgroundCommand({
    required this.oldBackground,
    required this.newBackground,
  });

  @override
  String get description => 'Change Background';

  @override
  PageModel apply(PageModel page) {
    return page.copyWith(background: newBackground);
  }

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(background: oldBackground);
  }
}

class ReplaceStrokeWithShapeCommand extends BoardCommand {
  final Stroke originalStroke;
  final ShapeObject shape;

  ReplaceStrokeWithShapeCommand({
    required this.originalStroke,
    required this.shape,
  });

  @override
  String get description => 'Convert Stroke to ${shape.shapeType.displayName}';

  @override
  PageModel apply(PageModel page) {
    final updatedStrokes =
        page.strokes.where((s) => s.id != originalStroke.id).toList();
    return page.copyWith(
      strokes: updatedStrokes,
      shapes: [...page.shapes, shape],
    );
  }

  @override
  PageModel undo(PageModel page) {
    final updatedShapes =
        page.shapes.where((sh) => sh.id != shape.id).toList();
    return page.copyWith(
      strokes: [...page.strokes, originalStroke],
      shapes: updatedShapes,
    );
  }
}

class ReplaceStrokesWithShapeCommand extends BoardCommand {
  final List<Stroke> originalStrokes;
  final ShapeObject shape;

  ReplaceStrokesWithShapeCommand({
    required this.originalStrokes,
    required this.shape,
  });

  @override
  String get description => 'Convert Strokes to ${shape.shapeType.displayName}';

  @override
  PageModel apply(PageModel page) {
    final removeIds = originalStrokes.map((s) => s.id).toSet();
    final updatedStrokes =
        page.strokes.where((s) => !removeIds.contains(s.id)).toList();
    return page.copyWith(
      strokes: updatedStrokes,
      shapes: [...page.shapes, shape],
    );
  }

  @override
  PageModel undo(PageModel page) {
    final updatedShapes =
        page.shapes.where((sh) => sh.id != shape.id).toList();
    return page.copyWith(
      strokes: [...page.strokes, ...originalStrokes],
      shapes: updatedShapes,
    );
  }
}


