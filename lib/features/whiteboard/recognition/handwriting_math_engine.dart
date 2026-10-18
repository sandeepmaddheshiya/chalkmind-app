import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/stroke_model.dart';
import '../models/shape_model.dart';
import '../models/tool_type.dart';
import 'math_evaluator.dart';
import 'shape_detector.dart';

class HandwritingMathResult {
  final String expression;
  final String answer;
  final Offset insertPosition;
  final double characterHeight;
  final int strokeColorValue;
  final double strokeWidth;
  final Offset direction;
  final Offset normal;

  const HandwritingMathResult({
    required this.expression,
    required this.answer,
    required this.insertPosition,
    required this.characterHeight,
    required this.strokeColorValue,
    required this.strokeWidth,
    required this.direction,
    required this.normal,
  });
}

class HandwritingMathEngine {
  /// Checks whether recent strokes contain an '=' sign at any angle
  static bool hasEqualSign(List<Stroke> strokes) {
    return detectAngleInvariantEqualSign(strokes) != null;
  }

  /// Extracts only the strokes belonging to the equation ending in '='
  /// (including the '=' sign itself), filtering out unrelated distant strokes.
  static List<Stroke>? getEquationStrokes(List<Stroke> pageStrokes) {
    if (pageStrokes.length < 2) return null;

    final equalSignInfo = detectAngleInvariantEqualSign(pageStrokes);
    if (equalSignInfo == null) return null;

    final eqCenter = equalSignInfo.center;
    final dir = equalSignInfo.direction;
    final normal = equalSignInfo.normal;

    final result = <Stroke>[];

    // Add '=' strokes
    for (final s in pageStrokes) {
      if (equalSignInfo.consumedStrokeIds.contains(s.id)) {
        result.add(s);
      }
    }

    // Add strokes to the left of '=' along the baseline
    for (final s in pageStrokes) {
      if (equalSignInfo.consumedStrokeIds.contains(s.id)) continue;

      final sCenter = s.bounds.center;
      final relOffset = sCenter - eqCenter;
      final u = relOffset.dx * dir.dx + relOffset.dy * dir.dy;
      final v = relOffset.dx * normal.dx + relOffset.dy * normal.dy;

      final maxV = math.max(300.0, equalSignInfo.length * 4.5);
      if (u < -4.0 && u > -2000.0 && v.abs() < maxV) {
        result.add(s);
      }
    }

    return result.length >= 2 ? result : null;
  }

  /// Extracts strokes belonging to the current problem, including any diagrams (like triangles,
  /// geometric figures, or vertical working) drawn in the vicinity of or above '='.
  static List<Stroke> getProblemStrokes(List<Stroke> pageStrokes) {
    if (pageStrokes.isEmpty) return [];
    final equalSignInfo = detectAngleInvariantEqualSign(pageStrokes);
    if (equalSignInfo == null) return pageStrokes;

    if (pageStrokes.length <= 35) {
      // Send all page strokes to preserve full context (diagrams, labels, systems of equations)
      return pageStrokes;
    }

    final eqCenter = equalSignInfo.center;
    final result = <Stroke>[];
    for (final s in pageStrokes) {
      final sCenter = s.bounds.center;
      final dist = (sCenter - eqCenter).distance;
      if (dist < 1500.0) {
        result.add(s);
      }
    }

    return result.length >= 2 ? result : pageStrokes;
  }

