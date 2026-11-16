// PDF import + highlight look-up, using a real PDF generated with the
// `pdf` package and the real PDFium engine (pdfrx).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:boardflow/core/storage/asset_store.dart';
import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/pdf_page_attachment.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/pdf/pdf_import_service.dart';
import 'package:boardflow/features/whiteboard/pdf/pdf_page_renderer.dart';
import 'package:boardflow/features/whiteboard/pdf/pdf_text_index.dart';
import 'package:boardflow/features/whiteboard/pdf/text_lookup_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/core/export/export_service.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:boardflow/features/whiteboard/ui/pdf_lookup_overlay.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' show Pdfrx;

Future<Uint8List> makePdf() async {
  final doc = pw.Document();
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    build: (_) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('Photosynthesis', style: const pw.TextStyle(fontSize: 28)),
        pw.SizedBox(height: 20),
        pw.Text('Plants convert light energy into chemical energy stored in glucose.',
            style: const pw.TextStyle(fontSize: 14)),
      ],
    ),
  ));
  doc.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4.landscape,
    build: (_) => pw.Text('Second page', style: const pw.TextStyle(fontSize: 20)),
  ));
  return doc.save();
}

/// Highlighter stroke drawn horizontally across a board rectangle.
Stroke highlight(Rect r) => Stroke(
      id: 'hl',
      points: [
        for (int i = 0; i <= 20; i++) StrokePoint(x: r.left + r.width * i / 20, y: r.center.dy, timestamp: i),
      ],
      colorValue: 0xFFFACC15,
      width: 22,
      opacity: 0.35,
      toolType: ToolType.highlighter,
    );

