import 'dart:math' as math;

import 'package:flutter/material.dart';

/// An imported PDF page shown as the "paper" of a board page.
///
/// The rendered page image and its word positions are stored as files in the
/// app's asset store (see `AssetStore`), not inside the project JSON, so
/// autosave stays fast. Paths here are relative to the asset store root.
@immutable
class PdfPageAttachment {
  final String docId;
  final int pageIndex; // 0-based page in the source PDF
  final int pageCount; // pages in the source PDF
  final String sourceName; // original file name, for display
  final String imagePath; // rendered page PNG cache (relative; may not exist yet)
  final String? wordsPath; // word boxes JSON cache (relative; may not exist yet)
  /// Stored copy of the source PDF (relative). Pages are rendered from it on
  /// demand. Null for boards imported by older versions (pre-rendered).
  final String? pdfPath;
  final double aspectRatio; // page width / height

  const PdfPageAttachment({
    required this.docId,
    required this.pageIndex,
    required this.pageCount,
    required this.sourceName,
    required this.imagePath,
    required this.wordsPath,
    required this.aspectRatio,
    this.pdfPath,
  });

  /// Standard page sheet (matches `BackgroundPainter.defaultPageRect`).
  static const Rect sheet = Rect.fromLTWH(40, 40, 1100, 1550);

  /// Where the page sits on the board: fitted inside the standard sheet,
  /// keeping the PDF's aspect ratio, centred horizontally, top-aligned.
  Rect get rect {
    final a = aspectRatio <= 0 ? sheet.width / sheet.height : aspectRatio;
    var w = sheet.width;
    var h = w / a;
    if (h > sheet.height) {
      h = sheet.height;
      w = h * a;
    }
    return Rect.fromLTWH(sheet.left + (sheet.width - w) / 2, sheet.top, w, h);
  }

  /// Converts a normalised page rectangle (0..1, top-left origin) to board
  /// coordinates.
  Rect toBoard(Rect normalized) {
    final r = rect;
    return Rect.fromLTRB(
      r.left + normalized.left * r.width,
      r.top + normalized.top * r.height,
      r.left + normalized.right * r.width,
      r.top + normalized.bottom * r.height,
    );
  }

  /// Converts a board rectangle to normalised page coordinates (clamped).
  Rect toNormalized(Rect board) {
    final r = rect;
    double nx(double x) => ((x - r.left) / r.width).clamp(0.0, 1.0);
    double ny(double y) => ((y - r.top) / r.height).clamp(0.0, 1.0);
    return Rect.fromLTRB(
      nx(board.left),
      ny(board.top),
      nx(math.max(board.left, board.right)),
      ny(math.max(board.top, board.bottom)),
    );
  }

  Map<String, dynamic> toJson() => {
    'docId': docId,
    'pageIndex': pageIndex,
    'pageCount': pageCount,
    'sourceName': sourceName,
    'imagePath': imagePath,
    'wordsPath': wordsPath,
    'aspectRatio': aspectRatio,
    'pdfPath': ?pdfPath,
  };

  factory PdfPageAttachment.fromJson(Map<String, dynamic> json) =>
      PdfPageAttachment(
        docId: json['docId'] as String,
        pageIndex: (json['pageIndex'] as num?)?.toInt() ?? 0,
        pageCount: (json['pageCount'] as num?)?.toInt() ?? 1,
        sourceName: json['sourceName'] as String? ?? 'PDF',
        imagePath: json['imagePath'] as String,
        wordsPath: json['wordsPath'] as String?,
        aspectRatio: (json['aspectRatio'] as num?)?.toDouble() ?? (1100 / 1550),
        pdfPath: json['pdfPath'] as String?,
      );
}

/// A word on a PDF page with its box in normalised page coordinates
/// (0..1, top-left origin).
@immutable
class PdfWord {
  final String text;
  final Rect rect;
  const PdfWord(this.text, this.rect);

  /// Compact JSON row: [text, left, top, right, bottom] (4 decimals).
  List<Object> toRow() {
    double r4(double v) => (v * 10000).roundToDouble() / 10000;
    return [text, r4(rect.left), r4(rect.top), r4(rect.right), r4(rect.bottom)];
  }

  static PdfWord fromRow(List<dynamic> row) => PdfWord(
    row[0] as String,
    Rect.fromLTRB(
      (row[1] as num).toDouble(),
      (row[2] as num).toDouble(),
      (row[3] as num).toDouble(),
      (row[4] as num).toDouble(),
    ),
  );
}
