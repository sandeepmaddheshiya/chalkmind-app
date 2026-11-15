import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/features/whiteboard/models/background_style.dart';
import 'package:boardflow/features/whiteboard/models/plot_model.dart';
import 'package:boardflow/features/whiteboard/recognition/math_function_parser.dart';

void main() {
  group('MathFunctionParser - Graphability Detection', () {
    test('Identifies standard graphable equations', () {
      expect(MathFunctionParser.isGraphable('y = x^2 - 4'), isTrue);
      expect(MathFunctionParser.isGraphable('y = sin(x)'), isTrue);
      expect(MathFunctionParser.isGraphable('y = 2x + 1'), isTrue);
      expect(MathFunctionParser.isGraphable('y = x^3 - 3x'), isTrue);
      expect(MathFunctionParser.isGraphable('x^2 + y^2 = 25'), isTrue);
      expect(MathFunctionParser.isGraphable('y = 1 / x'), isTrue);
      expect(MathFunctionParser.isGraphable('y = cos(x)'), isTrue);
      expect(MathFunctionParser.isGraphable('y = sqrt(x)'), isTrue);
    });

    test('Rejects non-graphable plain arithmetic or gibberish', () {
      expect(MathFunctionParser.isGraphable('15 * 8'), isFalse);
      expect(MathFunctionParser.isGraphable('144 + 6'), isFalse);
      expect(MathFunctionParser.isGraphable('Wizboard Teacher'), isFalse);
    });
  });

  group('MathFunctionParser - Function Evaluation & Key Points', () {
    test('Accurately evaluates parabola y = x^2 - 4 and detects roots & vertex', () {
      final fn = MathFunctionParser.parse('y = x^2 - 4');
      expect(fn, isNotNull);

      expect(fn!.evaluate(0), equals(-4.0));
      expect(fn.evaluate(2), equals(0.0));
      expect(fn.evaluate(-2), equals(0.0));
      expect(fn.evaluate(3), equals(5.0));

      final keyPoints = fn.findKeyPoints(-5.0, 5.0);
      final roots = keyPoints.where((k) => k.pointType == 'root').toList();
      final vertex = keyPoints.where((k) => k.pointType == 'vertex').toList();
      final yInt = keyPoints.where((k) => k.pointType == 'y_intercept').toList();

      expect(roots.length, greaterThanOrEqualTo(2));
      expect(roots.any((r) => (r.x - 2.0).abs() < 0.1), isTrue);
      expect(roots.any((r) => (r.x - (-2.0)).abs() < 0.1), isTrue);

      expect(vertex.isNotEmpty, isTrue);
      expect((vertex.first.x - 0.0).abs() < 0.1, isTrue);
      expect((vertex.first.y - (-4.0)).abs() < 0.1, isTrue);

      expect(yInt.isNotEmpty, isTrue);
      expect(yInt.first.y, equals(-4.0));
    });

    test('Accurately evaluates linear equation y = 2x + 1', () {
      final fn = MathFunctionParser.parse('y = 2x + 1');
      expect(fn, isNotNull);

      expect(fn!.evaluate(0), equals(1.0));
      expect(fn.evaluate(2), equals(5.0));
      expect(fn.evaluate(-0.5), equals(0.0));

      final keyPoints = fn.findKeyPoints(-5.0, 5.0);
      final roots = keyPoints.where((k) => k.pointType == 'root').toList();
      expect(roots.isNotEmpty, isTrue);
      expect((roots.first.x - (-0.5)).abs() < 0.1, isTrue);
    });

    test('Accurately evaluates circle x^2 + y^2 = 25 top and bottom branches', () {
      final fn = MathFunctionParser.parse('x^2 + y^2 = 25');
      expect(fn, isNotNull);
      expect(fn!.evaluateNegativeBranch, isNotNull);

      // Top branch: y = sqrt(25 - x^2)
      expect(fn.evaluate(0), equals(5.0));
      expect(fn.evaluate(3), equals(4.0));
      expect(fn.evaluate(4), equals(3.0));

      // Bottom branch: y = -sqrt(25 - x^2)
      expect(fn.evaluateNegativeBranch!(0), equals(-5.0));
      expect(fn.evaluateNegativeBranch!(3), equals(-4.0));
    });
  });

  group('PlotObject - Zoom, Pan & Model Serialization', () {
    test('Zoom in decreases span and zoom out increases span', () {
      final plot = const PlotObject(
        id: 'test_plot',
        equation: 'y = sin(x)',
        rect: Rect.fromLTWH(50, 50, 400, 300),
        xMin: -10,
        xMax: 10,
        yMin: -10,
        yMax: 10,
      );

      // Zoom in by factor 0.5
      final zoomedIn = plot.zoom(0.5);
      expect(zoomedIn.xMax - zoomedIn.xMin, equals(10.0)); // was 20, now 10
      expect(zoomedIn.xMin, equals(-5.0));
      expect(zoomedIn.xMax, equals(5.0));

      // Zoom out by factor 2.0
      final zoomedOut = zoomedIn.zoom(2.0);
      expect(zoomedOut.xMax - zoomedOut.xMin, equals(20.0));
      expect(zoomedOut.xMin, equals(-10.0));
      expect(zoomedOut.xMax, equals(10.0));
    });

    test('Pan shifts coordinate window correctly', () {
      final plot = const PlotObject(
        id: 'test_plot',
        equation: 'y = x',
        rect: Rect.fromLTWH(0, 0, 400, 300),
        xMin: -5,
        xMax: 5,
        yMin: -5,
        yMax: 5,
      );

      final panned = plot.pan(2.0, -1.0);
      expect(panned.xMin, equals(-3.0));
      expect(panned.xMax, equals(7.0));
      expect(panned.yMin, equals(-6.0));
      expect(panned.yMax, equals(4.0));
    });

    test('PlotObject JSON serialization roundtrip', () {
      final plot = const PlotObject(
        id: 'p123',
        equation: 'y = x^2 - 4',
        rect: Rect.fromLTWH(120, 180, 500, 400),
        xMin: -8.0,
        xMax: 8.0,
        yMin: -12.0,
        yMax: 12.0,
        colorValue: 0xFF10B981,
        showKeyPoints: false,
      );

      final json = plot.toJson();
      final restored = PlotObject.fromJson(json);

      expect(restored.id, equals(plot.id));
      expect(restored.equation, equals(plot.equation));
      expect(restored.rect.left, equals(plot.rect.left));
      expect(restored.rect.width, equals(plot.rect.width));
      expect(restored.xMin, equals(plot.xMin));
      expect(restored.xMax, equals(plot.xMax));
      expect(restored.colorValue, equals(plot.colorValue));
      expect(restored.showKeyPoints, equals(plot.showKeyPoints));
    });
  });

  group('Scientific Paper Backgrounds', () {
    test('Supports Isometric 3D and Polar Coordinates styles', () {
      expect(BackgroundStyle.isometric.displayName, equals('Isometric 3D'));
      expect(BackgroundStyle.polar.displayName, equals('Polar Coordinates'));

      final isoBg = const CanvasBackground(
        style: BackgroundStyle.isometric,
        spacing: 36.0,
      );
      final json = isoBg.toJson();
      final restored = CanvasBackground.fromJson(json);

      expect(restored.style, equals(BackgroundStyle.isometric));
      expect(restored.spacing, equals(36.0));
    });
  });
}