/// Path to a Linux PDFium build for running the real-engine tests locally:
///   PDFIUM_PATH=/path/to/libpdfium.so flutter test test/pdf_import_test.dart
/// (The Android/iOS/desktop app builds bundle their own PDFium.)
final String? _pdfium = Platform.environment['PDFIUM_PATH'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    tmp = Directory.systemTemp.createTempSync('boardflow_pdf_test');
    AssetStore.rootForTesting = tmp.path;
    Pdfrx.cacheDirectoryPath = tmp.path; // no path_provider in unit tests
    // Desktop unit tests need a native PDFium (the app bundles its own).
    Pdfrx.pdfiumModulePath ??= _pdfium;
  });
  tearDownAll(() {
    AssetStore.rootForTesting = null;
    tmp.deleteSync(recursive: true);
  });

  test('rejects files that are not PDFs (by signature, not extension)', () async {
    await expectLater(
      PdfImportService.import(Uint8List.fromList(utf8.encode('<html>not a pdf</html>')), fileName: 'x.pdf'),
      throwsA(isA<PdfImportException>()),
    );
    expect(PdfImportService.looksLikePdf(Uint8List.fromList(utf8.encode('%PDF-1.7\n...'))), isTrue);
  });

  test('page placement keeps aspect ratio inside the sheet', () {
    const portrait = PdfPageAttachment(
        docId: 'd', pageIndex: 0, pageCount: 1, sourceName: 'a', imagePath: 'p', wordsPath: null, aspectRatio: 595 / 842);
    expect(portrait.rect.width, closeTo(1095.4, 1)); // height-limited
    expect(portrait.rect.height, closeTo(1550, 0.1));
    const landscape = PdfPageAttachment(
        docId: 'd', pageIndex: 0, pageCount: 1, sourceName: 'a', imagePath: 'p', wordsPath: null, aspectRatio: 842 / 595);
    expect(landscape.rect.width, 1100);
    expect(landscape.rect.height, closeTo(1100 / (842 / 595), 0.1));
  });

  test('page JSON round-trips the PDF attachment; old pages have none', () {
    const pdf = PdfPageAttachment(
        docId: 'd', pageIndex: 2, pageCount: 9, sourceName: 'bio.pdf', imagePath: 'd/page_3.png', wordsPath: 'd/page_3.words.json', aspectRatio: 0.7);
    const page = PageModel(id: 'p', pageNumber: 1, pdf: pdf);
    final back = PageModel.fromJson(jsonDecode(jsonEncode(page.toJson())) as Map<String, dynamic>);
    expect(back.pdf!.sourceName, 'bio.pdf');
    expect(back.pdf!.pageIndex, 2);
    expect(PageModel.fromJson({'id': 'old', 'pageNumber': 1}).pdf, isNull);
  });

  group('highlight-to-look-up on a PDF page (word index fixture)', () {
    // A page with one line: "Mitochondria are the powerhouse of the cell".
    late PdfPageAttachment pdf;
    final words = <PdfWord>[];

    setUpAll(() {
      const line = ['Mitochondria', 'are', 'the', 'powerhouse', 'of', 'the', 'cell'];
      double x = 0.10;
      for (final w in line) {
        final width = w.length * 0.012;
        words.add(PdfWord(w, Rect.fromLTRB(x, 0.20, x + width, 0.22)));
        x += width + 0.01;
      }
      Directory('${tmp.path}/fixture').createSync(recursive: true);
      File('${tmp.path}/fixture/page_1.words.json')
          .writeAsStringSync(jsonEncode([for (final w in words) w.toRow()]));
      pdf = const PdfPageAttachment(
        docId: 'fixture',
        pageIndex: 0,
        pageCount: 1,
        sourceName: 'biology.pdf',
        imagePath: 'fixture/page_1.png',
        wordsPath: 'fixture/page_1.words.json',
        aspectRatio: 1100 / 1550,
      );
    });

    ({ProviderContainer c, WhiteboardNotifier n}) board() {
      final c = ProviderContainer();
      final n = c.read(whiteboardControllerProvider.notifier);
      final p = ProjectModel.createEmpty();
      n.loadProject(p.copyWith(pages: [p.pages.first.copyWith(pdf: pdf)]));
      return (c: c, n: n);
    }

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

    test('highlighting a word offers it for look-up, with context', () async {
      final b = board();
      addTearDown(b.c.dispose);
      final target = words.firstWhere((w) => w.text == 'powerhouse');
      b.n.addStroke(highlight(pdf.toBoard(target.rect)));
      await settle();
      final lookup = b.c.read(whiteboardControllerProvider).pdfLookup;
      expect(lookup, isNotNull);
      expect(lookup!.text, 'powerhouse');
      expect(lookup.context, 'Mitochondria are the powerhouse of the cell');
      expect(b.c.read(whiteboardControllerProvider).shapeSuggestion, isNull,
          reason: 'a straight highlighter stroke must not be offered as a "line" shape');
    });

    test('the offer goes away when you keep writing', () async {
      final b = board();
      addTearDown(b.c.dispose);
      b.n.addStroke(highlight(pdf.toBoard(words.first.rect)));
      await settle();
      expect(b.c.read(whiteboardControllerProvider).pdfLookup, isNotNull);
      b.n.addStroke(Stroke(
        id: 'pen',
        points: [StrokePoint(x: 500, y: 900, timestamp: 0), StrokePoint(x: 520, y: 920, timestamp: 1)],
        colorValue: 0xFF000000,
        width: 3,
        toolType: ToolType.pen,
      ));
      expect(b.c.read(whiteboardControllerProvider).pdfLookup, isNull);
    });

    test('pen/marker strokes on a PDF never trigger a look-up', () async {
      final b = board();
      addTearDown(b.c.dispose);
      final s = highlight(pdf.toBoard(words.first.rect));
      b.n.addStroke(s.copyWith(id: 'm', toolType: ToolType.marker));
      await settle();
      expect(b.c.read(whiteboardControllerProvider).pdfLookup, isNull);
    });

    test('importing pages into a board inserts them after the current page', () {
      final b = board();
      addTearDown(b.c.dispose);
      b.n.insertPages([
        PageModel(id: 'a', pageNumber: 0, pdf: pdf),
        PageModel(id: 'b', pageNumber: 0, pdf: pdf),
      ]);
      final project = b.c.read(whiteboardControllerProvider).project;
      expect(project.pages.length, 3);
      expect(project.currentPageIndex, 1);
      expect(project.pages.map((p) => p.pageNumber), [1, 2, 3]);
    });

    test('clearing a PDF page removes the ink but keeps the PDF', () {
      final b = board();
      addTearDown(b.c.dispose);
      b.n.addStroke(highlight(pdf.toBoard(words.first.rect)));
      b.n.clearCurrentPage();
      final page = b.c.read(whiteboardControllerProvider).project.currentPage;
      expect(page.strokes, isEmpty);
      expect(page.pdf, isNotNull);
    });

    test('export covers the whole PDF page', () {
      final page = PageModel(id: 'p', pageNumber: 1, pdf: pdf);
      expect(ExportService.exportRegion(page).contains(pdf.rect.bottomRight - const Offset(1, 1)), isTrue);
    });

    testWidgets('look-up bar shows the word and Meaning / Explain', (tester) async {
      final b = board();
      addTearDown(b.c.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: b.c,
        child: const MaterialApp(home: Scaffold(body: PdfLookupOverlay())),
      ));
      expect(find.text('Meaning'), findsNothing);
      await tester.runAsync(() async {
        b.n.addStroke(highlight(pdf.toBoard(words.last.rect)));
        await settle();
      });
      await tester.pump();
      expect(find.textContaining('cell'), findsOneWidget);
      expect(find.text('Meaning'), findsOneWidget);
      expect(find.text('Explain'), findsOneWidget);
      // Signed out in tests: tapping asks the user to sign in instead of failing silently.
      await tester.tap(find.text('Meaning'));
      await tester.pump();
      expect(find.textContaining('Sign in with Google'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      expect(find.text('Meaning'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('real PDF import (PDFium)', skip: _pdfium == null ? 'Set PDFIUM_PATH to a libpdfium.so to run' : null, () {
    late PdfImportResult result;

    setUpAll(() async {
      result = await PdfImportService.import(await makePdf(), fileName: 'biology.pdf');
    });

    test('import is lazy: pages render on first request and are then cached', () async {
      expect(result.pages.length, 2);
      expect(result.hasText, isTrue);
      final p1 = result.pages[0].pdf!;
      expect(p1.pdfPath, isNotNull);
      expect(PdfPageRenderer.instance.cachedImagePath(p1), isNull, reason: 'not rendered during import');
      final path = await PdfPageRenderer.instance.ensureImage(p1);
      expect(path, isNotNull);
      expect(PdfPageRenderer.instance.cachedImagePath(p1), path, reason: 'cached after first render');
      expect(p1.pageIndex, 0);
      expect(p1.pageCount, 2);
      expect(p1.aspectRatio, closeTo(595.28 / 841.89, 0.01));
      final png = File(path!).readAsBytesSync();
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(result.pages[1].pdf!.aspectRatio, greaterThan(1), reason: 'landscape page');
    });

    test('indexes words with positions in reading order', () async {
      final words = await PdfTextIndex.words(result.pages[0].pdf!);
      final texts = words.map((w) => w.text).toList();
      expect(texts.first, 'Photosynthesis');
      expect(texts, containsAllInOrder(['light', 'energy', 'into', 'chemical']));
      final title = words.first.rect;
      expect(title.top, lessThan(0.15), reason: 'title is near the top of the page');
      expect(title.left, lessThan(0.2));
    });

    test('a highlighter stroke over a word returns that word plus context', () async {
      final pdf = result.pages[0].pdf!;
      final words = await PdfTextIndex.words(pdf);
      final chemical = words.firstWhere((w) => w.text == 'chemical');
      final found = await PdfTextIndex.forStroke(pdf, highlight(pdf.toBoard(chemical.rect)));
      expect(found, isNotNull);
      expect(found!.text, 'chemical');
      expect(found.context, contains('light energy into chemical energy'));
    });

    test('a highlight across a phrase returns the whole phrase', () async {
      final pdf = result.pages[0].pdf!;
      final words = await PdfTextIndex.words(pdf);
      final a = words.firstWhere((w) => w.text == 'light');
      final b = words.firstWhere((w) => w.text == 'energy');
      final span = pdf.toBoard(a.rect).expandToInclude(pdf.toBoard(b.rect));
      final found = await PdfTextIndex.forStroke(pdf, highlight(span));
      expect(found!.text, 'light energy');
    });

    test('highlighting empty space on a text page offers nothing', () async {
      final pdf = result.pages[0].pdf!;
      final r = pdf.rect;
      final empty = Rect.fromLTWH(r.left + 50, r.bottom - 200, 200, 20);
      expect(await PdfTextIndex.forStroke(pdf, highlight(empty)), isNull);
    });

    test('the look-up prompt carries the word and its context', () async {
      final pdf = result.pages[0].pdf!;
      final words = await PdfTextIndex.words(pdf);
      final w = words.firstWhere((w) => w.text == 'glucose.');
      final found = (await PdfTextIndex.forStroke(pdf, highlight(pdf.toBoard(w.rect))))!;
      final msgs = await TextLookupService.buildMessages(LookupAction.meaning, found);
      final text = ((msgs.last['content'] as List).first as Map)['text'] as String;
      expect(text, contains('Highlighted text: "glucose."'));
      expect(text, contains('stored in glucose'));
      expect((msgs.last['content'] as List).length, 1, reason: 'text PDFs need no image');
    });

    test('a scanned page (no text) falls back to a cropped image', () async {
      final scanned = PdfPageAttachment(
        docId: result.pages[0].pdf!.docId,
        pageIndex: 0,
        pageCount: 1,
        sourceName: 'scan.pdf',
        imagePath: result.pages[0].pdf!.imagePath,
        wordsPath: null,
        aspectRatio: result.pages[0].pdf!.aspectRatio,
      );
      final r = scanned.rect;
      final found = await PdfTextIndex.forStroke(scanned, highlight(Rect.fromLTWH(r.left + 80, r.top + 80, 300, 30)));
      expect(found, isNotNull);
      expect(found!.hasText, isFalse);
      final msgs = await TextLookupService.buildMessages(LookupAction.explain, found);
      final content = msgs.last['content'] as List;
      expect(content.any((p) => (p as Map)['type'] == 'image_url'), isTrue);
    });
  });
}
