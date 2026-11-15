import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/shape_model.dart';
import '../models/stroke_model.dart';
import '../models/stroke_point.dart';
import '../models/tool_type.dart';

class ShapeDetectionResult {
  final ShapeType shapeType;
  final ShapeObject suggestedShape;
  final Stroke originalStroke;
  final List<Stroke>? originalStrokes; // If multi-stroke shape
  final double confidence; // 0.0 to 1.0

  const ShapeDetectionResult({
    required this.shapeType,
    required this.suggestedShape,
    required this.originalStroke,
    this.originalStrokes,
    required this.confidence,
  });
}

class ShapeDetector {
  /// At or above this straight-run fraction an outline has real sides, so it
  /// is never a circle. Hand-drawn circles measure 0.00-0.12; octagons
  /// 0.26-0.45; hexagons and fewer sides 0.48+ (see shape tests).
  static const double _polygonStraightness = 0.20;

  /// Below this an outline is a smooth curve, so it is never a 5-8 sided
  /// polygon (prevents gapped circles being "simplified" into octagons).
  static const double _smoothCurveStraightness = 0.15;

  /// Stroke area / best-fit rectangle area at or above which a four-cornered
  /// outline is a rectangle. Rectangles (even rounded) ≈ 0.9+; ellipses
  /// 0.785; regular hexagons 0.75; triangles and rhombi ≤ 0.6.
  static const double _minRectangularity = 0.84;

  static const uuid = Uuid();

  /// Analyze a finished stroke and accurately detect if it is a Line, Arrow, Rectangle/Square,
  /// Triangle, Circle/Oval, Diamond, or Star.
  static ShapeDetectionResult? detectShape(Stroke stroke) {
    final points = stroke.points;
    if (points.length < 5) return null;

    // Bounds of the ink itself. (Stroke.bounds is padded for hit-testing,
    // which made every converted shape ~1 pen-width too big on each side.)
    final bounds = _inkBounds(points);
    final maxDim = math.max(bounds.width, bounds.height);
    if (maxDim < 25.0) return null; // Ignore tiny marks or scribbles

    final first = points.first.offset;
    final last = points.last.offset;
    final totalPathLength = _calculatePathLength(points);
    final startToEndDistance = (last - first).distance;
    final isClosed =
        startToEndDistance < (totalPathLength * 0.40) ||
        startToEndDistance < (maxDim * 0.45);

    // 1. Non-Closed Shapes (Straight Line and Arrow)
    if (!isClosed) {
      // 1a. Single-stroke Arrow check
      final arrowResult = _checkSingleStrokeArrow(stroke, points);
      if (arrowResult != null) return arrowResult;

      // 1b. Straight Line Check
      final lineResult = _checkStraightLine(
        stroke,
        points,
        first,
        last,
        totalPathLength,
      );
      if (lineResult != null) return lineResult;
    }

    // 2. Closed / Near-Closed Shapes
    if (isClosed) {
      // 2a. Smooth round curve: Definitely Circle / Oval
      // Checking circle first prevents smooth hand-drawn circles from falsely being simplified into 8-sided octagons!
      final circleResult = _checkCircle(stroke, points, bounds);
      if (circleResult != null) return circleResult;

      final sharpCorners = _countSharpCorners(points, bounds);

      if (sharpCorners >= 3) {
        // Definitely a Polygon (Rectangle/Square, Triangle, Diamond)
        final polyResult = _checkPolygon(stroke, points, bounds);
        if (polyResult != null) return polyResult;

        final starResult = _checkStar(stroke, points, bounds);
        if (starResult != null) return starResult;
      } else {
        final polyResult = _checkPolygon(stroke, points, bounds);
        if (polyResult != null) return polyResult;

        final starResult = _checkStar(stroke, points, bounds);
        if (starResult != null) return starResult;
      }

      // Smooth round outline the bounds-based check missed (typically a
      // circle left open where the pen lifted, which skews its bounds).
      final fitted = _checkFittedCircle(stroke, points);
      if (fitted != null) return fitted;
    }

    return null;
  }

  /// Least-squares (Kåsa) circle fit. Accepts smooth outlines whose points
  /// sit at a near-constant distance from the fitted centre and which cover
  /// most of the circle.
  static ShapeDetectionResult? _checkFittedCircle(
    Stroke stroke,
    List<StrokePoint> points,
  ) {
    if (points.length < 12) return null;
    if (_looksPolygonal(points, _smoothCurveStraightness)) return null;

    // Solve x² + y² + Dx + Ey + F = 0 in least squares (normal equations).
    double sx = 0, sy = 0, sxx = 0, syy = 0, sxy = 0, sz = 0, sxz = 0, syz = 0;
    final n = points.length.toDouble();
    for (final p in points) {
      final x = p.x, y = p.y, z = x * x + y * y;
      sx += x;
      sy += y;
      sxx += x * x;
      syy += y * y;
      sxy += x * y;
      sz += z;
      sxz += x * z;
      syz += y * z;
    }
    // [sxx sxy sx][D]   [-sxz]
    // [sxy syy sy][E] = [-syz]
    // [sx  sy  n ][F]   [-sz ]
    final m = [
      [sxx, sxy, sx, -sxz],
      [sxy, syy, sy, -syz],
      [sx, sy, n, -sz],
    ];
    for (int c = 0; c < 3; c++) {
      int piv = c;
      for (int r = c + 1; r < 3; r++) {
        if (m[r][c].abs() > m[piv][c].abs()) piv = r;
      }
      if (m[piv][c].abs() < 1e-9) return null;
      final tmp = m[c];
      m[c] = m[piv];
      m[piv] = tmp;
      for (int r = 0; r < 3; r++) {
        if (r == c) continue;
        final f = m[r][c] / m[c][c];
        for (int k = c; k < 4; k++) {
          m[r][k] -= f * m[c][k];
        }
      }
    }
    final d = m[0][3] / m[0][0], e = m[1][3] / m[1][1], f = m[2][3] / m[2][2];
    final center = Offset(-d / 2, -e / 2);
    final r2 = center.dx * center.dx + center.dy * center.dy - f;
    if (r2 <= 0) return null;
    final radius = math.sqrt(r2);
    if (radius < 12.5) return null;

    double sum = 0, sumSq = 0;
    for (final p in points) {
      final dist = (p.offset - center).distance;
      sum += dist;
      sumSq += dist * dist;
    }
    final mean = sum / n;
    final cv = math.sqrt(math.max(0, sumSq / n - mean * mean)) / mean;
    if (cv > 0.08) return null;

    // Must sweep most of the way round (not just an arc).
    final arc = _calculatePathLength(points);
    if (arc < 2 * math.pi * radius * 0.70) return null;

    return ShapeDetectionResult(
      shapeType: ShapeType.circle,
      suggestedShape: ShapeObject(
        id: uuid.v4(),
        shapeType: ShapeType.circle,
        start: center - Offset(radius, radius),
        end: center + Offset(radius, radius),
        strokeColorValue: stroke.colorValue,
        strokeWidth: stroke.width,
      ),
      originalStroke: stroke,
      confidence: (1.0 - cv * 4).clamp(0.7, 0.95),
    );
  }

  /// Multi-stroke shape detector (e.g., 2-stroke arrow, 3-stroke triangle, 4-stroke rectangle)
  static ShapeDetectionResult? detectMultiStrokeShape(
    List<Stroke> recentStrokes,
  ) {
    if (recentStrokes.length < 2) return null;

    // 1. Check last 2 strokes for arrow (Line shaft + V arrowhead)
    if (recentStrokes.length >= 2) {
      final s1 = recentStrokes[recentStrokes.length - 2];
      final s2 = recentStrokes.last;
      final arrowResult = _checkTwoStrokeArrow(s1, s2);
      if (arrowResult != null) return arrowResult;
    }

    // 2. Check last 3 strokes for triangle
    if (recentStrokes.length >= 3) {
      final s1 = recentStrokes[recentStrokes.length - 3];
      final s2 = recentStrokes.length >= 2
          ? recentStrokes[recentStrokes.length - 2]
          : null;
      final s3 = recentStrokes.last;
      if (s2 != null) {
        final triResult = _checkThreeStrokeTriangle(s1, s2, s3);
        if (triResult != null) return triResult;
      }
    }

    // 3. Check last 4 strokes for rectangle
    if (recentStrokes.length >= 4) {
      final s1 = recentStrokes[recentStrokes.length - 4];
      final s2 = recentStrokes[recentStrokes.length - 3];
      final s3 = recentStrokes[recentStrokes.length - 2];
      final s4 = recentStrokes.last;
      final rectResult = _checkFourStrokeRectangle(s1, s2, s3, s4);
      if (rectResult != null) return rectResult;
    }

    return null;
  }