  /// Detects if the latest drawn strokes on the page form an arithmetic expression ending with '='
  /// Works at ANY angle (slanted handwriting, horizontal, vertical) and at any drawing scale.
  static HandwritingMathResult? detectHandwrittenEquation(List<Stroke> pageStrokes) {
    if (pageStrokes.length < 2) return null;

    // 1. Detect '=' sign at any angle near the end of the stroke list
    final equalSignInfo = detectAngleInvariantEqualSign(pageStrokes);
    if (equalSignInfo == null) return null;

    final eqCenter = equalSignInfo.center;
    final dir = equalSignInfo.direction; // Unit vector along text direction
    final normal = equalSignInfo.normal; // Unit normal vector perpendicular to text
    final eqHeight = math.max(30.0, equalSignInfo.length * 1.5);

    // GUARD A: Multiple '=' signs present on page (e.g. system of equations: x = 3, y = x + 2, y =)
    // A system of equations or multi-step derivation must be solved by Vision AI.
    final otherStrokes = pageStrokes.where((s) => !equalSignInfo.consumedStrokeIds.contains(s.id)).toList();
    if (detectAngleInvariantEqualSign(otherStrokes) != null) {
      return null;
    }

    // GUARD B: Geometric diagrams or shapes present on page (e.g. triangle, polygon, rectangle, circle)
    for (final s in pageStrokes) {
      if (equalSignInfo.consumedStrokeIds.contains(s.id)) continue;
      // Large diagram elements (arithmetic digits are almost never > 120x120px)
      if (s.bounds.width > 120.0 && s.bounds.height > 120.0) {
        return null;
      }
      if (s.points.length >= 5) {
        final shape = ShapeDetector.detectShape(s);
        if (shape != null &&
            shape.shapeType != ShapeType.line &&
            shape.shapeType != ShapeType.arrow) {
          return null;
        }
      }
    }

    // GUARD C: Multi-line / Vertical Stack Check
    // If strokes exist significantly above or below this equation line (|v| > 75px),
    // this is a multi-line problem or diagram context -> Delegate to Vision AI
    for (final s in otherStrokes) {
      final sCenter = s.bounds.center;
      final relOffset = sCenter - eqCenter;
      final u = relOffset.dx * dir.dx + relOffset.dy * dir.dy;
      final v = relOffset.dx * normal.dx + relOffset.dy * normal.dy;

      if (u > -1200.0 && u < 200.0) {
        final maxVertical = math.max(75.0, eqHeight * 2.2);
        if (v < -maxVertical || v > maxVertical) {
          return null;
        }
      }
    }

    // 2. Filter strokes to the left of '=' along the text direction vector
    final equationStrokes = <_ProjectedStroke>[];

    for (final s in pageStrokes) {
      if (equalSignInfo.consumedStrokeIds.contains(s.id)) continue;

      final sCenter = s.bounds.center;
      final relOffset = sCenter - eqCenter;

      // Project onto text direction (u) and normal (v)
      final u = relOffset.dx * dir.dx + relOffset.dy * dir.dy;
      final v = relOffset.dx * normal.dx + relOffset.dy * normal.dy;

      // Must be on the same equation baseline region to the left of '=' (including exponents and subscripts)
      final maxV = math.max(120.0, equalSignInfo.length * 3.5);
      if (u < -4.0 && u > -1400.0 && v.abs() < maxV) {
        equationStrokes.add(_ProjectedStroke(stroke: s, u: u, v: v));
      }
    }

    if (equationStrokes.isEmpty) return null;

    // Sort strokes from left to right along the text baseline (ascending u)
    equationStrokes.sort((a, b) => a.u.compareTo(b.u));

    // 3. Classify strokes in baseline-aligned coordinates
    final tokenString = _classifyBaselineAlignedStrokes(equationStrokes, dir, normal);
    if (tokenString.isEmpty) return null;

    // 4. Solve the equation using MathEvaluator
    final evalResult = MathEvaluator.evaluate(tokenString);
    if (evalResult == null) return null;

    // Calculate insertion position: placed directly after '=' along the text direction
    final targetHeight = math.max(28.0, math.min(140.0, equalSignInfo.length * 1.5));
    final insertOffset = eqCenter + dir * (equalSignInfo.length * 0.9 + 25.0) - normal * (targetHeight * 0.5);

    return HandwritingMathResult(
      expression: '$tokenString =',
      answer: evalResult.resultText,
      insertPosition: insertOffset,
      characterHeight: targetHeight,
      strokeColorValue: equalSignInfo.strokeColor,
      strokeWidth: equalSignInfo.strokeWidth,
      direction: dir,
      normal: normal,
    );
  }

