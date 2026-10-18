import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/features/whiteboard/models/background_style.dart';
import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/shape_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/text_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';

void main() {
  group('Stroke & StrokePoint serialization', () {
    test('StrokePoint round-trip JSON serialization', () {
      const pt = StrokePoint(x: 120.5, y: 340.2, pressure: 0.85, timestamp: 1600000);
      final json = pt.toJson();
      final restored = StrokePoint.fromJson(json);

      expect(restored.x, closeTo(120.5, 0.01));
      expect(restored.y, closeTo(340.2, 0.01));
      expect(restored.pressure, closeTo(0.85, 0.01));
      expect(restored.timestamp, 1600000);
    });

    test('Stroke round-trip JSON serialization and path generation', () {
      final stroke = Stroke(
        id: 'stroke-1',
        points: [
          const StrokePoint(x: 10, y: 10, timestamp: 100),
          const StrokePoint(x: 50, y: 80, timestamp: 200),
          const StrokePoint(x: 100, y: 120, timestamp: 300),
        ],
        colorValue: 0xFF1E293B,
        width: 4.0,
        opacity: 0.9,
        toolType: ToolType.pen,
      );

      final json = stroke.toJson();
      final restored = Stroke.fromJson(json);

      expect(restored.id, 'stroke-1');
      expect(restored.points.length, 3);
      expect(restored.colorValue, 0xFF1E293B);
      expect(restored.width, 4.0);
      expect(restored.toolType, ToolType.pen);
      expect(restored.bounds.isEmpty, isFalse);
    });

    test('Stroke translation moves all points by delta', () {
      final stroke = Stroke(
        id: 's-1',
        points: [
          const StrokePoint(x: 10, y: 20, timestamp: 100),
          const StrokePoint(x: 30, y: 40, timestamp: 200),
        ],
        colorValue: 0xFF000000,
        width: 2.0,
        toolType: ToolType.pencil,
      );

      final moved = stroke.translate(const Offset(5, -10));
      expect(moved.points[0].x, 15);
      expect(moved.points[0].y, 10);
      expect(moved.points[1].x, 35);
      expect(moved.points[1].y, 30);
    });
  });

  group('ShapeObject & TextObject serialization', () {
    test('ShapeObject rectangle serialization', () {
      const shape = ShapeObject(
        id: 'shape-1',
        shapeType: ShapeType.rectangle,
        start: Offset(10, 20),
        end: Offset(110, 120),
        strokeColorValue: 0xFF2563EB,
        strokeWidth: 3.0,
        isFilled: true,
        fillColorValue: 0x402563EB,
      );

      final json = shape.toJson();
      final restored = ShapeObject.fromJson(json);

      expect(restored.id, 'shape-1');
      expect(restored.shapeType, ShapeType.rectangle);
      expect(restored.start, const Offset(10, 20));
      expect(restored.end, const Offset(110, 120));
      expect(restored.isFilled, isTrue);
      expect(restored.bounds.width, closeTo(100 + 3.0 * 3.0, 0.1));
    });

    test('TextObject serialization and layout bounds', () {
      const text = TextObject(
        id: 'text-1',
        text: 'Newton Second Law: F = ma',
        position: Offset(40, 60),
        fontSize: 24.0,
        colorValue: 0xFF000000,
        isBold: true,
      );

      final json = text.toJson();
      final restored = TextObject.fromJson(json);

      expect(restored.id, 'text-1');
      expect(restored.text, 'Newton Second Law: F = ma');
      expect(restored.fontSize, 24.0);
      expect(restored.isBold, isTrue);
      expect(restored.bounds.contains(const Offset(50, 70)), isTrue);
    });
  });

  group('ProjectModel and PageModel lifecycle', () {
    test('ProjectModel createEmpty produces valid initial page and metadata', () {
      final project = ProjectModel.createEmpty(title: 'Calculus 101');
      expect(project.title, 'Calculus 101');
      expect(project.documentVersion, 1);
      expect(project.pages.length, 1);
      expect(project.currentPageIndex, 0);
      expect(project.currentPage.background.style, BackgroundStyle.plain);
    });

    test('ProjectModel JSON round-trip retains pages and elements', () {
      final original = ProjectModel(
        id: 'proj-1',
        title: 'Physics Lab',
        createdAt: DateTime(2026, 10, 17, 10, 0),
        updatedAt: DateTime(2026, 10, 17, 10, 30),
        documentVersion: 1,
        pages: [
          PageModel(
            id: 'page-1',
            pageNumber: 1,
            background: const CanvasBackground(style: BackgroundStyle.ruled),
            strokes: [
              Stroke(
                id: 's-1',
                points: [const StrokePoint(x: 0, y: 0, timestamp: 1)],
                colorValue: 0xFF000000,
                width: 2.0,
                toolType: ToolType.pen,
              ),
            ],
            shapes: [
              const ShapeObject(
                id: 'sh-1',
                shapeType: ShapeType.arrow,
                start: Offset(0, 0),
                end: Offset(50, 50),
                strokeColorValue: 0xFF000000,
                strokeWidth: 2.0,
              ),
            ],
          ),
        ],
      );

      final json = original.toJson();
      final restored = ProjectModel.fromJson(json);

      expect(restored.id, 'proj-1');
      expect(restored.title, 'Physics Lab');
      expect(restored.pages.length, 1);
      expect(restored.pages[0].background.style, BackgroundStyle.ruled);
      expect(restored.pages[0].strokes.length, 1);
      expect(restored.pages[0].shapes.length, 1);
    });
  });
}
