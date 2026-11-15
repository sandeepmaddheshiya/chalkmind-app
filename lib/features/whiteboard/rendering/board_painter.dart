import 'dart:math' as math;
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import '../models/shape_model.dart';
import '../models/stroke_model.dart';
import '../models/text_model.dart';
import '../models/tool_type.dart';
import 'stroke_smoother.dart';

class BoardPainter extends CustomPainter {
  final List<Stroke> strokes;
  final List<ShapeObject> shapes;
  final List<TextObject> texts;
  final Set<String> selectedIds;

  /// Elements not to paint (e.g. the selection while it is being dragged;
  /// a separate preview layer paints them at the drag offset).
  final Set<String> hiddenIds;

  BoardPainter({
    required this.strokes,
    required this.shapes,
    required this.texts,
    this.selectedIds = const {},
    this.hiddenIds = const {},
  });

  @override
  void paint(Canvas canvas, Size size) {
    paintElements(
      canvas,
      strokes: strokes,
      shapes: shapes,
      texts: texts,
      hiddenIds: hiddenIds,
    );
  }

  /// Paints board content in z-order: shapes, then ink, then text.
  static void paintElements(
    Canvas canvas, {
    required List<Stroke> strokes,
    required List<ShapeObject> shapes,
    required List<TextObject> texts,
    Set<String> hiddenIds = const {},
  }) {
    final hide = hiddenIds.isNotEmpty;
    for (final shape in shapes) {
      if (hide && hiddenIds.contains(shape.id)) continue;
      _paintShape(canvas, shape);
    }
    for (final stroke in strokes) {
      if (hide && hiddenIds.contains(stroke.id)) continue;
      _paintStroke(canvas, stroke);
    }
    for (final text in texts) {
      if (hide && hiddenIds.contains(text.id)) continue;
      text.layoutPainter.paint(canvas, text.position);
    }
  }

  static void _paintStroke(Canvas canvas, Stroke stroke) {
    if (stroke.points.isEmpty) return;

    final paint = Paint()
      ..color = stroke.color
      ..strokeWidth = stroke.width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (stroke.toolType == ToolType.highlighter) {
      paint.strokeCap = StrokeCap.square;
      paint.blendMode = BlendMode.multiply;
    } else if (stroke.toolType == ToolType.pencil) {
      paint.strokeCap = StrokeCap.round;
      // Pencil has a softer, lower opacity look
      paint.color = stroke.color.withValues(alpha: stroke.opacity * 0.75);
    }

    canvas.drawPath(stroke.path, paint);
  }

