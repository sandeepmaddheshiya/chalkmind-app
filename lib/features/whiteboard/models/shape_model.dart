import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'tool_type.dart';

class ShapeObject {
  final String id;
  final ShapeType shapeType;
  final Offset start;
  final Offset end;
  final int strokeColorValue;
  final double strokeWidth;
  final int? fillColorValue;
  final bool isFilled;
  final List<Offset>? customVertices; // For authentic triangles, stars, polygons

  const ShapeObject({
    required this.id,
    required this.shapeType,
    required this.start,
    required this.end,
    required this.strokeColorValue,
    required this.strokeWidth,
    this.fillColorValue,
    this.isFilled = false,
    this.customVertices,
  });

  Color get strokeColor => Color(strokeColorValue);
  Color? get fillColor => fillColorValue != null ? Color(fillColorValue!) : null;

  Rect get bounds {
    if (customVertices != null && customVertices!.isNotEmpty) {
      double minX = customVertices!.first.dx;
      double maxX = customVertices!.first.dx;
      double minY = customVertices!.first.dy;
      double maxY = customVertices!.first.dy;

      for (final v in customVertices!) {
        if (v.dx < minX) minX = v.dx;
        if (v.dx > maxX) maxX = v.dx;
        if (v.dy < minY) minY = v.dy;
        if (v.dy > maxY) maxY = v.dy;
      }
      final padding = strokeWidth * 1.5;
      return Rect.fromLTRB(minX - padding, minY - padding, maxX + padding, maxY + padding);
    }

    final left = math.min(start.dx, end.dx);
    final top = math.min(start.dy, end.dy);
    final right = math.max(start.dx, end.dx);
    final bottom = math.max(start.dy, end.dy);
    final padding = strokeWidth * 1.5;
    return Rect.fromLTRB(
      left - padding,
      top - padding,
      right + padding,
      bottom + padding,
    );
  }

  bool hitTest(Offset point, {double threshold = 16.0}) {
    final b = bounds.inflate(threshold);
    if (!b.contains(point)) return false;

    if (isFilled) return true;

    // Check custom polygon boundary
    if (customVertices != null && customVertices!.length >= 3) {
      for (int i = 0; i < customVertices!.length; i++) {
        final v1 = customVertices![i];
        final v2 = customVertices![(i + 1) % customVertices!.length];
        if (_distToSegment(point, v1, v2) <= (strokeWidth / 2 + threshold)) {
          return true;
        }
      }
      return false;
    }

    // Standard shape boundaries
    switch (shapeType) {
      case ShapeType.line:
      case ShapeType.arrow:
        return _distToSegment(point, start, end) <= (strokeWidth / 2 + threshold);
      case ShapeType.rectangle:
        final r = Rect.fromPoints(start, end);
        final outer = r.inflate(strokeWidth / 2 + threshold);
        final inner = r.deflate(strokeWidth / 2 + threshold);
        return outer.contains(point) && !inner.contains(point);
      case ShapeType.circle:
        final r = Rect.fromPoints(start, end);
        final center = r.center;
        final radiusX = r.width / 2;
        final radiusY = r.height / 2;
        if (radiusX == 0 || radiusY == 0) return false;
        final normX = (point.dx - center.dx) / radiusX;
        final normY = (point.dy - center.dy) / radiusY;
        final val = normX * normX + normY * normY;
        return (val - 1.0).abs() < 0.45;
      case ShapeType.triangle:
      case ShapeType.star:
      case ShapeType.diamond:
      case ShapeType.pentagon:
      case ShapeType.hexagon:
      case ShapeType.heptagon:
      case ShapeType.octagon:
        return b.contains(point);
    }
  }

  static double _distToSegment(Offset p, Offset v, Offset w) {
    final l2 = (v.dx - w.dx) * (v.dx - w.dx) + (v.dy - w.dy) * (v.dy - w.dy);
    if (l2 == 0) return (p - v).distance;
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2,
      ),
    );
    final projection = Offset(v.dx + t * (w.dx - v.dx), v.dy + t * (w.dy - v.dy));
    return (p - projection).distance;
  }

  ShapeObject translate(Offset delta) {
    return ShapeObject(
      id: id,
      shapeType: shapeType,
      start: start + delta,
      end: end + delta,
      strokeColorValue: strokeColorValue,
      strokeWidth: strokeWidth,
      fillColorValue: fillColorValue,
      isFilled: isFilled,
      customVertices: customVertices?.map((v) => v + delta).toList(),
    );
  }

  ShapeObject copyWith({
    String? id,
    ShapeType? shapeType,
    Offset? start,
    Offset? end,
    int? strokeColorValue,
    double? strokeWidth,
    int? fillColorValue,
    bool? isFilled,
    List<Offset>? customVertices,
  }) {
    return ShapeObject(
      id: id ?? this.id,
      shapeType: shapeType ?? this.shapeType,
      start: start ?? this.start,
      end: end ?? this.end,
      strokeColorValue: strokeColorValue ?? this.strokeColorValue,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      fillColorValue: fillColorValue ?? this.fillColorValue,
      isFilled: isFilled ?? this.isFilled,
      customVertices: customVertices ?? this.customVertices,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'shapeType': shapeType.name,
    'start': {'dx': start.dx, 'dy': start.dy},
    'end': {'dx': end.dx, 'dy': end.dy},
    'strokeColorValue': strokeColorValue,
    'strokeWidth': strokeWidth,
    'fillColorValue': fillColorValue,
    'isFilled': isFilled,
    'customVertices': customVertices
        ?.map((v) => {'dx': v.dx, 'dy': v.dy})
        .toList(),
  };

  factory ShapeObject.fromJson(Map<String, dynamic> json) {
    final s = json['start'] as Map<String, dynamic>;
    final e = json['end'] as Map<String, dynamic>;
    final verts = json['customVertices'] as List<dynamic>?;

    return ShapeObject(
      id: json['id'] as String,
      shapeType: ShapeType.values.firstWhere(
        (st) => st.name == json['shapeType'],
        orElse: () => ShapeType.rectangle,
      ),
      start: Offset((s['dx'] as num).toDouble(), (s['dy'] as num).toDouble()),
      end: Offset((e['dx'] as num).toDouble(), (e['dy'] as num).toDouble()),
      strokeColorValue: json['strokeColorValue'] as int,
      strokeWidth: (json['strokeWidth'] as num).toDouble(),
      fillColorValue: json['fillColorValue'] as int?,
      isFilled: json['isFilled'] as bool? ?? false,
      customVertices: verts
          ?.map((v) => Offset(
                (v['dx'] as num).toDouble(),
                (v['dy'] as num).toDouble(),
              ))
          .toList(),
    );
  }
}
