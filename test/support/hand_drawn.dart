// Synthetic "hand-drawn" strokes with realistic tablet properties: dense,
// unevenly spaced samples, pen jitter, an unclosed gap where the pen lifted,
// optionally rounded corners and uneven side lengths.
import 'dart:math' as math;

import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:flutter/material.dart';

/// Polygon outline (or circle when [sides] == 0) drawn as a single stroke.
Stroke handDrawn({
  required int sides,
  Offset center = const Offset(300, 300),
  double radius = 80,
  double rx = 1.0, // horizontal stretch
  double jitter = 1.2,
  double gapFraction = 0.05, // unclosed part of the outline
  double cornerRounding = 0.0, // 0..0.4 of side length cut off at corners
  double irregularity = 0.0, // random radius variation of vertices
  double rotation = 0.0,
  double spacing = 3.0, // px between samples (tablet ~2-5 px)
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  double g() =>
      (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * jitter;

  // Build the ideal outline as a dense polyline.
  final outline = <Offset>[];
  if (sides == 0) {
    final n = (2 * math.pi * radius / spacing).round();
    for (int i = 0; i <= n; i++) {
      final a = rotation - math.pi / 2 + 2 * math.pi * i / n;
      outline.add(
        center + Offset(math.cos(a) * radius * rx, math.sin(a) * radius),
      );
    }
  } else {
    final verts = [
      for (int i = 0; i < sides; i++)
        () {
          final a = rotation - math.pi / 2 + 2 * math.pi * i / sides;
          final r = radius * (1 + (rnd.nextDouble() - 0.5) * 2 * irregularity);
          return center + Offset(math.cos(a) * r * rx, math.sin(a) * r);
        }(),
    ];
    for (int i = 0; i < sides; i++) {
      final a = verts[i], b = verts[(i + 1) % sides];
      final c = verts[(i + 2) % sides];
      // side a->b, rounding the corner at b toward c
      final cut = cornerRounding;
      final start = Offset.lerp(a, b, i == 0 ? 0 : cut)!;
      final end = Offset.lerp(a, b, 1 - cut)!;
      final len = (end - start).distance;
      final n = math.max(2, (len / spacing).round());
      for (int j = 0; j < n; j++) {
        outline.add(Offset.lerp(start, end, j / n)!);
      }
      if (cut > 0) {
        // quadratic corner from end -> b -> lerp(b,c,cut)
        final to = Offset.lerp(b, c, cut)!;
        for (int j = 0; j < 4; j++) {
          final t = j / 4;
          final p =
              end * ((1 - t) * (1 - t)) + b * (2 * (1 - t) * t) + to * (t * t);
          outline.add(p);
        }
      }
    }
    // With rounded corners the last corner already overlaps the start of
    // the first side; jumping back to the vertex would be an unnatural reversal.
    if (cornerRounding == 0) outline.add(verts.first);
  }

  final keep = (outline.length * (1 - gapFraction)).round();
  final pts = <StrokePoint>[];
  for (int i = 0; i < keep; i++) {
    final p = outline[i];
    pts.add(StrokePoint(x: p.dx + g(), y: p.dy + g(), timestamp: i * 8));
  }
  return Stroke(
    id: 'hd-$sides-$seed',
    points: pts,
    colorValue: 0xFF000000,
    width: 3,
    toolType: ToolType.pen,
  );
}

/// Hand-drawn rectangle [w]×[h] rotated by [angle], starting at a corner.
/// [overshoot] > 0 continues past the start corner (common when closing a box).
Stroke handDrawnRect({
  required double w,
  required double h,
  Offset center = const Offset(300, 300),
  double angle = 0.0,
  double jitter = 1.2,
  double gapFraction = 0.0,
  double overshoot = 0.0,
  double cornerRounding = 0.0,
  double spacing = 3.0,
  int startCorner = 0,
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  double g() =>
      (rnd.nextDouble() + rnd.nextDouble() + rnd.nextDouble() - 1.5) * jitter;
  final c = math.cos(angle), s = math.sin(angle);
  Offset rot(double x, double y) =>
      center + Offset(x * c - y * s, x * s + y * c);
  final base = [
    rot(-w / 2, -h / 2),
    rot(w / 2, -h / 2),
    rot(w / 2, h / 2),
    rot(-w / 2, h / 2),
  ];
  final verts = [for (int i = 0; i < 4; i++) base[(i + startCorner) % 4]];

  final outline = <Offset>[];
  for (int i = 0; i < 4; i++) {
    final a = verts[i], b = verts[(i + 1) % 4], nxt = verts[(i + 2) % 4];
    final start = Offset.lerp(a, b, i == 0 ? 0 : cornerRounding)!;
    final end = Offset.lerp(a, b, 1 - cornerRounding)!;
    final n = math.max(2, ((end - start).distance / spacing).round());
    for (int j = 0; j < n; j++) {
      outline.add(Offset.lerp(start, end, j / n)!);
    }
    if (cornerRounding > 0) {
      final to = Offset.lerp(b, nxt, cornerRounding)!;
      for (int j = 0; j < 4; j++) {
        final t = j / 4;
        outline.add(
          end * ((1 - t) * (1 - t)) + b * (2 * (1 - t) * t) + to * (t * t),
        );
      }
    }
  }
  if (cornerRounding == 0) outline.add(verts.first);
  if (overshoot > 0) {
    final dir = verts[1] - verts[0];
    final n = math.max(1, (dir.distance * overshoot / spacing).round());
    for (int j = 1; j <= n; j++) {
      outline.add(Offset.lerp(verts[0], verts[1], overshoot * j / n)!);
    }
  }
  final keep = (outline.length * (1 - gapFraction)).round();
  return Stroke(
    id: 'rect-$seed',
    points: [
      for (int i = 0; i < keep; i++)
        StrokePoint(
          x: outline[i].dx + g(),
          y: outline[i].dy + g(),
          timestamp: i * 8,
        ),
    ],
    colorValue: 0xFF000000,
    width: 3,
    toolType: ToolType.pen,
  );
}
