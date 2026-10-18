import 'package:flutter/material.dart';

class SelectionPainter extends CustomPainter {
  final Rect? selectionMarquee;
  final Rect? boundingBox;
  final bool isDragging;

  SelectionPainter({
    this.selectionMarquee,
    this.boundingBox,
    this.isDragging = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Paint selection marquee rectangle while user is dragging selection area
    if (selectionMarquee != null) {
      final fillPaint = Paint()
        ..color = const Color(0x263B82F6) // 15% blue
        ..style = PaintingStyle.fill;

      final borderPaint = Paint()
        ..color = const Color(0xFF3B82F6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      canvas.drawRect(selectionMarquee!, fillPaint);
      canvas.drawRect(selectionMarquee!, borderPaint);
    }

    // 2. Paint bounding box around selected elements
    if (boundingBox != null) {
      final boxPaint = Paint()
        ..color = const Color(0xFF3B82F6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;

      final handlePaint = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.fill;

      final handleBorder = Paint()
        ..color = const Color(0xFF2563EB)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      // Draw dashed-like or clear bounding box
      canvas.drawRect(boundingBox!, boxPaint);

      // Draw 4 corner handles
      final corners = [
        boundingBox!.topLeft,
        boundingBox!.topRight,
        boundingBox!.bottomLeft,
        boundingBox!.bottomRight,
      ];

      for (final corner in corners) {
        canvas.drawCircle(corner, 6.0, handlePaint);
        canvas.drawCircle(corner, 6.0, handleBorder);
      }
    }
  }

  @override
  bool shouldRepaint(covariant SelectionPainter oldDelegate) {
    return oldDelegate.selectionMarquee != selectionMarquee ||
        oldDelegate.boundingBox != boundingBox ||
        oldDelegate.isDragging != isDragging;
  }
}
