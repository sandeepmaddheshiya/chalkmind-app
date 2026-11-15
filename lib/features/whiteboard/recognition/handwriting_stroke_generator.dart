import 'dart:math' as math;
import 'dart:ui' show Path, PathMetric, Rect;

import 'package:flutter/material.dart' show Offset;
import 'package:uuid/uuid.dart';

import '../models/stroke_model.dart';
import '../models/stroke_point.dart';
import '../models/tool_type.dart';

/// Writes text (usually a maths answer) as natural-looking handwritten ink.
///
/// Each character is designed as smooth pen paths (cubic curves, real loops
/// for 0/6/8/9) in a unit box, then sampled evenly and transformed to sit on
/// the writer's baseline, at their letter height and angle. A slight forward
/// slant and small per-letter variations (size, baseline, tilt) make it look
/// hand-written rather than typeset. Variation is seeded from the text, so the
/// same answer always looks the same.
class HandwritingStrokeGenerator {
  static const uuid = Uuid();

  /// Characters with real handwritten glyphs. Others are placed as typed
  /// text by the caller instead (see [canWrite]).
  static const String writableCharacters = '0123456789.,+-−=/*×÷()%:^xXyYzZaAbBcC²³ ';

  /// True when every character of [text] has a real handwritten glyph.
  static bool canWrite(String text) =>
      text.isNotEmpty && text.split('').every(writableCharacters.contains);

  /// Forward slant of handwriting (horizontal shift per unit of height).
  static const double _slant = 0.14;

  /// Gap between letters, as a fraction of letter height.
  static const double _letterGap = 0.11;

  /// Distance between pen samples, in pixels.
  static const double _sampleSpacing = 1.8;

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
    final h = characterHeight;
    final dir = _unit(direction, const Offset(1, 0));
    final norm = _unit(normal, const Offset(0, 1));
    final rnd = math.Random(text.hashCode ^ h.round());
    final strokes = <Stroke>[];
    var x = 0.0; // pen position along the baseline, in pixels
    var time = DateTime.now().millisecondsSinceEpoch;