  static AngleInvariantEqualSign? detectAngleInvariantEqualSign(List<Stroke> strokes) {
    final count = strokes.length;
    if (count < 2) return null;

    // Check pairs among the last 6 strokes to allow for quick dots/punctuation
    final checkLimit = math.max(0, count - 6);

    for (int i = count - 1; i > checkLimit; i--) {
      for (int j = i - 1; j >= checkLimit; j--) {
        final s1 = strokes[j];
        final s2 = strokes[i];

        final eq = _checkTwoStrokesForEqual(s1, s2);
        if (eq != null) return eq;
      }
    }

    return null;
  }

  static AngleInvariantEqualSign? _checkTwoStrokesForEqual(Stroke s1, Stroke s2) {
    final chord1 = _getStrokeChord(s1);
    final chord2 = _getStrokeChord(s2);

    final len1 = chord1.distance;
    final len2 = chord2.distance;

    // Length check: bars should be between 8px and 450px on tablets
    if (len1 < 8.0 || len1 > 450.0 || len2 < 8.0 || len2 > 450.0) return null;

    // Length ratio check: two bars of '=' should be reasonably similar in size
    final maxLen = math.max(len1, len2);
    final minLen = math.min(len1, len2);
    if (maxLen / minLen > 2.5) return null;

    // Straightness check: chord should be >= 65% of total path length
    if (len1 / _getPathLength(s1) < 0.65 || len2 / _getPathLength(s2) < 0.65) return null;

    // Compute angle of each bar
    double angle1 = math.atan2(chord1.dy, chord1.dx);
    double angle2 = math.atan2(chord2.dy, chord2.dx);

    // Normalize angles to [0, pi)
    if (angle1 < 0) angle1 += math.pi;
    if (angle2 < 0) angle2 += math.pi;

    // Parallel check: angle difference must be <= 35 degrees
    final angleDiff = (angle1 - angle2).abs();
    final isParallel = angleDiff < 0.60 || (math.pi - angleDiff) < 0.60;
    if (!isParallel) return null;

    // Average angle
    final avgAngle = (angle1 + angle2) / 2;
    var dir = Offset(math.cos(avgAngle), math.sin(avgAngle));
    if (dir.dx < 0) {
      dir = -dir;
    }
    final normal = Offset(-dir.dy, dir.dx);

    final c1 = s1.bounds.center;
    final c2 = s2.bounds.center;
    final delta = c2 - c1;

    // Longitudinal separation along bar direction: bars must overlap
    final uSep = (delta.dx * dir.dx + delta.dy * dir.dy).abs();
    if (uSep > maxLen * 0.90) return null;

    // Perpendicular separation: must be between 4px and maxLen * 2.0 + 80px
    final vSep = (delta.dx * normal.dx + delta.dy * normal.dy).abs();
    if (vSep < 4.0 || vSep > maxLen * 2.2 + 80.0) return null;

    final unionCenter = Offset((c1.dx + c2.dx) / 2, (c1.dy + c2.dy) / 2);

    return AngleInvariantEqualSign(
      center: unionCenter,
      direction: dir,
      normal: normal,
      length: (len1 + len2) / 2,
      strokeColor: s2.colorValue,
      strokeWidth: s2.width,
      consumedStrokeIds: {s1.id, s2.id},
    );
  }

  static Offset _getStrokeChord(Stroke s) {
    if (s.points.isEmpty) return Offset.zero;
    return s.points.last.offset - s.points.first.offset;
  }

  static double _getPathLength(Stroke s) {
    double l = 0.0;
    for (int i = 0; i < s.points.length - 1; i++) {
      l += s.points[i].distanceTo(s.points[i + 1]);
    }
    return l > 0 ? l : 1.0;
  }

