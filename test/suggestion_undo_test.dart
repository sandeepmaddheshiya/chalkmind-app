// Undo / redo must withdraw "Convert to shape?" and similar offers.
import 'dart:math' as math;

import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A hand-drawn closed triangle.
Stroke triangle() {
  const corners = [(300.0, 200.0), (450.0, 460.0), (150.0, 460.0), (300.0, 200.0)];
  final pts = <StrokePoint>[];
  var t = 0;
  for (var i = 0; i < corners.length - 1; i++) {
    final (x0, y0) = corners[i];
    final (x1, y1) = corners[i + 1];
    for (var k = 0; k < 20; k++) {
      final f = k / 20;
      pts.add(StrokePoint(
        x: x0 + (x1 - x0) * f + math.sin(t * 0.7) * 0.8,
        y: y0 + (y1 - y0) * f,
        timestamp: t++ * 8,
      ));
    }
  }
  pts.add(StrokePoint(x: 300, y: 200, timestamp: t * 8));
  return Stroke(id: 'tri', points: pts, colorValue: 0xFF111827, width: 3.5, toolType: ToolType.pen);
}

void main() {
  late ProviderContainer c;
  late WhiteboardNotifier n;

  setUp(() {
    c = ProviderContainer();
    n = c.read(whiteboardControllerProvider.notifier);
    n.loadProject(ProjectModel.createEmpty());
    // Shape offers only: keep the math engine out of this test.
    if (c.read(whiteboardControllerProvider).isAutoMathEnabled) n.toggleAutoMath();
  });
  tearDown(() => c.dispose());

  test('undo withdraws the shape offer for the stroke it removed', () {
    n.addStroke(triangle());
    expect(c.read(whiteboardControllerProvider).shapeSuggestion, isNotNull,
        reason: 'precondition: the triangle is offered for conversion');
    n.undo();
    final s = c.read(whiteboardControllerProvider);
    expect(s.project.currentPage.strokes, isEmpty);
    expect(s.shapeSuggestion, isNull);
  });

  test('redo does not bring back a stale offer', () {
    n.addStroke(triangle());
    n.undo();
    n.redo();
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes, hasLength(1));
    expect(c.read(whiteboardControllerProvider).shapeSuggestion, isNull);
  });
}
