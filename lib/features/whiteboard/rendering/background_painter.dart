import 'package:flutter/foundation.dart' show ValueListenable;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/background_style.dart';

class BackgroundPainter extends CustomPainter {
  final CanvasBackground background;
  final bool isInfiniteCanvas;
  final Rect? pageBounds;
  final Matrix4? transform;

  /// When set, the painter repaints (without a widget rebuild) whenever the
  /// canvas transform changes, reading the live matrix at paint time.
  final ValueListenable<Matrix4>? transformListenable;

  const BackgroundPainter({
    required this.background,
    this.isInfiniteCanvas = false,
    this.pageBounds,
    this.transform,
    this.transformListenable,
  }) : super(repaint: transformListenable);

  Matrix4? get _matrix => transformListenable?.value ?? transform;

  // Standard high-definition paginated sheet size (A4 / Tablet presentation standard)
  static const Rect defaultPageRect = Rect.fromLTWH(40, 40, 1100, 1550);

  @override
  void paint(Canvas canvas, Size size) {
    if (isInfiniteCanvas) {
      _paintInfinite(canvas, size);
    } else {
      _paintPaginated(canvas, size);
    }
  }

  void _paintInfinite(Canvas canvas, Size size) {
    final viewportRect = Offset.zero & size;

    // 1. Paint base background surface color across entire viewport
    final bgPaint = Paint()..color = background.color;
    canvas.drawRect(viewportRect, bgPaint);

    if (background.style == BackgroundStyle.plain) return;

    final matrix = _matrix ?? Matrix4.identity();
    final spacing = background.spacing.clamp(16.0, 120.0);

    // Compute visible scene rectangle using inverse matrix
    final Matrix4 inverse;
    try {
      inverse = Matrix4.inverted(matrix);
    } catch (_) {
      return;
    }

    final p1 = MatrixUtils.transformPoint(inverse, Offset.zero);
    final p2 = MatrixUtils.transformPoint(
      inverse,
      Offset(size.width, size.height),
    );
    final p3 = MatrixUtils.transformPoint(inverse, Offset(size.width, 0));
    final p4 = MatrixUtils.transformPoint(inverse, Offset(0, size.height));

    final minX = [p1.dx, p2.dx, p3.dx, p4.dx].reduce((a, b) => a < b ? a : b);
    final maxX = [p1.dx, p2.dx, p3.dx, p4.dx].reduce((a, b) => a > b ? a : b);
    final minY = [p1.dy, p2.dy, p3.dy, p4.dy].reduce((a, b) => a < b ? a : b);
    final maxY = [p1.dy, p2.dy, p3.dy, p4.dy].reduce((a, b) => a > b ? a : b);

    final sceneBounds = Rect.fromLTRB(
      minX - spacing * 2,
      minY - spacing * 2,
      maxX + spacing * 2,
      maxY + spacing * 2,
    );

    // Draw pattern in scene coordinates transformed into viewport
    canvas.save();
    canvas.transform(matrix.storage);
    _drawPattern(canvas, sceneBounds);
    canvas.restore();
  }

  void _paintPaginated(Canvas canvas, Size size) {
    final viewportRect = Offset.zero & size;
    final page = pageBounds ?? defaultPageRect;

    // 1. Paint desk / studio background surface outside the page sheet
    final isDark = background.isDark;
    final deskColor = isDark
        ? const Color(0xFF0F172A)
        : const Color(0xFFE2E8F0);
    canvas.drawRect(viewportRect, Paint()..color = deskColor);

    final matrix = _matrix ?? Matrix4.identity();
    canvas.save();
    canvas.transform(matrix.storage);

    // 2. Realistic soft drop shadow under page sheet
    final shadowRRect = RRect.fromRectAndRadius(
      page.shift(const Offset(0, 8)),
      const Radius.circular(12),
    );
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.16)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
    canvas.drawRRect(shadowRRect, shadowPaint);

    // 3. Paint page sheet surface
    final pageRRect = RRect.fromRectAndRadius(page, const Radius.circular(12));
    final pagePaint = Paint()..color = background.color;
    canvas.drawRRect(pageRRect, pagePaint);

    // 4. Clip to page and draw background pattern inside page sheet
    if (background.style != BackgroundStyle.plain) {
      canvas.save();
      canvas.clipRRect(pageRRect);
      _drawPattern(canvas, page);
      canvas.restore();
    }

    // 5. Draw subtle paper page border
    final borderPaint = Paint()
      ..color = isDark ? Colors.white12 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawRRect(pageRRect, borderPaint);

