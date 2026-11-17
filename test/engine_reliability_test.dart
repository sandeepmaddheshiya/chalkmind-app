import 'dart:convert';

import 'package:boardflow/core/export/export_service.dart';
import 'package:boardflow/core/storage/project_storage_service.dart';
import 'package:boardflow/features/whiteboard/history/board_command.dart';
import 'package:boardflow/features/whiteboard/history/history_manager.dart';
import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/plot_model.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/text_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/recognition/handwriting_math_engine.dart';
import 'package:boardflow/features/whiteboard/recognition/handwriting_stroke_generator.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Stroke line(String id, Offset a, Offset b, {int n = 20}) => Stroke(
      id: id,
      points: [
        for (int i = 0; i <= n; i++)
          StrokePoint.fromOffset(Offset.lerp(a, b, i / n)!, timestamp: i),
      ],
      colorValue: 0xFF000000,
      width: 3,
      toolType: ToolType.pen,
    );

PlotObject plot(String id) =>
    PlotObject(id: id, equation: 'y = x^2', rect: const Rect.fromLTWH(600, 600, 300, 200));

({ProviderContainer c, WhiteboardNotifier n}) setup({List<Stroke> strokes = const []}) {
  final c = ProviderContainer();
  final n = c.read(whiteboardControllerProvider.notifier);
  final p = ProjectModel.createEmpty();
  n.loadProject(p.copyWith(pages: [p.pages.first.copyWith(strokes: strokes)]));
  // Keep tests deterministic: no recognition side effects.
  n.setAutoMath(false);
  n.setAutoShape(false);
  return (c: c, n: n);
}

