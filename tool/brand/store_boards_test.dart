// Builds the sample boards used for Play Store screenshots (not part of the
// test suite). Run:  OUT=/tmp/boards flutter test tool/brand/store_boards_test.dart
// then copy the files into the app's app_flutter/boardflow_projects folder
// on a debug build (adb push + run-as) and capture screens; compose them
// with tool/brand/store_screenshots.py.
import 'dart:convert';
import 'dart:io';

import 'package:boardflow/features/whiteboard/models/background_style.dart';
import 'package:boardflow/features/whiteboard/models/page_model.dart';
import 'package:boardflow/features/whiteboard/models/plot_model.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/shape_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/models/text_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/recognition/handwriting_stroke_generator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const ink = 0xFF111827, blue = 0xFF1D4ED8, green = 0xFF047857, red = 0xFFDC2626;
int _id = 0;
String id() => 'store-${_id++}';

List<Stroke> hw(String text, double x, double y, {double h = 58, int color = ink, double w = 4.2}) =>
    HandwritingStrokeGenerator.generateHandwrittenStrokes(
      text: text, startPosition: Offset(x, y), characterHeight: h, colorValue: color, strokeWidth: w);

TextObject title(String t, {double y = 70}) =>
    TextObject(id: id(), text: t, position: Offset(90, y), fontSize: 44, colorValue: 0xFF0F3D36, isBold: true);

TextObject note(String t, double x, double y, {int color = 0xFF6B7280, double size = 26}) =>
    TextObject(id: id(), text: t, position: Offset(x, y), fontSize: size, colorValue: color);

ProjectModel board(String name, PageModel page, DateTime at) => ProjectModel.createEmpty(title: name)
    .copyWith(pages: [page], updatedAt: at, createdAt: at.subtract(const Duration(days: 2)));

void main() {
  test('store boards', () {
    final out = Directory(Platform.environment['OUT'] ?? '/tmp/store_boards')..createSync(recursive: true);
    final now = DateTime.now();

    // 1. Linear equations: worked lines, and "12 × 8" waiting for its "=".
    final algebra = PageModel(
      id: id(), pageNumber: 1,
      background: const CanvasBackground(style: BackgroundStyle.ruled, spacing: 56, patternColorValue: 0x2A1D4ED8),
      texts: [title('Linear equations'), note('Solve for x', 92, 140)],
      strokes: [
        ...hw('3x + 5 = 20', 120, 230),
        ...hw('3x = 15', 120, 330),
        ...hw('x = 5', 120, 430, color: green),
        ...hw('2(x - 4) = 10', 120, 590),
        ...hw('2x - 8 = 10', 120, 690),
        ...hw('2x = 18', 120, 790),
        ...hw('x = 9', 120, 890, color: green),
        ...hw('12 × 8', 120, 1060, color: blue),
      ],
    );

    // 2. A student's working with a slip on line 2.
    final check = PageModel(
      id: id(), pageNumber: 1,
      background: const CanvasBackground(style: BackgroundStyle.grid, spacing: 40),
      texts: [title('Homework: Q4'), note('Solve 3(x − 2) = 2x + 5', 92, 140)],
      strokes: [
        ...hw('3(x - 2) = 2x + 5', 120, 240),
        ...hw('3x - 2 = 2x + 5', 120, 350),
        ...hw('x = 7', 120, 460),
      ],
    );

    // 3. Pythagoras with a neat triangle.
    final pyth = PageModel(
      id: id(), pageNumber: 1,
      texts: [title('Pythagoras')],
      shapes: [
        ShapeObject(id: id(), shapeType: ShapeType.triangle, start: const Offset(160, 220), end: const Offset(700, 640),
            strokeColorValue: blue, strokeWidth: 5,
            customVertices: const [Offset(160, 220), Offset(160, 640), Offset(700, 640)]),
        ShapeObject(id: id(), shapeType: ShapeType.rectangle, start: const Offset(160, 600), end: const Offset(200, 640),
            strokeColorValue: blue, strokeWidth: 3),
      ],
      strokes: [
        ...hw('a = 3', 30 + 50, 400, h: 46, color: blue),
        ...hw('b = 4', 370, 670, h: 46, color: blue),
        ...hw('c', 450, 380, h: 46, color: red),
        ...hw('c² = a² + b²', 120, 800),
        ...hw('c² = 9 + 16', 120, 900),
        ...hw('c² = 25', 120, 1000),
        ...hw('c = 5', 120, 1100, color: green),
      ],
    );

    // 4. Graphs.
    final graphs = PageModel(
      id: id(), pageNumber: 1,
      background: const CanvasBackground(style: BackgroundStyle.grid, spacing: 40),
      texts: [title('Quadratic graphs')],
      strokes: [...hw('y = x² - 4', 120, 150, color: blue)],
      plots: [
        PlotObject(id: id(), equation: 'y = x^2 - 4', rect: const Rect.fromLTWH(110, 260, 980, 720),
            xMin: -5, xMax: 5, yMin: -6, yMax: 8),
      ],
    );

    final projects = [
      board('Linear equations · Class 8', algebra, now),
      board('Homework check · Q4', check, now.subtract(const Duration(hours: 3))),
      board('Pythagoras · Geometry', pyth, now.subtract(const Duration(days: 1))),
      board('Quadratic graphs', graphs, now.subtract(const Duration(days: 2))),
    ];
    for (final p in projects) {
      File('${out.path}/${p.id}.bf').writeAsStringSync(jsonEncode(p.toJson()));
      File('${out.path}/${p.id}.meta').writeAsStringSync(jsonEncode(p.summary().toJson()));
      // ignore: avoid_print
      print('${p.title} -> ${p.id}');
    }
  });
}