  static void _paintShape(Canvas canvas, ShapeObject shape) {
    final strokePaint = Paint()
      ..color = shape.strokeColor
      ..strokeWidth = shape.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final fillPaint = shape.isFilled && shape.fillColor != null
        ? (Paint()
            ..color = shape.fillColor!
            ..style = PaintingStyle.fill)
        : null;

    final rect = Rect.fromPoints(shape.start, shape.end);

    // If custom vertices are present (e.g. detected triangle or star), draw exact polygon
    if (shape.customVertices != null && shape.customVertices!.length >= 3) {
      final polyPath = Path();
      polyPath.moveTo(
        shape.customVertices!.first.dx,
        shape.customVertices!.first.dy,
      );
      for (int i = 1; i < shape.customVertices!.length; i++) {
        polyPath.lineTo(
          shape.customVertices![i].dx,
          shape.customVertices![i].dy,
        );
      }
      polyPath.close();

      if (fillPaint != null) canvas.drawPath(polyPath, fillPaint);
      canvas.drawPath(polyPath, strokePaint);
      return;
    }

    switch (shape.shapeType) {
      case ShapeType.line:
        canvas.drawLine(shape.start, shape.end, strokePaint);
        break;

      case ShapeType.arrow:
        canvas.drawLine(shape.start, shape.end, strokePaint);
        final arrowHead = StrokeSmoother.createArrowHead(
          tip: shape.end,
          from: shape.start,
          headLength: math.max(16.0, shape.strokeWidth * 3.5),
          headAngle: math.pi / 6, // 30 degrees
        );
        canvas.drawPath(arrowHead, strokePaint);
        break;

      case ShapeType.rectangle:
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        if (fillPaint != null) canvas.drawRRect(rrect, fillPaint);
        canvas.drawRRect(rrect, strokePaint);
        break;

      case ShapeType.circle:
        if (fillPaint != null) canvas.drawOval(rect, fillPaint);
        canvas.drawOval(rect, strokePaint);
        break;

      case ShapeType.triangle:
        final path = Path();
        if (shape.customVertices != null && shape.customVertices!.length >= 3) {
          path.moveTo(shape.customVertices![0].dx, shape.customVertices![0].dy);
          for (int i = 1; i < shape.customVertices!.length; i++) {
            path.lineTo(
              shape.customVertices![i].dx,
              shape.customVertices![i].dy,
            );
          }
          path.close();
        } else {
          final top = Offset(
            (shape.start.dx + shape.end.dx) / 2,
            math.min(shape.start.dy, shape.end.dy),
          );
          final bottomLeft = Offset(
            math.min(shape.start.dx, shape.end.dx),
            math.max(shape.start.dy, shape.end.dy),
          );
          final bottomRight = Offset(
            math.max(shape.start.dx, shape.end.dx),
            math.max(shape.start.dy, shape.end.dy),
          );
          path.moveTo(top.dx, top.dy);
          path.lineTo(bottomLeft.dx, bottomLeft.dy);
          path.lineTo(bottomRight.dx, bottomRight.dy);
          path.close();
        }

        if (fillPaint != null) canvas.drawPath(path, fillPaint);
        canvas.drawPath(path, strokePaint);
        break;

      case ShapeType.star:
        final starPath = _createStarPath(rect);
        if (fillPaint != null) canvas.drawPath(starPath, fillPaint);
        canvas.drawPath(starPath, strokePaint);
        break;

      case ShapeType.diamond:
        final diamondPath = Path();
        diamondPath.moveTo(rect.center.dx, rect.top);
        diamondPath.lineTo(rect.right, rect.center.dy);
        diamondPath.lineTo(rect.center.dx, rect.bottom);
        diamondPath.lineTo(rect.left, rect.center.dy);
        diamondPath.close();
        if (fillPaint != null) canvas.drawPath(diamondPath, fillPaint);
        canvas.drawPath(diamondPath, strokePaint);
        break;

      case ShapeType.pentagon:
      case ShapeType.hexagon:
      case ShapeType.heptagon:
      case ShapeType.octagon:
        final Path polyPath;
        if (shape.customVertices != null && shape.customVertices!.length >= 3) {
          polyPath = Path();
          polyPath.moveTo(
            shape.customVertices![0].dx,
            shape.customVertices![0].dy,
          );
          for (int i = 1; i < shape.customVertices!.length; i++) {
            polyPath.lineTo(
              shape.customVertices![i].dx,
              shape.customVertices![i].dy,
            );
          }
          polyPath.close();
        } else {
          final sides = shape.shapeType == ShapeType.pentagon
              ? 5
              : shape.shapeType == ShapeType.hexagon
              ? 6
              : shape.shapeType == ShapeType.heptagon
              ? 7
              : 8;
          polyPath = _createRegularPolygonPath(rect, sides);
        }
        if (fillPaint != null) canvas.drawPath(polyPath, fillPaint);
        canvas.drawPath(polyPath, strokePaint);
        break;
    }
  }

  static Path _createRegularPolygonPath(
    Rect rect,
    int sides, {
    double startAngle = -math.pi / 2,
  }) {
    final path = Path();
    final center = rect.center;
    final rx = rect.width / 2;
    final ry = rect.height / 2;

    for (int i = 0; i < sides; i++) {
      final angle = startAngle + (i * 2 * math.pi / sides);
      final x = center.dx + rx * math.cos(angle);
      final y = center.dy + ry * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  static Path _createStarPath(Rect rect) {
    final path = Path();
    final center = rect.center;
    final rOuter = math.min(rect.width, rect.height) / 2;
    final rInner = rOuter * 0.42;

    for (int i = 0; i < 10; i++) {
      final angle = -math.pi / 2 + (i * math.pi / 5);
      final r = (i % 2 == 0) ? rOuter : rInner;
      final x = center.dx + r * math.cos(angle);
      final y = center.dy + r * math.sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) {
    // Selection is drawn by SelectionPainter, so it doesn't force a repaint
    // of the (potentially large) board layer.
    return !identical(oldDelegate.strokes, strokes) ||
        !identical(oldDelegate.shapes, shapes) ||
        !identical(oldDelegate.texts, texts) ||
        !setEquals(oldDelegate.hiddenIds, hiddenIds);
  }
}
