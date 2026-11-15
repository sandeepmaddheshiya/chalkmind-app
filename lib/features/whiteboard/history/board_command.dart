import 'dart:ui' show Offset;

import '../models/background_style.dart';
import '../models/page_model.dart';
import '../models/plot_model.dart';
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
    final updated = page.strokes
        .where((s) => !idsToRemove.contains(s.id))
        .toList();
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

/// Generic, order-preserving edit: removes some elements and adds others in
/// one undoable step. Original z-order (list index) of removed elements is
/// captured from the page the command is first applied to, so undo restores
/// them exactly where they were rather than appending to the top.
class ReplaceElementsCommand extends BoardCommand {
  final String _desc;
  final List<Stroke> removedStrokes;
  final List<ShapeObject> removedShapes;
  final List<TextObject> removedTexts;
  final List<PlotObject> removedPlots;
  final List<Stroke> addedStrokes;
  final List<ShapeObject> addedShapes;
  final List<TextObject> addedTexts;
  final List<PlotObject> addedPlots;

  List<int>? _strokeIdx, _shapeIdx, _textIdx, _plotIdx;

  ReplaceElementsCommand({
    String description = 'Edit Elements',
    this.removedStrokes = const [],
    this.removedShapes = const [],
    this.removedTexts = const [],
    this.removedPlots = const [],
    this.addedStrokes = const [],
    this.addedShapes = const [],
    this.addedTexts = const [],
    this.addedPlots = const [],
  }) : _desc = description;

  @override
  String get description => _desc;

  bool get isEmpty =>
      removedStrokes.isEmpty &&
      removedShapes.isEmpty &&
      removedTexts.isEmpty &&
      removedPlots.isEmpty &&
      addedStrokes.isEmpty &&
      addedShapes.isEmpty &&
      addedTexts.isEmpty &&
      addedPlots.isEmpty;

  /// Records the z-order of removed elements as they appear in [before].
  /// Use when the edit was already applied live (e.g. during an eraser drag)
  /// and the command is recorded with [HistoryManager.push].
  void captureOrder(PageModel before) {
    _sortRemovedByCapturedOrder(before);
    _strokeIdx = _indicesOf(
      before.strokes,
      removedStrokes.map((e) => e.id).toSet(),
      (e) => e.id,
    );
    _shapeIdx = _indicesOf(
      before.shapes,
      removedShapes.map((e) => e.id).toSet(),
      (e) => e.id,
    );
    _textIdx = _indicesOf(
      before.texts,
      removedTexts.map((e) => e.id).toSet(),
      (e) => e.id,
    );
    _plotIdx = _indicesOf(
      before.plots,
      removedPlots.map((e) => e.id).toSet(),
      (e) => e.id,
    );
  }

  static List<int> _indicesOf<T>(
    List<T> list,
    Set<String> ids,
    String Function(T) idOf,
  ) {
    final out = <int>[];
    if (ids.isEmpty) return out;
    for (int i = 0; i < list.length; i++) {
      if (ids.contains(idOf(list[i]))) out.add(i);
    }
    return out;
  }

  static List<T> _remove<T>(
    List<T> list,
    List<T> removed,
    List<T> added,
    String Function(T) idOf,
  ) {
    if (removed.isEmpty && added.isEmpty) return list;
    final ids = removed.map(idOf).toSet();
    final addedIds = added.map(idOf).toSet();
    return [
      for (final e in list)
        if (!ids.contains(idOf(e)) && !addedIds.contains(idOf(e))) e,
      ...added,
    ];
  }

  static List<T> _restore<T>(
    List<T> list,
    List<T> removed,
    List<T> added,
    List<int>? indices,
    String Function(T) idOf,
  ) {
    if (removed.isEmpty && added.isEmpty) return list;
    final addedIds = added.map(idOf).toSet();
    final result = [
      for (final e in list)
        if (!addedIds.contains(idOf(e))) e,
    ];
    if (removed.isEmpty) return result;
    // Re-insert in the original order at the original indices.
    final byId = {for (final r in removed) idOf(r): r};
    final ordered = <MapEntry<int, T>>[];
    if (indices != null && indices.length == removed.length) {
      // indices are ascending page positions; match them to removed elements
      // by the order those elements had on the page.
      final removedInPageOrder = removed.toList();
      for (int i = 0; i < indices.length; i++) {
        ordered.add(MapEntry(indices[i], removedInPageOrder[i]));
      }
    } else {
      for (final r in removed) {
        ordered.add(MapEntry(1 << 30, r));
      }
    }
    for (final entry in ordered) {
      if (!byId.containsKey(idOf(entry.value))) continue;
      final at = entry.key.clamp(0, result.length);
      result.insert(at, entry.value);
    }
    return result;
  }

  @override
  PageModel apply(PageModel page) {
    if (_strokeIdx == null) captureOrder(page);
    return page.copyWith(
      strokes: _remove(page.strokes, removedStrokes, addedStrokes, (e) => e.id),
      shapes: _remove(page.shapes, removedShapes, addedShapes, (e) => e.id),
      texts: _remove(page.texts, removedTexts, addedTexts, (e) => e.id),
      plots: _remove(page.plots, removedPlots, addedPlots, (e) => e.id),
    );
  }