PageModel pageOf(ProviderContainer c) => c.read(whiteboardControllerProvider).project.currentPage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ReplaceElementsCommand', () {
    test('undo restores deleted elements at their original z-order', () {
      final strokes = [for (int i = 0; i < 5; i++) line('s$i', Offset(i * 10, 0), Offset(i * 10, 50))];
      var page = PageModel(id: 'p', pageNumber: 1, strokes: strokes);
      final h = HistoryManager();
      page = h.execute(DeleteElementsCommand(strokes: [strokes[3], strokes[1]]), page);
      expect(page.strokes.map((s) => s.id), ['s0', 's2', 's4']);
      page = h.undo(page);
      expect(page.strokes.map((s) => s.id), ['s0', 's1', 's2', 's3', 's4']);
      page = h.redo(page);
      expect(page.strokes.map((s) => s.id), ['s0', 's2', 's4']);
    });

    test('MoveElementsCommand moves and restores strokes, texts and plots', () {
      final s = line('s', Offset.zero, const Offset(10, 0));
      const t = TextObject(id: 't', text: 'hi', position: Offset(5, 5), colorValue: 0);
      var page = PageModel(id: 'p', pageNumber: 1, strokes: [s], texts: const [t], plots: [plot('g')]);
      final h = HistoryManager();
      page = h.execute(MoveElementsCommand({'s', 't', 'g'}, const Offset(100, 50)), page);
      expect(page.strokes.first.points.first.x, closeTo(100, 1e-9));
      expect(page.texts.first.position, const Offset(105, 55));
      expect(page.plots.first.rect.topLeft, const Offset(700, 650));
      page = h.undo(page);
      expect(page.strokes.first.points.first.x, closeTo(0, 1e-9));
      expect(page.texts.first.position, const Offset(5, 5));
      expect(page.plots.first.rect.topLeft, const Offset(600, 600));
    });
  });

  group('WhiteboardNotifier editing', () {
    test('selection move is a single undoable step', () {
      final t = setup(strokes: [line('a', Offset.zero, const Offset(50, 0))]);
      addTearDown(t.c.dispose);
      t.n.setSelectedObjects({'a'});
      t.n.translateSelected(const Offset(30, 40));
      expect(pageOf(t.c).strokes.first.points.first.offset, const Offset(30, 40));
      t.n.undo();
      expect(pageOf(t.c).strokes.first.points.first.offset, Offset.zero);
      expect(t.c.read(whiteboardControllerProvider).canUndo, isFalse);
    });

    test('an eraser gesture across many strokes is one undo step', () {
      final strokes = [for (int i = 0; i < 6; i++) line('v$i', Offset(i * 30.0, 0), Offset(i * 30.0, 100))];
      final t = setup(strokes: strokes);
      addTearDown(t.c.dispose);
      t.n.setTool(ToolType.strokeEraser);
      t.n.beginEraseGesture();
      // One fast swipe sampled at only two points: interpolation must still
      // catch every vertical line in between.
      t.n.eraseAlong(const Offset(-10, 50), const Offset(160, 50));
      t.n.endEraseGesture();
      expect(pageOf(t.c).strokes, isEmpty);
      t.n.undo();
      expect(pageOf(t.c).strokes.map((s) => s.id), [for (int i = 0; i < 6; i++) 'v$i']);
      expect(t.c.read(whiteboardControllerProvider).canUndo, isFalse);
    });

    test('area eraser removes only the ink under the eraser and is undoable', () {
      final t = setup(strokes: [line('h', Offset.zero, const Offset(400, 0), n: 80)]);
      addTearDown(t.c.dispose);
      t.n.setTool(ToolType.areaEraser);
      t.n.beginEraseGesture();
      t.n.eraseAlong(const Offset(200, -30), const Offset(200, 30));
      t.n.endEraseGesture();
      final pieces = pageOf(t.c).strokes;
      expect(pieces.length, 2, reason: 'stroke split into left and right parts');
      expect(pieces.every((s) => s.id != 'h'), isTrue);
      final xs = [for (final s in pieces) for (final p in s.points) p.x];
      expect(xs.any((x) => (x - 200).abs() < 15), isFalse, reason: 'ink under eraser removed');
      t.n.undo();
      expect(pageOf(t.c).strokes.single.id, 'h');
    });

    test('undo history is kept per page across page switches', () {
      final t = setup();
      addTearDown(t.c.dispose);
      t.n.addStroke(line('p1', Offset.zero, const Offset(10, 10)));
      t.n.addNewPage();
      expect(t.c.read(whiteboardControllerProvider).canUndo, isFalse);
      t.n.addStroke(line('p2', Offset.zero, const Offset(10, 10)));
      t.n.previousPage();
      expect(t.c.read(whiteboardControllerProvider).canUndo, isTrue);
      t.n.undo();
      expect(pageOf(t.c).strokes, isEmpty);
      t.n.nextPage();
      expect(pageOf(t.c).strokes.single.id, 'p2');
      expect(t.c.read(whiteboardControllerProvider).canUndo, isTrue);
    });

    test('plots participate in history, clear page and delete selection', () {
      final t = setup();
      addTearDown(t.c.dispose);
      t.n.addPlot(plot('g1'));
      expect(pageOf(t.c).plots.length, 1);
      t.n.undo();
      expect(pageOf(t.c).plots, isEmpty);
      t.n.redo();
      t.n.clearCurrentPage();
      expect(pageOf(t.c).plots, isEmpty, reason: 'clear page removes graphs too');
      t.n.undo();
      expect(pageOf(t.c).plots.single.id, 'g1');
      t.n.setSelectedObjects({'g1'});
      t.n.deleteSelected();
      expect(pageOf(t.c).plots, isEmpty);
      t.n.undo();
      expect(pageOf(t.c).plots.single.id, 'g1');
    });

    test('copy/paste and duplicate create offset copies with new ids, one undo each', () {
      final t = setup(strokes: [line('a', Offset.zero, const Offset(50, 0))]);
      addTearDown(t.c.dispose);
      t.n.setSelectedObjects({'a'});
      t.n.copySelected();
      t.n.pasteClipboard();
      var page = pageOf(t.c);
      expect(page.strokes.length, 2);
      final pasted = page.strokes.last;
      expect(pasted.id, isNot('a'));
      expect(pasted.points.first.offset, const Offset(24, 24));
      expect(t.c.read(whiteboardControllerProvider).selectedObjectIds, {pasted.id});
      t.n.pasteClipboard(); // cascades further
      expect(pageOf(t.c).strokes.last.points.first.offset, const Offset(48, 48));
      t.n.duplicateSelected();
      expect(pageOf(t.c).strokes.length, 4);
      t.n.undo();
      t.n.undo();
      t.n.undo();
      expect(pageOf(t.c).strokes.single.id, 'a');
      expect(t.c.read(whiteboardControllerProvider).selectedObjectIds, isEmpty,
          reason: 'selection of undone elements is pruned');
    });

    test('cut removes and paste restores elsewhere', () {
      final t = setup(strokes: [line('a', Offset.zero, const Offset(50, 0))]);
      addTearDown(t.c.dispose);
      t.n.setSelectedObjects({'a'});
      t.n.cutSelected();
      expect(pageOf(t.c).strokes, isEmpty);
      t.n.pasteClipboard();
      expect(pageOf(t.c).strokes.length, 1);
    });

    test('selectAll includes every element type', () {
      final t = setup(strokes: [line('a', Offset.zero, const Offset(50, 0))]);
      addTearDown(t.c.dispose);
      t.n.addText(const TextObject(id: 'tx', text: 'x', position: Offset.zero, colorValue: 0));
      t.n.addPlot(plot('g'));
      t.n.selectAll();
      final s = t.c.read(whiteboardControllerProvider);
      expect(s.selectedObjectIds, {'a', 'tx', 'g'});
      expect(s.currentTool, ToolType.select);
    });

    test('loading a project resets transient AI/selection state', () {
      final t = setup(strokes: [line('a', Offset.zero, const Offset(50, 0))]);
      addTearDown(t.c.dispose);
      t.n.setSelectedObjects({'a'});
      t.n.setZoomAndPan(2.0, const Offset(10, 10));
      t.n.loadProject(ProjectModel.createEmpty());
      final s = t.c.read(whiteboardControllerProvider);
      expect(s.selectedObjectIds, isEmpty);
      expect(s.zoomScale, 1.0);
      expect(s.aiErrorMessage, isNull);
      expect(s.canUndo, isFalse);
    });

    test('auto-solve while signed out says so once instead of failing silently', () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(whiteboardControllerProvider.notifier);
      n.loadProject(ProjectModel.createEmpty());
      n.setAutoShape(false);
      // A triangle-sized diagram stroke plus "x =" (two short horizontal dashes):
      // local maths can't solve it, so it needs the AI solver.
      n.addStroke(line('tri', const Offset(0, 0), const Offset(200, 200), n: 30));
      n.addStroke(line('x1', const Offset(300, 100), const Offset(320, 120)));
      n.addStroke(line('eq1', const Offset(340, 105), const Offset(370, 105)));
      n.addStroke(line('eq2', const Offset(340, 118), const Offset(370, 118)));
      await Future<void>.delayed(Duration.zero); // solving is asynchronous
      final msg = c.read(whiteboardControllerProvider).aiErrorMessage;
      expect(msg, isNotNull);
      expect(msg, contains('Sign in'));
      expect(c.read(whiteboardControllerProvider).isCalculatingMath, isFalse);
      n.dismissAiError();
      n.addStroke(line('eq3', const Offset(340, 130), const Offset(370, 130)));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(whiteboardControllerProvider).aiErrorMessage, isNull, reason: 'only once per session');
    });

    test('answers the handwriting writer cannot draw are placed as typed text', () {
      final t = setup();
      addTearDown(t.c.dispose);
      expect(HandwritingStrokeGenerator.canWrite('108'), isTrue);
      expect(HandwritingStrokeGenerator.canWrite('2H₂ + O₂ → 2H₂O'), isFalse);
      t.c.read(whiteboardControllerProvider.notifier).state = t.c.read(whiteboardControllerProvider).copyWith(
            handwritingMathResult: () => const HandwritingMathResult(
              expression: 'H₂ + O₂ →',
              answer: '2H₂ + O₂ → 2H₂O',
              insertPosition: Offset(400, 100),
              characterHeight: 40,
              strokeColorValue: 0xFF000000,
              strokeWidth: 3,
              direction: Offset(1, 0),
              normal: Offset(0, 1),
            ),
          );
      t.n.acceptHandwrittenMath();
      final page = pageOf(t.c);
      expect(page.strokes, isEmpty, reason: 'no scribbled placeholder strokes');
      expect(page.texts.single.text, '2H₂ + O₂ → 2H₂O');
      expect(page.texts.single.position, const Offset(400, 100));
      t.n.undo();
      expect(pageOf(t.c).texts, isEmpty);
    });

    test('Solve Selected while signed out reports a clear error', () async {
      final t = setup(strokes: [
        line('a', Offset.zero, const Offset(50, 0)),
        line('b', const Offset(0, 20), const Offset(50, 20)),
      ]);
      addTearDown(t.c.dispose);
      t.n.setSelectedObjects({'a', 'b'});
      await t.n.solveSelectedStrokes();
      final s = t.c.read(whiteboardControllerProvider);
      expect(s.isCalculatingMath, isFalse);
      expect(s.aiErrorMessage, contains('Sign in'));
      t.n.dismissAiError();
      expect(t.c.read(whiteboardControllerProvider).aiErrorMessage, isNull);
    });
  });

  group('Serialization', () {
    test('compact point format round-trips and stays backward compatible', () {
      final s = Stroke(
        id: 's',
        points: const [
          StrokePoint(x: 1.234567, y: 2.5, pressure: 0.51234, timestamp: 42),
          StrokePoint(x: 3, y: 4, timestamp: 43),
        ],
        colorValue: 0xFF123456,
        width: 2,
        toolType: ToolType.marker,
      );
      final json = jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>;
      expect(json.containsKey('pts'), isTrue);
      final back = Stroke.fromJson(json);
      expect(back.points.length, 2);
      expect(back.points.first.x, closeTo(1.23, 1e-9));
      expect(back.points.first.pressure, closeTo(0.512, 1e-9));
      expect(back.points.first.timestamp, 42);
      expect(back.toolType, ToolType.marker);

      // Legacy (v1) files store per-point objects under "points".
      final legacy = Stroke.fromJson({
        'id': 'old',
        'points': [
          {'x': 1, 'y': 2, 'pressure': 0.5, 'timestamp': 7},
        ],
        'colorValue': 1,
        'width': 3,
        'toolType': 'pen',
      });
      expect(legacy.points.single.offset, const Offset(1, 2));
    });

    test('project JSON records the current document version', () {
      final json = ProjectModel.createEmpty().toJson();
      expect(json['documentVersion'], ProjectModel.currentDocumentVersion);
    });
  });

  group('Export', () {
    test('export region covers the sheet and content below the fold', () {
      final page = PageModel(
        id: 'p',
        pageNumber: 1,
        strokes: [line('deep', const Offset(100, 1500), const Offset(200, 1500))],
        plots: [plot('g')],
      );
      final region = ExportService.exportRegion(page);
      expect(region.contains(const Offset(150, 1500)), isTrue);
      expect(region.bottom, greaterThan(1500));
      expect(region.contains(const Offset(900, 800)), isTrue, reason: 'plot included');
    });

    test('renders a page with a plot to PNG', () async {
      final page = PageModel(id: 'p', pageNumber: 1, plots: [plot('g')]);
      final bytes = await ExportService.renderPageToImage(page: page, pixelRatio: 0.5);
      expect(bytes.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  });

  test('boards autosave to the saved list shortly after changes (no Save needed)', () async {
    final saved = <ProjectModel>[];
    final c = ProviderContainer(overrides: [
      projectStorageProvider.overrideWithValue(_RecordingStorage(saved)),
    ]);
    addTearDown(c.dispose);
    final n = c.read(whiteboardControllerProvider.notifier);
    n.loadProject(ProjectModel.createEmpty(title: 'Autosaved'));
    n.setAutoMath(false);
    n.setAutoShape(false);
    n.addStroke(line('a', Offset.zero, const Offset(50, 0)));
    n.addStroke(line('b', Offset.zero, const Offset(0, 50)));
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(saved, isEmpty, reason: 'debounced while drawing');
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(saved.length, 1, reason: 'one save for a burst of edits');
    expect(saved.single.title, 'Autosaved');
    expect(saved.single.currentPage.strokes.length, 2);
  });
}

class _RecordingStorage extends ProjectStorageService {
  final List<ProjectModel> saved;
  _RecordingStorage(this.saved);
  @override
  Future<void> saveProject(ProjectModel project) async => saved.add(project);
}