    canvas.restore();
  }

  void _drawPattern(Canvas canvas, Rect bounds) {
    final isDark = background.isDark;
    final defaultPatternColor = isDark
        ? const Color(0x2EFFFFFF) // Subtle light lines for dark boards
        : const Color(0x26000000); // Subtle dark lines for light boards

    final patternPaint = Paint()
      ..color = defaultPatternColor
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final spacing = background.spacing.clamp(16.0, 120.0);

    switch (background.style) {
      case BackgroundStyle.plain:
        break;

      case BackgroundStyle.grid:
        // Draw vertical lines
        double x = bounds.left + (spacing - (bounds.left % spacing));
        while (x < bounds.right) {
          canvas.drawLine(
            Offset(x, bounds.top),
            Offset(x, bounds.bottom),
            patternPaint,
          );
          x += spacing;
        }
        // Draw horizontal lines
        double y = bounds.top + (spacing - (bounds.top % spacing));
        while (y < bounds.bottom) {
          canvas.drawLine(
            Offset(bounds.left, y),
            Offset(bounds.right, y),
            patternPaint,
          );
          y += spacing;
        }
        break;

      case BackgroundStyle.ruled:
        // Notebook ruled lines
        double y = bounds.top + (spacing - (bounds.top % spacing));
        while (y < bounds.bottom) {
          canvas.drawLine(
            Offset(bounds.left, y),
            Offset(bounds.right, y),
            patternPaint,
          );
          y += spacing;
        }

        // Draw classic margin line
        final marginX = bounds.left + 72.0;
        if (marginX < bounds.right) {
          final marginPaint = Paint()
            ..color = isDark ? const Color(0x40F87171) : const Color(0x60EF4444)
            ..strokeWidth = 1.5;
          canvas.drawLine(
            Offset(marginX, bounds.top),
            Offset(marginX, bounds.bottom),
            marginPaint,
          );
        }
        break;

      case BackgroundStyle.dotted:
        final dotPaint = Paint()
          ..color = isDark ? const Color(0x4DFFFFFF) : const Color(0x4D000000)
          ..style = PaintingStyle.fill;

        double x = bounds.left + (spacing - (bounds.left % spacing));
        while (x < bounds.right) {
          double y = bounds.top + (spacing - (bounds.top % spacing));
          while (y < bounds.bottom) {
            canvas.drawCircle(Offset(x, y), 1.25, dotPaint);
            y += spacing;
          }
          x += spacing;
        }
        break;

      case BackgroundStyle.graph:
        // Graph paper: fine 1x lines and accented 5x lines
        final majorPaint = Paint()
          ..color = isDark ? const Color(0x45FFFFFF) : const Color(0x3B000000)
          ..strokeWidth = 1.25
          ..style = PaintingStyle.stroke;

        int stepX = 0;
        double gx = bounds.left;
        while (gx < bounds.right) {
          final isMajor = (stepX % 5 == 0);
          canvas.drawLine(
            Offset(gx, bounds.top),
            Offset(gx, bounds.bottom),
            isMajor ? majorPaint : patternPaint,
          );
          gx += spacing / 2;
          stepX++;
        }

        int stepY = 0;
        double gy = bounds.top;
        while (gy < bounds.bottom) {
          final isMajor = (stepY % 5 == 0);
          canvas.drawLine(
            Offset(bounds.left, gy),
            Offset(bounds.right, gy),
            isMajor ? majorPaint : patternPaint,
          );
          gy += spacing / 2;
          stepY++;
        }
        break;

      case BackgroundStyle.isometric:
        // 3D Isometric equilateral grid (30-degree diagonals and horizontal lines)
        final isoSpacing = spacing.clamp(20.0, 80.0);
        final rowHeight = isoSpacing * math.sqrt(3) / 2;

        // 1. Horizontal lines
        double hy = bounds.top + (rowHeight - (bounds.top % rowHeight));
        while (hy < bounds.bottom) {
          canvas.drawLine(
            Offset(bounds.left, hy),
            Offset(bounds.right, hy),
            patternPaint,
          );
          hy += rowHeight;
        }

        // 2. 30-degree and -30-degree diagonal lines
        final diagSpacing = isoSpacing;
        final startX = bounds.left - bounds.height * math.sqrt(3);
        final endX = bounds.right + bounds.height * math.sqrt(3);

        double dx = startX;
        while (dx < endX) {
          final p1 = Offset(dx, bounds.top);
          final p2 = Offset(dx + bounds.height / math.sqrt(3), bounds.bottom);
          canvas.drawLine(p1, p2, patternPaint);

          final p3 = Offset(dx, bounds.top);
          final p4 = Offset(dx - bounds.height / math.sqrt(3), bounds.bottom);
          canvas.drawLine(p3, p4, patternPaint);

          dx += diagSpacing;
        }
        break;

      case BackgroundStyle.polar:
        // Concentric circles with radial angle lines
        final center = bounds.center;
        final maxR =
            math.sqrt(
              bounds.width * bounds.width + bounds.height * bounds.height,
            ) /
            2;
        final radialStep = spacing.clamp(24.0, 90.0);

        // Concentric circles
        double r = radialStep;
        int circleIndex = 1;
        while (r <= maxR) {
          final isMajor = (circleIndex % 5 == 0);
          final cPaint = isMajor
              ? (Paint()
                  ..color = isDark
                      ? const Color(0x45FFFFFF)
                      : const Color(0x3B000000)
                  ..strokeWidth = 1.3
                  ..style = PaintingStyle.stroke)
              : patternPaint;
          canvas.drawCircle(center, r, cPaint);
          r += radialStep;
          circleIndex++;
        }

        // Radial rays every 15 degrees
        for (int deg = 0; deg < 360; deg += 15) {
          final isMajor = (deg % 90 == 0);
          final isMedium = (deg % 45 == 0);
          final rayPaint = isMajor
              ? (Paint()
                  ..color = isDark
                      ? const Color(0x66FFFFFF)
                      : const Color(0x55000000)
                  ..strokeWidth = 1.5
                  ..style = PaintingStyle.stroke)
              : (isMedium
                    ? (Paint()
                        ..color = isDark
                            ? const Color(0x3BFFFFFF)
                            : const Color(0x33000000)
                        ..strokeWidth = 1.1
                        ..style = PaintingStyle.stroke)
                    : patternPaint);

          final rad = deg * math.pi / 180;
          final rayEnd = Offset(
            center.dx + maxR * math.cos(rad),
            center.dy + maxR * math.sin(rad),
          );
          canvas.drawLine(center, rayEnd, rayPaint);
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundPainter oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.isInfiniteCanvas != isInfiniteCanvas ||
        oldDelegate.pageBounds != pageBounds ||
        oldDelegate.transform != transform ||
        oldDelegate.transformListenable != transformListenable;
  }
}
