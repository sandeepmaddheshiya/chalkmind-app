// Regression tests for circle vs polygon confusion seen on a Galaxy Tab:
// a hand-drawn octagon was offered as "Circle / Oval", and circles left open
// where the pen lifted were offered as octagons. Strokes are synthetic but
// realistic: dense samples, pen jitter, an unclosed gap, rounded corners,
// uneven sides. Each case runs with several random seeds.
import 'dart:math' as math;

import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/recognition/shape_detector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/hand_drawn.dart';

void main() {
  const seeds = [1, 2, 3, 4, 5];

  void expectShape(
    String name,
    ShapeType expected,
    Stroke Function(int seed) make,
  ) {
    test('$name -> ${expected.name}', () {
      for (final seed in seeds) {
        final r = ShapeDetector.detectShape(make(seed));
        expect(r?.shapeType, expected, reason: '$name (seed $seed)');
      }
    });
  }

  group('Circles stay circles', () {
    expectShape(
      'circle',
      ShapeType.circle,
      (s) => handDrawn(sides: 0, seed: s),
    );
    expectShape(
      'wobbly circle',
      ShapeType.circle,
      (s) => handDrawn(sides: 0, jitter: 3, seed: s),
    );
    expectShape(
      'small circle',
      ShapeType.circle,
      (s) => handDrawn(sides: 0, radius: 40, seed: s),
    );
    expectShape(
      'oval',
      ShapeType.circle,
      (s) => handDrawn(sides: 0, rx: 1.5, seed: s),
    );
    expectShape(
      'circle left 15% open',
      ShapeType.circle,
      (s) => handDrawn(sides: 0, gapFraction: 0.15, seed: s),
    );
  });

  group('Octagons are octagons, not circles', () {
    expectShape(
      'octagon',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, seed: s),
    );
    expectShape(
      'octagon, rounded corners',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, cornerRounding: 0.2, seed: s),
    );
    expectShape(
      'octagon, shaky hand',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, jitter: 2.5, seed: s),
    );
    expectShape(
      'small octagon',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, radius: 40, seed: s),
    );
    // ±8% uneven corners. At ±12% some seeds produce a corner that bends only
    // ~17°, which is legitimately ambiguous between 7 and 8 sides.
    expectShape(
      'uneven octagon',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, irregularity: 0.08, seed: s),
    );
    expectShape(
      'octagon left open',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, gapFraction: 0.08, seed: s),
    );
    expectShape(
      'tilted octagon',
      ShapeType.octagon,
      (s) => handDrawn(sides: 8, rotation: 0.3, seed: s),
    );
  });

  group('Other polygons keep their side count', () {
    expectShape(
      'heptagon',
      ShapeType.heptagon,
      (s) => handDrawn(sides: 7, seed: s),
    );
    expectShape(
      'hexagon',
      ShapeType.hexagon,
      (s) => handDrawn(sides: 6, seed: s),
    );
    expectShape(
      'hexagon, rounded corners',
      ShapeType.hexagon,
      (s) => handDrawn(sides: 6, cornerRounding: 0.25, seed: s),
    );
    expectShape(
      'pentagon',
      ShapeType.pentagon,
      (s) => handDrawn(sides: 5, seed: s),
    );
    expectShape(
      'square',
      ShapeType.rectangle,
      (s) => handDrawn(sides: 4, rotation: 0.785, seed: s),
    );
  });

  test('straight-run fraction separates circles from octagons', () {
    for (final seed in seeds) {
      expect(
        ShapeDetector.straightRunFraction(
          handDrawn(sides: 0, seed: seed).points,
        ),
        lessThan(0.15),
      );
      expect(
        ShapeDetector.straightRunFraction(
          handDrawn(sides: 8, seed: seed).points,
        ),
        greaterThan(0.25),
      );
    }
  });

  group('Rectangles and squares', () {
    /// Detected rectangle's drawn size (shape bounds include stroke padding).
    Size drawnSize(ShapeDetectionResult r) {
      final b = r.suggestedShape.bounds;
      final pad = r.suggestedShape.strokeWidth * 3;
      return Size(b.width - pad, b.height - pad);
    }

    void expectRect(
      String name,
      Stroke Function(int seed) make, {
      Size? size,
      bool tilted = false,
    }) {
      test(name, () {
        for (final seed in seeds) {
          final r = ShapeDetector.detectShape(make(seed));
          expect(
            r?.shapeType,
            ShapeType.rectangle,
            reason: '$name (seed $seed)',
          );
          expect(
            r!.suggestedShape.customVertices != null,
            tilted,
            reason: 'tilt kept only when drawn tilted',
          );
          if (size != null) {
            final s = drawnSize(r);
            expect(
              s.width,
              closeTo(size.width, 6),
              reason: 'width, seed $seed',
            );
            expect(
              s.height,
              closeTo(size.height, 6),
              reason: 'height, seed $seed',
            );
          }
        }
      });
    }

    expectRect(
      'square is converted at the drawn size (not padded)',
      (s) => handDrawnRect(w: 160, h: 160, seed: s),
      size: const Size(160, 160),
    );
    expectRect(
      'nearly-square box snaps to a perfect square',
      (s) => handDrawnRect(w: 155, h: 148, seed: s),
      size: const Size(151.5, 151.5),
    );
    expectRect(
      'wide rectangle keeps its proportions',
      (s) => handDrawnRect(w: 240, h: 120, seed: s),
      size: const Size(240, 120),
    );
    expectRect(
      'tall rectangle',
      (s) => handDrawnRect(w: 120, h: 170, seed: s),
      size: const Size(120, 170),
    );
    expectRect(
      'small square',
      (s) => handDrawnRect(w: 50, h: 50, seed: s),
      size: const Size(50, 50),
    );
    expectRect(
      'rounded corners are not a pentagon',
      (s) => handDrawnRect(w: 200, h: 140, cornerRounding: 0.15, seed: s),
    );
    expectRect(
      'very rounded corners',
      (s) => handDrawnRect(w: 200, h: 140, cornerRounding: 0.25, seed: s),
    );
    expectRect(
      'pen runs past the start corner',
      (s) => handDrawnRect(w: 200, h: 140, overshoot: 0.2, seed: s),
    );
    expectRect(
      'left slightly open',
      (s) => handDrawnRect(w: 200, h: 140, gapFraction: 0.06, seed: s),
    );
    expectRect(
      'shaky hand',
      (s) => handDrawnRect(w: 200, h: 140, jitter: 2.5, seed: s),
    );
    expectRect(
      'started from another corner',
      (s) => handDrawnRect(w: 200, h: 140, startCorner: 2, seed: s),
    );
    expectRect(
      'a 3° wobble stays upright',
      (s) => handDrawnRect(w: 200, h: 140, angle: 3 * math.pi / 180, seed: s),
    );

    test('a tilted rectangle keeps its tilt and size', () {
      for (final seed in seeds) {
        final r = ShapeDetector.detectShape(
          handDrawnRect(w: 200, h: 140, angle: 20 * math.pi / 180, seed: seed),
        );
        expect(r?.shapeType, ShapeType.rectangle);
        final v = r!.suggestedShape.customVertices!;
        expect(v.length, 4);
        final sides = [
          for (int i = 0; i < 4; i++) (v[(i + 1) % 4] - v[i]).distance,
        ]..sort();
        expect(sides.first, closeTo(140, 6));
        expect(sides.last, closeTo(200, 6));
        final edge = v[1] - v[0];
        var deg = math.atan2(edge.dy, edge.dx) * 180 / math.pi;
        deg = ((deg % 90) + 90) % 90; // orientation modulo 90°
        expect(deg, closeTo(20, 2));
      }
    });

    test('a square tilted 30° stays a (tilted) square, not a diamond', () {
      for (final seed in seeds) {
        final r = ShapeDetector.detectShape(
          handDrawnRect(w: 150, h: 150, angle: 30 * math.pi / 180, seed: seed),
        );
        expect(r?.shapeType, ShapeType.rectangle);
        final v = r!.suggestedShape.customVertices!;
        expect(
          (v[1] - v[0]).distance,
          closeTo((v[2] - v[1]).distance, 0.01),
          reason: 'square snapped',
        );
      }
    });

    test('a square stood on its corner (45°) is a diamond', () {
      for (final seed in seeds) {
        final r = ShapeDetector.detectShape(
          handDrawnRect(w: 150, h: 150, angle: math.pi / 4, seed: seed),
        );
        expect(r?.shapeType, ShapeType.diamond);
      }
    });

    test('circles are not mistaken for squares', () {
      for (final seed in seeds) {
        expect(
          ShapeDetector.detectShape(
            handDrawn(sides: 0, gapFraction: 0.15, seed: seed),
          )?.shapeType,
          ShapeType.circle,
        );
      }
    });
  });
}
