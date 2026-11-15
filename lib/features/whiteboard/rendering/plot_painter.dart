import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/plot_model.dart';
import '../recognition/math_function_parser.dart';

class PlotPainter extends CustomPainter {
  final PlotObject plot;
  final MathFunction? compiledFunction;
  final bool isDark;

  const PlotPainter({
    required this.plot,
    required this.compiledFunction,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final xSpan = plot.xMax - plot.xMin;
    final ySpan = plot.yMax - plot.yMin;
    if (xSpan <= 0 || ySpan <= 0) return;

    // Coordinate mapping functions
    double toScreenX(double mathX) =>
        ((mathX - plot.xMin) / xSpan) * size.width;

    double toScreenY(double mathY) =>
        size.height - ((mathY - plot.yMin) / ySpan) * size.height;

    // 1. Draw Cartesian Grid Lines & Numbers
    if (plot.showGrid) {
      _drawGrid(canvas, size, toScreenX, toScreenY);
    }

    // 2. Draw Central X and Y Axes with Arrows
    _drawAxes(canvas, size, toScreenX, toScreenY);

    // 3. Draw Function Curves
    if (compiledFunction != null) {
      _drawCurve(canvas, size, toScreenX, toScreenY);

      // 4. Draw Highlighted Key Points (Roots, Intercepts, Vertex)
      if (plot.showKeyPoints) {
        _drawKeyPoints(canvas, size, toScreenX, toScreenY);
      }
    }
  }

  void _drawGrid(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final xSpan = plot.xMax - plot.xMin;
    final step = _calculateGridStep(xSpan);

    final gridPaint = Paint()
      ..color = isDark ? const Color(0x1FFFFFFF) : const Color(0x1F000000)
      ..strokeWidth = 1.0;

    final textStyle = TextStyle(
      color: isDark ? const Color(0xB3FFFFFF) : const Color(0xFF475569),
      fontSize: 9.5,
      fontWeight: FontWeight.w600,
    );

    // Vertical grid lines (X ticks)
    final firstX = (plot.xMin / step).floor() * step;
    for (double x = firstX; x <= plot.xMax + step * 0.1; x += step) {
      if ((x - 0.0).abs() < 1e-6) continue; // Skip x=0 (axis handles it)
      final sx = toScreenX(x);
      if (sx < 0 || sx > size.width) continue;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: _formatTickNum(x), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final originY = toScreenY(0.0).clamp(16.0, size.height - 20.0);
      tp.paint(canvas, Offset(sx - tp.width / 2, originY + 4));
    }

    // Horizontal grid lines (Y ticks)
    final firstY = (plot.yMin / step).floor() * step;
    for (double y = firstY; y <= plot.yMax + step * 0.1; y += step) {
      if ((y - 0.0).abs() < 1e-6) continue;
      final sy = toScreenY(y);
      if (sy < 0 || sy > size.height) continue;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), gridPaint);

      final tp = TextPainter(
        text: TextSpan(text: _formatTickNum(y), style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();

      final originX = toScreenX(0.0).clamp(24.0, size.width - tp.width - 6);
      tp.paint(canvas, Offset(originX - tp.width - 4, sy - tp.height / 2));
    }
  }

  void _drawAxes(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final axisPaint = Paint()
      ..color = isDark ? const Color(0xCCFFFFFF) : const Color(0xFF334155)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;

    final originX = toScreenX(0.0);
    final originY = toScreenY(0.0);

    // X Axis (Horizontal)
    if (originY >= 0 && originY <= size.height) {
      canvas.drawLine(
        Offset(0, originY),
        Offset(size.width, originY),
        axisPaint,
      );

      // Arrow on X+ end
      final path = Path()
        ..moveTo(size.width - 7, originY - 4)
        ..lineTo(size.width, originY)
        ..lineTo(size.width - 7, originY + 4);
      canvas.drawPath(path, axisPaint);

      // "x" axis label
      final tp = TextPainter(
        text: TextSpan(
          text: 'x',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(size.width - 12, originY - 16));
    }

    // Y Axis (Vertical)
    if (originX >= 0 && originX <= size.width) {
      canvas.drawLine(
        Offset(originX, 0),
        Offset(originX, size.height),
        axisPaint,
      );

      // Arrow on Y+ end
      final path = Path()
        ..moveTo(originX - 4, 7)
        ..lineTo(originX, 0)
        ..lineTo(originX + 4, 7);
      canvas.drawPath(path, axisPaint);

      // "y" axis label
      final tp = TextPainter(
        text: TextSpan(
          text: 'y',
          style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF0F172A),
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(originX + 6, 2));
    }

    // Origin (0,0) label
    if (originX >= 0 &&
        originX <= size.width &&
        originY >= 0 &&
        originY <= size.height) {
      final tp = TextPainter(
        text: TextSpan(
          text: '0',
          style: TextStyle(
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
            fontSize: 9.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(originX + 4, originY + 3));
    }
  }

  void _drawCurve(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final fn = compiledFunction!;
    final curveColor = isDark ? const Color(0xFF38BDF8) : plot.curveColor;

    // Glowing underlay for beautiful rich modern visual finish
    final glowPaint = Paint()
      ..color = curveColor.withValues(alpha: isDark ? 0.35 : 0.18)
      ..strokeWidth = 5.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final curvePaint = Paint()
      ..color = curveColor
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final xSpan = plot.xMax - plot.xMin;
    final pixelWidth = size.width.toInt();
    if (pixelWidth <= 0) return;

    // Draw main branch (glow + solid)
    _sampleAndDrawBranch(
      canvas,
      size,
      fn.evaluate,
      glowPaint,
      pixelWidth,
      xSpan,
      toScreenX,
      toScreenY,
    );
    _sampleAndDrawBranch(
      canvas,
      size,
      fn.evaluate,
      curvePaint,
      pixelWidth,
      xSpan,
      toScreenX,
      toScreenY,
    );

    // Draw negative branch (e.g. bottom half of circles)
    if (fn.evaluateNegativeBranch != null) {
      _sampleAndDrawBranch(
        canvas,
        size,
        fn.evaluateNegativeBranch!,
        glowPaint,
        pixelWidth,
        xSpan,
        toScreenX,
        toScreenY,
      );
      _sampleAndDrawBranch(
        canvas,
        size,
        fn.evaluateNegativeBranch!,
        curvePaint,
        pixelWidth,
        xSpan,
        toScreenX,
        toScreenY,
      );
    }
  }

  void _sampleAndDrawBranch(
    Canvas canvas,
    Size size,
    double Function(double) evaluate,
    Paint paint,
    int pixelWidth,
    double xSpan,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final path = Path();
    bool isDrawing = false;
    double? lastSy;

    // High resolution sampling (one sample per pixel for silky smoothness)
    final totalSamples = math.min(600, pixelWidth * 2);
    for (int i = 0; i <= totalSamples; i++) {
      final t = i / totalSamples;
      final mathX = plot.xMin + t * xSpan;
      double mathY;
      try {
        mathY = evaluate(mathX);
      } catch (_) {
        isDrawing = false;
        lastSy = null;
        continue;
      }

      if (mathY.isNaN || mathY.isInfinite) {
        isDrawing = false;
        lastSy = null;
        continue;
      }

      final sx = toScreenX(mathX);
      final sy = toScreenY(mathY);

      // Handle vertical asymptotes / discontinuities (e.g. 1/x or tan(x))
      if (lastSy != null && (sy - lastSy).abs() > size.height * 0.75) {
        isDrawing = false;
      }

      if (!isDrawing) {
        path.moveTo(sx, sy);
        isDrawing = true;
      } else {
        path.lineTo(sx, sy);
      }

      lastSy = sy;
    }

    canvas.drawPath(path, paint);
  }

  void _drawKeyPoints(
    Canvas canvas,
    Size size,
    double Function(double) toScreenX,
    double Function(double) toScreenY,
  ) {
    final keyPoints = compiledFunction!.findKeyPoints(plot.xMin, plot.xMax);
    if (keyPoints.isEmpty) return;

    // Filter to visible key points within bounds
    final visible = <KeyPoint>[];
    for (final kp in keyPoints) {
      final sx = toScreenX(kp.x);
      final sy = toScreenY(kp.y);
      if (sx >= -15 &&
          sx <= size.width + 15 &&
          sy >= -15 &&
          sy <= size.height + 15) {
        visible.add(kp);
      }
    }
    if (visible.isEmpty) return;

    // Sort by X coordinate for collision prevention
    visible.sort((a, b) => a.x.compareTo(b.x));

    for (int i = 0; i < visible.length; i++) {
      final kp = visible[i];
      final sx = toScreenX(kp.x);
      final sy = toScreenY(kp.y);

      final Color ptColor;
      if (kp.pointType == 'root') {
        ptColor = const Color(0xFF059669); // Emerald Green for Roots
      } else if (kp.pointType == 'vertex' || kp.pointType == 'extrema') {
        ptColor = const Color(0xFFD97706); // Amber for Vertex / Extrema
      } else {
        ptColor = const Color(0xFF7C3AED); // Purple for Y-Intercept
      }

      // 1. Soft glow around key point
      final glowPaint = Paint()
        ..color = ptColor.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
      canvas.drawCircle(Offset(sx, sy), 7.5, glowPaint);

      // 2. Point circle with crisp border
      final dotPaint = Paint()..color = ptColor;
      canvas.drawCircle(Offset(sx, sy), 4.5, dotPaint);
      final ringPaint = Paint()
        ..color = isDark ? const Color(0xFF1E293B) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(Offset(sx, sy), 4.5, ringPaint);

      // 3. Compact coordinate label badge
      final labelSpan = TextSpan(
        children: [
          TextSpan(
            text: '${kp.coordinateText}\n',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          TextSpan(
            text: kp.label,
            style: TextStyle(
              fontSize: 8.0,
              fontWeight: FontWeight.w500,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
        ],
      );

      final tp = TextPainter(
        text: labelSpan,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();

      final badgeW = tp.width + 10;
      final badgeH = tp.height + 4;

      // Smart anti-collision placement:
      // Vertex minimum goes BELOW the point; roots go ABOVE the point!
      double badgeY;
      if (kp.pointType == 'vertex' || kp.pointType == 'extrema') {
        // Place below if there's space below, else above
        if (sy + badgeH + 12 < size.height) {
          badgeY = sy + 10;
        } else {
          badgeY = sy - badgeH - 10;
        }
      } else {
        // Roots go above point
        if (sy - badgeH - 10 > 4) {
          badgeY = sy - badgeH - 10;
        } else {
          badgeY = sy + 10;
        }
      }

      double badgeX = sx - badgeW / 2;

      // If neighboring point is within 55px horizontally, stagger
      if (i > 0) {
        final prevSx = toScreenX(visible[i - 1].x);
        if ((sx - prevSx).abs() < 55) {
          badgeX = sx + 2; // Shift current right
        }
      }

      // Clamp inside viewport
      badgeX = badgeX.clamp(4.0, size.width - badgeW - 4);
      badgeY = badgeY.clamp(4.0, size.height - badgeH - 4);

      final badgeRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(badgeX, badgeY, badgeW, badgeH),
        const Radius.circular(6),
      );

      // Drop shadow for crisp contrast
      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.4 : 0.08)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawRRect(badgeRRect.shift(const Offset(0, 1.5)), shadowPaint);

      // Badge Surface
      final badgeBgPaint = Paint()
        ..color = isDark ? const Color(0xF01E293B) : const Color(0xF8FFFFFF);
      canvas.drawRRect(badgeRRect, badgeBgPaint);

      // Badge Border
      final badgeBorderPaint = Paint()
        ..color = isDark ? const Color(0x33FFFFFF) : const Color(0x24000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;
      canvas.drawRRect(badgeRRect, badgeBorderPaint);

      tp.paint(canvas, Offset(badgeX + 5, badgeY + 2));
    }
  }

  static double _calculateGridStep(double span) {
    if (span <= 4) return 0.5;
    if (span <= 10) return 1.0;
    if (span <= 25) return 2.0;
    if (span <= 50) return 5.0;
    if (span <= 100) return 10.0;
    return 20.0;
  }

  static String _formatTickNum(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-4) {
      return v.round().toString();
    }
    return v.toStringAsFixed(1);
  }

  @override
  bool shouldRepaint(covariant PlotPainter oldDelegate) {
    return oldDelegate.plot != plot ||
        oldDelegate.compiledFunction != compiledFunction ||
        oldDelegate.isDark != isDark;
  }
}
