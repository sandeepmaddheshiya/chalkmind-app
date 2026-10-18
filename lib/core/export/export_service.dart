import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../features/whiteboard/models/page_model.dart';
import '../../features/whiteboard/models/project_model.dart';
import '../../features/whiteboard/rendering/background_painter.dart';
import '../../features/whiteboard/rendering/board_painter.dart';

class ExportService {
  /// Render a page to high-res image bytes
  static Future<Uint8List> renderPageToImage({
    required PageModel page,
    Size targetSize = const Size(1920, 1080),
    double pixelRatio = 2.0,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Apply scale for crisp presentation quality
    canvas.scale(pixelRatio, pixelRatio);

    // 1. Paint background
    final bgPainter = BackgroundPainter(background: page.background);
    bgPainter.paint(canvas, targetSize);

    // 2. Paint shapes, strokes, and text
    final boardPainter = BoardPainter(
      strokes: page.strokes,
      shapes: page.shapes,
      texts: page.texts,
    );
    boardPainter.paint(canvas, targetSize);

    final picture = recorder.endRecording();
    final img = await picture.toImage(
      (targetSize.width * pixelRatio).round(),
      (targetSize.height * pixelRatio).round(),
    );

    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Export single page as PNG file
  static Future<File> exportPageAsPng({
    required PageModel page,
    required String fileName,
  }) async {
    final imageBytes = await renderPageToImage(page: page);
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName.png');
    await file.writeAsBytes(imageBytes);
    return file;
  }

  /// Export entire project as a multi-page PDF document
  static Future<File> exportProjectAsPdf({
    required ProjectModel project,
    required String fileName,
  }) async {
    final pdf = pw.Document();

    for (int i = 0; i < project.pages.length; i++) {
      final page = project.pages[i];
      final imageBytes = await renderPageToImage(
        page: page,
        targetSize: const Size(1920, 1080),
        pixelRatio: 1.5, // Crisp 1080p equivalent
      );

      final pdfImage = pw.MemoryImage(imageBytes);
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: pw.EdgeInsets.zero,
          build: (pw.Context context) {
            return pw.FullPage(
              ignoreMargins: true,
              child: pw.Image(pdfImage, fit: pw.BoxFit.fill),
            );
          },
        ),
      );
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$fileName.pdf');
    await file.writeAsBytes(await pdf.save());
    return file;
  }
}