  // --- Baseline-Aligned Stroke Classification ---
  static String _classifyBaselineAlignedStrokes(
    List<_ProjectedStroke> projected,
    Offset dir,
    Offset normal,
  ) {
    final buffer = StringBuffer();
    int i = 0;

    final heights = projected.map((p) => p.stroke.bounds.height).toList()..sort();
    final medianHeight = heights.isNotEmpty ? heights[heights.length ~/ 2] : 40.0;

    while (i < projected.length) {
      final curr = projected[i];

      // Check 2-stroke operators and digits only if they overlap horizontally along text baseline:
      if (i + 1 < projected.length && _strokesOverlapInU(curr.stroke, projected[i + 1].stroke, dir)) {
        final next = projected[i + 1];
        if (_isTwoStrokePlus(curr.stroke, next.stroke, dir, normal)) {
          buffer.write(' + ');
          i += 2;
          continue;
        }
        if (_isTwoStrokeMultiply(curr.stroke, next.stroke, dir, normal)) {
          final prev = buffer.toString().trim();
          final isAfterDigit = prev.isNotEmpty && RegExp(r'\d$').hasMatch(prev);
          final isMultiplication = isAfterDigit && i + 2 < projected.length;
          if (isMultiplication) {
            buffer.write(' * ');
          } else {
            final token = 'x';
            _appendToken(buffer, token, curr, medianHeight);
          }
          i += 2;
          continue;
        }
        if (_isTwoStrokeFive(curr.stroke, next.stroke, dir, normal)) {
          final token = '5';
          _appendToken(buffer, token, curr, medianHeight);
          i += 2;
          continue;
        }
        if (_isTwoStrokeFour(curr.stroke, next.stroke, dir, normal)) {
          final token = '4';
          _appendToken(buffer, token, curr, medianHeight);
          i += 2;
          continue;
        }
      }

      // Single stroke token classification
      final token = _classifySingleStrokeAligned(curr.stroke, dir, normal);
      if (token == null) {
        // Any unknown token (e.g. diagram stroke) aborts local evaluation
        // so Vision AI can process the complete problem
        return '';
      }
      _appendToken(buffer, token, curr, medianHeight);
      i++;
    }

    return buffer.toString().trim();
  }

  static void _appendToken(StringBuffer buffer, String token, _ProjectedStroke curr, double medianHeight) {
    // Check if token is an exponent/superscript (e.g. 2^2, a^3, b^3, x^2)
    final isElevated = curr.v < -medianHeight * 0.12;
    final isSmaller = curr.stroke.bounds.height <= medianHeight * 0.85;
    final prevText = buffer.toString().trim();
    final canBeExponent = prevText.isNotEmpty &&
        (RegExp(r'[\d)xyzabnc]$', caseSensitive: false).hasMatch(prevText)) &&
        RegExp(r'^\d+$').hasMatch(token);

    if (canBeExponent && (isElevated || isSmaller)) {
      buffer.write('^$token');
    } else {
      buffer.write(token);
    }
  }

  static bool _strokesOverlapInU(Stroke s1, Stroke s2, Offset dir) {
    double minU1 = double.infinity, maxU1 = -double.infinity;
    for (final p in s1.points) {
      final u = p.x * dir.dx + p.y * dir.dy;
      if (u < minU1) minU1 = u;
      if (u > maxU1) maxU1 = u;
    }

    double minU2 = double.infinity, maxU2 = -double.infinity;
    for (final p in s2.points) {
      final u = p.x * dir.dx + p.y * dir.dy;
      if (u < minU2) minU2 = u;
      if (u > maxU2) maxU2 = u;
    }

    // Two strokes must actually overlap along the text baseline (not separated by gap)
    final overlap = math.min(maxU1, maxU2) - math.max(minU1, minU2);
    return overlap > -2.0;
  }

  static bool _isTwoStrokePlus(Stroke s1, Stroke s2, Offset dir, Offset normal) {
    final chord1 = _getStrokeChord(s1);
    final chord2 = _getStrokeChord(s2);

    final len1 = chord1.distance;
    final len2 = chord2.distance;
    final maxLen = math.max(len1, len2);

    // Both strokes must be straight lines (not curved digits like 2, 3, 0)
    if (len1 / _getPathLength(s1) < 0.70 || len2 / _getPathLength(s2) < 0.70) {
      return false;
    }

    final c1 = s1.bounds.center;
    final c2 = s2.bounds.center;
    // Centers of the two crossing bars must be very close
    if ((c1 - c2).distance > maxLen * 0.55 + 20.0) return false;

    // Project chords onto dir and normal
    final u1 = (chord1.dx * dir.dx + chord1.dy * dir.dy).abs();
    final v1 = (chord1.dx * normal.dx + chord1.dy * normal.dy).abs();

    final u2 = (chord2.dx * dir.dx + chord2.dy * dir.dy).abs();
    final v2 = (chord2.dx * normal.dx + chord2.dy * normal.dy).abs();

    final s1AlongDir = u1 > v1 * 1.15;
    final s1AcrossDir = v1 > u1 * 1.15;
    final s2AlongDir = u2 > v2 * 1.15;
    final s2AcrossDir = v2 > u2 * 1.15;

    return (s1AlongDir && s2AcrossDir) || (s1AcrossDir && s2AlongDir);
  }

