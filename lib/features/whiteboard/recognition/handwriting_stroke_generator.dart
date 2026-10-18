import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/stroke_model.dart';
import '../models/stroke_point.dart';
import '../models/tool_type.dart';

class HandwritingStrokeGenerator {
  static const uuid = Uuid();

  /// Converts a text result (e.g. "4" or "144" or "3.14") into natural handwritten vector Strokes
  /// Supports slant angle via direction and normal vectors
  static List<Stroke> generateHandwrittenStrokes({
    required String text,
    required Offset startPosition,
    required double characterHeight,
    required int colorValue,
    required double strokeWidth,
    Offset direction = const Offset(1, 0),
    Offset normal = const Offset(0, 1),
    ToolType toolType = ToolType.pen,
  }) {
    final List<Stroke> resultStrokes = [];
    final charWidth = characterHeight * 0.65;
    final charSpacing = characterHeight * 0.22;

    double progress = 0.0;
    final now = DateTime.now().millisecondsSinceEpoch;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      final charOrigin = startPosition + direction * progress;

      final glyphStrokes = _getGlyphStrokes(
        char,
        charOrigin,
        direction,
        normal,
        charWidth,
        characterHeight,
        now + (i * 50),
      );

      for (final points in glyphStrokes) {
        if (points.isNotEmpty) {
          resultStrokes.add(
            Stroke(
              id: uuid.v4(),
              points: points,
              colorValue: colorValue,
              width: strokeWidth,
              toolType: toolType,
            ),
          );
        }
      }

      progress += (char == '.' || char == ',') ? (charWidth * 0.4) : (charWidth + charSpacing);
    }

