import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/page_model.dart';
import '../models/plot_model.dart';
import '../models/shape_model.dart';
import '../models/stroke_model.dart';
import '../models/text_model.dart';
import '../pdf/pdf_text_index.dart';
import '../recognition/math_function_parser.dart';
import '../rendering/board_painter.dart';
import '../rendering/plot_painter.dart';

/// What the AI should look at: the selection if there is one, otherwise the
/// whole page.
class BoardContext {
  final String description; // structured text summary for the prompt
  final String? imageBase64; // PNG of the relevant region (null if empty)
  final bool isSelection;
  final int elementCount;

  const BoardContext({
    required this.description,
    required this.imageBase64,
    required this.isSelection,
    required this.elementCount,
  });

  bool get isEmpty => elementCount == 0;

  static const int _maxTextChars = 4000;
  static const double _maxImageSide = 1024;

  /// Builds context for [page], limited to [selectedIds] when non-empty.
  static Future<BoardContext> build({
    required PageModel page,
    required int pageNumber,
    required int totalPages,
    Set<String> selectedIds = const {},
  }) async {
    final sel = selectedIds.isNotEmpty;
    bool keep(String id) => !sel || selectedIds.contains(id);

    final strokes = page.strokes.where((e) => keep(e.id)).toList();
    final shapes = page.shapes.where((e) => keep(e.id)).toList();
    final texts = page.texts.where((e) => keep(e.id)).toList();
    final plots = page.plots.where((e) => keep(e.id)).toList();
    // Imported PDF page: its text is the main content (whole-page requests).
    String pdfText = '';
    if (page.pdf != null && !sel) {
      pdfText = await PdfTextIndex.pageText(page.pdf!);
      if (pdfText.length > 6000) {
        pdfText = '${pdfText.substring(0, 6000)} [truncated]';
      }
    }
    final count =
        strokes.length +
        shapes.length +
        texts.length +
        plots.length +
        (page.pdf != null && !sel ? 1 : 0);

    var description = describe(
      strokes: strokes,
      shapes: shapes,
      texts: texts,
      plots: plots,
      pageNumber: pageNumber,
      totalPages: totalPages,
      isSelection: sel,
    );
    if (page.pdf != null && !sel) {
      final p = page.pdf!;
      description =
          '$description\n'
          'This page is page ${p.pageIndex + 1} of the imported PDF "${p.sourceName}"'
          '${pdfText.isEmpty ? ' (scanned, no text layer).' : '. Its text:\n"""$pdfText"""'}\n'
          'Ink on the board is the user\'s annotation on top of this PDF page.';
    }

    // Typed text and graph equations are fully captured as text; only send an
    // image when there is visual content (ink, shapes, graphs) to look at.
    final needsImage =
        strokes.isNotEmpty || shapes.isNotEmpty || plots.isNotEmpty;
    final image = needsImage
        ? await renderRegionPng(
            strokes: strokes,
            shapes: shapes,
            texts: texts,
            plots: plots,
          )
        : null;

    return BoardContext(
      description: description,
      imageBase64: image == null ? null : base64Encode(image),
      isSelection: sel,
      elementCount: count,
    );
  }

  /// Text summary of board elements, ordered top-to-bottom, left-to-right.
  static String describe({
    required List<Stroke> strokes,
    required List<ShapeObject> shapes,
    required List<TextObject> texts,
    required List<PlotObject> plots,
    required int pageNumber,
    required int totalPages,
    required bool isSelection,
  }) {
    final b = StringBuffer();
    b.writeln(
      isSelection
          ? 'Context: the user SELECTED part of page $pageNumber of $totalPages.'
          : 'Context: the whole of page $pageNumber of $totalPages.',
    );

    if (texts.isNotEmpty) {
      final ordered = [...texts]
        ..sort((a, c) {
          final dy = a.position.dy - c.position.dy;
          if (dy.abs() > 20) return dy.sign.toInt();
          return (a.position.dx - c.position.dx).sign.toInt();
        });
      b.writeln('Typed text on the board (reading order):');
      int used = 0;
      for (final t in ordered) {
        final line = t.text.replaceAll('\n', ' / ');
        if (used + line.length > _maxTextChars) {
          b.writeln('- [more text truncated]');
          break;
        }
        used += line.length;
        b.writeln('- "$line"');
      }
    }
    if (plots.isNotEmpty) {
      b.writeln('Graphs plotted: ${plots.map((p) => p.equation).join('; ')}');
    }
    if (shapes.isNotEmpty) {
      final counts = <String, int>{};
      for (final s in shapes) {
        counts[s.shapeType.displayName] =
            (counts[s.shapeType.displayName] ?? 0) + 1;
      }
      b.writeln(
        'Shapes: ${counts.entries.map((e) => '${e.value} ${e.key}').join(', ')}',
      );
    }
    if (strokes.isNotEmpty) {
      b.writeln(
        'Handwritten ink strokes: ${strokes.length} (see attached image).',
      );
    }
    if (texts.isEmpty && plots.isEmpty && shapes.isEmpty && strokes.isEmpty) {
      b.writeln('The board is empty.');
    }
    return b.toString().trim();
  }

  /// Renders elements to a white-background PNG, scaled to fit within
  /// [_maxImageSide] so token use stays bounded on large boards.
  static Future<Uint8List?> renderRegionPng({
    required List<Stroke> strokes,
    required List<ShapeObject> shapes,
    required List<TextObject> texts,
    required List<PlotObject> plots,
    double padding = 24,
  }) async {
    Rect? bounds;
    void add(Rect r) =>
        bounds = bounds == null ? r : bounds!.expandToInclude(r);
    for (final s in strokes) {
      add(s.bounds);
    }
    for (final s in shapes) {
      add(s.bounds);
    }
    for (final t in texts) {
      add(t.bounds);
    }
    for (final p in plots) {
      add(p.rect);
    }
    if (bounds == null || bounds!.width < 4 || bounds!.height < 4) return null;

    final region = bounds!.inflate(padding);
    final scale = math.min(
      1.0,
      _maxImageSide / math.max(region.width, region.height),
    );
    final w = (region.width * scale).ceil().clamp(32, 4096);
    final h = (region.height * scale).ceil().clamp(32, 4096);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      Paint()..color = Colors.white,
    );
    canvas.scale(scale);
    canvas.translate(-region.left, -region.top);
    BoardPainter.paintElements(
      canvas,
      strokes: strokes,
      shapes: shapes,
      texts: texts,
    );
    paintPlots(canvas, plots);

    final image = await recorder.endRecording().toImage(w, h);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  /// Paints plot cards (normally live widgets) into a canvas, for snapshots
  /// and export.
  static void paintPlots(
    Canvas canvas,
    List<PlotObject> plots, {
    bool isDark = false,
  }) {
    for (final plot in plots) {
      if (plot.isMinimized) continue;
      canvas.save();
      canvas.translate(plot.rect.left, plot.rect.top);
      final local = Offset.zero & plot.rect.size;
      canvas.clipRect(local);
      canvas.drawRect(
        local,
        Paint()..color = isDark ? const Color(0xFF0F172A) : Colors.white,
      );
      PlotPainter(
        plot: plot,
        compiledFunction: MathFunctionParser.parse(plot.equation),
        isDark: isDark,
      ).paint(canvas, plot.rect.size);
      canvas.drawRect(
        local,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0x33000000),
      );
      canvas.restore();
    }
  }
}
