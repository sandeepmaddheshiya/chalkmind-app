import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/stroke_point.dart';

class StrokeSmoother {
  /// Generates a smooth bezier path through a collection of stroke points
  static Path smoothPoints(List<StrokePoint> points) {
    final path = Path();
    if (points.isEmpty) return path;

    if (points.length == 1) {
      path.addOval(Rect.fromCircle(center: points.first.offset, radius: 0.5));
      return path;
    }

    if (points.length == 2) {
      path.moveTo(points[0].x, points[0].y);
      path.lineTo(points[1].x, points[1].y);
      return path;
    }

    path.moveTo(points[0].x, points[0].y);
    for (int i = 1; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final midPoint = Offset((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
      path.quadraticBezierTo(p1.x, p1.y, midPoint.dx, midPoint.dy);
    }
    path.lineTo(points.last.x, points.last.y);

    return path;
  }

  /// Calculates adjusted stroke width factoring in stylus pressure and velocity
  static double calculateEffectiveWidth({
    required double baseWidth,
    required double pressure,
    required double velocity,
  }) {
    // Stylus pressure scaling (0.5x to 1.5x)
    double pressureFactor = (pressure <= 0.0) ? 1.0 : (0.5 + pressure);
    pressureFactor = pressureFactor.clamp(0.4, 1.8);

    // Slight velocity dampening for natural handwriting feel
    final speed = velocity.clamp(0.0, 3000.0);
    final velocityFactor = 1.0 - (speed / 3000.0) * 0.25;

    return baseWidth * pressureFactor * velocityFactor;
  }

  /// Arrow head generator utility
  static Path createArrowHead({
    required Offset tip,
    required Offset from,
    required double headLength,
    required double headAngle,
  }) {
    final path = Path();
    final angle = math.atan2(tip.dy - from.dy, tip.dx - from.dx);

    final leftAngle = angle + headAngle;
    final rightAngle = angle - headAngle;

    final leftPoint = Offset(
      tip.dx - headLength * math.cos(leftAngle),
      tip.dy - headLength * math.sin(leftAngle),
    );
    final rightPoint = Offset(
      tip.dx - headLength * math.cos(rightAngle),
      tip.dy - headLength * math.sin(rightAngle),
    );

    path.moveTo(tip.dx, tip.dy);
    path.lineTo(leftPoint.dx, leftPoint.dy);
    path.moveTo(tip.dx, tip.dy);
    path.lineTo(rightPoint.dx, rightPoint.dy);

    return path;
  }
}