  static double _calculatePathLength(List<StrokePoint> points) {
    double length = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
      length += points[i].distanceTo(points[i + 1]);
    }
    return length;
  }

  // --- Arrow Classifiers (Single-Stroke and Two-Stroke) ---

  static ShapeDetectionResult? _checkSingleStrokeArrow(
    Stroke stroke,
    List<StrokePoint> points,
  ) {
    if (points.length < 6) return null;

    final pStart = points.first.offset;
    double maxDist = 0;
    int maxIdx = 0;

    for (int i = 0; i < points.length; i++) {
      final d = (points[i].offset - pStart).distance;
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxDist < 35.0) return null;

    // Arrowhead drawn at the end: shaft is 0..maxIdx, barb is maxIdx..end
    if (maxIdx >= (points.length * 0.50).toInt() &&
        maxIdx < points.length - 1) {
      final shaftPath = _calculatePathLength(points.sublist(0, maxIdx + 1));
      if (shaftPath <= 0) return null;
      final shaftDirect = (points[maxIdx].offset - pStart).distance;

      // Shaft must be reasonably straight
      if (shaftDirect / shaftPath >= 0.82) {
        final pTip = points[maxIdx].offset;
        final shaftVec = pTip - pStart;

        // Barb points must stay near tip
        bool barbStaysNearTip = true;
        for (int i = maxIdx + 1; i < points.length; i++) {
          if ((points[i].offset - pTip).distance >
              math.max(45.0, shaftDirect * 0.45)) {
            barbStaysNearTip = false;
            break;
          }
        }

        if (barbStaysNearTip) {
          final barbVec = points.last.offset - pTip;
          if (barbVec.distance > 5.0) {
            final dot =
                (shaftVec.dx * barbVec.dx + shaftVec.dy * barbVec.dy) /
                (shaftVec.distance * barbVec.distance);
            // Barb points backward relative to shaft direction (dot < 0.35)
            if (dot < 0.35) {
              final shape = ShapeObject(
                id: uuid.v4(),
                shapeType: ShapeType.arrow,
                start: pStart,
                end: pTip,
                strokeColorValue: stroke.colorValue,
                strokeWidth: stroke.width,
              );

              return ShapeDetectionResult(
                shapeType: ShapeType.arrow,
                suggestedShape: shape,
                originalStroke: stroke,
                confidence: 0.92,
              );
            }
          }
        }
      }
    }

    return null;
  }

  static ShapeDetectionResult? _checkTwoStrokeArrow(Stroke s1, Stroke s2) {
    // s1: Shaft (straight line)
    // s2: Arrowhead ("V" shape)
    final p1Start = s1.points.first.offset;
    final p1End = s1.points.last.offset;
    final shaftLen = (p1End - p1Start).distance;
    if (shaftLen < 30.0) return null;
    final shaftPath = _calculatePathLength(s1.points);
    if (shaftLen / shaftPath < 0.85) return null;

    // Analyze s2: Should be a V shape (2 segments with an acute angle)
    final offsets2 = s2.points.map((p) => p.offset).toList();
    final simplified2 = _rdpSimplify(offsets2, 5.0);
    if (simplified2.length == 3) {
      final apex = simplified2[1];
      final arm1 = simplified2[0] - apex;
      final arm2 = simplified2[2] - apex;

      if (arm1.distance > 6.0 && arm2.distance > 6.0) {
        final dot =
            (arm1.dx * arm2.dx + arm1.dy * arm2.dy) /
            (arm1.distance * arm2.distance);
        final angle = math.acos(dot.clamp(-1.0, 1.0));

        // V angle between 25° and 100° (0.40 to 1.80 rad)
        if (angle >= 0.40 && angle <= 1.80) {
          final distToEnd = (apex - p1End).distance;
          final distToStart = (apex - p1Start).distance;

          if (distToEnd <= 35.0) {
            // Arrow pointing from s1Start to s1End
            final shape = ShapeObject(
              id: uuid.v4(),
              shapeType: ShapeType.arrow,
              start: p1Start,
              end: p1End,
              strokeColorValue: s2.colorValue,
              strokeWidth: s2.width,
            );

            return ShapeDetectionResult(
              shapeType: ShapeType.arrow,
              suggestedShape: shape,
              originalStroke: s2,
              originalStrokes: [s1, s2],
              confidence: 0.94,
            );
          } else if (distToStart <= 35.0) {
            // Arrow pointing from s1End to s1Start
            final shape = ShapeObject(
              id: uuid.v4(),
              shapeType: ShapeType.arrow,
              start: p1End,
              end: p1Start,
              strokeColorValue: s2.colorValue,
              strokeWidth: s2.width,
            );

            return ShapeDetectionResult(
              shapeType: ShapeType.arrow,
              suggestedShape: shape,
              originalStroke: s2,
              originalStrokes: [s1, s2],
              confidence: 0.94,
            );
          }
        }
      }
    }

    return null;
  }

  // --- Straight Line Classifier ---
  static ShapeDetectionResult? _checkStraightLine(
    Stroke stroke,
    List<StrokePoint> points,
    Offset first,
    Offset last,
    double totalPathLength,
  ) {
    final directDistance = (last - first).distance;
    if (directDistance < 30.0) return null;

    final chordRatio = directDistance / totalPathLength;
    if (chordRatio > 0.88) {
      final shape = ShapeObject(
        id: uuid.v4(),
        shapeType: ShapeType.line,
        start: first,
        end: last,
        strokeColorValue: stroke.colorValue,
        strokeWidth: stroke.width,
      );

      return ShapeDetectionResult(
        shapeType: ShapeType.line,
        suggestedShape: shape,
        originalStroke: stroke,
        confidence: chordRatio,
      );
    }
    return null;
  }

  // --- Polygon Classifier (Rectangle/Square, Triangle, Diamond, Pentagon, Hexagon, Heptagon, Octagon) ---
  static ShapeDetectionResult? _checkPolygon(
    Stroke stroke,
    List<StrokePoint> points,
    Rect bounds,
  ) {
    final offsets = points.map((p) => p.offset).toList();
    final boundsArea = bounds.width * bounds.height;
    if (boundsArea < 200) return null;

    final area = _calculatePolygonArea(offsets);
    final fillRatio = area / boundsArea;

    // 1. Closed-contour RDP simplification
    final simplified = _simplifyClosedContour(offsets, bounds);
    if (simplified.length < 3) return null;

    final mergedVertices = _mergeCollinearVertices(simplified);
    // Smooth curves (e.g. a circle with a gap) must not become 5-8 gons.
    // Sparse input (<= 12 samples) is effectively a list of vertices.
    final hasStraightSides =
        points.length <= 12 ||
        _looksPolygonal(points, _smoothCurveStraightness);
    // A smooth curve (circle, oval, gapped circle) has no straight sides, so
    // it is never a polygon. Without this, the "fills its bounding box"
    // rectangle fallback below also accepted circles (fill ratio ~0.79).
    if (!hasStraightSides) return null;

    // Four-sided boxes, including rounded corners, small boxes and tilted
    // ones: the stroke nearly fills its best-fit (oriented) rectangle and has
    // four corners. Checked before vertex counting, which splits rounded
    // corners (rectangle -> "pentagon").
    final nv = mergedVertices.length;
    if (hasStraightSides && nv >= 4 && nv <= 6) {
      final fit = _fitOrientedRect(offsets);
      final rectangularity = fit.w * fit.h > 0 ? area / (fit.w * fit.h) : 0.0;
      final sides = points.length <= 12 ? nv : estimateSides(points);
      if (rectangularity >= _minRectangularity &&
          (sides == 4 || (sides == 0 && nv == 4))) {
        // A square stood on its corner is a diamond.
        final squareish = (fit.w - fit.h).abs() / math.max(fit.w, fit.h) < 0.18;
        if (squareish &&
            (fit.angle.abs() - math.pi / 4).abs() < 10 * math.pi / 180) {
          return _buildDiamondResult(stroke, bounds);
        }
        return _buildRectangleResult(stroke, bounds);
      }
    }

    // Check Rectangle / Square first if exactly 4 orthogonal vertices
    if (fillRatio >= 0.70 &&
        mergedVertices.length == 4 &&
        _isOrthogonalRectangle(mergedVertices)) {
      return _buildRectangleResult(stroke, bounds);
    }

    // 2. Check by vertex count
    final n = mergedVertices.length;

    // 2-pre. 5-8 sided polygons: trust the corner count from the turning
    // profile when it is close to the simplified vertex count (rounded
    // corners can split into two simplified vertices, e.g. hexagon -> 7).
    if (hasStraightSides && n >= 4) {
      final sides = estimateSides(points);
      if (sides >= 5 && sides <= 8 && (n - sides).abs() <= 2) {
        final regular = _regularizePolygon(mergedVertices, bounds, sides);
        switch (sides) {
          case 5:
            return _buildPentagonResult(stroke, bounds, regular);
          case 6:
            return _buildHexagonResult(stroke, bounds, regular);
          case 7:
            return _buildHeptagonResult(stroke, bounds, regular);
          case 8:
            return _buildOctagonResult(stroke, bounds, regular);
        }
      }
    }

    // 2. Check by exact vertex count first:
    // 2a. Triangle (3 vertices)
    if (n == 3 && _isValidTriangle(mergedVertices, bounds)) {
      final regularized = _regularizeTriangle(mergedVertices, bounds);
      return _buildTriangleResult(stroke, bounds, regularized);
    }

    // 2b. Diamond (Rhombus - 4 vertices with diagonal orientation)
    if (n == 4 && _isDiamond(mergedVertices, bounds)) {
      return _buildDiamondResult(stroke, bounds);
    }

    // 2c. Rectangle / Square (4 vertices)
    if (n == 4 && _isOrthogonalRectangle(mergedVertices)) {
      return _buildRectangleResult(stroke, bounds);
    }

    // 2d. Pentagon (5 vertices)
    if (hasStraightSides && n == 5 && _isReasonablePolygon(mergedVertices, 5)) {
      return _buildPentagonResult(
        stroke,
        bounds,
        _regularizePolygon(mergedVertices, bounds, 5),
      );
    }

    // 2e. Hexagon (6 vertices)
    if (hasStraightSides && n == 6 && _isReasonablePolygon(mergedVertices, 6)) {
      return _buildHexagonResult(
        stroke,
        bounds,
        _regularizePolygon(mergedVertices, bounds, 6),
      );
    }

    // 2f. Heptagon (7 vertices)
    if (hasStraightSides && n == 7 && _isReasonablePolygon(mergedVertices, 7)) {
      final circleRes = _checkCircle(stroke, points, bounds);
      if (circleRes != null) return circleRes;
      return _buildHeptagonResult(
        stroke,
        bounds,
        _regularizePolygon(mergedVertices, bounds, 7),
      );
    }

    // 2g. Octagon (8 vertices)
    if (hasStraightSides && n == 8 && _isReasonablePolygon(mergedVertices, 8)) {
      final circleRes = _checkCircle(stroke, points, bounds);
      if (circleRes != null) return circleRes;
      return _buildOctagonResult(
        stroke,
        bounds,
        _regularizePolygon(mergedVertices, bounds, 8),
      );
    }

    // 3. Sub-candidate checks (tolerance for 1 stray corner or hook):
    // 3a. Triangle from 4 vertices
    if (n == 4 && fillRatio < 0.65) {
      for (int i = 0; i < 4; i++) {
        final candidate = [
          for (int j = 0; j < 4; j++)
            if (j != i) mergedVertices[j],
        ];
        if (_isValidTriangle(candidate, bounds)) {
          final regularized = _regularizeTriangle(candidate, bounds);
          return _buildTriangleResult(stroke, bounds, regularized);
        }
      }
    }

    // 3b. Rectangle from 5 vertices
    if (n == 5) {
      for (int i = 0; i < 5; i++) {
        final candidate = [
          for (int j = 0; j < 5; j++)
            if (j != i) mergedVertices[j],
        ];
        if (_isOrthogonalRectangle(candidate)) {
          return _buildRectangleResult(stroke, bounds);
        }
      }
    }

    // 3c. Pentagon from 6 vertices
    if (hasStraightSides && n == 6) {
      for (int i = 0; i < 6; i++) {
        final candidate = [
          for (int j = 0; j < 6; j++)
            if (j != i) mergedVertices[j],
        ];
        if (_isReasonablePolygon(candidate, 5)) {
          return _buildPentagonResult(
            stroke,
            bounds,
            _regularizePolygon(candidate, bounds, 5),
          );
        }
      }
    }

    // 3d. Hexagon from 7 vertices
    if (hasStraightSides && n == 7) {
      for (int i = 0; i < 7; i++) {
        final candidate = [
          for (int j = 0; j < 7; j++)
            if (j != i) mergedVertices[j],
        ];
        if (_isReasonablePolygon(candidate, 6)) {
          return _buildHexagonResult(
            stroke,
            bounds,
            _regularizePolygon(candidate, bounds, 6),
          );
        }
      }
    }

    // 3e. Octagon from 9 vertices
    if (hasStraightSides && n == 9) {
      final circleRes = _checkCircle(stroke, points, bounds);
      if (circleRes != null) return circleRes;
      for (int i = 0; i < 9; i++) {
        final candidate = [
          for (int j = 0; j < 9; j++)
            if (j != i) mergedVertices[j],
        ];
        if (_isReasonablePolygon(candidate, 8)) {
          return _buildOctagonResult(
            stroke,
            bounds,
            _regularizePolygon(candidate, bounds, 8),
          );
        }
      }
    }

    // 4. Fallback for Rectangle: High fill ratio and aspect ratio
    if (fillRatio >= 0.70 && _isDominantRectangle(offsets, bounds, fillRatio)) {
      return _buildRectangleResult(stroke, bounds);
    }

    return null;
  }

  static double _calculatePolygonArea(List<Offset> pts) {
    if (pts.length < 3) return 0.0;
    double area = 0.0;
    for (int i = 0; i < pts.length; i++) {
      final p1 = pts[i];
      final p2 = pts[(i + 1) % pts.length];
      area += (p1.dx * p2.dy - p2.dx * p1.dy);
    }
    return (area / 2.0).abs();
  }

  static bool _isDominantRectangle(
    List<Offset> offsets,
    Rect bounds,
    double fillRatio,
  ) {
    if (fillRatio < 0.70) return false;
    final aspect = bounds.width / bounds.height;
    if (aspect < 0.35 || aspect > 2.8) return false;

    final marginX = bounds.width * 0.22;
    final marginY = bounds.height * 0.22;
    int nearBorderPoints = 0;

    for (final p in offsets) {
      final nearLeft = (p.dx - bounds.left).abs() <= marginX;
      final nearRight = (p.dx - bounds.right).abs() <= marginX;
      final nearTop = (p.dy - bounds.top).abs() <= marginY;
      final nearBottom = (p.dy - bounds.bottom).abs() <= marginY;
      if (nearLeft || nearRight || nearTop || nearBottom) {
        nearBorderPoints++;
      }
    }

    if ((nearBorderPoints / offsets.length) < 0.75) return false;

    // A rectangle fills all 4 corners/quadrants
    bool hasTL = false, hasTR = false, hasBL = false, hasBR = false;
    final midX = bounds.center.dx;
    final midY = bounds.center.dy;
    for (final p in offsets) {
      if (p.dx <= midX && p.dy <= midY) hasTL = true;
      if (p.dx >= midX && p.dy <= midY) hasTR = true;
      if (p.dx <= midX && p.dy >= midY) hasBL = true;
      if (p.dx >= midX && p.dy >= midY) hasBR = true;
    }
    return hasTL && hasTR && hasBL && hasBR;
  }

  static bool _isDiamond(List<Offset> v4, Rect bounds) {
    if (v4.length != 4) return false;
    final center = bounds.center;
    for (final v in v4) {
      final rel = v - center;
      final nearXAxis =
          rel.dy.abs() < bounds.height * 0.28 &&
          rel.dx.abs() > bounds.width * 0.28;
      final nearYAxis =
          rel.dx.abs() < bounds.width * 0.28 &&
          rel.dy.abs() > bounds.height * 0.28;
      if (!nearXAxis && !nearYAxis) return false;
    }
    return true;
  }

  static ShapeDetectionResult _buildDiamondResult(Stroke stroke, Rect bounds) {
    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.diamond,
      start: bounds.topLeft,
      end: bounds.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.diamond,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.90,
    );
  }

  static ShapeDetectionResult _buildPentagonResult(
    Stroke stroke,
    Rect bounds, [
    List<Offset>? customVertices,
  ]) {
    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.pentagon,
      start: bounds.topLeft,
      end: bounds.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
      customVertices: customVertices ?? _generateRegularPolygon(bounds, 5),
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.pentagon,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.95,
    );
  }

  static ShapeDetectionResult _buildHexagonResult(
    Stroke stroke,
    Rect bounds, [
    List<Offset>? customVertices,
  ]) {
    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.hexagon,
      start: bounds.topLeft,
      end: bounds.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
      customVertices:
          customVertices ?? _generateRegularPolygon(bounds, 6, startAngle: 0.0),
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.hexagon,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.95,
    );
  }

  static ShapeDetectionResult _buildHeptagonResult(
    Stroke stroke,
    Rect bounds, [
    List<Offset>? customVertices,
  ]) {
    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.heptagon,
      start: bounds.topLeft,
      end: bounds.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
      customVertices: customVertices ?? _generateRegularPolygon(bounds, 7),
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.heptagon,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.93,
    );
  }

  static ShapeDetectionResult _buildOctagonResult(
    Stroke stroke,
    Rect bounds, [
    List<Offset>? customVertices,
  ]) {
    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.octagon,
      start: bounds.topLeft,
      end: bounds.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
      customVertices:
          customVertices ??
          _generateRegularPolygon(bounds, 8, startAngle: -math.pi / 8),
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.octagon,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.95,
    );
  }

  static bool _isReasonablePolygon(List<Offset> verts, int expectedSides) {
    if (verts.length != expectedSides) return false;
    final expectedTurn = 2 * math.pi / expectedSides;
    final n = verts.length;

    // Check side lengths: balanced sides
    final sideLengths = <double>[];
    for (int i = 0; i < n; i++) {
      final len = (verts[(i + 1) % n] - verts[i]).distance;
      if (len < 4.0) return false;
      sideLengths.add(len);
    }
    final minSide = sideLengths.reduce(math.min);
    final maxSide = sideLengths.reduce(math.max);
    if (minSide / maxSide < 0.28) return false;

    int validTurns = 0;
    for (int i = 0; i < n; i++) {
      final prev = verts[(i - 1 + n) % n];
      final curr = verts[i];
      final next = verts[(i + 1) % n];

      final v1 = curr - prev;
      final v2 = next - curr;
      if (v1.distance < 4 || v2.distance < 4) continue;

      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
      final turnAngle = math.acos(dot.clamp(-1.0, 1.0));

      if ((turnAngle - expectedTurn).abs() < 0.65) {
        validTurns++;
      }
    }

    return validTurns >= expectedSides - 1;
  }

  static List<Offset> _simplifyClosedContour(
    List<Offset> offsets,
    Rect bounds,
  ) {
    if (offsets.length < 5) return List.from(offsets);

    final epsilon = math.max(3.5, (bounds.width + bounds.height) * 0.035);

    final first = offsets.first;
    int maxIdx = 0;
    double maxDist = 0.0;
    for (int i = 0; i < offsets.length; i++) {
      final d = (offsets[i] - first).distance;
      if (d > maxDist) {
        maxDist = d;
        maxIdx = i;
      }
    }

    if (maxIdx < 2 || maxIdx >= offsets.length - 2) {
      final simplified = _rdpSimplify(offsets, epsilon);
      return _cleanClosedVertices(simplified, bounds, epsilon);
    }

    final half1 = _rdpSimplify(offsets.sublist(0, maxIdx + 1), epsilon);
    final half2 = _rdpSimplify(offsets.sublist(maxIdx), epsilon);
    final combined = [...half1.sublist(0, half1.length - 1), ...half2];

    return _cleanClosedVertices(combined, bounds, epsilon);
  }

  static List<Offset> _cleanClosedVertices(
    List<Offset> verts,
    Rect bounds,
    double epsilon,
  ) {
    if (verts.length < 3) return verts;
    final clean = List<Offset>.from(verts);
    final closeTolerance = math.max(
      16.0,
      (bounds.width + bounds.height) * 0.12,
    );
    while (clean.length > 3 &&
        (clean.first - clean.last).distance < closeTolerance) {
      clean.removeLast();
    }
    final deduped = <Offset>[];
    for (final v in clean) {
      if (deduped.isEmpty || (v - deduped.last).distance > 4.0) {
        deduped.add(v);
      }
    }
    if (deduped.length > 3 && (deduped.first - deduped.last).distance < 4.0) {
      deduped.removeLast();
    }
    return deduped;
  }

  static List<Offset> _generateRegularPolygon(
    Rect bounds,
    int sides, {
    double startAngle = -math.pi / 2,
  }) {
    final center = bounds.center;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    final verts = <Offset>[];
    for (int i = 0; i < sides; i++) {
      final angle = startAngle + (i * 2 * math.pi / sides);
      verts.add(
        Offset(
          center.dx + rx * math.cos(angle),
          center.dy + ry * math.sin(angle),
        ),
      );
    }
    return verts;
  }

  static List<Offset> _regularizePolygon(
    List<Offset> verts,
    Rect bounds,
    int sides,
  ) {
    return _generateRegularPolygon(
      bounds,
      sides,
      startAngle: sides == 6 ? 0.0 : (sides == 8 ? -math.pi / 8 : -math.pi / 2),
    );
  }

  static bool _isOrthogonalRectangle(List<Offset> v4) {
    if (v4.length != 4) return false;
    for (int i = 0; i < 4; i++) {
      final pPrev = v4[(i - 1 + 4) % 4];
      final pCurr = v4[i];
      final pNext = v4[(i + 1) % 4];

      final v1 = pCurr - pPrev;
      final v2 = pNext - pCurr;
      if (v1.distance < 4 || v2.distance < 4) return false;

      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
      final turnAngle = math.acos(dot.clamp(-1.0, 1.0));

      // Rectangle corners must turn ~90 degrees (between 68° and 112° / 1.18 to 1.95 rad)
      if (turnAngle < 1.18 || turnAngle > 1.95) {
        return false;
      }
    }

    // Opposite edges must be roughly parallel
    final side0 = v4[1] - v4[0];
    final side2 = v4[3] - v4[2];
    if (side0.distance < 4 || side2.distance < 4) return false;
    final dotOpp =
        (side0.dx * side2.dx + side0.dy * side2.dy) /
        (side0.distance * side2.distance);
    if (dotOpp.abs() < 0.55) return false;

    return true;
  }

  static ShapeDetectionResult _buildRectangleResult(
    Stroke stroke,
    Rect bounds,
  ) {
    final fit = _fitOrientedRect(stroke.points.map((p) => p.offset).toList());
    var w = fit.w, h = fit.h, angle = fit.angle;

    // Nearly upright: make it exactly upright.
    if (angle.abs() < _uprightSnap) angle = 0;
    // Nearly square: make it exactly square.
    if ((w - h).abs() / math.max(w, h) < _squareSnap) {
      w = h = (w + h) / 2;
    }

    final List<Offset>? vertices;
    Rect box;
    if (angle == 0) {
      vertices = null;
      box = Rect.fromCenter(center: fit.center, width: w, height: h);
    } else {
      final c = math.cos(angle), sn = math.sin(angle);
      Offset corner(double x, double y) =>
          fit.center + Offset(x * c - y * sn, x * sn + y * c);
      vertices = [
        corner(-w / 2, -h / 2),
        corner(w / 2, -h / 2),
        corner(w / 2, h / 2),
        corner(-w / 2, h / 2),
      ];
      box = _boundsOf(vertices);
    }

    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.rectangle,
      start: box.topLeft,
      end: box.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
      customVertices: vertices,
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.rectangle,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.96,
    );
  }

  /// Tilt (radians) below which a rectangle is snapped upright.
  static const double _uprightSnap = 6 * math.pi / 180;

  /// Relative side difference below which a rectangle becomes a square.
  static const double _squareSnap = 0.12;

  static Rect _boundsOf(List<Offset> pts) {
    double minX = pts.first.dx, maxX = minX, minY = pts.first.dy, maxY = minY;
    for (final p in pts) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static Rect _inkBounds(List<StrokePoint> points) =>
      _boundsOf(points.map((p) => p.offset).toList());

  /// Minimum-area enclosing rectangle (searched over rotations).
  /// [angle] is the rotation of the rectangle's first side, in (-45°, 45°].
  @visibleForTesting
  static ({Offset center, double w, double h, double angle}) fitOrientedRect(
    List<Offset> pts,
  ) => _fitOrientedRect(pts);

  static ({Offset center, double w, double h, double angle}) _fitOrientedRect(
    List<Offset> pts,
  ) {
    final sample = pts.length > 120
        ? [for (int i = 0; i < 120; i++) pts[(i * pts.length) ~/ 120]]
        : pts;

    ({double area, double angle, Rect box}) measure(double a) {
      final c = math.cos(-a), s = math.sin(-a);
      double minX = double.infinity,
          maxX = -double.infinity,
          minY = double.infinity,
          maxY = -double.infinity;
      for (final p in sample) {
        final x = p.dx * c - p.dy * s, y = p.dx * s + p.dy * c;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
      final box = Rect.fromLTRB(minX, minY, maxX, maxY);
      return (area: box.width * box.height, angle: a, box: box);
    }

    var best = measure(0);
    for (int deg = 1; deg < 90; deg++) {
      final m = measure(deg * math.pi / 180);
      if (m.area < best.area) best = m;
    }
    // Refine to 0.1°.
    final coarse = best.angle;
    for (int t = -10; t <= 10; t++) {
      final m = measure(coarse + t * math.pi / 1800);
      if (m.area < best.area) best = m;
    }

    var angle = best.angle;
    var w = best.box.width, h = best.box.height;
    // Rotate the local box centre back to canvas coordinates.
    final lc = best.box.center;
    final c = math.cos(angle), s = math.sin(angle);
    final center = Offset(lc.dx * c - lc.dy * s, lc.dx * s + lc.dy * c);
    // Normalise to (-45°, 45°] by swapping sides.
    while (angle > math.pi / 4) {
      angle -= math.pi / 2;
      final t = w;
      w = h;
      h = t;
    }
    while (angle <= -math.pi / 4) {
      angle += math.pi / 2;
      final t = w;
      w = h;
      h = t;
    }
    return (center: center, w: w, h: h, angle: angle);
  }

  static bool _isValidTriangle(List<Offset> v3, Rect bounds) {
    if (v3.length != 3) return false;
    final p1 = v3[0];
    final p2 = v3[1];
    final p3 = v3[2];
    final area =
        ((p2.dx - p1.dx) * (p3.dy - p1.dy) - (p3.dx - p1.dx) * (p2.dy - p1.dy))
            .abs() /
        2;
    if (area < (bounds.width * bounds.height * 0.15)) return false;

    for (int i = 0; i < 3; i++) {
      final prev = v3[(i - 1 + 3) % 3];
      final curr = v3[i];
      final next = v3[(i + 1) % 3];
      final v1 = curr - prev;
      final v2 = next - curr;
      if (v1.distance < 4 || v2.distance < 4) return false;
      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
      final turnAngle = math.acos(dot.clamp(-1.0, 1.0));
      if (turnAngle < 0.55 || turnAngle > 2.55) return false;
    }
    return true;
  }

  static List<Offset> _regularizeTriangle(List<Offset> v3, Rect bounds) {
    if (v3.length != 3) return v3;

    // Check Right-angled Triangle first
    for (int i = 0; i < 3; i++) {
      final prev = v3[(i - 1 + 3) % 3];
      final curr = v3[i];
      final next = v3[(i + 1) % 3];
      final vA = prev - curr;
      final vB = next - curr;
      final dot = (vA.dx * vB.dx + vA.dy * vB.dy) / (vA.distance * vB.distance);
      final angle = math.acos(dot.clamp(-1.0, 1.0));

      // Right angle is ~90 degrees
      if ((angle - math.pi / 2).abs() < 0.28) {
        final corners = [
          bounds.topLeft,
          bounds.topRight,
          bounds.bottomRight,
          bounds.bottomLeft,
        ];
        corners.sort(
          (a, b) => (curr - a).distance.compareTo((curr - b).distance),
        );
        final corner = corners.first;
        final otherH = Offset(
          corner.dx == bounds.left ? bounds.right : bounds.left,
          corner.dy,
        );
        final otherV = Offset(
          corner.dx,
          corner.dy == bounds.top ? bounds.bottom : bounds.top,
        );
        return [corner, otherH, otherV];
      }
    }

    // Sort by Y: top to bottom
    final sortedByY = List<Offset>.from(v3)
      ..sort((a, b) => a.dy.compareTo(b.dy));
    final top = sortedByY[0];
    final mid = sortedByY[1];
    final bot = sortedByY[2];

    // Case 1: Upright triangle (apex near top-center, base near bottom horizontal)
    if (top.dy <= bounds.top + bounds.height * 0.25 &&
        (bot.dy - mid.dy).abs() <= bounds.height * 0.25 &&
        mid.dy >= bounds.bottom - bounds.height * 0.35) {
      return [
        Offset(bounds.center.dx, bounds.top),
        Offset(bounds.left, bounds.bottom),
        Offset(bounds.right, bounds.bottom),
      ];
    }

    // Case 2: Inverted triangle (apex near bottom-center, base near top horizontal)
    if (bot.dy >= bounds.bottom - bounds.height * 0.25 &&
        (mid.dy - top.dy).abs() <= bounds.height * 0.25 &&
        mid.dy <= bounds.top + bounds.height * 0.35) {
      return [
        Offset(bounds.center.dx, bounds.bottom),
        Offset(bounds.left, bounds.top),
        Offset(bounds.right, bounds.top),
      ];
    }

    // Case 3: Right-pointing triangle (apex near right-center, base near left vertical)
    final sortedByX = List<Offset>.from(v3)
      ..sort((a, b) => a.dx.compareTo(b.dx));
    final left1 = sortedByX[0];
    final left2 = sortedByX[1];
    final rightApex = sortedByX[2];
    if (rightApex.dx >= bounds.right - bounds.width * 0.25 &&
        (left2.dx - left1.dx).abs() <= bounds.width * 0.25 &&
        left2.dx <= bounds.left + bounds.width * 0.35) {
      return [
        Offset(bounds.right, bounds.center.dy),
        Offset(bounds.left, bounds.bottom),
        Offset(bounds.left, bounds.top),
      ];
    }

    // Case 4: Left-pointing triangle
    final right1 = sortedByX[1];
    final right2 = sortedByX[2];
    final leftApex = sortedByX[0];
    if (leftApex.dx <= bounds.left + bounds.width * 0.25 &&
        (right2.dx - right1.dx).abs() <= bounds.width * 0.25 &&
        right1.dx >= bounds.right - bounds.width * 0.35) {
      return [
        Offset(bounds.left, bounds.center.dy),
        Offset(bounds.right, bounds.top),
        Offset(bounds.right, bounds.bottom),
      ];
    }

    return v3;
  }

  static ShapeDetectionResult _buildTriangleResult(
    Stroke stroke,
    Rect bounds,
    List<Offset> regularizedVertices,
  ) {
    final shape = ShapeObject(
      id: uuid.v4(),
      shapeType: ShapeType.triangle,
      start: bounds.topLeft,
      end: bounds.bottomRight,
      strokeColorValue: stroke.colorValue,
      strokeWidth: stroke.width,
      customVertices: regularizedVertices,
    );

    return ShapeDetectionResult(
      shapeType: ShapeType.triangle,
      suggestedShape: shape,
      originalStroke: stroke,
      confidence: 0.95,
    );
  }

  // --- Circle / Ellipse Classifier ---
  static ShapeDetectionResult? _checkCircle(
    Stroke stroke,
    List<StrokePoint> points,
    Rect bounds,
  ) {
    final maxDim = math.max(bounds.width, bounds.height);
    if (maxDim < 25.0) return null;

    final aspectRatio = bounds.width / bounds.height;
    if (aspectRatio < 0.35 || aspectRatio > 2.80) return null;

    // A true circle or oval has smooth curvature and NO multiple sharp corners.
    final sharpCornerCount = _countSharpCorners(points, bounds);
    if (sharpCornerCount >= 2) return null;

    // Shallow-cornered polygons (octagon 45°, heptagon 51°) have no "sharp"
    // corners and are radially almost round; their straight sides give them
    // away.
    if (_looksPolygonal(points, _polygonStraightness)) return null;

    final center = bounds.center;
    final rx = bounds.width / 2;
    final ry = bounds.height / 2;
    if (rx < 4.0 || ry < 4.0) return null;

    // 1. Normalized Ellipse Radial Deviation
    double sumNormDist = 0.0;
    final normDistances = <double>[];
    for (final p in points) {
      final dx = (p.offset.dx - center.dx) / rx;
      final dy = (p.offset.dy - center.dy) / ry;
      final nd = math.sqrt(dx * dx + dy * dy);
      normDistances.add(nd);
      sumNormDist += nd;
    }
    final meanNormDist = sumNormDist / points.length;

    double normVariance = 0.0;
    for (final nd in normDistances) {
      normVariance += (nd - meanNormDist) * (nd - meanNormDist);
    }
    final normStdDev = math.sqrt(normVariance / points.length);
    final normCv = normStdDev / meanNormDist;

    // 2. Circular Radial Deviation (for roughly 1:1 circles)
    double sumDist = 0.0;
    final distances = <double>[];
    for (final p in points) {
      final dist = (p.offset - center).distance;
      distances.add(dist);
      sumDist += dist;
    }
    final meanDist = sumDist / points.length;

    double variance = 0.0;
    for (final d in distances) {
      variance += (d - meanDist) * (d - meanDist);
    }
    final stdDev = math.sqrt(variance / points.length);
    final circCv = stdDev / meanDist;

    // 3. Fill ratio (enclosed area / bounds area)
    final offsets = points.map((p) => p.offset).toList();
    final area = _calculatePolygonArea(offsets);
    final boundsArea = bounds.width * bounds.height;
    final fillRatio = boundsArea > 0 ? (area / boundsArea) : 0.0;

    // Circle or ellipse must have:
    // - Low normalized radial deviation (normCv < 0.22) or circular CV < 0.22
    // - Reasonable fill ratio (ellipse ideal is ~0.785, hand-drawn is 0.56 to 0.92)
    // - Centered distribution (meanNormDist between 0.80 and 1.25)
    final isGoodCircle =
        (normCv < 0.22 || circCv < 0.22) &&
        (fillRatio >= 0.56 && fillRatio <= 0.92) &&
        (meanNormDist >= 0.80 && meanNormDist <= 1.25);

    if (isGoodCircle) {
      // If width and height are within 18% of each other, regularize to a perfect geometric circle!
      Offset shapeStart = bounds.topLeft;
      Offset shapeEnd = bounds.bottomRight;

      final dimDiff = (bounds.width - bounds.height).abs();
      if (dimDiff / maxDim < 0.18) {
        final avgRadius = (bounds.width + bounds.height) / 4;
        shapeStart = Offset(center.dx - avgRadius, center.dy - avgRadius);
        shapeEnd = Offset(center.dx + avgRadius, center.dy + avgRadius);
      }

      final shape = ShapeObject(
        id: uuid.v4(),
        shapeType: ShapeType.circle,
        start: shapeStart,
        end: shapeEnd,
        strokeColorValue: stroke.colorValue,
        strokeWidth: stroke.width,
      );

      final confidenceScore = (1.0 - math.min(normCv, circCv) * 2.2).clamp(
        0.75,
        0.98,
      );

      return ShapeDetectionResult(
        shapeType: ShapeType.circle,
        suggestedShape: shape,
        originalStroke: stroke,
        confidence: confidenceScore,
      );
    }
    return null;
  }

  /// Fraction of the outline made of straight runs (0..1).
  ///
  /// The outline is resampled evenly, then for each short window we measure
  /// how much the pen direction turns. A circle turns steadily everywhere
  /// (every window turns ~15°), so almost no window is "straight". A polygon
  /// concentrates its turning at the corners, so the windows along its sides
  /// barely turn. This separates octagons/heptagons (45°/51° corners, too
  /// shallow for [_countSharpCorners]) from circles, which radial-deviation
  /// checks cannot: a regular octagon is within ~4% of a circle radially.
  @visibleForTesting
  static double straightRunFraction(List<StrokePoint> points) {
    final h = _headingProfile(
      points.map((p) => p.offset).toList(),
      closeLoop: false,
    );
    if (h == null) return 0.0;
    int straight = 0, total = 0;
    for (int i = 0; i + _turnWindow < h.length; i++) {
      total++;
      if ((h[i + _turnWindow] - h[i]).abs() < _straightTurnLimit) straight++;
    }
    return total == 0 ? 0.0 : straight / total;
  }

  static const int _profileSamples = 96;

  /// True when the outline has straight runs AND a polygon-like number of
  /// corners. Many small evenly spaced bumps (a wobbly circle) can produce
  /// short straight stretches but give a corner count above 8, so they are
  /// not treated as a polygon.
  static bool _looksPolygonal(
    List<StrokePoint> points,
    double minStraightness,
  ) {
    if (straightRunFraction(points) < minStraightness) return false;
    final sides = estimateSides(points);
    return sides == 0 || sides <= 8;
  }

  /// Densifies raw pen samples with a Catmull-Rom spline (through every
  /// sample) so that sparse samples of a curve stay curved. Joining sparse
  /// samples with straight lines would manufacture fake "straight sides" on
  /// a quickly drawn circle. Collinear samples along a real side stay straight.
  static List<StrokePoint> _splineDensify(
    List<Offset> p, {
    bool closed = false,
  }) {
    final n = p.length;
    Offset get(int i) => closed ? p[((i % n) + n) % n] : p[i.clamp(0, n - 1)];
    final out = <StrokePoint>[];
    final segs = closed ? n : n - 1;
    for (int i = 0; i < segs; i++) {
      final p0 = get(i - 1), p1 = get(i), p2 = get(i + 1), p3 = get(i + 2);
      final m = ((p2 - p1).distance / 2.0).ceil().clamp(1, 64);
      for (int j = 0; j < m; j++) {
        final t = j / m, t2 = t * t, t3 = t2 * t;
        final q =
            (p1 * 2 +
                (p2 - p0) * t +
                (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
                (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
            0.5;
        out.add(StrokePoint(x: q.dx, y: q.dy, timestamp: 0));
      }
    }
    final last = closed ? p.first : p.last;
    out.add(StrokePoint(x: last.dx, y: last.dy, timestamp: 0));
    return out;
  }

  static const int _turnWindow = 4; // ≈ 1/24 of the outline
  // A circle turns 2π·w/samples per window; "straight" means much less.
  static const double _straightTurnLimit =
      2 * math.pi * _turnWindow / _profileSamples * 0.35;

  /// Unwrapped pen direction along an evenly resampled, lightly smoothed
  /// outline. With [closeLoop] the outline is closed across the pen-lift
  /// gap so the corner where the stroke starts/ends is also seen.
  static List<double>? _headingProfile(
    List<Offset> outline, {
    required bool closeLoop,
  }) {
    if (outline.length < 12) return null;
    final raw = _resamplePoints(
      _splineDensify(outline, closed: closeLoop),
      _profileSamples,
    );
    if (raw.length < 24) return null;
    // Light moving-average smoothing removes pen jitter (which otherwise makes
    // small, wobbly circles look locally straight or kinked) while keeping
    // corners, which span many samples, intact.
    final pts = <Offset>[
      for (int i = 0; i < raw.length; i++)
        () {
          final a = math.max(0, i - 1), b = math.min(raw.length - 1, i + 1);
          var sum = Offset.zero;
          for (int j = a; j <= b; j++) {
            sum += raw[j];
          }
          return sum / (b - a + 1).toDouble();
        }(),
    ];
    // Direction over a short chord (k samples) to suppress residual jitter.
    const k = 3;
    final headings = <double>[];
    double prev = 0;
    for (int i = 0; i + k < pts.length; i++) {
      final d = pts[i + k] - pts[i];
      if (d.distance < 1e-6) {
        headings.add(headings.isEmpty ? 0 : headings.last);
        continue;
      }
      var h = math.atan2(d.dy, d.dx);
      if (headings.isNotEmpty) {
        while (h - prev > math.pi) {
          h -= 2 * math.pi;
        }
        while (h - prev < -math.pi) {
          h += 2 * math.pi;
        }
      }
      headings.add(h);
      prev = h;
    }
    return headings;
  }

  /// The single closed loop traced by a closing stroke. When the pen runs
  /// past where it started (overshoot, or a rounded final corner that
  /// overlaps the first side), the loop is cut where the stroke's end passes
  /// closest to its own beginning, so the overlap isn't traversed twice and
  /// doesn't add a fake corner. With a gap, this is simply start to end.
  static List<Offset> _trimClosingOverlap(List<Offset> pts) {
    if (pts.length < 12) return pts;
    final n = pts.length;
    final head = (n * 0.25).floor();
    final tailStart = n - head - 1;
    int bi = 0, bj = n - 1;
    double best = (pts.first - pts.last).distance;
    for (int i = 0; i <= head; i++) {
      for (int j = tailStart; j < n; j++) {
        final d = (pts[i] - pts[j]).distance;
        if (d < best) {
          best = d;
          bi = i;
          bj = j;
        }
      }
    }
    if (bj - bi < n * 0.5) return pts; // not a loop
    return pts.sublist(bi, bj + 1);
  }

  /// Counts polygon sides as clusters of turning separated by straight runs.
  /// More robust than counting simplified vertices, where one rounded corner
  /// can split into two. The outline is treated as a closed loop (bridging
  /// the pen-lift gap) with wrap-around indexing, so the corner where the
  /// stroke starts and ends counts like any other. Returns 0 when the outline
  /// is not a clean convex polygon (total turning far from 360°, or very
  /// unequal corners).
  @visibleForTesting
  static int estimateSides(List<StrokePoint> points) {
    if (points.length < 12) return 0;
    final raw = _resamplePoints(
      _splineDensify(
        _trimClosingOverlap(points.map((p) => p.offset).toList()),
        closed: true,
      ),
      _profileSamples + 1,
    );
    if (raw.length < 24) return 0;
    raw.removeLast(); // last == first: circular from here on
    final n = raw.length;
    Offset at(int i) => raw[((i % n) + n) % n];
    final pts = [
      for (int i = 0; i < n; i++) (at(i - 1) + at(i) + at(i + 1)) / 3.0,
    ];
    Offset sp(int i) => pts[((i % n) + n) % n];

    const k = 3;
    final heading = [
      for (int i = 0; i < n; i++)
        () {
          final d = sp(i + k) - sp(i);
          return math.atan2(d.dy, d.dx);
        }(),
    ];
    double turnBetween(int a, int b) {
      var d = heading[((b % n) + n) % n] - heading[((a % n) + n) % n];
      while (d > math.pi) {
        d -= 2 * math.pi;
      }
      while (d <= -math.pi) {
        d += 2 * math.pi;
      }
      return d;
    }

    double total = 0;
    for (int i = 0; i < n; i++) {
      total += turnBetween(i, i + 1);
    }
    if ((total.abs() - 2 * math.pi).abs() > 2 * math.pi * 0.3) return 0;
    final dir = total.sign;

    const half = _turnWindow ~/ 2;
    final turning = [
      for (int i = 0; i < n; i++)
        turnBetween(i - half, i + half) * dir >= _straightTurnLimit,
    ];
    if (turning.every((t) => t)) return 0; // no straight runs at all: a curve

    // A corner can be split in two by a one-sample "straight" blip
    // (pen jitter at the corner). Close such tiny gaps between turning runs.
    for (int i = 0; i < n; i++) {
      if (turning[i] || !turning[(i - 1 + n) % n]) continue;
      int len = 0;
      while (len < 2 && !turning[(i + len) % n]) {
        len++;
      }
      if (len <= 1 && turning[(i + len) % n]) {
        for (int j = 0; j < len; j++) {
          turning[(i + j) % n] = true;
        }
      }
    }
    if (turning.every((t) => t)) return 0;

    // Start scanning just after a straight sample so no cluster wraps.
    final s0 = turning.indexOf(false);
    final clusterTurns = <double>[];
    int i = 0;
    while (i < n) {
      if (!turning[(s0 + i) % n]) {
        i++;
        continue;
      }
      final a = s0 + i;
      while (i < n && turning[(s0 + i) % n]) {
        i++;
      }
      final b = s0 + i;
      clusterTurns.add((turnBetween(a - 1, b) * dir).clamp(0.0, math.pi));
    }
    // Ignore wobble: a real corner turns at least ~18°.
    final corners = clusterTurns.where((t) => t >= 0.31).toList();
    if (corners.length < 3) return 0;
    final mean = corners.reduce((a, b) => a + b) / corners.length;
    final maxDev = corners.map((t) => (t - mean).abs()).reduce(math.max);
    if (maxDev > mean * 0.75) return 0;
    return corners.length;
  }

  static int _countSharpCorners(List<StrokePoint> points, Rect bounds) {
    if (points.length < 3) return 0;

    // For sparse strokes (<= 12 points, e.g. tests or fast corner sketches)
    if (points.length <= 12) {
      final clean = points.map((p) => p.offset).toList();
      final closeTolerance = math.max(
        16.0,
        (bounds.width + bounds.height) * 0.12,
      );
      if (clean.length > 3 &&
          (clean.first - clean.last).distance < closeTolerance) {
        clean.removeLast();
      }
      if (clean.length < 3) return 0;
      int count = 0;
      final n = clean.length;
      for (int i = 0; i < n; i++) {
        final prev = clean[(i - 1 + n) % n];
        final curr = clean[i];
        final next = clean[(i + 1) % n];
        final vIn = curr - prev;
        final vOut = next - curr;
        if (vIn.distance < 4 || vOut.distance < 4) continue;
        final dot =
            (vIn.dx * vOut.dx + vIn.dy * vOut.dy) /
            (vIn.distance * vOut.distance);
        final turn = math.acos(dot.clamp(-1.0, 1.0));
        if (turn >= 0.60 && turn <= 2.65) count++;
      }
      return count;
    }

    // For dense hand-drawn strokes (> 12 points):
    // Measure curvature using a step window to filter jitter without introducing RDP chords
    final step = math.max(3, (points.length / 12).round());
    int sharpCorners = 0;
    int lastCornerIdx = -step;
    final n = points.length;

    for (int i = 0; i < n; i++) {
      final prev = points[(i - step + n) % n].offset;
      final curr = points[i].offset;
      final next = points[(i + step) % n].offset;

      final vIn = curr - prev;
      final vOut = next - curr;
      if (vIn.distance < 4 || vOut.distance < 4) continue;

      final dot =
          (vIn.dx * vOut.dx + vIn.dy * vOut.dy) /
          (vIn.distance * vOut.distance);
      final turnAngle = math.acos(dot.clamp(-1.0, 1.0));

      // Turn angles between 53° and 150° (0.92 to 2.65 rad)
      // Supports Hexagon (60°), Pentagon (72°), Square/Rectangle (90°), Triangle (120°)
      // Notice: Smooth circle turning angles are <= 44° (0.76 rad), preventing circle from registering fake sharp corners!
      if (turnAngle >= 0.92 && turnAngle <= 2.65) {
        if (i - lastCornerIdx >= step) {
          sharpCorners++;
          lastCornerIdx = i;
        }
      }
    }
    return sharpCorners;
  }

  // --- Star Classifier (Perimeter and Crossed 5-Pointed Stars) ---
  static ShapeDetectionResult? _checkStar(
    Stroke stroke,
    List<StrokePoint> points,
    Rect bounds,
  ) {
    final center = bounds.center;
    final maxRadius = math.max(bounds.width, bounds.height) / 2;
    if (maxRadius < 20.0) return null;

    // A star must be non-convex: fill ratio must be <= 0.58
    final area = _calculatePolygonArea(points.map((p) => p.offset).toList());
    final boundsArea = bounds.width * bounds.height;
    if (boundsArea > 0 && (area / boundsArea) > 0.58) {
      return null;
    }

    // 1. Perimeter Star (5 outer peaks with deep inner valleys)
    final perimeterResult = _checkPerimeterStar(
      stroke,
      points,
      bounds,
      center,
      maxRadius,
    );
    if (perimeterResult != null) return perimeterResult;

    // 2. Crossed 5-point Star (Pentagram drawn with criss-crossing strokes)
    final crossedResult = _checkCrossedStar(
      stroke,
      points,
      bounds,
      center,
      maxRadius,
    );
    if (crossedResult != null) return crossedResult;

    return null;
  }

  static ShapeDetectionResult? _checkPerimeterStar(
    Stroke stroke,
    List<StrokePoint> points,
    Rect bounds,
    Offset center,
    double maxRadius,
  ) {
    final sampledOffsets = _resamplePoints(points, 80);
    if (sampledOffsets.length < 30) return null;

    final radii = sampledOffsets.map((p) => (p - center).distance).toList();

    // Smooth radii to remove small hand tremors
    final smoothedRadii = <double>[];
    for (int i = 0; i < radii.length; i++) {
      final prev = radii[(i - 1 + radii.length) % radii.length];
      final curr = radii[i];
      final next = radii[(i + 1) % radii.length];
      smoothedRadii.add((prev + curr * 2 + next) / 4);
    }

    final peakIndices = <int>[];
    final valleyIndices = <int>[];
    final minPeakRadius = maxRadius * 0.50;

    for (int i = 0; i < smoothedRadii.length; i++) {
      final prev =
          smoothedRadii[(i - 1 + smoothedRadii.length) % smoothedRadii.length];
      final curr = smoothedRadii[i];
      final next = smoothedRadii[(i + 1) % smoothedRadii.length];

      if (curr >= prev && curr > next && curr >= minPeakRadius) {
        if (peakIndices.isEmpty || (i - peakIndices.last).abs() > 5) {
          peakIndices.add(i);
        }
      }

      if (curr <= prev && curr < next) {
        if (valleyIndices.isEmpty || (i - valleyIndices.last).abs() > 5) {
          valleyIndices.add(i);
        }
      }
    }

    // A star must have 5 outer peaks (or 6 for hexagram)
    if (peakIndices.length == 5 || peakIndices.length == 6) {
      double avgPeak = 0;
      for (final idx in peakIndices) {
        avgPeak += smoothedRadii[idx];
      }
      avgPeak /= peakIndices.length;

      if (valleyIndices.length >= 4) {
        double avgValley = 0;
        for (final idx in valleyIndices) {
          avgValley += smoothedRadii[idx];
        }
        avgValley /= valleyIndices.length;

        final indentation = (avgPeak - avgValley) / avgPeak;
        // In a true star, inner valleys indent by at least 32% (avgValley <= avgPeak * 0.65)
        if (indentation >= 0.32 && avgValley <= avgPeak * 0.65) {
          // Check for true reflex angles at the inner valleys:
          int reflexCount = 0;
          final n = sampledOffsets.length;
          for (final vIdx in valleyIndices) {
            final pPrev = sampledOffsets[(vIdx - 3 + n) % n];
            final pCurr = sampledOffsets[vIdx];
            final pNext = sampledOffsets[(vIdx + 3 + n) % n];
            final v1 = pCurr - pPrev;
            final v2 = pNext - pCurr;
            // Cross product of path tangents
            final cross = v1.dx * v2.dy - v1.dy * v2.dx;
            // Vector from center to valley point
            final toCenter = center - pCurr;
            final norm = Offset(-v2.dy, v2.dx);
            if (norm.dx * toCenter.dx + norm.dy * toCenter.dy > 0 ||
                cross.abs() > 5.0) {
              reflexCount++;
            }
          }

          if (reflexCount >= 3) {
            final starShape = ShapeObject(
              id: uuid.v4(),
              shapeType: ShapeType.star,
              start: bounds.topLeft,
              end: bounds.bottomRight,
              strokeColorValue: stroke.colorValue,
              strokeWidth: stroke.width,
              isFilled: false,
            );

            return ShapeDetectionResult(
              shapeType: ShapeType.star,
              suggestedShape: starShape,
              originalStroke: stroke,
              confidence: 0.95,
            );
          }
        }
      }
    }
    return null;
  }

  static ShapeDetectionResult? _checkCrossedStar(
    Stroke stroke,
    List<StrokePoint> points,
    Rect bounds,
    Offset center,
    double maxRadius,
  ) {
    if (points.length < 15) return null;
    final totalLen = _calculatePathLength(points);
    // Crossed star has 5 long chords across the shape: totalLen must be at least 3.2 * longestSide
    if (totalLen < bounds.longestSide * 3.2) return null;

    // Check for criss-crossing lines (self-intersections)
    final intersections = _countSelfIntersections(
      points.map((p) => p.offset).toList(),
      bounds,
    );
    // A crossed 5-point star MUST have at least 3 self-intersections in the interior
    if (intersections < 3) return null;

    final sampled = _resamplePoints(points, 90);
    final radii = sampled.map((p) => (p - center).distance).toList();

    final outerTips = <Offset>[];
    final tipAngles = <double>[];
    final minTipRadius = maxRadius * 0.65;

    for (int i = 0; i < radii.length; i++) {
      final prev = radii[(i - 1 + radii.length) % radii.length];
      final curr = radii[i];
      final next = radii[(i + 1) % radii.length];

      if (curr >= prev && curr > next && curr >= minTipRadius) {
        final p = sampled[i];
        final angle = math.atan2(p.dy - center.dy, p.dx - center.dx);
        bool isDuplicate = false;
        for (final a in tipAngles) {
          final diff = (angle - a).abs();
          final normDiff = diff > math.pi ? 2 * math.pi - diff : diff;
          if (normDiff < 0.45) {
            isDuplicate = true;
            break;
          }
        }
        if (!isDuplicate) {
          outerTips.add(p);
          tipAngles.add(angle);
        }
      }
    }

    if (outerTips.length == 5 || outerTips.length == 6) {
      final starShape = ShapeObject(
        id: uuid.v4(),
        shapeType: ShapeType.star,
        start: bounds.topLeft,
        end: bounds.bottomRight,
        strokeColorValue: stroke.colorValue,
        strokeWidth: stroke.width,
        isFilled: false,
      );

      return ShapeDetectionResult(
        shapeType: ShapeType.star,
        suggestedShape: starShape,
        originalStroke: stroke,
        confidence: 0.95,
      );
    }
    return null;
  }

  static int _countSelfIntersections(List<Offset> points, Rect bounds) {
    final simplified = _rdpSimplify(points, bounds.longestSide * 0.05);
    if (simplified.length < 5) return 0;

    int crossings = 0;
    final n = simplified.length - 1;
    for (int i = 0; i < n; i++) {
      final a1 = simplified[i];
      final a2 = simplified[i + 1];
      for (int j = i + 2; j < n; j++) {
        if (i == 0 && j == n - 1) continue; // Skip closure edge
        final b1 = simplified[j];
        final b2 = simplified[j + 1];
        if (_segmentsIntersect(a1, a2, b1, b2)) {
          crossings++;
        }
      }
    }
    return crossings;
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    double ccw(Offset p1, Offset p2, Offset p3) {
      return (p3.dy - p1.dy) * (p2.dx - p1.dx) -
          (p2.dy - p1.dy) * (p3.dx - p1.dx);
    }

    final d1 = ccw(c, d, a);
    final d2 = ccw(c, d, b);
    final d3 = ccw(a, b, c);
    final d4 = ccw(a, b, d);

    if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
      return true;
    }
    return false;
  }

  // --- Multi-Stroke Helpers ---
  static ShapeDetectionResult? _checkThreeStrokeTriangle(
    Stroke s1,
    Stroke s2,
    Stroke s3,
  ) {
    final strokes = [s1, s2, s3];
    for (final s in strokes) {
      final chord = (s.points.last.offset - s.points.first.offset).distance;
      if (chord < 20.0) return null;
      if (chord / _calculatePathLength(s.points) < 0.78) return null;
    }

    final pts1 = [s1.points.first.offset, s1.points.last.offset];
    final pts2 = [s2.points.first.offset, s2.points.last.offset];
    final pts3 = [s3.points.first.offset, s3.points.last.offset];

    const threshold = 45.0;
    final c1 = _findConnection(pts1, pts2, threshold);
    final c2 = _findConnection(pts2, pts3, threshold);
    final c3 = _findConnection(pts3, pts1, threshold);

    if (c1 != null && c2 != null && c3 != null) {
      final area =
          ((c2.dx - c1.dx) * (c3.dy - c1.dy) -
                  (c3.dx - c1.dx) * (c2.dy - c1.dy))
              .abs() /
          2;
      final rect = s1.bounds
          .expandToInclude(s2.bounds)
          .expandToInclude(s3.bounds);
      if (area < rect.width * rect.height * 0.18) return null;

      final regularized = _regularizeTriangle([c1, c2, c3], rect);

      final shape = ShapeObject(
        id: uuid.v4(),
        shapeType: ShapeType.triangle,
        start: rect.topLeft,
        end: rect.bottomRight,
        strokeColorValue: s3.colorValue,
        strokeWidth: s3.width,
        customVertices: regularized,
      );

      return ShapeDetectionResult(
        shapeType: ShapeType.triangle,
        suggestedShape: shape,
        originalStroke: s3,
        originalStrokes: [s1, s2, s3],
        confidence: 0.94,
      );
    }
    return null;
  }

  static ShapeDetectionResult? _checkFourStrokeRectangle(
    Stroke s1,
    Stroke s2,
    Stroke s3,
    Stroke s4,
  ) {
    final strokes = [s1, s2, s3, s4];
    for (final s in strokes) {
      final chord = (s.points.last.offset - s.points.first.offset).distance;
      if (chord < 15.0) return null;
      if (chord / _calculatePathLength(s.points) < 0.80) return null;
    }

    final angles = <double>[];
    for (final s in strokes) {
      final delta = s.points.last.offset - s.points.first.offset;
      var a = math.atan2(delta.dy, delta.dx);
      if (a < 0) a += math.pi;
      angles.add(a);
    }

    final baseAngle = angles[0];
    final groupA = <int>[0];
    final groupB = <int>[];

    for (int i = 1; i < 4; i++) {
      final diff = (angles[i] - baseAngle).abs();
      final normDiff = diff > math.pi / 2 ? math.pi - diff : diff;
      if (normDiff < 0.40) {
        groupA.add(i);
      } else {
        groupB.add(i);
      }
    }

    if (groupA.length != 2 || groupB.length != 2) return null;

    final diffAB = (angles[groupA[0]] - angles[groupB[0]]).abs();
    final normAB = diffAB > math.pi / 2 ? math.pi - diffAB : diffAB;
    if (normAB < (math.pi / 2 - 0.55) || normAB > (math.pi / 2 + 0.55)) {
      return null;
    }

    final rect = s1.bounds
        .expandToInclude(s2.bounds)
        .expandToInclude(s3.bounds)
        .expandToInclude(s4.bounds);
    if (rect.width < 35.0 || rect.height < 35.0) return null;

    final center = rect.center;
    for (final s in strokes) {
      for (final p in s.points) {
        if ((p.offset - center).distance <
            math.min(rect.width, rect.height) * 0.20) {
          return null; // Crosses center! Math cross, not rectangle boundary
        }
      }
    }

    const threshold = 45.0;
    final pts1 = [s1.points.first.offset, s1.points.last.offset];
    final pts2 = [s2.points.first.offset, s2.points.last.offset];
    final pts3 = [s3.points.first.offset, s3.points.last.offset];
    final pts4 = [s4.points.first.offset, s4.points.last.offset];

    final c1 = _findConnection(pts1, pts2, threshold);
    final c2 = _findConnection(pts2, pts3, threshold);
    final c3 = _findConnection(pts3, pts4, threshold);
    final c4 = _findConnection(pts4, pts1, threshold);

    if (c1 != null && c2 != null && c3 != null && c4 != null) {
      final shape = ShapeObject(
        id: uuid.v4(),
        shapeType: ShapeType.rectangle,
        start: rect.topLeft,
        end: rect.bottomRight,
        strokeColorValue: s4.colorValue,
        strokeWidth: s4.width,
      );

      return ShapeDetectionResult(
        shapeType: ShapeType.rectangle,
        suggestedShape: shape,
        originalStroke: s4,
        originalStrokes: [s1, s2, s3, s4],
        confidence: 0.92,
      );
    }
    return null;
  }

  static Offset? _findConnection(
    List<Offset> lineA,
    List<Offset> lineB,
    double threshold,
  ) {
    for (final a in lineA) {
      for (final b in lineB) {
        if ((a - b).distance <= threshold) {
          return Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
        }
      }
    }
    return null;
  }

  // --- Ramer-Douglas-Peucker Algorithm ---
  static List<Offset> _rdpSimplify(List<Offset> pts, double epsilon) {
    if (pts.length < 3) return List.from(pts);

    int maxIndex = 0;
    double maxDistance = 0.0;

    for (int i = 1; i < pts.length - 1; i++) {
      final dist = _perpendicularDistance(pts[i], pts.first, pts.last);
      if (dist > maxDistance) {
        maxDistance = dist;
        maxIndex = i;
      }
    }

    if (maxDistance > epsilon) {
      final left = _rdpSimplify(pts.sublist(0, maxIndex + 1), epsilon);
      final right = _rdpSimplify(pts.sublist(maxIndex), epsilon);
      return [...left.sublist(0, left.length - 1), ...right];
    } else {
      return [pts.first, pts.last];
    }
  }

  static double _perpendicularDistance(Offset p, Offset lineA, Offset lineB) {
    final dx = lineB.dx - lineA.dx;
    final dy = lineB.dy - lineA.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len == 0) return (p - lineA).distance;
    return ((dy * p.dx -
                dx * p.dy +
                lineB.dx * lineA.dy -
                lineB.dy * lineA.dx) /
            len)
        .abs();
  }

  static List<Offset> _mergeCollinearVertices(List<Offset> vertices) {
    if (vertices.length <= 3) return List.from(vertices);

    final result = <Offset>[];
    final n = vertices.length;
    for (int i = 0; i < n; i++) {
      final prev = vertices[(i - 1 + n) % n];
      final curr = vertices[i];
      final next = vertices[(i + 1) % n];

      final v1 = curr - prev;
      final v2 = next - curr;
      if (v1.distance < 4.0 || v2.distance < 4.0) continue;

      final dot = (v1.dx * v2.dx + v1.dy * v2.dy) / (v1.distance * v2.distance);
      final turnAngle = math.acos(dot.clamp(-1.0, 1.0));

      if (turnAngle >= 0.45) {
        result.add(curr);
      }
    }
    return result.length >= 3 ? result : List.from(vertices);
  }

  static List<Offset> _resamplePoints(
    List<StrokePoint> points,
    int targetCount,
  ) {
    if (points.isEmpty) return [];
    if (points.length == 1) return [points.first.offset];

    final totalLen = _calculatePathLength(points);
    if (totalLen <= 0) return points.map((p) => p.offset).toList();

    final step = totalLen / (targetCount - 1);
    final res = <Offset>[points.first.offset];

    double currentDist = 0.0;
    int segIdx = 0;
    double segCovered = 0.0;

    for (int i = 1; i < targetCount - 1; i++) {
      final targetDist = i * step;
      while (segIdx < points.length - 1) {
        final pA = points[segIdx].offset;
        final pB = points[segIdx + 1].offset;
        final segLen = (pB - pA).distance;

        if (currentDist + (segLen - segCovered) >= targetDist) {
          final needed = targetDist - currentDist;
          final t = (segCovered + needed) / (segLen > 0 ? segLen : 1.0);
          res.add(
            Offset(pA.dx + (pB.dx - pA.dx) * t, pA.dy + (pB.dy - pA.dy) * t),
          );
          segCovered += needed;
          currentDist = targetDist;
          break;
        } else {
          currentDist += (segLen - segCovered);
          segCovered = 0.0;
          segIdx++;
        }
      }
    }
    res.add(points.last.offset);
    return res;
  }
}
