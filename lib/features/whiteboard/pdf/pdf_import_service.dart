import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../../../core/storage/asset_store.dart';
import '../models/background_style.dart';
import '../models/page_model.dart';
import '../models/pdf_page_attachment.dart';

/// User-facing import failure.
class PdfImportException implements Exception {
  final String message;
  const PdfImportException(this.message);
  @override
  String toString() => message;
}

class PdfImportResult {
  final List<PageModel> pages;
  final int totalPagesInFile;
  final bool hasText; // false for scanned PDFs (no text layer)
  const PdfImportResult(this.pages, this.totalPagesInFile, this.hasText);
  bool get wasTruncated => pages.length < totalPagesInFile;
}

/// Imports a PDF as board pages: each page is rendered to an image (the
/// page's "paper") and its words are indexed with their positions so a
/// highlighter stroke can tell which words it covers.
class PdfImportService {
  static const int maxBytes = 150 * 1024 * 1024;
  static const int maxPages = 100;

  static Future<PdfImportResult> import(
    Uint8List bytes, {
    required String fileName,
    CanvasBackground background = const CanvasBackground(),
    int firstPageNumber = 1,
    void Function(int done, int total)? onProgress,
  }) async {
    if (bytes.length > maxBytes) {
      throw const PdfImportException('This PDF is larger than 150 MB.');
    }
    if (!looksLikePdf(bytes)) {
      throw const PdfImportException('This file is not a PDF.');
    }

    final sw = Stopwatch()..start();
    await pdfrxFlutterInitialize();
    final docId = const Uuid().v4();
    PdfDocument? doc;
    try {
      try {
        doc = await PdfDocument.openData(bytes, sourceName: 'import-$docId');
      } on PdfPasswordException {
        throw const PdfImportException('This PDF is password-protected. Remove the password and try again.');
      } catch (e) {
        throw PdfImportException('Could not open this PDF. It may be damaged. ($e)');
      }

      final total = doc.pages.length;
      if (total == 0) throw const PdfImportException('This PDF has no pages.');
      final count = total > maxPages ? maxPages : total;

      // Keep a copy of the PDF; pages are rendered from it on demand
      // (see PdfPageRenderer), so import cost no longer grows with page count.
      final dir = await AssetStore.docDir(docId);
      await File('${dir.path}/source.pdf').writeAsBytes(bytes, flush: true);

      final pages = <PageModel>[
        for (int i = 0; i < count; i++)
          PageModel(
            id: const Uuid().v4(),
            pageNumber: firstPageNumber + i,
            background: background,
            pdf: PdfPageAttachment(
              docId: docId,
              pageIndex: i,
              pageCount: total,
              sourceName: fileName,
              imagePath: '$docId/page_${i + 1}.png',
              wordsPath: '$docId/page_${i + 1}.words.json',
              pdfPath: '$docId/source.pdf',
              aspectRatio: doc.pages[i].width / doc.pages[i].height,
            ),
          ),
      ];

      // Quick text check on the first page (for the "scanned PDF" notice);
      // its word index is cached for later.
      final firstText = await doc.pages.first.loadText();
      final hasText = firstText != null && firstText.fullText.trim().isNotEmpty;

      onProgress?.call(count, count);
      debugPrint('PdfImportService: imported $count pages in ${sw.elapsedMilliseconds} ms');
      return PdfImportResult(pages, total, hasText);
    } catch (e) {
      // Don't leave half-imported files behind.
      await AssetStore.deleteDoc(docId);
      if (e is PdfImportException) rethrow;
      throw PdfImportException('Import failed: $e');
    } finally {
      await doc?.dispose();
    }
  }

  /// PDF signature check ("%PDF-" within the first 1 KB, per the spec's
  /// tolerance for leading bytes). Doesn't trust the file extension.
  static bool looksLikePdf(Uint8List b) {
    final end = b.length < 1024 ? b.length : 1024;
    for (int i = 0; i + 4 < end; i++) {
      if (b[i] == 0x25 &&
          b[i + 1] == 0x50 &&
          b[i + 2] == 0x44 &&
          b[i + 3] == 0x46 &&
          b[i + 4] == 0x2D) {
        return true;
      }
    }
    return false;
  }

  /// Groups per-character boxes into words. PDF boxes use points with a
  /// bottom-left origin; output is normalised with a top-left origin.
  static List<PdfWord> wordsFromChars(
    String text,
    List<PdfRect> rects,
    double pageW,
    double pageH,
  ) {
    final words = <PdfWord>[];
    final n = text.length < rects.length ? text.length : rects.length;
    final buf = StringBuffer();
    double l = 0, t = 0, r = 0, b = 0;
    bool open = false;

    void flush() {
      if (open && buf.isNotEmpty) {
        words.add(
          PdfWord(
            buf.toString(),
            ui.Rect.fromLTRB(
              l / pageW,
              1 - t / pageH,
              r / pageW,
              1 - b / pageH,
            ),
          ),
        );
      }
      buf.clear();
      open = false;
    }

    for (int i = 0; i < n; i++) {
      final ch = text[i];
      final rc = rects[i];
      final isSpace = ch.trim().isEmpty;
      if (isSpace || rc.isEmpty) {
        flush();
        continue;
      }
      // A big jump to the left or a new line also ends a word.
      if (open && (rc.left < l - 2 || rc.bottom > t || rc.top < b)) flush();
      if (!open) {
        l = rc.left;
        t = rc.top;
        r = rc.right;
        b = rc.bottom;
        open = true;
      } else {
        if (rc.left < l) l = rc.left;
        if (rc.top > t) t = rc.top;
        if (rc.right > r) r = rc.right;
        if (rc.bottom < b) b = rc.bottom;
      }
      buf.write(ch);
    }
    flush();
    return words;
  }
}