    for (final char in text.split('')) {
      final glyph = _glyph(char);
      if (glyph == null) {
        x += 0.35 * h; // unknown: leave a gap (callers check canWrite first)
        continue;
      }
      if (glyph.paths.isNotEmpty) {
        // Small natural variation per letter.
        final scale = 1 + (rnd.nextDouble() - 0.5) * 0.06;
        final lift = (rnd.nextDouble() - 0.5) * 0.04 * h;
        final tilt = (rnd.nextDouble() - 0.5) * 0.05; // radians
        final gh = h * scale;
        final pivot = Offset(glyph.advance * gh / 2, gh / 2);

        for (final unitPath in glyph.paths) {
          final path = unitPath(gh).path;
          for (final metric in path.computeMetrics()) {
            final pts = _sample(metric);
            if (pts.isEmpty) continue;
            final out = <StrokePoint>[];
            for (final p in pts) {
              // Tilt around the glyph centre, then slant (shear), then place.
              final c = p - pivot;
              final r = Offset(
                c.dx * math.cos(tilt) - c.dy * math.sin(tilt),
                c.dx * math.sin(tilt) + c.dy * math.cos(tilt),
              ) + pivot;
              final sheared = Offset(r.dx + (gh - r.dy) * _slant, r.dy);
              // Align glyph baseline (gh) to the line's baseline (h).
              final world = startPosition +
                  dir * (x + sheared.dx) +
                  norm * (sheared.dy + (h - gh) + lift);
              out.add(StrokePoint(x: world.dx, y: world.dy, timestamp: time));
              time += 6;
            }
            strokes.add(Stroke(
              id: uuid.v4(),
              points: out,
              colorValue: colorValue,
              width: strokeWidth,
              toolType: toolType,
            ));
            time += 60; // pen lift
          }
        }
      }
      x += (glyph.advance + _letterGap) * h;
    }
    return strokes;
  }

  static Offset _unit(Offset v, Offset fallback) {
    final d = v.distance;
    return d < 1e-6 ? fallback : v / d;
  }

  /// Evenly spaced points along one pen path.
  static List<Offset> _sample(PathMetric m) {
    if (m.length < 0.5) {
      final t = m.getTangentForOffset(0);
      return t == null ? const [] : [t.position, t.position + const Offset(0.6, 0.6)];
    }
    final n = math.max(2, (m.length / _sampleSpacing).ceil());
    return [
      for (int i = 0; i <= n; i++) m.getTangentForOffset(m.length * i / n)!.position,
    ];
  }

  // ---------------------------------------------------------------------------
  // Glyphs. Coordinates are in units of letter height: y = 0 is the top of a
  // capital/digit, y = 1 the baseline, y > 1 a descender (as in 'y'). x runs
  // from 0 to the glyph's advance width. Lowercase x-height starts at 0.45.

  static _Glyph? _glyph(String c) {
    switch (c) {
      case ' ':
        return const _Glyph(0.32, []);
      case '0':
        return _Glyph(0.56, [
          (s) => _p(s)
            ..moveTo(0.30, 0.0)
            ..cubicTo(0.06, 0.0, 0.02, 0.32, 0.02, 0.52)
            ..cubicTo(0.02, 0.80, 0.14, 1.0, 0.28, 1.0)
            ..cubicTo(0.46, 1.0, 0.54, 0.76, 0.54, 0.48)
            ..cubicTo(0.54, 0.20, 0.44, 0.0, 0.28, 0.02),
        ]);
      case '1':
        return _Glyph(0.36, [
          (s) => _p(s)
            ..moveTo(0.04, 0.22)
            ..quadraticBezierTo(0.18, 0.12, 0.26, 0.0)
            ..lineTo(0.26, 1.0),
        ]);
      case '2':
        return _Glyph(0.56, [
          (s) => _p(s)
            ..moveTo(0.04, 0.22)
            ..cubicTo(0.08, 0.02, 0.48, -0.06, 0.50, 0.24)
            ..cubicTo(0.52, 0.46, 0.22, 0.70, 0.02, 1.0)
            ..quadraticBezierTo(0.30, 0.97, 0.56, 1.0),
        ]);
      case '3':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.04, 0.12)
            ..cubicTo(0.18, -0.04, 0.50, -0.02, 0.48, 0.22)
            ..cubicTo(0.46, 0.40, 0.30, 0.46, 0.18, 0.46)
            ..cubicTo(0.44, 0.46, 0.54, 0.62, 0.52, 0.76)
            ..cubicTo(0.50, 1.02, 0.14, 1.06, 0.02, 0.86),
        ]);
      case '4':
        return _Glyph(0.58, [
          (s) => _p(s)
            ..moveTo(0.40, 0.0)
            ..lineTo(0.03, 0.66)
            ..lineTo(0.56, 0.66),
          (s) => _p(s)
            ..moveTo(0.42, 0.30)
            ..lineTo(0.42, 1.0),
        ]);
      case '5':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.12, 0.02)
            ..lineTo(0.08, 0.44)
            ..cubicTo(0.26, 0.32, 0.54, 0.38, 0.53, 0.68)
            ..cubicTo(0.52, 0.98, 0.16, 1.04, 0.02, 0.86),
          (s) => _p(s)
            ..moveTo(0.12, 0.02)
            ..lineTo(0.50, 0.0),
        ]);
      case '6':
        return _Glyph(0.56, [
          (s) => _p(s)
            ..moveTo(0.46, 0.04)
            ..cubicTo(0.20, 0.10, 0.04, 0.40, 0.04, 0.66)
            ..cubicTo(0.04, 0.90, 0.16, 1.0, 0.30, 1.0)
            ..cubicTo(0.46, 1.0, 0.54, 0.88, 0.54, 0.74)
            ..cubicTo(0.54, 0.58, 0.42, 0.48, 0.28, 0.48)
            ..cubicTo(0.16, 0.48, 0.06, 0.56, 0.05, 0.68),
        ]);
      case '7':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.02, 0.03)
            ..quadraticBezierTo(0.30, -0.01, 0.54, 0.02)
            ..cubicTo(0.40, 0.30, 0.26, 0.62, 0.20, 1.0),
        ]);
      case '8':
        return _Glyph(0.56, [
          (s) => _p(s)
            ..moveTo(0.46, 0.14)
            ..cubicTo(0.42, 0.0, 0.08, -0.01, 0.08, 0.22)
            ..cubicTo(0.08, 0.38, 0.26, 0.42, 0.30, 0.46)
            ..cubicTo(0.48, 0.52, 0.56, 0.64, 0.54, 0.78)
            ..cubicTo(0.52, 1.01, 0.04, 1.02, 0.04, 0.76)
            ..cubicTo(0.04, 0.60, 0.20, 0.52, 0.30, 0.46)
            ..cubicTo(0.40, 0.40, 0.50, 0.32, 0.46, 0.14),
        ]);
      case '9':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.50, 0.24)
            ..cubicTo(0.48, 0.06, 0.36, 0.0, 0.26, 0.0)
            ..cubicTo(0.10, 0.0, 0.02, 0.12, 0.02, 0.26)
            ..cubicTo(0.02, 0.42, 0.14, 0.50, 0.26, 0.50)
            ..cubicTo(0.40, 0.50, 0.50, 0.40, 0.50, 0.24)
            ..cubicTo(0.50, 0.56, 0.46, 0.84, 0.36, 1.0),
        ]);
      case '.':
        return _Glyph(0.18, [(s) => _dot(s, 0.075, 0.965)]);
      case ',':
        return _Glyph(0.2, [
          (s) => _p(s)
            ..moveTo(0.10, 0.92)
            ..quadraticBezierTo(0.11, 1.06, 0.02, 1.16),
        ]);
      case ':':
        return _Glyph(0.18, [(s) => _dot(s, 0.075, 0.55), (s) => _dot(s, 0.075, 0.965)]);
      case '+':
        return _Glyph(0.52, [
          (s) => _p(s)
            ..moveTo(0.26, 0.34)
            ..lineTo(0.25, 0.84),
          (s) => _p(s)
            ..moveTo(0.02, 0.60)
            ..quadraticBezierTo(0.26, 0.58, 0.50, 0.59),
        ]);
      case '-':
      case '−':
        return _Glyph(0.44, [
          (s) => _p(s)
            ..moveTo(0.03, 0.60)
            ..quadraticBezierTo(0.22, 0.58, 0.42, 0.59),
        ]);
      case '=':
        return _Glyph(0.50, [
          (s) => _p(s)
            ..moveTo(0.03, 0.48)
            ..quadraticBezierTo(0.25, 0.46, 0.48, 0.47),
          (s) => _p(s)
            ..moveTo(0.03, 0.70)
            ..quadraticBezierTo(0.25, 0.68, 0.48, 0.69),
        ]);
      case '×':
      case '*':
        return _Glyph(0.46, [
          (s) => _p(s)
            ..moveTo(0.04, 0.40)
            ..lineTo(0.42, 0.80),
          (s) => _p(s)
            ..moveTo(0.42, 0.40)
            ..lineTo(0.04, 0.80),
        ]);
      case '÷':
        return _Glyph(0.48, [
          (s) => _p(s)
            ..moveTo(0.03, 0.60)
            ..lineTo(0.45, 0.60),
          (s) => _dot(s, 0.24, 0.40),
          (s) => _dot(s, 0.24, 0.80),
        ]);
      case '/':
        return _Glyph(0.42, [
          (s) => _p(s)
            ..moveTo(0.04, 1.0)
            ..lineTo(0.40, 0.0),
        ]);
      case '(':
        return _Glyph(0.30, [
          (s) => _p(s)
            ..moveTo(0.26, -0.02)
            ..quadraticBezierTo(-0.04, 0.50, 0.26, 1.06),
        ]);
      case ')':
        return _Glyph(0.30, [
          (s) => _p(s)
            ..moveTo(0.04, -0.02)
            ..quadraticBezierTo(0.34, 0.50, 0.04, 1.06),
        ]);
      case '%':
        return _Glyph(0.62, [
          (s) => _p(s)..addOval(_r(0.02, 0.02, 0.20, 0.26, s)),
          (s) => _p(s)
            ..moveTo(0.54, 0.0)
            ..lineTo(0.08, 1.0),
          (s) => _p(s)..addOval(_r(0.38, 0.72, 0.20, 0.26, s)),
        ]);
      case '^':
        return _Glyph(0.40, [
          (s) => _p(s)
            ..moveTo(0.04, 0.36)
            ..lineTo(0.20, 0.06)
            ..lineTo(0.36, 0.36),
        ]);
      case 'x':
        return _Glyph(0.48, [
          (s) => _p(s)
            ..moveTo(0.04, 0.46)
            ..cubicTo(0.18, 0.46, 0.30, 1.0, 0.46, 1.0),
          (s) => _p(s)
            ..moveTo(0.44, 0.46)
            ..lineTo(0.04, 1.0),
        ]);
      case 'X':
        return _Glyph(0.56, [
          (s) => _p(s)
            ..moveTo(0.02, 0.0)
            ..lineTo(0.54, 1.0),
          (s) => _p(s)
            ..moveTo(0.54, 0.0)
            ..lineTo(0.02, 1.0),
        ]);
      case 'y':
        return _Glyph(0.48, [
          (s) => _p(s)
            ..moveTo(0.04, 0.46)
            ..cubicTo(0.04, 0.82, 0.14, 0.92, 0.24, 0.92)
            ..cubicTo(0.36, 0.92, 0.44, 0.80, 0.44, 0.46)
            ..lineTo(0.44, 1.12)
            ..cubicTo(0.44, 1.36, 0.18, 1.40, 0.06, 1.24),
        ]);
      case 'Y':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.02, 0.0)
            ..lineTo(0.27, 0.50)
            ..lineTo(0.27, 1.0),
          (s) => _p(s)
            ..moveTo(0.52, 0.0)
            ..lineTo(0.27, 0.50),
        ]);
      case 'z':
        return _Glyph(0.46, [
          (s) => _p(s)
            ..moveTo(0.04, 0.47)
            ..lineTo(0.42, 0.47)
            ..lineTo(0.03, 1.0)
            ..quadraticBezierTo(0.22, 0.97, 0.44, 1.0),
        ]);
      case 'Z':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.03, 0.02)
            ..lineTo(0.50, 0.02)
            ..lineTo(0.02, 1.0)
            ..quadraticBezierTo(0.26, 0.97, 0.52, 1.0),
        ]);
      case 'a':
        return _Glyph(0.50, [
          (s) => _p(s)
            ..moveTo(0.42, 0.56)
            ..cubicTo(0.34, 0.42, 0.04, 0.44, 0.04, 0.74)
            ..cubicTo(0.04, 1.02, 0.36, 1.04, 0.42, 0.78),
          (s) => _p(s)
            ..moveTo(0.43, 0.46)
            ..lineTo(0.43, 0.90)
            ..quadraticBezierTo(0.44, 1.0, 0.50, 0.98),
        ]);
      case 'A':
        return _Glyph(0.58, [
          (s) => _p(s)
            ..moveTo(0.02, 1.0)
            ..lineTo(0.29, 0.0)
            ..lineTo(0.56, 1.0),
          (s) => _p(s)
            ..moveTo(0.12, 0.64)
            ..lineTo(0.46, 0.64),
        ]);
      case 'b':
        return _Glyph(0.50, [
          (s) => _p(s)
            ..moveTo(0.06, 0.0)
            ..lineTo(0.06, 1.0),
          (s) => _p(s)
            ..moveTo(0.06, 0.68)
            ..cubicTo(0.14, 0.42, 0.48, 0.42, 0.48, 0.72)
            ..cubicTo(0.48, 1.04, 0.12, 1.04, 0.06, 0.90),
        ]);
      case 'B':
        return _Glyph(0.52, [
          (s) => _p(s)
            ..moveTo(0.06, 0.0)
            ..lineTo(0.06, 1.0),
          (s) => _p(s)
            ..moveTo(0.06, 0.02)
            ..cubicTo(0.48, -0.02, 0.48, 0.46, 0.06, 0.46)
            ..cubicTo(0.56, 0.44, 0.56, 1.02, 0.06, 0.98),
        ]);
      case 'c':
        return _Glyph(0.46, [
          (s) => _p(s)
            ..moveTo(0.42, 0.54)
            ..cubicTo(0.30, 0.42, 0.04, 0.46, 0.04, 0.73)
            ..cubicTo(0.04, 1.02, 0.32, 1.04, 0.44, 0.92),
        ]);
      case 'C':
        return _Glyph(0.54, [
          (s) => _p(s)
            ..moveTo(0.50, 0.12)
            ..cubicTo(0.36, -0.04, 0.02, 0.02, 0.02, 0.50)
            ..cubicTo(0.02, 0.98, 0.36, 1.04, 0.52, 0.88),
        ]);
      case '²':
        return _superscript('2');
      case '³':
        return _superscript('3');
    }
    return null;
  }

  /// Small raised digit (exponent).
  static _Glyph _superscript(String digit) {
    final base = _glyph(digit)!;
    return _Glyph(base.advance * 0.55, [
      for (final p in base.paths)
        (s) => _ScaledPath.wrap(p(s * 0.55).path.shift(Offset(0, -0.04 * s))),
    ]);
  }

  /// A small round dot (decimal point, colon, division sign) centred at
  /// ([x], [y]), visible at any pen width.
  static _ScaledPath _dot(double s, double x, double y) =>
      _p(s)..addOval(Rect.fromCircle(center: Offset(x * s, y * s), radius: 0.028 * s));

  /// New path that interprets coordinates in units of size [s].
  static _ScaledPath _p(double s) => _ScaledPath(s);

  static Rect _r(double l, double t, double w, double h, double s) =>
      Rect.fromLTWH(l * s, t * s, w * s, h * s);
}

class _Glyph {
  final double advance; // width in units of letter height
  final List<_ScaledPath Function(double size)> paths;
  const _Glyph(this.advance, this.paths);
}

/// Builds a [Path] from coordinates given in units of letter height
/// (multiplied by [s]), so glyphs are designed once and drawn at any size.
class _ScaledPath {
  _ScaledPath(this.s) : path = Path();
  _ScaledPath.wrap(this.path) : s = 1;

  final double s;
  final Path path;

  void moveTo(double x, double y) => path.moveTo(x * s, y * s);
  void lineTo(double x, double y) => path.lineTo(x * s, y * s);
  void quadraticBezierTo(double x1, double y1, double x2, double y2) =>
      path.quadraticBezierTo(x1 * s, y1 * s, x2 * s, y2 * s);
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) =>
      path.cubicTo(x1 * s, y1 * s, x2 * s, y2 * s, x3 * s, y3 * s);
  void addOval(Rect r) => path.addOval(r);
}