  static bool _isTwoStrokeMultiply(Stroke s1, Stroke s2, Offset dir, Offset normal) {
    final chord1 = _getStrokeChord(s1);
    final chord2 = _getStrokeChord(s2);

    final pathLen1 = _getPathLength(s1);
    final pathLen2 = _getPathLength(s2);
    // Both strokes MUST be straight lines:
    if (chord1.distance / pathLen1 < 0.70 || chord2.distance / pathLen2 < 0.70) {
      return false;
    }

    final maxLen = math.max(chord1.distance, chord2.distance);
    final c1 = s1.bounds.center;
    final c2 = s2.bounds.center;
    if ((c1 - c2).distance > maxLen * 0.75 + 15.0) return false;

    // Project chords into baseline coordinates (u, v)
    final du1 = chord1.dx * dir.dx + chord1.dy * dir.dy;
    final dv1 = chord1.dx * normal.dx + chord1.dy * normal.dy;
    final du2 = chord2.dx * dir.dx + chord2.dy * dir.dy;
    final dv2 = chord2.dx * normal.dx + chord2.dy * normal.dy;

    final u1 = du1.abs();
    final v1 = dv1.abs();
    final u2 = du2.abs();
    final v2 = dv2.abs();

    final isDiag1 = u1 > 0.25 * v1 && v1 > 0.25 * u1;
    final isDiag2 = u2 > 0.25 * v2 && v2 > 0.25 * u2;
    if (!isDiag1 || !isDiag2) return false;

    // The two diagonal strokes must cross (opposite slope direction)
    final slope1 = dv1 / (du1.abs() > 0.001 ? du1 : 0.001);
    final slope2 = dv2 / (du2.abs() > 0.001 ? du2 : 0.001);
    return (slope1 * slope2) < 0;
  }

  static bool _isTwoStrokeFive(Stroke s1, Stroke s2, Offset dir, Offset normal) {
    final b1 = s1.bounds;
    final b2 = s2.bounds;
    final union = b1.expandToInclude(b2);

    final chord1 = _getStrokeChord(s1);
    final chord2 = _getStrokeChord(s2);

    final u1 = (chord1.dx * dir.dx + chord1.dy * dir.dy).abs();
    final v1 = (chord1.dx * normal.dx + chord1.dy * normal.dy).abs();
    final u2 = (chord2.dx * dir.dx + chord2.dy * dir.dy).abs();
    final v2 = (chord2.dx * normal.dx + chord2.dy * normal.dy).abs();

    final s1IsBar = u1 > v1 * 1.3 && _getPathLength(s1) / chord1.distance < 1.35;
    final s2IsBar = u2 > v2 * 1.3 && _getPathLength(s2) / chord2.distance < 1.35;

    if (s1IsBar && !s2IsBar) {
      return b2.height > union.height * 0.60;
    } else if (s2IsBar && !s1IsBar) {
      return b1.height > union.height * 0.60;
    }
    return false;
  }

  static bool _isTwoStrokeFour(Stroke s1, Stroke s2, Offset dir, Offset normal) {
    final chord1 = _getStrokeChord(s1);
    final chord2 = _getStrokeChord(s2);

    final u1 = (chord1.dx * dir.dx + chord1.dy * dir.dy).abs();
    final v1 = (chord1.dx * normal.dx + chord1.dy * normal.dy).abs();
    final u2 = (chord2.dx * dir.dx + chord2.dy * dir.dy).abs();
    final v2 = (chord2.dx * normal.dx + chord2.dy * normal.dy).abs();

    final s1IsVertical = v1 > u1 * 1.8;
    final s2IsVertical = v2 > u2 * 1.8;
    return (s1IsVertical && !s2IsVertical) || (s2IsVertical && !s1IsVertical);
  }

