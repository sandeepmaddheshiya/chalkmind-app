import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/stroke_point.dart';
import '../models/tool_type.dart';
import 'stroke_smoother.dart';

class ActiveStrokePainter extends CustomPainter {
  final List<StrokePoint>? activePoints;
  final ToolType toolType;
  final Color color;
  final double width;
  final double opacity;
  final ShapeType? activeShapeType;
  final Offset? shapeStart;
  final Offset? shapeEnd;
  final bool isShapeFilled;
  final Offset? eraserPosition;
  final double eraserRadius;
  final Offset? laserPosition;

  ActiveStrokePainter({
    this.activePoints,
    required this.toolType,
    required this.color,
    required this.width,
    this.opacity = 1.0,
    this.activeShapeType,
    this.shapeStart,
    this.shapeEnd,
    this.isShapeFilled = false,
    this.eraserPosition,
    this.eraserRadius = 18.0,
    this.laserPosition,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paint active drawing stroke
    if (activePoints != null && activePoints!.isNotEmpty) {
      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      if (toolType == ToolType.highlighter) {
        paint.strokeCap = StrokeCap.square;
        paint.blendMode = BlendMode.multiply;
      } else if (toolType == ToolType.pencil) {
        paint.color = color.withValues(alpha: opacity * 0.75);
      }

      final path = StrokeSmoother.smoothPoints(activePoints!);
      canvas.drawPath(path, paint);
    }

    // 2. Paint active shape preview
    if (activeShapeType != null && shapeStart != null && shapeEnd != null) {
      final strokePaint = Paint()
        ..color = color.withValues(alpha: 0.85)
        ..strokeWidth = width
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final fillPaint = isShapeFilled
          ? (Paint()
            ..color = color.withValues(alpha: 0.2)
            ..style = PaintingStyle.fill)
          : null;

      final rect = Rect.fromPoints(shapeStart!, shapeEnd!);

      switch (activeShapeType!) {
        case ShapeType.line:
          canvas.drawLine(shapeStart!, shapeEnd!, strokePaint);
          break;

        case ShapeType.arrow:
          canvas.drawLine(shapeStart!, shapeEnd!, strokePaint);
          final arrowHead = StrokeSmoother.createArrowHead(
            tip: shapeEnd!,
            from: shapeStart!,
            headLength: math.max(16.0, width * 3.5),
            headAngle: math.pi / 6,
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
          final top = Offset((shapeStart!.dx + shapeEnd!.dx) / 2, math.min(shapeStart!.dy, shapeEnd!.dy));
          final bottomLeft = Offset(math.min(shapeStart!.dx, shapeEnd!.dx), math.max(shapeStart!.dy, shapeEnd!.dy));
          final bottomRight = Offset(math.max(shapeStart!.dx, shapeEnd!.dx), math.max(shapeStart!.dy, shapeEnd!.dy));
          path.moveTo(top.dx, top.dy);
          path.lineTo(bottomLeft.dx, bottomLeft.dy);
          path.lineTo(bottomRight.dx, bottomRight.dy);
          path.close();

          if (fillPaint != null) canvas.drawPath(path, fillPaint);
          canvas.drawPath(path, strokePaint);
          break;

        case ShapeType.star:
          final starPath = Path();
          final center = rect.center;
          final rOuter = math.min(rect.width, rect.height) / 2;
          final rInner = rOuter * 0.42;
          for (int i = 0; i < 10; i++) {
            final angle = -math.pi / 2 + (i * math.pi / 5);
            final r = (i % 2 == 0) ? rOuter : rInner;
            final x = center.dx + r * math.cos(angle);
            final y = center.dy + r * math.sin(angle);
            if (i == 0) {
              starPath.moveTo(x, y);
            } else {
              starPath.lineTo(x, y);
            }
          }
          starPath.close();
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
          final sides = activeShapeType == ShapeType.pentagon
              ? 5
              : activeShapeType == ShapeType.hexagon
                  ? 6
                  : activeShapeType == ShapeType.heptagon
                      ? 7
                      : 8;
          final polyPath = Path();
          final center = rect.center;
          final rx = rect.width / 2;
          final ry = rect.height / 2;
          const startAngle = -math.pi / 2;
          for (int i = 0; i < sides; i++) {
            final angle = startAngle + (i * 2 * math.pi / sides);
            final x = center.dx + rx * math.cos(angle);
            final y = center.dy + ry * math.sin(angle);
            if (i == 0) {
              polyPath.moveTo(x, y);
            } else {
              polyPath.lineTo(x, y);
            }
          }
          polyPath.close();
          if (fillPaint != null) canvas.drawPath(polyPath, fillPaint);
          canvas.drawPath(polyPath, strokePaint);
          break;
      }
    }

    // 3. Paint eraser cursor indicator
    if (eraserPosition != null) {
      final eraserBorder = Paint()
        ..color = const Color(0xCCEF4444) // Semi-transparent red circle
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final eraserFill = Paint()
        ..color = const Color(0x26EF4444)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(eraserPosition!, eraserRadius, eraserFill);
      canvas.drawCircle(eraserPosition!, eraserRadius, eraserBorder);
    }

    // 4. Paint laser pointer
    if (laserPosition != null) {
      final laserGlow = Paint()
        ..color = const Color(0x80EF4444)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      final laserDot = Paint()
        ..color = const Color(0xFFFF0055)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(laserPosition!, 12.0, laserGlow);
      canvas.drawCircle(laserPosition!, 5.0, laserDot);
    }
  }

  @override
  bool shouldRepaint(covariant ActiveStrokePainter oldDelegate) {
    return true; // Active layer continuously repaints during gesture
  }
}
