import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../../features/whiteboard/assistant/board_context.dart';
import '../../features/whiteboard/pdf/pdf_page_renderer.dart';
import '../../features/whiteboard/models/page_model.dart';
import '../../features/whiteboard/models/project_model.dart';
import '../../features/whiteboard/rendering/background_painter.dart';
import '../../features/whiteboard/rendering/board_painter.dart';

class ExportService {
  /// The board region an export should cover: the standard page sheet plus
  /// any content outside it (infinite canvas, content below the fold).
  static Rect exportRegion(PageModel page) {
    Rect region = BackgroundPainter.defaultPageRect;
    void add(Rect r) => region = region.expandToInclude(r);
    for (final s in page.strokes) {
      add(s.bounds);
    }
    for (final s in page.shapes) {
      add(s.bounds);
    }
    for (final t in page.texts) {
      add(t.bounds);
    }
    for (final p in page.plots) {
      add(p.rect);
    }
    if (page.pdf != null) add(page.pdf!.rect);
    return region.inflate(32);
  }

  /// Render a page to high-res PNG bytes. By default the image covers
  /// [exportRegion]; pass [targetSize] to render a fixed area from the origin.
  static Future<Uint8List> renderPageToImage({
    required PageModel page,
    Size? targetSize,
    double pixelRatio = 2.0,
  }) async {
    final region = targetSize != null
        ? Offset.zero & targetSize
        : exportRegion(page);
    // Cap the bitmap so huge infinite boards can't exhaust memory.
    const maxSide = 6000.0;
    final longest =
        (region.width > region.height ? region.width : region.height) *
        pixelRatio;
    final ratio = longest > maxSide
        ? pixelRatio * maxSide / longest
        : pixelRatio;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(ratio, ratio);

    // 1. Paper pattern across the whole region (no desk surround).
    BackgroundPainter(
      background: page.background,
      isInfiniteCanvas: true,
      transform: Matrix4.translationValues(-region.left, -region.top, 0),
    ).paint(canvas, region.size);

    // 2. Imported PDF page under the ink.
    final pdfImage = await _loadPdfImage(page);
    if (pdfImage != null) {
      final r = page.pdf!.rect.shift(-region.topLeft);
      canvas.drawImageRect(
        pdfImage,
        Rect.fromLTWH(
          0,
          0,
          pdfImage.width.toDouble(),
          pdfImage.height.toDouble(),
        ),
        r,
        Paint()..filterQuality = FilterQuality.high,
      );
    }

    // 3. Shapes, strokes, text, then graph plots (live widgets on the canvas,
    // so they need explicit rendering for export).
    canvas.translate(-region.left, -region.top);
    BoardPainter.paintElements(
      canvas,
      strokes: page.strokes,
      shapes: page.shapes,
      texts: page.texts,
    );
    BoardContext.paintPlots(canvas, page.plots, isDark: page.background.isDark);

    final picture = recorder.endRecording();
    pdfImage?.dispose();
    final img = await picture.toImage(
      (region.width * ratio).round(),
      (region.height * ratio).round(),
    );
    picture.dispose();
    try {
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('PNG encoding failed');
      return byteData.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }

  static Future<ui.Image?> _loadPdfImage(PageModel page) async {
    final pdf = page.pdf;
    if (pdf == null) return null;
    final path = await PdfPageRenderer.instance.ensureImage(pdf);
    if (path == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        await File(path).readAsBytes(),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
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
      final region = exportRegion(page);
      final imageBytes = await renderPageToImage(page: page, pixelRatio: 1.5);

      final pdfImage = pw.MemoryImage(imageBytes);
      // Orientation follows the content; contain (not fill) keeps aspect.
      final format = region.width > region.height
          ? PdfPageFormat.a4.landscape
          : PdfPageFormat.a4;
      pdf.addPage(
        pw.Page(
          pageFormat: format,
          margin: const pw.EdgeInsets.all(12),
          build: (pw.Context context) {
            return pw.Center(child: pw.Image(pdfImage, fit: pw.BoxFit.contain));
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