  static String? _classifySingleStrokeAligned(Stroke s, Offset dir, Offset normal) {
    final pts = s.points;
    if (pts.length < 2) return null;

    final chord = _getStrokeChord(s);
    final uChord = (chord.dx * dir.dx + chord.dy * dir.dy).abs();
    final vChord = (chord.dx * normal.dx + chord.dy * normal.dy).abs();
    final pathLen = _getPathLength(s);
    final chordDist = chord.distance;
    final straightness = pathLen > 0 ? (chordDist / pathLen) : 1.0;

    // Project all points into baseline coordinates (u, v)
    final uVals = <double>[];
    final vVals = <double>[];
    for (final p in pts) {
      uVals.add(p.x * dir.dx + p.y * dir.dy);
      vVals.add(p.x * normal.dx + p.y * normal.dy);
    }

    final minU = uVals.reduce(math.min);
    final maxU = uVals.reduce(math.max);
    final minV = vVals.reduce(math.min);
    final maxV = vVals.reduce(math.max);

    final uSpan = maxU - minU;
    final vSpan = maxV - minV;

    final firstU = uVals.first;
    final lastU = uVals.last;
    final firstV = vVals.first;
    final lastV = vVals.last;

    // 0. Dot / Decimal point (.)
    if (uSpan < 12.0 && vSpan < 12.0 && pathLen < 22.0) {
      return '.';
    }

    // 1. Minus (-) : Straight stroke along text baseline
    if (straightness > 0.70 && uChord > vChord * 1.8 && uSpan > 10.0 && vSpan < uSpan * 0.45) {
      return ' - ';
    }

    // 2. Division slash (/) : Straight diagonal stroke
    if (straightness > 0.75 && vChord > 15.0 && uChord > 6.0 && (lastV - firstV) > 0 && (lastU - firstU) < 0) {
      return ' / ';
    }

    // 3. Number One (1) : Straight stroke perpendicular to text baseline
    if (straightness > 0.70 && vChord > uChord * 1.8 && vSpan > 15.0) {
      return '1';
    }

    // 4. Closed loops: Zero (0) vs Eight (8) vs Letter 'a'
    final startToEnd = (pts.last.offset - pts.first.offset).distance;
    final isClosedLoop = startToEnd < pathLen * 0.35 && vSpan > 14.0 && uSpan > 8.0;

    if (isClosedLoop) {
      // Check for hourglass waist of digit 8:
      // An '8' has a top lobe (v ~ 0.25) and bottom lobe (v ~ 0.75) wider than the middle waist (v ~ 0.50)
      final v25 = minV + vSpan * 0.25;
      final v50 = minV + vSpan * 0.50;
      final v75 = minV + vSpan * 0.75;
      final band = vSpan * 0.15;

      double minU25 = maxU, maxU25 = minU;
      double minU50 = maxU, maxU50 = minU;
      double minU75 = maxU, maxU75 = minU;

      for (int k = 0; k < pts.length; k++) {
        final v = vVals[k];
        final u = uVals[k];
        if ((v - v25).abs() < band) {
          if (u < minU25) minU25 = u;
          if (u > maxU25) maxU25 = u;
        }
        if ((v - v50).abs() < band) {
          if (u < minU50) minU50 = u;
          if (u > maxU50) maxU50 = u;
        }
        if ((v - v75).abs() < band) {
          if (u < minU75) minU75 = u;
          if (u > maxU75) maxU75 = u;
        }
      }

      final wTop = maxU25 > minU25 ? maxU25 - minU25 : 0.0;
      final wMid = maxU50 > minU50 ? maxU50 - minU50 : 0.0;
      final wBot = maxU75 > minU75 ? maxU75 - minU75 : 0.0;

      final hasWaist = wTop > uSpan * 0.40 && wBot > uSpan * 0.40 && wMid < math.min(wTop, wBot) * 0.72;
      if (hasWaist) {
        return '8';
      }

      // Check if it's letter 'a': single loop with right-side downward stem
      final endsBottomRight = lastU > minU + uSpan * 0.45 && lastV > minV + vSpan * 0.50;
      if (endsBottomRight && wMid > uSpan * 0.60) {
        return 'a';
      }

      int midCrossings = 0;
      for (int k = 0; k < vVals.length - 1; k++) {
        if ((vVals[k] - v50) * (vVals[k + 1] - v50) < 0) {
          midCrossings++;
        }
      }

      if (midCrossings <= 2) {
        return '0';
      }

      if (endsBottomRight) {
        return 'a';
      }

      return null;
    }

    // 4b. Detect 'y' / 'u' / 'w' cup-and-descender shape
    // A math digit (2, 3, 5, etc.) does NOT oscillate vertically (down, up, down)
    if (pts.length >= 8 && vSpan > 15.0) {
      int vDirections = 0;
      double lastExtremumV = firstV;
      bool movingDown = true;
      for (int k = 1; k < pts.length; k++) {
        final curV = vVals[k];
        if (movingDown && curV > lastExtremumV + vSpan * 0.20) {
          vDirections++;
          movingDown = false;
          lastExtremumV = curV;
        } else if (!movingDown && curV < lastExtremumV - vSpan * 0.20) {
          vDirections++;
          movingDown = true;
          lastExtremumV = curV;
        }
      }
      if (vDirections >= 2) {
        // Multi-inflection cup/descender letter (e.g. cursive 'y', 'u', 'w')
        return null;
      }
    }

    // Check Letter 'b':
    // Starts at top-left, has a tall left ascender stem in upper half (u < minU + uSpan * 0.58)
    // and a bottom-right loop in the lower half (reaches u > minU + uSpan * 0.65)
    final bStartsTopLeft = firstU < minU + uSpan * 0.50 && firstV < minV + vSpan * 0.35;
    if (bStartsTopLeft && vSpan > 18.0) {
      double maxUInTop = minU;
      double maxUInBot = minU;
      for (int k = 0; k < pts.length; k++) {
        final v = vVals[k];
        final u = uVals[k];
        if (v < minV + vSpan * 0.45) {
          if (u > maxUInTop) maxUInTop = u;
        } else {
          if (u > maxUInBot) maxUInBot = u;
        }
      }
      final hasLeftAscender = (maxUInTop - minU) < uSpan * 0.58;
      final hasBottomRightLoop = (maxUInBot - minU) > uSpan * 0.65;
      if (hasLeftAscender && hasBottomRightLoop) {
        return 'b';
      }
    }

    // Check Letter 'c':
    // Open crescent curving to the left: starts top-right, curves through left, ends bottom-right
    if (firstU > minU + uSpan * 0.45 && firstV < minV + vSpan * 0.40 &&
        lastU > minU + uSpan * 0.45 && lastV > minV + vSpan * 0.60 &&
        !isClosedLoop && straightness < 0.65) {
      double minUInMid = maxU;
      for (int k = 0; k < pts.length; k++) {
        if ((vVals[k] - (minV + vSpan * 0.5)).abs() < vSpan * 0.25) {
          if (uVals[k] < minUInMid) minUInMid = uVals[k];
        }
      }
      if (minUInMid < minU + uSpan * 0.35) {
        return 'c';
      }
    }

    // 5. Open loop digits: Nine (9) vs Six (6) vs Seven (7) vs Two (2) vs Three (3) vs Five (5) vs Four (4)
    final startsTop = firstV < minV + vSpan * 0.45;
    final endsBottom = lastV > minV + vSpan * 0.65;
    final pLen = pts.length;

    // Check Nine (9):
    // Starts in upper half, loops in upper half, and stem descends on the RIGHT side to bottom
    bool hasTopLoop = false;
    if (pLen >= 6 && startsTop && endsBottom) {
      final pEarly = pts[(pLen * 0.15).toInt()].offset;
      for (int k = (pLen * 0.35).toInt(); k < (pLen * 0.75).toInt(); k++) {
        final d = (pts[k].offset - pEarly).distance;
        final vK = vVals[k];
        if (d < math.max(22.0, vSpan * 0.35) && vK < minV + vSpan * 0.65) {
          hasTopLoop = true;
          break;
        }
      }
    }

    final stemOnRight = lastU > minU + uSpan * 0.40;
    if (hasTopLoop && endsBottom && stemOnRight) {
      return '9';
    }

    // Check Six (6):
    // Starts top, descends, and has a bottom loop (point near end meets mid-stem)
    bool hasBottomLoop = false;
    if (pLen >= 6 && startsTop && lastV < maxV - vSpan * 0.10) {
      final pLate = pts.last.offset;
      for (int k = (pLen * 0.25).toInt(); k < (pLen * 0.65).toInt(); k++) {
        final d = (pts[k].offset - pLate).distance;
        final vK = vVals[k];
        if (d < math.max(22.0, vSpan * 0.35) && vK > minV + vSpan * 0.35) {
          hasBottomLoop = true;
          break;
        }
      }
    }

    if (hasBottomLoop) {
      return '6';
    }

    // Check Seven (7):
    // Starts top-left, moves to top-right, goes down to bottom-left/center
    final startsTopLeft = firstU < minU + uSpan * 0.50 && firstV < minV + vSpan * 0.35;
    final endsBottomLeft = lastU < minU + uSpan * 0.65 && endsBottom;
    if (startsTopLeft && endsBottomLeft && straightness > 0.55 && !hasTopLoop) {
      double maxUAtTop = minU;
      for (int k = 0; k < pts.length; k++) {
        if (vVals[k] < minV + vSpan * 0.40 && uVals[k] > maxUAtTop) {
          maxUAtTop = uVals[k];
        }
      }
      if (maxUAtTop > minU + uSpan * 0.70) {
        return '7';
      }
    }

    // Check Two (2):
    // Top arch, diagonals down to bottom-left, horizontal base to bottom-right
    if (startsTop && endsBottom) {
      final isCurved = pathLen / math.max(1.0, chordDist) > 1.25;
      final endsRight = lastU > minU + uSpan * 0.40;
      if (isCurved && endsRight) {
        return '2';
      }
    }

    // Check Five (5):
    // Single stroke 5: starts top-right, top bar left, stem down, bottom lobe open left
    if (firstU > minU + uSpan * 0.35 && firstV < minV + vSpan * 0.40 && lastU < minU + uSpan * 0.70) {
      final isCurved = pathLen / math.max(1.0, chordDist) > 1.25;
      if (isCurved && vSpan > 15.0) {
        return '5';
      }
    }

    // Check Three (3):
    // Two rightward lobes, leftward center indent
    if (vSpan > 16.0 && lastU < minU + uSpan * 0.60) {
      final midV = minV + vSpan * 0.50;
      double minUNearMid = maxU;
      for (int k = 0; k < pts.length; k++) {
        if ((vVals[k] - midV).abs() < vSpan * 0.20) {
          if (uVals[k] < minUNearMid) minUNearMid = uVals[k];
        }
      }
      if (minUNearMid < minU + uSpan * 0.65) {
        return '3';
      }
    }

    // Check single-stroke Four (4):
    // Must NOT be a straight diagonal line (e.g. straightness must be < 0.72)
    if (straightness < 0.72 && startsTop && endsBottom && lastU > minU + uSpan * 0.40) {
      return '4';
    }

    return null;
  }
}

class AngleInvariantEqualSign {
  final Offset center;
  final Offset direction;
  final Offset normal;
  final double length;
  final int strokeColor;
  final double strokeWidth;
  final Set<String> consumedStrokeIds;

  AngleInvariantEqualSign({
    required this.center,
    required this.direction,
    required this.normal,
    required this.length,
    required this.strokeColor,
    required this.strokeWidth,
    required this.consumedStrokeIds,
  });
}

class _ProjectedStroke {
  final Stroke stroke;
  final double u; // Position along equation baseline
  final double v; // Position perpendicular to baseline

  _ProjectedStroke({required this.stroke, required this.u, required this.v});
}