  /// Ensures removed* lists are in page order so they pair with indices.
  void _sortRemovedByCapturedOrder(PageModel page) {
    List<T> sortBy<T>(
      List<T> removed,
      List<T> pageList,
      String Function(T) idOf,
    ) {
      final pos = <String, int>{};
      for (int i = 0; i < pageList.length; i++) {
        pos[idOf(pageList[i])] = i;
      }
      return [...removed]..sort(
        (a, b) => (pos[idOf(a)] ?? 1 << 30).compareTo(pos[idOf(b)] ?? 1 << 30),
      );
    }

    _sortedStrokes = sortBy(removedStrokes, page.strokes, (e) => e.id);
    _sortedShapes = sortBy(removedShapes, page.shapes, (e) => e.id);
    _sortedTexts = sortBy(removedTexts, page.texts, (e) => e.id);
    _sortedPlots = sortBy(removedPlots, page.plots, (e) => e.id);
  }

  List<Stroke>? _sortedStrokes;
  List<ShapeObject>? _sortedShapes;
  List<TextObject>? _sortedTexts;
  List<PlotObject>? _sortedPlots;

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(
      strokes: _restore(
        page.strokes,
        _sortedStrokes ?? removedStrokes,
        addedStrokes,
        _strokeIdx,
        (e) => e.id,
      ),
      shapes: _restore(
        page.shapes,
        _sortedShapes ?? removedShapes,
        addedShapes,
        _shapeIdx,
        (e) => e.id,
      ),
      texts: _restore(
        page.texts,
        _sortedTexts ?? removedTexts,
        addedTexts,
        _textIdx,
        (e) => e.id,
      ),
      plots: _restore(
        page.plots,
        _sortedPlots ?? removedPlots,
        addedPlots,
        _plotIdx,
        (e) => e.id,
      ),
    );
  }
}

class DeleteElementsCommand extends ReplaceElementsCommand {
  DeleteElementsCommand({
    List<Stroke> strokes = const [],
    List<ShapeObject> shapes = const [],
    List<TextObject> texts = const [],
    List<PlotObject> plots = const [],
  }) : super(
         description: 'Delete Elements',
         removedStrokes: strokes,
         removedShapes: shapes,
         removedTexts: texts,
         removedPlots: plots,
       );

  List<Stroke> get strokes => removedStrokes;
  List<ShapeObject> get shapes => removedShapes;
  List<TextObject> get texts => removedTexts;
  List<PlotObject> get plots => removedPlots;
}

class AddElementsCommand extends ReplaceElementsCommand {
  AddElementsCommand({
    super.description = 'Add Elements',
    List<Stroke> strokes = const [],
    List<ShapeObject> shapes = const [],
    List<TextObject> texts = const [],
    List<PlotObject> plots = const [],
  }) : super(
         addedStrokes: strokes,
         addedShapes: shapes,
         addedTexts: texts,
         addedPlots: plots,
       );
}

/// Moves elements (by id) by a fixed delta. Undo moves them back.
class MoveElementsCommand extends BoardCommand {
  final Set<String> ids;
  final Offset delta;
  MoveElementsCommand(this.ids, this.delta);

  @override
  String get description => 'Move ${ids.length} element(s)';

  PageModel _move(PageModel page, Offset d) => page.copyWith(
    strokes: [
      for (final s in page.strokes) ids.contains(s.id) ? s.translate(d) : s,
    ],
    shapes: [
      for (final s in page.shapes) ids.contains(s.id) ? s.translate(d) : s,
    ],
    texts: [
      for (final t in page.texts) ids.contains(t.id) ? t.translate(d) : t,
    ],
    plots: [
      for (final p in page.plots)
        ids.contains(p.id) ? p.copyWith(rect: p.rect.shift(d)) : p,
    ],
  );

  @override
  PageModel apply(PageModel page) => _move(page, delta);

  @override
  PageModel undo(PageModel page) => _move(page, -delta);
}

class ClearPageCommand extends BoardCommand {
  final List<Stroke> previousStrokes;
  final List<ShapeObject> previousShapes;
  final List<TextObject> previousTexts;
  final List<PlotObject> previousPlots;

  ClearPageCommand({
    required this.previousStrokes,
    required this.previousShapes,
    required this.previousTexts,
    this.previousPlots = const [],
  });

  @override
  String get description => 'Clear Page';

  @override
  PageModel apply(PageModel page) {
    return page.copyWith(strokes: [], shapes: [], texts: [], plots: []);
  }

  @override
  PageModel undo(PageModel page) {
    return page.copyWith(
      strokes: previousStrokes,
      shapes: previousShapes,
      texts: previousTexts,
      plots: previousPlots,
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
    final updatedStrokes = page.strokes
        .where((s) => s.id != originalStroke.id)
        .toList();
    return page.copyWith(
      strokes: updatedStrokes,
      shapes: [...page.shapes, shape],
    );
  }

  @override
  PageModel undo(PageModel page) {
    final updatedShapes = page.shapes.where((sh) => sh.id != shape.id).toList();
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
    final updatedStrokes = page.strokes
        .where((s) => !removeIds.contains(s.id))
        .toList();
    return page.copyWith(
      strokes: updatedStrokes,
      shapes: [...page.shapes, shape],
    );
  }

  @override
  PageModel undo(PageModel page) {
    final updatedShapes = page.shapes.where((sh) => sh.id != shape.id).toList();
    return page.copyWith(
      strokes: [...page.strokes, ...originalStrokes],
      shapes: updatedShapes,
    );
  }
}