    return resultStrokes;
  }

  static List<List<StrokePoint>> _getGlyphStrokes(
    String char,
    Offset origin,
    Offset dir,
    Offset norm,
    double w,
    double h,
    int baseTime,
  ) {
    Offset toWorld(double uNorm, double vNorm) {
      return origin + dir * (uNorm * w) + norm * (vNorm * h);
    }

    switch (char) {
      case '0':
        return [
          _sampleCurve([
            toWorld(0.5, 0.0),
            toWorld(0.0, 0.35),
            toWorld(0.0, 0.7),
            toWorld(0.5, 1.0),
            toWorld(1.0, 0.7),
            toWorld(1.0, 0.35),
            toWorld(0.5, 0.0),
          ], baseTime),
        ];

      case '1':
        return [
          _sampleCurve([
            toWorld(0.2, 0.25),
            toWorld(0.5, 0.0),
            toWorld(0.5, 1.0),
          ], baseTime),
        ];

      case '2':
        return [
          _sampleCurve([
            toWorld(0.15, 0.25),
            toWorld(0.5, 0.0),
            toWorld(0.9, 0.25),
            toWorld(0.15, 0.9),
            toWorld(1.0, 1.0),
          ], baseTime),
        ];

      case '3':
        return [
          _sampleCurve([
            toWorld(0.1, 0.15),
            toWorld(0.9, 0.15),
            toWorld(0.5, 0.45),
            toWorld(1.0, 0.75),
            toWorld(0.1, 1.0),
          ], baseTime),
        ];

      case '4':
        return [
          _sampleCurve([
            toWorld(0.75, 0.05),
            toWorld(0.1, 0.6),
            toWorld(0.9, 0.6),
          ], baseTime),
          _sampleCurve([
            toWorld(0.75, 0.35),
            toWorld(0.75, 1.0),
          ], baseTime + 15),
        ];

      case '5':
        return [
          _sampleCurve([
            toWorld(0.9, 0.0),
            toWorld(0.2, 0.0),
            toWorld(0.15, 0.45),
            toWorld(0.9, 0.6),
            toWorld(0.9, 1.0),
            toWorld(0.1, 0.9),
          ], baseTime),
        ];

      case '6':
        return [
          _sampleCurve([
            toWorld(0.8, 0.0),
            toWorld(0.1, 0.6),
            toWorld(0.5, 1.0),
            toWorld(1.0, 0.75),
            toWorld(0.5, 0.5),
            toWorld(0.1, 0.65),
          ], baseTime),
        ];

      case '7':
        return [
          _sampleCurve([
            toWorld(0.0, 0.0),
            toWorld(1.0, 0.0),
            toWorld(0.4, 1.0),
          ], baseTime),
        ];

      case '8':
        return [
          _sampleCurve([
            toWorld(0.5, 0.45),
            toWorld(0.1, 0.2),
            toWorld(0.5, 0.0),
            toWorld(0.9, 0.2),
            toWorld(0.5, 0.45),
            toWorld(0.1, 0.8),
            toWorld(0.5, 1.0),
            toWorld(0.9, 0.8),
            toWorld(0.5, 0.45),
          ], baseTime),
        ];

      case '9':
        return [
          _sampleCurve([
            toWorld(0.9, 0.4),
            toWorld(0.5, 0.5),
            toWorld(0.0, 0.25),
            toWorld(0.5, 0.0),
            toWorld(0.9, 0.25),
            toWorld(0.9, 0.9),
            toWorld(0.2, 1.0),
          ], baseTime),
        ];

      case '.':
        final pt1 = toWorld(0.5, 0.95);
        final pt2 = toWorld(0.55, 0.98);
        return [
          [
            StrokePoint(x: pt1.dx, y: pt1.dy, timestamp: baseTime),
            StrokePoint(x: pt2.dx, y: pt2.dy, timestamp: baseTime + 5),
          ],
        ];

      case '+':
        return [
          _sampleCurve([
            toWorld(0.5, 0.2),
            toWorld(0.5, 0.8),
          ], baseTime),
          _sampleCurve([
            toWorld(0.2, 0.5),
            toWorld(0.8, 0.5),
          ], baseTime + 10),
        ];

      case '=':
        return [
          _sampleCurve([
            toWorld(0.1, 0.38),
            toWorld(0.9, 0.38),
          ], baseTime),
          _sampleCurve([
            toWorld(0.1, 0.62),
            toWorld(0.9, 0.62),
          ], baseTime + 10),
        ];

      case '/':
        return [
          _sampleCurve([
            toWorld(0.15, 0.95),
            toWorld(0.85, 0.05),
          ], baseTime),
        ];

      case '*':
        return [
          _sampleCurve([
            toWorld(0.25, 0.25),
            toWorld(0.75, 0.75),
          ], baseTime),
          _sampleCurve([
            toWorld(0.25, 0.75),
            toWorld(0.75, 0.25),
          ], baseTime + 10),
        ];

      case '(':
        return [
          _sampleCurve([
            toWorld(0.7, 0.05),
            toWorld(0.3, 0.5),
            toWorld(0.7, 0.95),
          ], baseTime),
        ];

      case ')':
        return [
          _sampleCurve([
            toWorld(0.3, 0.05),
            toWorld(0.7, 0.5),
            toWorld(0.3, 0.95),
          ], baseTime),
        ];

      case 'x':
      case 'X':
        return [
          _sampleCurve([
            toWorld(0.2, 0.25),
            toWorld(0.8, 0.95),
          ], baseTime),
          _sampleCurve([
            toWorld(0.8, 0.25),
            toWorld(0.2, 0.95),
          ], baseTime + 10),
        ];

      case 'y':
      case 'Y':
        return [
          _sampleCurve([
            toWorld(0.15, 0.25),
            toWorld(0.5, 0.65),
          ], baseTime),
          _sampleCurve([
            toWorld(0.85, 0.25),
            toWorld(0.15, 1.15),
          ], baseTime + 10),
        ];

      case 'z':
      case 'Z':
        return [
          _sampleCurve([
            toWorld(0.15, 0.25),
            toWorld(0.85, 0.25),
            toWorld(0.15, 0.95),
            toWorld(0.85, 0.95),
          ], baseTime),
        ];

      case '-':
        return [
          _sampleCurve([
            toWorld(0.15, 0.55),
            toWorld(0.85, 0.55),
          ], baseTime),
        ];

      case 'a':
      case 'A':
        return [
          _sampleCurve([
            toWorld(0.75, 0.45),
            toWorld(0.40, 0.35),
            toWorld(0.20, 0.58),
            toWorld(0.40, 0.82),
            toWorld(0.75, 0.72),
            toWorld(0.75, 0.38),
            toWorld(0.75, 0.95),
            toWorld(0.85, 0.92),
          ], baseTime),
        ];

      case 'b':
      case 'B':
        return [
          _sampleCurve([
            toWorld(0.22, 0.05),
            toWorld(0.22, 0.95),
            toWorld(0.22, 0.52),
            toWorld(0.75, 0.52),
            toWorld(0.78, 0.78),
            toWorld(0.50, 0.95),
            toWorld(0.22, 0.92),
          ], baseTime),
        ];

      case 'c':
      case 'C':
        return [
          _sampleCurve([
            toWorld(0.80, 0.45),
            toWorld(0.50, 0.35),
            toWorld(0.25, 0.60),
            toWorld(0.50, 0.85),
            toWorld(0.80, 0.80),
          ], baseTime),
        ];

      case '²':
        return [
          _sampleCurve([
            toWorld(0.20, 0.12),
            toWorld(0.50, 0.00),
            toWorld(0.80, 0.12),
            toWorld(0.20, 0.40),
            toWorld(0.85, 0.40),
          ], baseTime),
        ];

      case '³':
        return [
          _sampleCurve([
            toWorld(0.20, 0.05),
            toWorld(0.80, 0.05),
            toWorld(0.50, 0.22),
            toWorld(0.85, 0.32),
            toWorld(0.20, 0.42),
          ], baseTime),
        ];

      case '^':
        return [
          _sampleCurve([
            toWorld(0.20, 0.35),
            toWorld(0.50, 0.05),
            toWorld(0.80, 0.35),
          ], baseTime),
        ];

      case ' ':
        return [];

      default:
        // Generic fallback stroke so unknown characters are still visibly written
        return [
          _sampleCurve([
            toWorld(0.2, 0.8),
            toWorld(0.8, 0.2),
          ], baseTime),
        ];
    }
  }

  static List<StrokePoint> _sampleCurve(List<Offset> waypoints, int baseTime) {
    final List<StrokePoint> points = [];
    int time = baseTime;

    for (int i = 0; i < waypoints.length - 1; i++) {
      final p1 = waypoints[i];
      final p2 = waypoints[i + 1];
      final dist = (p2 - p1).distance;
      final steps = (dist / 4.0).clamp(3, 16).toInt();

      for (int s = 0; s < steps; s++) {
        final t = s / steps;
        final x = p1.dx + (p2.dx - p1.dx) * t;
        final y = p1.dy + (p2.dy - p1.dy) * t;
        points.add(StrokePoint(x: x, y: y, timestamp: time));
        time += 4;
      }
    }
    points.add(StrokePoint(x: waypoints.last.dx, y: waypoints.last.dy, timestamp: time));
    return points;
  }
}
