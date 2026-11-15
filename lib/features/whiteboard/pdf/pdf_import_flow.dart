import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/background_style.dart';
import 'pdf_import_service.dart';

/// Pick a PDF, import it with a progress dialog, and report problems.
/// Returns null if cancelled or failed (the user has been told why).
class PdfImportFlow {
  static Future<PdfImportResult?> pickAndImport(
    BuildContext context, {
    CanvasBackground background = const CanvasBackground(),
    int firstPageNumber = 1,
  }) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    if (files.isEmpty || !context.mounted) return null;
    final file = files.first;

    final progress = ValueNotifier<(int, int)>((0, 0));
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Importing PDF'),
          content: ValueListenableBuilder<(int, int)>(
            valueListenable: progress,
            builder: (_, p, _) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 14),
                LinearProgressIndicator(value: p.$2 == 0 ? null : p.$1 / p.$2),
                const SizedBox(height: 8),
                Text(p.$2 == 0 ? 'Opening…' : 'Page ${p.$1} of ${p.$2}'),
              ],
            ),
          ),
        ),
      ),
    );

    PdfImportResult? result;
    String? error;
    try {
      final len = file.lengthSync() ?? await file.length() ?? 0;
      if (len > PdfImportService.maxBytes) {
        throw const PdfImportException('This PDF is larger than 150 MB.');
      }
      result = await PdfImportService.import(
        await file.readAsBytes(),
        fileName: file.name,
        background: background,
        firstPageNumber: firstPageNumber,
        onProgress: (d, t) => progress.value = (d, t),
      );
    } on PdfImportException catch (e) {
      error = e.message;
    } catch (e) {
      error = 'Import failed: $e';
    }

    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    progress.dispose();
    if (!context.mounted) return null;

    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error), backgroundColor: Colors.red.shade700),
      );
      return null;
    }
    final r = result!;
    final notes = <String>[
      if (r.wasTruncated)
        'Imported the first ${r.pages.length} of ${r.totalPagesInFile} pages.',
      if (!r.hasText)
        'This looks like a scanned PDF: look-ups will read the highlighted area as an image.',
    ];
    if (notes.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(notes.join(' '))));
    }
    return r;
  }
}
