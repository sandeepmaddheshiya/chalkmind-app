import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/recognition/handwriting_math_engine.dart';
import 'package:boardflow/features/whiteboard/recognition/handwriting_stroke_generator.dart';
import 'package:boardflow/features/whiteboard/recognition/math_evaluator.dart';
import 'package:boardflow/features/whiteboard/recognition/shape_detector.dart';
import 'package:boardflow/features/whiteboard/recognition/universal_math_engine.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_state.dart';
void main() {
  group('MathEvaluator tests', () {
    test('Basic arithmetic evaluation', () {
      final res1 = MathEvaluator.evaluate('15 * 8 =');
      expect(res1, isNotNull);
      expect(res1!.resultText, '120');
      expect(res1.fullEquation, '15 * 8 = 120');

      final res2 = MathEvaluator.evaluate('(24 + 16) / 5');
      expect(res2, isNotNull);
      expect(res2!.resultText, '8');

      final res3 = MathEvaluator.evaluate('12.5 + 7.5 =');
      expect(res3, isNotNull);
      expect(res3!.resultText, '20');
    });

    test('Powers, square roots, and percentages', () {
      final res1 = MathEvaluator.evaluate('2^8');
      expect(res1, isNotNull);
      expect(res1!.resultText, '256');

      final res2 = MathEvaluator.evaluate('sqrt(144) + 6');
      expect(res2, isNotNull);
      expect(res2!.resultText, '18');

      final res3 = MathEvaluator.evaluate('15% of 800 =');
      expect(res3, isNotNull);
      expect(res3!.resultText, '120');
    });

    test('Trigonometric expressions in degrees', () {
      final sinRes = MathEvaluator.evaluate('sin(30)');
      expect(sinRes, isNotNull);
      expect(sinRes!.numericResult, closeTo(0.5, 0.001));

      final cosRes = MathEvaluator.evaluate('cos(60)');
      expect(cosRes, isNotNull);
      expect(cosRes!.numericResult, closeTo(0.5, 0.001));
    });

    test('Invalid or incomplete math returns null safely without throwing', () {
      expect(MathEvaluator.evaluate('hello teacher'), isNull);
      expect(MathEvaluator.evaluate('x + y ='), isNull);
      expect(MathEvaluator.evaluate('5 / 0'), isNull); // Division by zero handled
    });
  });

  group('ShapeDetector tests', () {
    test('Detects hand-drawn circular stroke', () {
      // Generate points approximating a hand-drawn circle centered at (100, 100) with radius 50
      final points = <StrokePoint>[];
      const int steps = 36;
      for (int i = 0; i <= steps; i++) {
        final angle = (i / steps) * 2 * math.pi;
        // slight human hand noise (+/- 2px)
        final noise = (i % 3 == 0) ? 1.5 : -1.0;
        final r = 50.0 + noise;
        final x = 100.0 + r * math.cos(angle);
        final y = 100.0 + r * math.sin(angle);
        points.add(StrokePoint(x: x, y: y, timestamp: i * 20));
      }

      final stroke = Stroke(
        id: 'rough-circle',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(stroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.circle);
      expect(result.suggestedShape.shapeType, ShapeType.circle);
      expect(result.confidence, greaterThan(0.6));
    });

    test('Detects straight line stroke', () {
      final points = <StrokePoint>[
        const StrokePoint(x: 10, y: 10, timestamp: 1),
        const StrokePoint(x: 40, y: 11, timestamp: 2),
        const StrokePoint(x: 80, y: 10, timestamp: 3),
        const StrokePoint(x: 120, y: 12, timestamp: 4),
        const StrokePoint(x: 160, y: 10, timestamp: 5),
      ];

      final stroke = Stroke(
        id: 'rough-line',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(stroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.line);
    });

    test('Ignores random scribble or tiny mark', () {
      final tinyPoints = [
        const StrokePoint(x: 10, y: 10, timestamp: 1),
        const StrokePoint(x: 12, y: 12, timestamp: 2),
      ];
      final tinyStroke = Stroke(
        id: 'tiny',
        points: tinyPoints,
        colorValue: 0xFF000000,
        width: 2.0,
        toolType: ToolType.pen,
      );
      expect(ShapeDetector.detectShape(tinyStroke), isNull);
    });

    test('Detects hand-drawn 5-pointed star', () {
      // 5-pointed star outline: 5 outer tips (r=60), 5 inner valleys (r=24)
      final center = const Offset(150, 150);
      const rOuter = 60.0;
      const rInner = 24.0;
      final points = <StrokePoint>[];

      for (int i = 0; i <= 10; i++) {
        final angle = -math.pi / 2 + (i * math.pi / 5);
        final r = (i % 2 == 0) ? rOuter : rInner;
        final x = center.dx + r * math.cos(angle);
        final y = center.dy + r * math.sin(angle);
        points.add(StrokePoint(x: x, y: y, timestamp: i * 50));
      }

      final starStroke = Stroke(
        id: 'star-stroke',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(starStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.star);
      expect(result.suggestedShape.shapeType, ShapeType.star);
    });

    test('Detects hand-drawn triangle with custom vertices', () {
      final points = <StrokePoint>[
        const StrokePoint(x: 100, y: 50, timestamp: 1),
        const StrokePoint(x: 75, y: 100, timestamp: 2),
        const StrokePoint(x: 50, y: 150, timestamp: 3),
        const StrokePoint(x: 100, y: 150, timestamp: 4),
        const StrokePoint(x: 150, y: 150, timestamp: 5),
        const StrokePoint(x: 125, y: 100, timestamp: 6),
        const StrokePoint(x: 100, y: 50, timestamp: 7),
      ];

      final triStroke = Stroke(
        id: 'triangle-stroke',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(triStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.triangle);
      expect(result.suggestedShape.customVertices, isNotNull);
      expect(result.suggestedShape.customVertices!.length, 3);
    });
  });

  group('HandwritingMathEngine slanted equation tests', () {
    test('Detects 2 + 2 = at a 25-degree slant angle', () {
      // Slant angle: ~25 degrees upward (cos ~0.90, sin ~ -0.42)
      final slantAngle = -0.45; // ~25.7 deg up
      final dir = Offset(math.cos(slantAngle), math.sin(slantAngle));
      final normal = Offset(-dir.dy, dir.dx);

      Offset slant(double u, double v) {
        const origin = Offset(200, 300);
        return origin + dir * u + normal * v;
      }

      // Stroke 1: '2' (u: 0..40, v: 0..60)
      final p2A = slant(5, 5);
      final p2B = slant(30, 0);
      final p2C = slant(40, 15);
      final p2D = slant(5, 55);
      final p2E = slant(40, 60);
      final s2A = Stroke(
        id: 'digit-2A',
        points: [
          StrokePoint(x: p2A.dx, y: p2A.dy, timestamp: 1),
          StrokePoint(x: p2B.dx, y: p2B.dy, timestamp: 2),
          StrokePoint(x: p2C.dx, y: p2C.dy, timestamp: 3),
          StrokePoint(x: p2D.dx, y: p2D.dy, timestamp: 4),
          StrokePoint(x: p2E.dx, y: p2E.dy, timestamp: 5),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 2 & 3: '+' at u: 70..100, v: 15..45
      final pPlusH1 = slant(70, 30);
      final pPlusH2 = slant(100, 30);
      final sPlusH = Stroke(
        id: 'plus-h',
        points: [
          StrokePoint(x: pPlusH1.dx, y: pPlusH1.dy, timestamp: 10),
          StrokePoint(x: pPlusH2.dx, y: pPlusH2.dy, timestamp: 11),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final pPlusV1 = slant(85, 15);
      final pPlusV2 = slant(85, 45);
      final sPlusV = Stroke(
        id: 'plus-v',
        points: [
          StrokePoint(x: pPlusV1.dx, y: pPlusV1.dy, timestamp: 12),
          StrokePoint(x: pPlusV2.dx, y: pPlusV2.dy, timestamp: 13),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 4: second '2' (u: 130..170, v: 0..60)
      final p2_2A = slant(135, 5);
      final p2_2B = slant(160, 0);
      final p2_2C = slant(170, 15);
      final p2_2D = slant(135, 55);
      final p2_2E = slant(170, 60);
      final s2B = Stroke(
        id: 'digit-2B',
        points: [
          StrokePoint(x: p2_2A.dx, y: p2_2A.dy, timestamp: 20),
          StrokePoint(x: p2_2B.dx, y: p2_2B.dy, timestamp: 21),
          StrokePoint(x: p2_2C.dx, y: p2_2C.dy, timestamp: 22),
          StrokePoint(x: p2_2D.dx, y: p2_2D.dy, timestamp: 23),
          StrokePoint(x: p2_2E.dx, y: p2_2E.dy, timestamp: 24),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 5 & 6: '=' bars (u: 200..240, v: 22 and 38)
      final pEq1A = slant(200, 22);
      final pEq1B = slant(240, 22);
      final sEq1 = Stroke(
        id: 'eq-bar1',
        points: [
          StrokePoint(x: pEq1A.dx, y: pEq1A.dy, timestamp: 30),
          StrokePoint(x: pEq1B.dx, y: pEq1B.dy, timestamp: 31),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final pEq2A = slant(200, 38);
      final pEq2B = slant(240, 38);
      final sEq2 = Stroke(
        id: 'eq-bar2',
        points: [
          StrokePoint(x: pEq2A.dx, y: pEq2A.dy, timestamp: 32),
          StrokePoint(x: pEq2B.dx, y: pEq2B.dy, timestamp: 33),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final strokes = [s2A, sPlusH, sPlusV, s2B, sEq1, sEq2];

      final detection = HandwritingMathEngine.detectHandwrittenEquation(strokes);
      expect(detection, isNotNull);
      expect(detection!.answer, '4');
      expect(detection.expression, contains('2 + 2 ='));
    });

    test('Detects 5 + 5 = at a slant angle producing 10', () {
      final slantAngle = -0.40;
      final dir = Offset(math.cos(slantAngle), math.sin(slantAngle));
      final normal = Offset(-dir.dy, dir.dx);

      Offset slant(double u, double v) {
        const origin = Offset(150, 400);
        return origin + dir * u + normal * v;
      }

      // Stroke 1: '5' (starts top-right, goes top-left, down, loops right, ends bottom-left)
      final s5A = Stroke(
        id: 'digit-5A',
        points: [
          StrokePoint(x: slant(35, 5).dx, y: slant(35, 5).dy, timestamp: 1),
          StrokePoint(x: slant(10, 5).dx, y: slant(10, 5).dy, timestamp: 2),
          StrokePoint(x: slant(10, 30).dx, y: slant(10, 30).dy, timestamp: 3),
          StrokePoint(x: slant(40, 40).dx, y: slant(40, 40).dy, timestamp: 4),
          StrokePoint(x: slant(35, 55).dx, y: slant(35, 55).dy, timestamp: 5),
          StrokePoint(x: slant(15, 55).dx, y: slant(15, 55).dy, timestamp: 6),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 2 & 3: '+'
      final sPlusH = Stroke(
        id: 'plus-5h',
        points: [
          StrokePoint(x: slant(70, 30).dx, y: slant(70, 30).dy, timestamp: 10),
          StrokePoint(x: slant(100, 30).dx, y: slant(100, 30).dy, timestamp: 11),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sPlusV = Stroke(
        id: 'plus-5v',
        points: [
          StrokePoint(x: slant(85, 15).dx, y: slant(85, 15).dy, timestamp: 12),
          StrokePoint(x: slant(85, 45).dx, y: slant(85, 45).dy, timestamp: 13),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 4: second '5'
      final s5B = Stroke(
        id: 'digit-5B',
        points: [
          StrokePoint(x: slant(165, 5).dx, y: slant(165, 5).dy, timestamp: 20),
          StrokePoint(x: slant(140, 5).dx, y: slant(140, 5).dy, timestamp: 21),
          StrokePoint(x: slant(140, 30).dx, y: slant(140, 30).dy, timestamp: 22),
          StrokePoint(x: slant(170, 40).dx, y: slant(170, 40).dy, timestamp: 23),
          StrokePoint(x: slant(165, 55).dx, y: slant(165, 55).dy, timestamp: 24),
          StrokePoint(x: slant(145, 55).dx, y: slant(145, 55).dy, timestamp: 25),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 5 & 6: '='
      final sEq1 = Stroke(
        id: 'eq-5-1',
        points: [
          StrokePoint(x: slant(200, 22).dx, y: slant(200, 22).dy, timestamp: 30),
          StrokePoint(x: slant(240, 22).dx, y: slant(240, 22).dy, timestamp: 31),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq2 = Stroke(
        id: 'eq-5-2',
        points: [
          StrokePoint(x: slant(200, 38).dx, y: slant(200, 38).dy, timestamp: 32),
          StrokePoint(x: slant(240, 38).dx, y: slant(240, 38).dy, timestamp: 33),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final strokes = [s5A, sPlusH, sPlusV, s5B, sEq1, sEq2];
      final detection = HandwritingMathEngine.detectHandwrittenEquation(strokes);

      expect(detection, isNotNull);
      expect(detection!.answer, '10');
      expect(detection.expression, contains('5 + 5 ='));
    });

    test('Detects 9 * 12 = and calculates 108 in real-time without silly mistakes', () {
      // Stroke 1: '9' (starts top-right, loops in upper half, stem straight down)
      final s9 = Stroke(
        id: 'digit-9',
        points: const [
          StrokePoint(x: 35, y: 20, timestamp: 1),
          StrokePoint(x: 20, y: 10, timestamp: 2),
          StrokePoint(x: 10, y: 20, timestamp: 3),
          StrokePoint(x: 20, y: 32, timestamp: 4),
          StrokePoint(x: 35, y: 32, timestamp: 5), // loop meets
          StrokePoint(x: 35, y: 45, timestamp: 6),
          StrokePoint(x: 35, y: 60, timestamp: 7), // stem ends at bottom
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 2 & 3: '*' (multiply cross)
      final sMult1 = Stroke(
        id: 'mult-diag1',
        points: const [
          StrokePoint(x: 55, y: 22, timestamp: 10),
          StrokePoint(x: 80, y: 48, timestamp: 11),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sMult2 = Stroke(
        id: 'mult-diag2',
        points: const [
          StrokePoint(x: 80, y: 22, timestamp: 12),
          StrokePoint(x: 55, y: 48, timestamp: 13),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 4: '1'
      final s1 = Stroke(
        id: 'digit-1',
        points: const [
          StrokePoint(x: 105, y: 15, timestamp: 15),
          StrokePoint(x: 105, y: 60, timestamp: 16),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 5: '2'
      final s2 = Stroke(
        id: 'digit-2',
        points: const [
          StrokePoint(x: 125, y: 25, timestamp: 20),
          StrokePoint(x: 140, y: 15, timestamp: 21),
          StrokePoint(x: 145, y: 30, timestamp: 22),
          StrokePoint(x: 125, y: 60, timestamp: 23),
          StrokePoint(x: 150, y: 60, timestamp: 24),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 6 & 7: '='
      final sEq1 = Stroke(
        id: 'eq-9-1',
        points: const [
          StrokePoint(x: 175, y: 30, timestamp: 30),
          StrokePoint(x: 215, y: 30, timestamp: 31),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq2 = Stroke(
        id: 'eq-9-2',
        points: const [
          StrokePoint(x: 175, y: 46, timestamp: 32),
          StrokePoint(x: 215, y: 46, timestamp: 33),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final strokes = [s9, sMult1, sMult2, s1, s2, sEq1, sEq2];
      final detection = HandwritingMathEngine.detectHandwrittenEquation(strokes);

      expect(detection, isNotNull);
      expect(detection!.answer, '108');
      expect(detection.expression, contains('9 * 12 ='));
    });

    test('Detects 2^2 + 5 = with superscript exponent and calculates 9', () {
      // Stroke 1: Baseline '2' (height = 45, center y = 37)
      final s2A = Stroke(
        id: 'base-2',
        points: const [
          StrokePoint(x: 20, y: 25, timestamp: 1),
          StrokePoint(x: 35, y: 15, timestamp: 2),
          StrokePoint(x: 40, y: 30, timestamp: 3),
          StrokePoint(x: 20, y: 60, timestamp: 4),
          StrokePoint(x: 45, y: 60, timestamp: 5),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 2: Superscript '2' (height = 20, elevated at y = 5..25, center y = 15)
      final s2Exp = Stroke(
        id: 'exp-2',
        points: const [
          StrokePoint(x: 55, y: 10, timestamp: 10),
          StrokePoint(x: 65, y: 5, timestamp: 11),
          StrokePoint(x: 68, y: 12, timestamp: 12),
          StrokePoint(x: 55, y: 25, timestamp: 13),
          StrokePoint(x: 70, y: 25, timestamp: 14),
        ],
        colorValue: 0xFF000000,
        width: 2.5,
        toolType: ToolType.pen,
      );

      // Stroke 3 & 4: '+'
      final sPlusH = Stroke(
        id: 'plus-h',
        points: const [
          StrokePoint(x: 85, y: 38, timestamp: 20),
          StrokePoint(x: 115, y: 38, timestamp: 21),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sPlusV = Stroke(
        id: 'plus-v',
        points: const [
          StrokePoint(x: 100, y: 23, timestamp: 22),
          StrokePoint(x: 100, y: 53, timestamp: 23),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 5: '5'
      final s5 = Stroke(
        id: 'digit-5',
        points: const [
          StrokePoint(x: 150, y: 18, timestamp: 30),
          StrokePoint(x: 130, y: 18, timestamp: 31),
          StrokePoint(x: 130, y: 35, timestamp: 32),
          StrokePoint(x: 155, y: 42, timestamp: 33),
          StrokePoint(x: 150, y: 60, timestamp: 34),
          StrokePoint(x: 130, y: 60, timestamp: 35),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 6 & 7: '='
      final sEq1 = Stroke(
        id: 'eq-exp-1',
        points: const [
          StrokePoint(x: 180, y: 30, timestamp: 40),
          StrokePoint(x: 220, y: 30, timestamp: 41),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq2 = Stroke(
        id: 'eq-exp-2',
        points: const [
          StrokePoint(x: 180, y: 46, timestamp: 42),
          StrokePoint(x: 220, y: 46, timestamp: 43),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final strokes = [s2A, s2Exp, sPlusH, sPlusV, s5, sEq1, sEq2];
      final detection = HandwritingMathEngine.detectHandwrittenEquation(strokes);

      expect(detection, isNotNull);
      expect(detection!.answer, '9');
      expect(detection.expression, contains('2^2 + 5 ='));
    });

    test('Math strokes (+ and =) are never falsely recognized as a 4-stroke rectangle', () {
      final sPlusH = Stroke(
        id: 'p-h',
        points: const [
          StrokePoint(x: 100, y: 150, timestamp: 1),
          StrokePoint(x: 150, y: 150, timestamp: 2),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );
      final sPlusV = Stroke(
        id: 'p-v',
        points: const [
          StrokePoint(x: 125, y: 125, timestamp: 3),
          StrokePoint(x: 125, y: 175, timestamp: 4),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );
      final sEq1 = Stroke(
        id: 'e-1',
        points: const [
          StrokePoint(x: 200, y: 140, timestamp: 5),
          StrokePoint(x: 250, y: 140, timestamp: 6),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );
      final sEq2 = Stroke(
        id: 'e-2',
        points: const [
          StrokePoint(x: 200, y: 160, timestamp: 7),
          StrokePoint(x: 250, y: 160, timestamp: 8),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final mathStrokes = [sPlusH, sPlusV, sEq1, sEq2];
      final result = ShapeDetector.detectMultiStrokeShape(mathStrokes);
      expect(result, isNull, reason: 'Math strokes must never be detected as a rectangle');
      expect(HandwritingMathEngine.hasEqualSign(mathStrokes), isTrue);
    });

    test('Non-arithmetic variables (like cursive y =) never hallucinate numbers', () {
      // Stroke 1: Cursive 'y' with descending loop
      final sY = Stroke(
        id: 'var-y',
        points: const [
          StrokePoint(x: 100, y: 150, timestamp: 1),
          StrokePoint(x: 120, y: 180, timestamp: 2),
          StrokePoint(x: 140, y: 150, timestamp: 3),
          StrokePoint(x: 140, y: 220, timestamp: 4),
          StrokePoint(x: 110, y: 240, timestamp: 5),
          StrokePoint(x: 95, y: 200, timestamp: 6),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq1 = Stroke(
        id: 'eq-y-1',
        points: const [
          StrokePoint(x: 170, y: 160, timestamp: 10),
          StrokePoint(x: 210, y: 160, timestamp: 11),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq2 = Stroke(
        id: 'eq-y-2',
        points: const [
          StrokePoint(x: 170, y: 175, timestamp: 12),
          StrokePoint(x: 210, y: 175, timestamp: 13),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final strokes = [sY, sEq1, sEq2];
      // Local single-line engine must return null so multimodal Vision AI is delegated to
      final localResult = HandwritingMathEngine.detectHandwrittenEquation(strokes);
      expect(localResult, isNull, reason: 'Must not hallucinate bogus arithmetic numbers on variable equations');

      // Problem strokes must capture the problem context
      final problemStrokes = HandwritingMathEngine.getProblemStrokes(strokes);
      expect(problemStrokes.length, greaterThanOrEqualTo(2));
    });

    test('Geometry diagram with slanted x = delegates to Vision AI without hallucinating powers', () {
      // Right triangle strokes + 'x =' on hypotenuse
      final legV = Stroke(
        id: 'tri-leg-v',
        points: const [
          StrokePoint(x: 100, y: 100, timestamp: 1),
          StrokePoint(x: 100, y: 300, timestamp: 2),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final legH = Stroke(
        id: 'tri-leg-h',
        points: const [
          StrokePoint(x: 100, y: 300, timestamp: 3),
          StrokePoint(x: 350, y: 300, timestamp: 4),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final hyp = Stroke(
        id: 'tri-hyp',
        points: const [
          StrokePoint(x: 100, y: 100, timestamp: 5),
          StrokePoint(x: 350, y: 300, timestamp: 6),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Label '2' on vertical leg
      final s2 = Stroke(
        id: 'label-2',
        points: const [
          StrokePoint(x: 70, y: 180, timestamp: 7),
          StrokePoint(x: 85, y: 170, timestamp: 8),
          StrokePoint(x: 88, y: 185, timestamp: 9),
          StrokePoint(x: 70, y: 215, timestamp: 10),
          StrokePoint(x: 90, y: 215, timestamp: 11),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // 'x =' on hypotenuse
      final sX = Stroke(
        id: 'label-x',
        points: const [
          StrokePoint(x: 230, y: 170, timestamp: 12),
          StrokePoint(x: 255, y: 195, timestamp: 13),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq1 = Stroke(
        id: 'eq-diag-1',
        points: const [
          StrokePoint(x: 265, y: 175, timestamp: 14),
          StrokePoint(x: 295, y: 175, timestamp: 15),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final sEq2 = Stroke(
        id: 'eq-diag-2',
        points: const [
          StrokePoint(x: 265, y: 190, timestamp: 16),
          StrokePoint(x: 295, y: 190, timestamp: 17),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final allStrokes = [legV, legH, hyp, s2, sX, sEq1, sEq2];
      final localResult = HandwritingMathEngine.detectHandwrittenEquation(allStrokes);
      // ignore: avoid_print
      print('DEBUG localResult: ${localResult?.expression} => ${localResult?.answer}');
      expect(localResult, isNull, reason: 'Diagram with x = must return null locally and delegate to Vision AI');

      final problemStrokes = HandwritingMathEngine.getProblemStrokes(allStrokes);
      expect(problemStrokes.length, allStrokes.length, reason: 'All diagram strokes must be sent to Vision AI');
    });

    test('System of equations (x = 3, y = x + 2, y =) delegates to Vision AI and returns null locally', () {
      // Line 1: x = 3 (y ~ 100)
      final sLine1X1 = Stroke(id: 'l1-x1', points: const [StrokePoint(x: 100, y: 80, timestamp: 1), StrokePoint(x: 120, y: 110, timestamp: 2)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine1X2 = Stroke(id: 'l1-x2', points: const [StrokePoint(x: 120, y: 80, timestamp: 3), StrokePoint(x: 100, y: 110, timestamp: 4)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine1Eq1 = Stroke(id: 'l1-eq1', points: const [StrokePoint(x: 135, y: 90, timestamp: 5), StrokePoint(x: 160, y: 90, timestamp: 6)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine1Eq2 = Stroke(id: 'l1-eq2', points: const [StrokePoint(x: 135, y: 102, timestamp: 7), StrokePoint(x: 160, y: 102, timestamp: 8)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine1Three = Stroke(id: 'l1-3', points: const [StrokePoint(x: 180, y: 80, timestamp: 9), StrokePoint(x: 195, y: 88, timestamp: 10), StrokePoint(x: 185, y: 95, timestamp: 11), StrokePoint(x: 195, y: 105, timestamp: 12), StrokePoint(x: 180, y: 112, timestamp: 13)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);

      // Line 2: y = x + 2 (y ~ 200)
      final sLine2Y = Stroke(id: 'l2-y', points: const [StrokePoint(x: 100, y: 180, timestamp: 20), StrokePoint(x: 110, y: 200, timestamp: 21), StrokePoint(x: 120, y: 185, timestamp: 22), StrokePoint(x: 115, y: 225, timestamp: 23)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2Eq1 = Stroke(id: 'l2-eq1', points: const [StrokePoint(x: 135, y: 190, timestamp: 24), StrokePoint(x: 160, y: 190, timestamp: 25)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2Eq2 = Stroke(id: 'l2-eq2', points: const [StrokePoint(x: 135, y: 202, timestamp: 26), StrokePoint(x: 160, y: 202, timestamp: 27)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2X1 = Stroke(id: 'l2-x1', points: const [StrokePoint(x: 175, y: 180, timestamp: 28), StrokePoint(x: 195, y: 210, timestamp: 29)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2X2 = Stroke(id: 'l2-x2', points: const [StrokePoint(x: 195, y: 180, timestamp: 30), StrokePoint(x: 175, y: 210, timestamp: 31)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2PlusH = Stroke(id: 'l2-ph', points: const [StrokePoint(x: 210, y: 195, timestamp: 32), StrokePoint(x: 230, y: 195, timestamp: 33)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2PlusV = Stroke(id: 'l2-pv', points: const [StrokePoint(x: 220, y: 185, timestamp: 34), StrokePoint(x: 220, y: 205, timestamp: 35)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine2Two = Stroke(id: 'l2-2', points: const [StrokePoint(x: 245, y: 185, timestamp: 36), StrokePoint(x: 260, y: 180, timestamp: 37), StrokePoint(x: 262, y: 190, timestamp: 38), StrokePoint(x: 245, y: 212, timestamp: 39), StrokePoint(x: 265, y: 212, timestamp: 40)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);

      // Line 3: y = (y ~ 300)
      final sLine3Y = Stroke(id: 'l3-y', points: const [StrokePoint(x: 100, y: 280, timestamp: 50), StrokePoint(x: 110, y: 300, timestamp: 51), StrokePoint(x: 120, y: 285, timestamp: 52), StrokePoint(x: 115, y: 325, timestamp: 53)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine3Eq1 = Stroke(id: 'l3-eq1', points: const [StrokePoint(x: 135, y: 290, timestamp: 54), StrokePoint(x: 160, y: 290, timestamp: 55)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);
      final sLine3Eq2 = Stroke(id: 'l3-eq2', points: const [StrokePoint(x: 135, y: 302, timestamp: 56), StrokePoint(x: 160, y: 302, timestamp: 57)], colorValue: 0xFF000000, width: 3.0, toolType: ToolType.pen);

      final systemStrokes = [
        sLine1X1, sLine1X2, sLine1Eq1, sLine1Eq2, sLine1Three,
        sLine2Y, sLine2Eq1, sLine2Eq2, sLine2X1, sLine2X2, sLine2PlusH, sLine2PlusV, sLine2Two,
        sLine3Y, sLine3Eq1, sLine3Eq2,
      ];

      final localResult = HandwritingMathEngine.detectHandwrittenEquation(systemStrokes);
      expect(localResult, isNull, reason: 'Multi-line system of equations must NOT hallucinate arithmetic; must return null and delegate to Vision AI');

      final problemStrokes = HandwritingMathEngine.getProblemStrokes(systemStrokes);
      expect(problemStrokes.length, systemStrokes.length, reason: 'All system of equations strokes must be sent to Vision AI');
    });
  });

  group('ShapeDetector Square and Star Specific Tests', () {
    test('Hand-drawn square with sharp corners detects as Rectangle, NEVER as Circle', () {
      // 4 corners of a square: (100, 100) -> (220, 100) -> (220, 220) -> (100, 220) -> (100, 100)
      final points = <StrokePoint>[
        // Top edge
        const StrokePoint(x: 100, y: 100, timestamp: 1),
        const StrokePoint(x: 140, y: 99, timestamp: 2),
        const StrokePoint(x: 180, y: 101, timestamp: 3),
        const StrokePoint(x: 220, y: 100, timestamp: 4),
        // Right edge
        const StrokePoint(x: 219, y: 140, timestamp: 5),
        const StrokePoint(x: 221, y: 180, timestamp: 6),
        const StrokePoint(x: 220, y: 220, timestamp: 7),
        // Bottom edge
        const StrokePoint(x: 180, y: 221, timestamp: 8),
        const StrokePoint(x: 140, y: 219, timestamp: 9),
        const StrokePoint(x: 100, y: 220, timestamp: 10),
        // Left edge
        const StrokePoint(x: 101, y: 180, timestamp: 11),
        const StrokePoint(x: 99, y: 140, timestamp: 12),
        const StrokePoint(x: 100, y: 100, timestamp: 13),
      ];

      final squareStroke = Stroke(
        id: 'hand-drawn-square',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(squareStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.rectangle);
      expect(result.shapeType, isNot(ShapeType.circle));
    });

    test('Detects hand-drawn crossed pentagram star', () {
      // 5-point crossed star (pentagram) drawn in 1 stroke:
      // Tip 1 (top): (150, 50)
      // Tip 3 (bottom-right): (220, 220)
      // Tip 5 (top-left): (80, 110)
      // Tip 2 (top-right): (220, 110)
      // Tip 4 (bottom-left): (80, 220)
      // Back to Tip 1: (150, 50)
      final points = <StrokePoint>[
        const StrokePoint(x: 150, y: 50, timestamp: 1),
        const StrokePoint(x: 185, y: 135, timestamp: 2),
        const StrokePoint(x: 220, y: 220, timestamp: 3),
        const StrokePoint(x: 150, y: 165, timestamp: 4),
        const StrokePoint(x: 80, y: 110, timestamp: 5),
        const StrokePoint(x: 150, y: 110, timestamp: 6),
        const StrokePoint(x: 220, y: 110, timestamp: 7),
        const StrokePoint(x: 150, y: 165, timestamp: 8),
        const StrokePoint(x: 80, y: 220, timestamp: 9),
        const StrokePoint(x: 115, y: 135, timestamp: 10),
        const StrokePoint(x: 150, y: 50, timestamp: 11),
      ];

      final starStroke = Stroke(
        id: 'pentagram-star',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(starStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.star);
    });

    test('Hand-drawn square with corner overshoot detects as Rectangle, NEVER as Star', () {
      // The exact failure mode from user screenshot 4:
      // Start (100, 100) -> (220, 100) -> (220, 220) -> (100, 220) -> (100, 100) -> overshoot to (125, 100)
      final points = <StrokePoint>[
        const StrokePoint(x: 100, y: 100, timestamp: 1),
        const StrokePoint(x: 140, y: 100, timestamp: 2),
        const StrokePoint(x: 180, y: 100, timestamp: 3),
        const StrokePoint(x: 220, y: 100, timestamp: 4),
        const StrokePoint(x: 220, y: 140, timestamp: 5),
        const StrokePoint(x: 220, y: 180, timestamp: 6),
        const StrokePoint(x: 220, y: 220, timestamp: 7),
        const StrokePoint(x: 180, y: 220, timestamp: 8),
        const StrokePoint(x: 140, y: 220, timestamp: 9),
        const StrokePoint(x: 100, y: 220, timestamp: 10),
        const StrokePoint(x: 100, y: 180, timestamp: 11),
        const StrokePoint(x: 100, y: 140, timestamp: 12),
        const StrokePoint(x: 100, y: 100, timestamp: 13),
        // Corner overshoot stub past the starting corner:
        const StrokePoint(x: 115, y: 100, timestamp: 14),
        const StrokePoint(x: 128, y: 101, timestamp: 15),
      ];

      final squareWithOvershoot = Stroke(
        id: 'square-overshoot',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(squareWithOvershoot);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.rectangle, reason: 'Square with overshoot must be detected as Rectangle');
      expect(result.shapeType, isNot(ShapeType.star), reason: 'Square must NEVER be falsely classified as a Star');
    });

    test('Detects hand-drawn single-stroke Arrow', () {
      final points = <StrokePoint>[
        // Shaft from (100, 100) to (300, 100)
        const StrokePoint(x: 100, y: 100, timestamp: 1),
        const StrokePoint(x: 150, y: 101, timestamp: 2),
        const StrokePoint(x: 200, y: 100, timestamp: 3),
        const StrokePoint(x: 250, y: 99, timestamp: 4),
        const StrokePoint(x: 300, y: 100, timestamp: 5), // Tip
        // Backward barb from (300, 100) to (270, 80)
        const StrokePoint(x: 285, y: 90, timestamp: 6),
        const StrokePoint(x: 270, y: 80, timestamp: 7),
      ];

      final arrowStroke = Stroke(
        id: 'single-stroke-arrow',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(arrowStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.arrow);
      expect(result.suggestedShape.end.dx, closeTo(300, 5));
    });

    test('Detects hand-drawn two-stroke Arrow', () {
      // Stroke 1: Shaft
      final s1 = Stroke(
        id: 'arrow-shaft',
        points: const [
          StrokePoint(x: 50, y: 150, timestamp: 1),
          StrokePoint(x: 150, y: 150, timestamp: 2),
          StrokePoint(x: 250, y: 150, timestamp: 3),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      // Stroke 2: V-head at (250, 150)
      final s2 = Stroke(
        id: 'arrow-head',
        points: const [
          StrokePoint(x: 225, y: 130, timestamp: 4),
          StrokePoint(x: 250, y: 150, timestamp: 5),
          StrokePoint(x: 225, y: 170, timestamp: 6),
        ],
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectMultiStrokeShape([s1, s2]);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.arrow);
      expect(result.originalStrokes?.length, 2);
    });

    test('Hand-drawn triangle with overshoot detects as Triangle and regularizes cleanly', () {
      final points = <StrokePoint>[
        const StrokePoint(x: 150, y: 50, timestamp: 1),
        const StrokePoint(x: 185, y: 125, timestamp: 2),
        const StrokePoint(x: 220, y: 200, timestamp: 3),
        const StrokePoint(x: 150, y: 200, timestamp: 4),
        const StrokePoint(x: 80, y: 200, timestamp: 5),
        const StrokePoint(x: 115, y: 125, timestamp: 6),
        const StrokePoint(x: 150, y: 50, timestamp: 7),
        // slight closure overshoot
        const StrokePoint(x: 165, y: 80, timestamp: 8),
      ];

      final triStroke = Stroke(
        id: 'triangle-overshoot',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(triStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.triangle);
      expect(result.suggestedShape.customVertices, isNotNull);
      expect(result.suggestedShape.customVertices!.length, 3);
    });

    test('Hand-drawn square with rounded corners detects as Rectangle, NEVER as Star (Screenshot 2)', () {
      // Stroke resembling Screenshot 2: drawn starting top-left, going down, right with sag/curve, up, left
      final points = <StrokePoint>[
        const StrokePoint(x: 100, y: 100, timestamp: 1),
        const StrokePoint(x: 102, y: 150, timestamp: 2),
        const StrokePoint(x: 105, y: 200, timestamp: 3),
        const StrokePoint(x: 115, y: 215, timestamp: 4), // rounded corner
        const StrokePoint(x: 150, y: 220, timestamp: 5), // bottom edge
        const StrokePoint(x: 200, y: 218, timestamp: 6),
        const StrokePoint(x: 218, y: 205, timestamp: 7), // rounded corner
        const StrokePoint(x: 220, y: 160, timestamp: 8), // right edge
        const StrokePoint(x: 222, y: 105, timestamp: 9),
        const StrokePoint(x: 215, y: 98, timestamp: 10), // rounded corner
        const StrokePoint(x: 160, y: 100, timestamp: 11), // top edge
        const StrokePoint(x: 100, y: 102, timestamp: 12),
      ];

      final squareStroke = Stroke(
        id: 'rounded-square',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(squareStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.rectangle, reason: 'Must detect as Rectangle');
      expect(result.shapeType, isNot(ShapeType.star), reason: 'Must NEVER falsely detect as Star');
    });

    test('Detects hand-drawn regular Pentagon (5-sided polygon)', () {
      final center = const Offset(150, 150);
      const radius = 60.0;
      final points = <StrokePoint>[];

      for (int i = 0; i <= 5; i++) {
        final angle = -math.pi / 2 + (i * 2 * math.pi / 5);
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        points.add(StrokePoint(x: x, y: y, timestamp: i * 50));
      }

      final pentagonStroke = Stroke(
        id: 'pentagon-stroke',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(pentagonStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.pentagon);
      expect(result.suggestedShape.shapeType, ShapeType.pentagon);
    });

    test('Detects hand-drawn regular Hexagon (6-sided polygon)', () {
      final center = const Offset(150, 150);
      const radius = 60.0;
      final points = <StrokePoint>[];

      for (int i = 0; i <= 6; i++) {
        final angle = (i * 2 * math.pi / 6);
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        points.add(StrokePoint(x: x, y: y, timestamp: i * 50));
      }

      final hexagonStroke = Stroke(
        id: 'hexagon-stroke',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(hexagonStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.hexagon);
      expect(result.suggestedShape.shapeType, ShapeType.hexagon);
    });

    test('Detects hand-drawn regular Octagon (8-sided polygon)', () {
      final center = const Offset(150, 150);
      const radius = 60.0;
      final points = <StrokePoint>[];

      for (int i = 0; i <= 8; i++) {
        final angle = -math.pi / 8 + (i * 2 * math.pi / 8);
        final x = center.dx + radius * math.cos(angle);
        final y = center.dy + radius * math.sin(angle);
        points.add(StrokePoint(x: x, y: y, timestamp: i * 50));
      }

      final octagonStroke = Stroke(
        id: 'octagon-stroke',
        points: points,
        colorValue: 0xFF000000,
        width: 3.0,
        toolType: ToolType.pen,
      );

      final result = ShapeDetector.detectShape(octagonStroke);
      expect(result, isNotNull);
      expect(result!.shapeType, ShapeType.octagon);
      expect(result.suggestedShape.shapeType, ShapeType.octagon);
    });
  });

  group('Algebraic Formulas Real-Time (0ms) Tests', () {
    test('Evaluates a^3 - b^3 = algebraically without hallucinating arithmetic', () {
      final res = MathEvaluator.evaluate('a^3 - b^3 =');
      expect(res, isNotNull);
      expect(res!.resultText, '(a - b)(a² + ab + b²)');
      expect(res.fullEquation, 'a^3 - b^3 = (a - b)(a² + ab + b²)');
    });

    test('Evaluates (a + b)^2 = algebraically in real time', () {
      final res = MathEvaluator.evaluate('(a + b)^2 =');
      expect(res, isNotNull);
      expect(res!.resultText, 'a² + 2ab + b²');
    });

    test('Generates handwritten strokes for algebraic answer (a - b)(a² + ab + b²)', () {
      final strokes = HandwritingStrokeGenerator.generateHandwrittenStrokes(
        text: '(a - b)(a² + ab + b²)',
        startPosition: const Offset(100, 100),
        characterHeight: 32.0,
        colorValue: 0xFF000000,
        strokeWidth: 3.0,
      );

      expect(strokes, isNotEmpty);
      expect(strokes.length, greaterThan(10));
      for (final s in strokes) {
        expect(s.points, isNotEmpty);
      }
    });

    test('Generates pedagogical steps and theoretical explanation for a^3 - b^3', () {
      final details = UniversalMathEngine.getStepsAndExplanation('a^3 - b^3 =', '(a - b)(a² + ab + b²)');
      expect(details.steps, isNotEmpty);
      expect(details.steps.length, greaterThanOrEqualTo(3));
      expect(details.steps.first, contains('Difference of Cubes'));
      expect(details.explanation, isNotNull);
      expect(details.explanation!, contains('linear factor'));
    });

    test('Generates pedagogical steps for Pythagorean Theorem', () {
      final details = UniversalMathEngine.getStepsAndExplanation('x = √(3² + 4²) =', '5');
      expect(details.steps, isNotEmpty);
      expect(details.steps.first, contains('Pythagorean Theorem'));
      expect(details.explanation, contains('hypotenuse'));
    });
  });

  group('Auto Toggles & Selection State Tests', () {
    test('WhiteboardState defaults to auto shape and auto math enabled', () {
      final state = WhiteboardState(project: ProjectModel.createEmpty(title: 'Test'));
      expect(state.isAutoShapeEnabled, isTrue);
      expect(state.isAutoMathEnabled, isTrue);
    });

    test('WhiteboardState toggles auto shape and auto math', () {
      var state = WhiteboardState(project: ProjectModel.createEmpty(title: 'Test'));
      state = state.copyWith(isAutoShapeEnabled: false, isAutoMathEnabled: false);
      expect(state.isAutoShapeEnabled, isFalse);
      expect(state.isAutoMathEnabled, isFalse);
    });

    test('Canvas Mode defaults to Paginated and toggles to Infinite Canvas', () {
      var state = WhiteboardState(project: ProjectModel.createEmpty(title: 'Test'));
      expect(state.isInfiniteCanvas, isFalse); // Paginated by default

      state = state.copyWith(isInfiniteCanvas: true);
      expect(state.isInfiniteCanvas, isTrue); // Infinite canvas

      state = state.copyWith(isInfiniteCanvas: false);
      expect(state.isInfiniteCanvas, isFalse); // Switch back to paginated
    });

    test('Canvas zoom scale and offset update smoothly in state', () {
      var state = WhiteboardState(project: ProjectModel.createEmpty(title: 'Test'));
      expect(state.zoomScale, equals(1.0));
      expect(state.panOffset, equals(Offset.zero));

      state = state.copyWith(zoomScale: 1.5, panOffset: const Offset(120, 240));
      expect(state.zoomScale, equals(1.5));
      expect(state.panOffset, equals(const Offset(120, 240)));
    });
  });
}


