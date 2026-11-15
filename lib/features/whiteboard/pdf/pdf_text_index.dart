import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../../../core/storage/asset_store.dart';
import '../models/pdf_page_attachment.dart';
import '../models/stroke_model.dart';
import 'pdf_page_renderer.dart';

/// What a highlighter stroke covered on a PDF page.
@immutable
class HighlightedText {
  final String text; // the highlighted words ('' for scanned pages)
  final String context; // surrounding words, to disambiguate meaning
  final Rect boardRect; // highlighted region in board coordinates
  final PdfPageAttachment pdf;
  const HighlightedText({
    required this.text,
    required this.context,
    required this.boardRect,
    required this.pdf,
  });
  bool get hasText => text.trim().isNotEmpty;
}

/// Loads per-page word boxes (cached) and maps highlighter strokes to text.
class PdfTextIndex {
  static final Map<String, List<PdfWord>> _cache = {};

  static Future<List<PdfWord>> words(PdfPageAttachment pdf) async {
    final rel = pdf.wordsPath;
    if (rel == null) return const [];
    final cached = _cache[rel];
    if (cached != null) return cached;
    // Extracted lazily the first time a page's text is needed.
    if (!await PdfPageRenderer.instance.ensureWords(pdf)) return const [];
    final path = AssetStore.resolve(rel);
    if (path == null) return const [];
    try {
      final rows = jsonDecode(await File(path).readAsString()) as List<dynamic>;
      final list = [for (final r in rows) PdfWord.fromRow(r as List<dynamic>)];
      if (_cache.length > 40) _cache.remove(_cache.keys.first);
      return _cache[rel] = list;
    } catch (e) {
      debugPrint('PdfTextIndex: cannot read $rel: $e');
      return const [];
    }
  }

  /// Indices (reading order) of words covered by [stroke]. A word counts
  /// when the highlighter passes over its middle, so brushing past the edge
  /// of a neighbouring word doesn't select it.
  static List<int> coveredWordIndices(
    List<PdfWord> words,
    PdfPageAttachment pdf,
    Stroke stroke,
  ) {
    if (words.isEmpty || stroke.points.isEmpty) return const [];
    final sb = stroke.bounds;
    final out = <int>[];
    for (int i = 0; i < words.length; i++) {
      final r = pdf.toBoard(words[i].rect);
      if (!r.overlaps(sb)) continue;
      // The pen must pass within the word's box, near its vertical middle.
      final tolerance = math.max(r.height * 0.5, stroke.width * 0.5);
      if (stroke.hitTest(
        r.center,
        threshold: tolerance - stroke.width / 2 + 1,
      )) {
        out.add(i);
        continue;
      }
      // Long words: the stroke may cover the word without crossing its exact
      // centre point; accept when a pen sample falls inside the box.
      final inner = r.deflate(math.min(r.width, r.height) * 0.15);
      if (stroke.points.any((p) => inner.contains(p.offset))) out.add(i);
    }
    return out;
  }

  /// Text under the stroke plus surrounding context, or a region-only result
  /// for scanned pages. Returns null if the stroke is not on the page.
  static Future<HighlightedText?> forStroke(
    PdfPageAttachment pdf,
    Stroke stroke,
  ) async {
    final region = stroke.bounds.intersect(pdf.rect);
    if (region.isEmpty || region.width < 4 || region.height < 4) return null;
    final ws = await words(pdf);
    final idx = coveredWordIndices(ws, pdf, stroke);
    if (idx.isEmpty) {
      // Scanned page (no text layer) or highlight over non-text: the caller
      // can send a cropped image instead.
      return ws.isEmpty
          ? HighlightedText(text: '', context: '', boardRect: region, pdf: pdf)
          : null;
    }
    final text = [for (final i in idx) ws[i].text].join(' ');
    final from = math.max(0, idx.first - 30),
        to = math.min(ws.length, idx.last + 31);
    final context = [for (int i = from; i < to; i++) ws[i].text].join(' ');
    Rect covered = pdf.toBoard(ws[idx.first].rect);
    for (final i in idx) {
      covered = covered.expandToInclude(pdf.toBoard(ws[i].rect));
    }
    return HighlightedText(
      text: text,
      context: context,
      boardRect: covered,
      pdf: pdf,
    );
  }

  /// PNG (base64) of a board region of the PDF page, upscaled so small text
  /// is legible to vision AI (max 1024 px). For scanned pages.
  static Future<String?> cropRegionPng(
    PdfPageAttachment pdf,
    Rect boardRect,
  ) async {
    final path = await PdfPageRenderer.instance.ensureImage(pdf);
    if (path == null) return null;
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final n = pdf.toNormalized(boardRect.inflate(12));
      final src = Rect.fromLTRB(
        n.left * image.width,
        n.top * image.height,
        n.right * image.width,
        n.bottom * image.height,
      );
      if (src.width < 2 || src.height < 2) return null;
      final scale = math.min(1024 / math.max(src.width, src.height), 3.0);
      final w = (src.width * scale).round(), h = (src.height * scale).round();
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      final out = await rec.endRecording().toImage(w, h);
      final png = await out.toByteData(format: ui.ImageByteFormat.png);
      out.dispose();
      return png == null ? null : base64Encode(png.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }

  /// Full text of a PDF page (for AI context such as summaries).
  static Future<String> pageText(PdfPageAttachment pdf) async =>
      (await words(pdf)).map((w) => w.text).join(' ');
}
