import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'stroke_point.dart';
import 'tool_type.dart';

class Stroke {
  final String id;
  final String layerId;
  final List<StrokePoint> points;
  final int colorValue;
  final double width;
  final double opacity;
  final ToolType toolType;

  // Cached geometry
  Rect? _bounds;
  Path? _cachedPath;

  Stroke({
    required this.id,
    this.layerId = 'default',
    required this.points,
    required this.colorValue,
    required this.width,
    this.opacity = 1.0,
    required this.toolType,
  });

  Color get color => Color(colorValue).withValues(alpha: opacity);

  Rect get bounds {
    if (_bounds != null) return _bounds!;
    if (points.isEmpty) {
      _bounds = Rect.zero;
      return _bounds!;
    }

    double minX = points.first.x;
    double maxX = points.first.x;
    double minY = points.first.y;
    double maxY = points.first.y;

    for (final p in points) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
    }

    final padding = width * 1.5;
    _bounds = Rect.fromLTRB(
      minX - padding,
      minY - padding,
      maxX + padding,
      maxY + padding,
    );
    return _bounds!;
  }

  Path get path {
    if (_cachedPath != null) return _cachedPath!;
    _cachedPath = createSmoothedPath(points);
    return _cachedPath!;
  }

  static Path createSmoothedPath(List<StrokePoint> pts) {
    final path = Path();
    if (pts.isEmpty) return path;

    if (pts.length == 1) {
      path.addOval(Rect.fromCircle(center: pts.first.offset, radius: 1.0));
      return path;
    }

    if (pts.length == 2) {
      path.moveTo(pts[0].x, pts[0].y);
      path.lineTo(pts[1].x, pts[1].y);
      return path;
    }

    // Midpoint quadratic bezier smoothing for responsive, smooth curves
    path.moveTo(pts[0].x, pts[0].y);
    for (int i = 1; i < pts.length - 1; i++) {
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final midPoint = Offset((p1.x + p2.x) / 2, (p1.y + p2.y) / 2);
      path.quadraticBezierTo(p1.x, p1.y, midPoint.dx, midPoint.dy);
    }
    path.lineTo(pts.last.x, pts.last.y);

    return path;
  }

  bool hitTest(Offset point, {double threshold = 16.0}) {
    if (!bounds.inflate(threshold).contains(point)) {
      return false;
    }

    final totalThreshold = (width / 2) + threshold;
    final totalThresholdSq = totalThreshold * totalThreshold;

    for (int i = 0; i < points.length - 1; i++) {
      final a = points[i].offset;
      final b = points[i + 1].offset;

      final distSq = _distToSegmentSquared(point, a, b);
      if (distSq <= totalThresholdSq) {
        return true;
      }
    }
    return false;
  }

  static double _distToSegmentSquared(Offset p, Offset v, Offset w) {
    final l2 = (v.dx - w.dx) * (v.dx - w.dx) + (v.dy - w.dy) * (v.dy - w.dy);
    if (l2 == 0) {
      return (p.dx - v.dx) * (p.dx - v.dx) + (p.dy - v.dy) * (p.dy - v.dy);
    }
    final t = math.max(
      0.0,
      math.min(
        1.0,
        ((p.dx - v.dx) * (w.dx - v.dx) + (p.dy - v.dy) * (w.dy - v.dy)) / l2,
      ),
    );
    final projection = Offset(
      v.dx + t * (w.dx - v.dx),
      v.dy + t * (w.dy - v.dy),
    );
    return (p.dx - projection.dx) * (p.dx - projection.dx) +
        (p.dy - projection.dy) * (p.dy - projection.dy);
  }

  Stroke translate(Offset delta) {
    final newPoints = points
        .map(
          (p) => StrokePoint(
            x: p.x + delta.dx,
            y: p.y + delta.dy,
            pressure: p.pressure,
            timestamp: p.timestamp,
          ),
        )
        .toList();
    return Stroke(
      id: id,
      layerId: layerId,
      points: newPoints,
      colorValue: colorValue,
      width: width,
      opacity: opacity,
      toolType: toolType,
    );
  }

  Stroke copyWith({
    String? id,
    String? layerId,
    List<StrokePoint>? points,
    int? colorValue,
    double? width,
    double? opacity,
    ToolType? toolType,
  }) {
    return Stroke(
      id: id ?? this.id,
      layerId: layerId ?? this.layerId,
      points: points ?? this.points,
      colorValue: colorValue ?? this.colorValue,
      width: width ?? this.width,
      opacity: opacity ?? this.opacity,
      toolType: toolType ?? this.toolType,
    );
  }

  /// Splits this stroke where it passes within [radius] of [center]
  /// (partial / area erasing). Returns `null` if the eraser misses the
  /// stroke, otherwise the surviving pieces (possibly empty).
  List<Stroke>? eraseCircle(
    Offset center,
    double radius,
    String Function() newId,
  ) {
    final r = radius + width / 2;
    if (!bounds.inflate(radius).contains(center)) return null;
    final r2 = r * r;
    bool anyHit = false;
    final pieces = <List<StrokePoint>>[];
    var current = <StrokePoint>[];
    for (final p in points) {
      final dx = p.x - center.dx, dy = p.y - center.dy;
      if (dx * dx + dy * dy <= r2) {
        anyHit = true;
        if (current.length >= 2) pieces.add(current);
        current = <StrokePoint>[];
      } else {
        current.add(p);
      }
    }
    if (!anyHit) {
      // Points can be sparse: also check segments crossing the eraser.
      if (!hitTest(center, threshold: radius)) return null;
      return const [];
    }
    if (current.length >= 2) pieces.add(current);
    return [
      for (final pts in pieces)
        Stroke(
          id: newId(),
          layerId: layerId,
          points: pts,
          colorValue: colorValue,
          width: width,
          opacity: opacity,
          toolType: toolType,
        ),
    ];
  }

  static double _r2(double v) => (v * 100).roundToDouble() / 100;
  static double _r3(double v) => (v * 1000).roundToDouble() / 1000;

  /// Compact point encoding: flat `[x, y, pressure, t, x, y, ...]`.
  /// ~3x faster to write and ~2.5x smaller than per-point objects.
  /// [fromJson] still reads the legacy `points` object list.
  List<num> _encodePoints() {
    final out = List<num>.filled(points.length * 4, 0);
    int i = 0;
    for (final p in points) {
      out[i++] = _r2(p.x);
      out[i++] = _r2(p.y);
      out[i++] = _r3(p.pressure);
      out[i++] = p.timestamp;
    }
    return out;
  }

  static List<StrokePoint> _decodePoints(List<dynamic> flat) {
    final n = flat.length ~/ 4;
    return List<StrokePoint>.generate(n, (k) {
      final i = k * 4;
      return StrokePoint(
        x: (flat[i] as num).toDouble(),
        y: (flat[i + 1] as num).toDouble(),
        pressure: (flat[i + 2] as num).toDouble(),
        timestamp: (flat[i + 3] as num).toInt(),
      );
    }, growable: false);
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'layerId': layerId,
    'pts': _encodePoints(),
    'colorValue': colorValue,
    'width': width,
    'opacity': opacity,
    'toolType': toolType.name,
  };

  factory Stroke.fromJson(Map<String, dynamic> json) {
    return Stroke(
      id: json['id'] as String,
      layerId: json['layerId'] as String? ?? 'default',
      points: json['pts'] is List
          ? _decodePoints(json['pts'] as List<dynamic>)
          : ((json['points'] as List<dynamic>?) ?? const [])
                .map((p) => StrokePoint.fromJson(p as Map<String, dynamic>))
                .toList(),
      colorValue: json['colorValue'] as int,
      width: (json['width'] as num).toDouble(),
      opacity: (json['opacity'] as num?)?.toDouble() ?? 1.0,
      toolType: ToolType.values.firstWhere(
        (e) => e.name == json['toolType'],
        orElse: () => ToolType.pen,
      ),
    );
  }
}
