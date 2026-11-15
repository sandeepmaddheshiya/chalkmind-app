// Headless performance benchmarks for the whiteboard engine.
//
// These measure UI-thread (Dart) cost of the hot paths on a large board.
// They do NOT measure GPU rasterization; use `flutter run --profile` with
// DevTools for frame raster timings on a real device.
//
// Run:  flutter test test/perf/engine_benchmark_test.dart
// Results are printed as `BENCH <name>: <value>` lines and the assertions use
// generous budgets so the suite catches order-of-magnitude regressions
// without being flaky on slower CI machines.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_point.dart';
import 'package:boardflow/features/whiteboard/models/text_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/rendering/board_painter.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const int kStrokeCount = 2000;
const int kPointsPerStroke = 60;
const int kTextCount = 200;

List<Stroke> _makeStrokes(int count, {int seed = 7}) {
  final rnd = math.Random(seed);
  return List.generate(count, (i) {
    final ox = rnd.nextDouble() * 4000;
    final oy = rnd.nextDouble() * 4000;
    return Stroke(
      id: 's$i',
      points: List.generate(kPointsPerStroke, (j) {
        return StrokePoint(
          x: ox + j * 2.0 + rnd.nextDouble() * 3,
          y: oy + math.sin(j / 5) * 20,
          timestamp: j,
        );
      }),
      colorValue: 0xFF111827,
      width: 3.5,
      toolType: ToolType.pen,
    );
  });
}

List<TextObject> _makeTexts(int count) => List.generate(
      count,
      (i) => TextObject(
        id: 't$i',
        text: 'Note number $i\nsecond line',
        position: Offset((i * 37) % 4000, (i * 91) % 4000),
        colorValue: 0xFF111827,
      ),
    );

/// Returns median microseconds over [runs] after [warmup] runs.
double _medianUs(void Function() body, {int runs = 15, int warmup = 3}) {
  for (int i = 0; i < warmup; i++) {
    body();
  }
  final samples = <int>[];
  for (int i = 0; i < runs; i++) {
    final sw = Stopwatch()..start();
    body();
    sw.stop();
    samples.add(sw.elapsedMicroseconds);
  }
  samples.sort();
  return samples[samples.length ~/ 2].toDouble();
}

void _report(String name, double us) {
  // ignore: avoid_print
  print('BENCH $name: ${(us / 1000).toStringAsFixed(3)} ms');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Engine benchmarks ($kStrokeCount strokes x $kPointsPerStroke pts, $kTextCount texts)', () {
    late List<Stroke> strokes;
    late List<TextObject> texts;

    setUp(() {
      strokes = _makeStrokes(kStrokeCount);
      texts = _makeTexts(kTextCount);
      // Prime cached paths / bounds as the live app would after first paint.
      for (final s in strokes) {
        s.path;
        s.bounds;
      }
    });

    test('full board repaint (record picture)', () {
      final us = _medianUs(() {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        BoardPainter(strokes: strokes, shapes: const [], texts: texts)
            .paint(canvas, const Size(1920, 1080));
        recorder.endRecording().dispose();
      });
      _report('board_repaint_full', us);
      expect(us, lessThan(250000));
    });

    test('text bounds for all texts (selection / erase hit-testing)', () {
      final us = _medianUs(() {
        for (final t in texts) {
          t.bounds;
        }
      });
      _report('text_bounds_all', us);
    });

    test('single eraser sample against whole board', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(whiteboardControllerProvider.notifier);
      final project = ProjectModel.createEmpty();
      notifier.loadProject(project.copyWith(pages: [
        project.pages.first.copyWith(strokes: strokes, texts: texts),
      ]));
      // Point in empty space: measures the pure scan cost per pointer move.
      final us = _medianUs(() => notifier.eraseAtPoint(const Offset(-500, -500)));
      _report('erase_sample_miss', us);
    });

    test('commit stroke on large board (incl. auto shape + auto math)', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(whiteboardControllerProvider.notifier);
      final project = ProjectModel.createEmpty();
      notifier.loadProject(project.copyWith(pages: [
        project.pages.first.copyWith(strokes: strokes),
      ]));
      int n = 0;
      final us = _medianUs(() {
        notifier.addStroke(_makeStrokes(1, seed: 1000 + n++).first
            .copyWith(id: 'new${n}_${DateTime.now().microsecondsSinceEpoch}'));
      });
      _report('commit_stroke', us);
    });

    test('undo + redo on large board', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(whiteboardControllerProvider.notifier);
      final project = ProjectModel.createEmpty();
      notifier.loadProject(project.copyWith(pages: [
        project.pages.first.copyWith(strokes: strokes),
      ]));
      notifier.setAutoMath(false);
      notifier.setAutoShape(false);
      notifier.addStroke(_makeStrokes(1, seed: 99).first.copyWith(id: 'u1'));
      final us = _medianUs(() {
        notifier.undo();
        notifier.redo();
      });
      _report('undo_redo_pair', us);
    });

    test('marquee select all on large board', () {
      final page = PageModel(id: 'p', pageNumber: 1, strokes: strokes, texts: texts);
      const marquee = Rect.fromLTWH(0, 0, 2000, 2000);
      final us = _medianUs(() {
        final ids = <String>{};
        for (final t in page.texts) {
          if (marquee.overlaps(t.bounds)) ids.add(t.id);
        }
        for (final s in page.strokes) {
          if (marquee.overlaps(s.bounds)) ids.add(s.id);
        }
      });
      _report('marquee_select', us);
    });

    test('save: serialize project to JSON', () {
      final project = ProjectModel.createEmpty();
      final p = project.copyWith(pages: [
        project.pages.first.copyWith(strokes: strokes, texts: texts),
      ]);
      final usMap = _medianUs(() => p.toJson(), runs: 5, warmup: 1);
      _report('to_json_maps_only', usMap);
      late String json;
      final us = _medianUs(() => json = jsonEncode(p.toJson()), runs: 5, warmup: 1);
      _report('serialize_json', us);
      // ignore: avoid_print
      print('BENCH serialized_size: ${(json.length / 1024 / 1024).toStringAsFixed(2)} MB');
      final us2 = _medianUs(
        () => ProjectModel.fromJson(jsonDecode(json) as Map<String, dynamic>),
        runs: 5,
        warmup: 1,
      );
      _report('deserialize_json', us2);
    });
  });
}
