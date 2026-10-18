import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/features/whiteboard/history/board_command.dart';
import 'package:boardflow/features/whiteboard/history/history_manager.dart';
import 'package:boardflow/features/whiteboard/models/background_style.dart';
import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/shape_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';

void main() {
  group('HistoryManager & BoardCommand', () {
    late PageModel page;
    late HistoryManager history;

    setUp(() {
      page = const PageModel(id: 'page-1', pageNumber: 1);
      history = HistoryManager(maxHistoryDepth: 10);
    });

    test('AddStrokeCommand execute and undo', () {
      final stroke = Stroke(
        id: 's-1',
        points: [const StrokePoint(x: 10, y: 10, timestamp: 1)],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      expect(history.canUndo, isFalse);
      page = history.execute(AddStrokeCommand(stroke), page);
      expect(page.strokes.length, 1);
      expect(history.canUndo, isTrue);

      page = history.undo(page);
      expect(page.strokes.isEmpty, isTrue);
      expect(history.canRedo, isTrue);

      page = history.redo(page);
      expect(page.strokes.length, 1);
    });

    test('ClearPageCommand clears and restores previous state', () {
      final stroke = Stroke(
        id: 's-1',
        points: [const StrokePoint(x: 10, y: 10, timestamp: 1)],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );
      const shape = ShapeObject(
        id: 'sh-1',
        shapeType: ShapeType.circle,
        start: Offset(0, 0),
        end: Offset(50, 50),
        strokeColorValue: 0xFF000000,
        strokeWidth: 2.0,
      );

      page = page.copyWith(strokes: [stroke], shapes: [shape]);
      expect(page.totalElements, 2);

      final clearCmd = ClearPageCommand(
        previousStrokes: page.strokes,
        previousShapes: page.shapes,
        previousTexts: page.texts,
      );

      page = history.execute(clearCmd, page);
      expect(page.isEmpty, isTrue);

      page = history.undo(page);
      expect(page.totalElements, 2);
    });

    test('History bounded depth does not grow beyond max limit', () {
      for (int i = 0; i < 20; i++) {
        final stroke = Stroke(
          id: 's-$i',
          points: [StrokePoint(x: i.toDouble(), y: i.toDouble(), timestamp: 1)],
          colorValue: 0xFF000000,
          width: 2.0,
          toolType: ToolType.pen,
        );
        page = history.execute(AddStrokeCommand(stroke), page);
      }

      expect(page.strokes.length, 20);
      expect(history.undoCount, 10); // Clamped at maxHistoryDepth (10)
    });

    test('ChangeBackgroundCommand changes and reverts background', () {
      const oldBg = CanvasBackground(style: BackgroundStyle.plain);
      const newBg = CanvasBackground(style: BackgroundStyle.graph, spacing: 40);

      final cmd = ChangeBackgroundCommand(oldBackground: oldBg, newBackground: newBg);
      page = history.execute(cmd, page);
      expect(page.background.style, BackgroundStyle.graph);

      page = history.undo(page);
      expect(page.background.style, BackgroundStyle.plain);
    });
  });
}
