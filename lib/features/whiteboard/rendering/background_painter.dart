import 'package:flutter/material.dart';
import '../models/background_style.dart';

class BackgroundPainter extends CustomPainter {
  final CanvasBackground background;
  final Rect? canvasBounds;

  const BackgroundPainter({
    required this.background,
    this.canvasBounds,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = canvasBounds ?? Offset.zero & size;

    // 1. Paint base background surface color
    final bgPaint = Paint()..color = background.color;
    canvas.drawRect(bounds, bgPaint);

    if (background.style == BackgroundStyle.plain) return;

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
          canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), patternPaint);
          x += spacing;
        }
        // Draw horizontal lines
        double y = bounds.top + (spacing - (bounds.top % spacing));
        while (y < bounds.bottom) {
          canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), patternPaint);
          y += spacing;
        }
        break;

      case BackgroundStyle.ruled:
        // Notebook ruled lines
        double y = bounds.top + (spacing - (bounds.top % spacing));
        while (y < bounds.bottom) {
          canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), patternPaint);
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
    }
  }

  @override
  bool shouldRepaint(covariant BackgroundPainter oldDelegate) {
    return oldDelegate.background != background ||
        oldDelegate.canvasBounds != canvasBounds;
  }
}
