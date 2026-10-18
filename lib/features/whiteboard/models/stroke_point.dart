import 'dart:math' as math;
import 'package:flutter/material.dart';

class StrokePoint {
  final double x;
  final double y;
  final double pressure;
  final int timestamp; // Milliseconds since epoch

  const StrokePoint({
    required this.x,
    required this.y,
    this.pressure = 1.0,
    required this.timestamp,
  });

  Offset get offset => Offset(x, y);

  double distanceTo(StrokePoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return math.sqrt(dx * dx + dy * dy);
  }

  Map<String, dynamic> toJson() => {
    'x': double.parse(x.toStringAsFixed(2)),
    'y': double.parse(y.toStringAsFixed(2)),
    'pressure': double.parse(pressure.toStringAsFixed(3)),
    'timestamp': timestamp,
  };

  factory StrokePoint.fromJson(Map<String, dynamic> json) {
    return StrokePoint(
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      pressure: (json['pressure'] as num?)?.toDouble() ?? 1.0,
      timestamp: json['timestamp'] as int? ?? 0,
    );
  }

  factory StrokePoint.fromOffset(
    Offset offset, {
    double pressure = 1.0,
    int? timestamp,
  }) {
    return StrokePoint(
      x: offset.dx,
      y: offset.dy,
      pressure: pressure,
      timestamp: timestamp ?? DateTime.now().millisecondsSinceEpoch,
    );
  }
}
