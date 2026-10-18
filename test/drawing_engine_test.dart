import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/features/whiteboard/models/shape_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/rendering/stroke_smoother.dart';

void main() {
  group('StrokeSmoother tests', () {
    test('smoothPoints handles empty, single, and multiple points without error', () {
      final emptyPath = StrokeSmoother.smoothPoints([]);
      expect(emptyPath.getBounds(), Rect.zero);

      final singlePointPath = StrokeSmoother.smoothPoints([
        const StrokePoint(x: 50, y: 50, timestamp: 1),
      ]);
      expect(singlePointPath.getBounds().isEmpty, isFalse);

      final multiPath = StrokeSmoother.smoothPoints([
        const StrokePoint(x: 0, y: 0, timestamp: 1),
        const StrokePoint(x: 50, y: 100, timestamp: 2),
        const StrokePoint(x: 100, y: 50, timestamp: 3),
      ]);
      expect(multiPath.getBounds().width, greaterThan(0));
      expect(multiPath.getBounds().height, greaterThan(0));
    });

    test('calculateEffectiveWidth scales with pressure and velocity', () {
      final normalWidth = StrokeSmoother.calculateEffectiveWidth(
        baseWidth: 4.0,
        pressure: 0.5,
        velocity: 500.0,
      );
      final heavyPressureWidth = StrokeSmoother.calculateEffectiveWidth(
        baseWidth: 4.0,
        pressure: 1.0,
        velocity: 500.0,
      );

      expect(heavyPressureWidth, greaterThan(normalWidth));
    });

    test('createArrowHead generates valid geometry', () {
      final arrowPath = StrokeSmoother.createArrowHead(
        tip: const Offset(100, 100),
        from: const Offset(0, 100),
        headLength: 20.0,
        headAngle: 0.5,
      );
      final bounds = arrowPath.getBounds();
      expect(bounds.right, closeTo(100, 0.1));
      expect(bounds.left, lessThan(100));
    });
  });

  group('Hit testing for eraser and selection', () {
    test('Stroke hitTest detects collision on segments and ignores far points', () {
      final stroke = Stroke(
        id: 's-1',
        points: [
          const StrokePoint(x: 0, y: 0, timestamp: 1),
          const StrokePoint(x: 100, y: 0, timestamp: 2),
        ],
        colorValue: 0xFF000000,
        width: 4.0,
        toolType: ToolType.pen,
      );

      // Directly on segment
      expect(stroke.hitTest(const Offset(50, 0), threshold: 10.0), isTrue);

      // Slightly off segment within threshold
      expect(stroke.hitTest(const Offset(50, 8), threshold: 10.0), isTrue);

      // Far away from segment
      expect(stroke.hitTest(const Offset(50, 100), threshold: 10.0), isFalse);
    });

    test('ShapeObject hitTest works for rectangle and filled areas', () {
      const unfilledRect = ShapeObject(
        id: 'rect-1',
        shapeType: ShapeType.rectangle,
        start: Offset(10, 10),
        end: Offset(100, 100),
        strokeColorValue: 0xFF000000,
        strokeWidth: 4.0,
        isFilled: false,
      );

      // On border
      expect(unfilledRect.hitTest(const Offset(10, 50)), isTrue);

      // Deep inside unfilled rectangle is false
      expect(unfilledRect.hitTest(const Offset(50, 50), threshold: 2.0), isFalse);

      const filledRect = ShapeObject(
        id: 'rect-2',
        shapeType: ShapeType.rectangle,
        start: Offset(10, 10),
        end: Offset(100, 100),
        strokeColorValue: 0xFF000000,
        strokeWidth: 4.0,
        isFilled: true,
      );

      // Inside filled rectangle is true
      expect(filledRect.hitTest(const Offset(50, 50)), isTrue);
    });
  });
}
