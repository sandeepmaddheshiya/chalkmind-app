import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/storage/asset_store.dart';
import '../models/pdf_page_attachment.dart';
import 'pdf_import_service.dart';

/// Renders imported PDF pages on demand and caches the results on disk.
///
/// Import no longer renders every page up front (seconds per page on a
/// mid-range tablet); instead a page is rendered the first time it is shown
/// (or prefetched as a neighbour), and its word positions are extracted the
/// first time something on that page needs text.
///
/// - Requests for the same page share one in-flight future.
/// - Work runs one job at a time so memory stays flat on low-end devices.
/// - Open documents are kept in a small LRU so page flips don't reopen files.
class PdfPageRenderer {
  PdfPageRenderer._();
  static final PdfPageRenderer instance = PdfPageRenderer._();

  /// Rendered width in pixels. Sharp at ~1.5x zoom on the 1100-wide sheet;
  /// smaller than before (1800) so rendering, encoding and decoding are
  /// ~25% cheaper and each decoded page uses ~10 MB instead of ~18 MB.
  static const double renderWidth = 1500;

  final Map<String, Future<String?>> _imageJobs = {};
  final Map<String, Future<bool>> _wordJobs = {};
  final LinkedHashMap<String, Future<PdfDocument>> _docs = LinkedHashMap();
  Future<void> _queue = Future.value();

  /// Absolute path of the page image if it is already cached, else null.
  String? cachedImagePath(PdfPageAttachment pdf) {
    final path = AssetStore.resolve(pdf.imagePath);
    if (path == null) return null;
    return File(path).existsSync() ? path : null;
  }

  /// Ensures the page image exists on disk; returns its path (null on failure).
  Future<String?> ensureImage(PdfPageAttachment pdf) {
    final cached = cachedImagePath(pdf);
    if (cached != null) return SynchronousFuture(cached);
    return _imageJobs.putIfAbsent(pdf.imagePath, () {
      final job = _serial(() => _renderImage(pdf));
      job.whenComplete(() => _imageJobs.remove(pdf.imagePath));
      return job;
    });
  }

  /// Ensures the page's word index exists on disk. Returns false if the page
  /// can't be read (the caller then treats it as having no text).
  Future<bool> ensureWords(PdfPageAttachment pdf) {
    final rel = pdf.wordsPath;
    if (rel == null) return SynchronousFuture(false);
    final path = AssetStore.resolve(rel);
    if (path != null && File(path).existsSync()) return SynchronousFuture(true);
    return _wordJobs.putIfAbsent(rel, () {
      final job = _serial(() => _extractWords(pdf));
      job.whenComplete(() => _wordJobs.remove(rel));
      return job;
    });
  }

  /// Renders the given pages in the background (e.g. the pages either side
  /// of the one being viewed) so flipping to them is instant.
  void prefetch(Iterable<PdfPageAttachment> pages) {
    for (final p in pages) {
      if (cachedImagePath(p) == null) unawaited(ensureImage(p));
    }
  }

  Future<T> _serial<T>(Future<T> Function() body) {
    final run = _queue.then((_) => body());
    _queue = run.then((_) {}, onError: (_) {});
    return run;
  }

  Future<PdfDocument> _open(PdfPageAttachment pdf) {
    final rel = pdf.pdfPath;
    if (rel == null) throw StateError('No source PDF stored for this page');
    final existing = _docs.remove(rel);
    if (existing != null) {
      _docs[rel] = existing; // mark most recently used
      return existing;
    }
    final path = AssetStore.resolve(rel);
    if (path == null) throw StateError('Asset storage unavailable');
    final opening = () async {
      await pdfrxFlutterInitialize();
      return PdfDocument.openFile(path);
    }();
    _docs[rel] = opening;
    while (_docs.length > 2) {
      final oldest = _docs.keys.first;
      unawaited(_docs.remove(oldest)!.then((d) => d.dispose(), onError: (_) {}));
    }
    return opening;
  }

  Future<String?> _renderImage(PdfPageAttachment pdf) async {
    final target = AssetStore.resolve(pdf.imagePath);
    if (target == null || pdf.pdfPath == null) return null;
    if (File(target).existsSync()) return target;
    final sw = Stopwatch()..start();
    try {
      final doc = await _open(pdf);
      final page = doc.pages[pdf.pageIndex];
      final w = renderWidth;
      final h = (page.height / page.width * w).roundToDouble();
      final img = await page.render(
        fullWidth: w,
        fullHeight: h,
        width: w.toInt(),
        height: h.toInt(),
        backgroundColor: 0xFFFFFFFF,
      );
      if (img == null) return null;
      final uiImage = await img.createImage();
      img.dispose();
      final png = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      uiImage.dispose();
      if (png == null) return null;
      final tmp = File('$target.tmp');
      await tmp.writeAsBytes(png.buffer.asUint8List(), flush: true);
      await tmp.rename(target);
      debugPrint('PdfPageRenderer: page ${pdf.pageIndex + 1} rendered in ${sw.elapsedMilliseconds} ms');
      return target;
    } catch (e) {
      debugPrint('PdfPageRenderer: render failed for page ${pdf.pageIndex + 1}: $e');
      return null;
    }
  }

  Future<bool> _extractWords(PdfPageAttachment pdf) async {
    final rel = pdf.wordsPath;
    final target = rel == null ? null : AssetStore.resolve(rel);
    if (target == null || pdf.pdfPath == null) return false;
    if (File(target).existsSync()) return true;
    final sw = Stopwatch()..start();
    try {
      final doc = await _open(pdf);
      final page = doc.pages[pdf.pageIndex];
      final raw = await page.loadText();
      final words = raw == null
          ? const <PdfWord>[]
          : PdfImportService.wordsFromChars(raw.fullText, raw.charRects, page.width, page.height);
      // An empty list is cached too: it marks a scanned page (no text layer).
      await File(target).writeAsString(jsonEncode([for (final w in words) w.toRow()]));
      debugPrint('PdfPageRenderer: page ${pdf.pageIndex + 1} text (${words.length} words) in ${sw.elapsedMilliseconds} ms');
      return true;
    } catch (e) {
      debugPrint('PdfPageRenderer: text failed for page ${pdf.pageIndex + 1}: $e');
      return false;
    }
  }
}
