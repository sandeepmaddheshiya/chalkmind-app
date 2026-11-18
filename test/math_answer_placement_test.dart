// Auto-solve on real handwriting captured from a Galaxy Tab:
//   line 1: "2 + 2 ="        (strokes 0-5)
//   line 2: "y = 4 + 3"      (strokes 8-15)
//   line 3: "y ="            (strokes 16-17)
// Strokes 6-7 and 18 were answers written by the app; they're dropped here.
import 'dart:convert';
import 'dart:io';

import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/stroke_model.dart';
import 'package:boardflow/features/whiteboard/recognition/handwriting_math_engine.dart';
import 'package:boardflow/core/backend/backend.dart';
import 'package:boardflow/features/whiteboard/recognition/ai_math_service.dart';
import 'package:boardflow/features/whiteboard/recognition/ink_recognizer.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

List<Stroke> userStrokes() {
  final p = ProjectModel.fromJson(
    jsonDecode(File('test/fixtures/y_equals_board.json').readAsStringSync())
        as Map<String, dynamic>,
  );
  final all = p.pages.first.strokes;
  return [for (var i = 0; i < all.length; i++) if (i != 6 && i != 7 && i != 18) all[i]];
}

void main() {
  final strokes = userStrokes();
  // Indices into [strokes] (app-written strokes removed).
  const firstEquals = {4, 5};
  const secondEquals = {7, 8};

  group('"=" trigger', () {
    test('fires only when an "=" has just been finished', () {
      final fired = <int>[];
      for (var n = 2; n <= strokes.length; n++) {
        if (HandwritingMathEngine.justFinishedEqualSign(strokes.take(n).toList()) != null) {
          fired.add(n - 1);
        }
      }
      expect(fired, [5, 8], reason: 'after the 2nd bar of each "=" only');
    });

    test('an "=" whose bars tilt slightly opposite ways is still found', () {
      // Captured "24 × 15 =": one bar slopes a hair up, the other a hair down.
      // Their angles wrap (≈179° and ≈0°) and used to average to vertical.
      final p = ProjectModel.fromJson(
        jsonDecode(File('test/fixtures/equals_opposite_tilt_board.json').readAsStringSync())
            as Map<String, dynamic>,
      );
      final s = p.pages.first.strokes;
      final eq = HandwritingMathEngine.justFinishedEqualSign(s);
      expect(eq, isNotNull);
      expect(eq!.direction.dx, greaterThan(0.95), reason: 'horizontal, not vertical');
      expect(HandwritingMathEngine.lineBefore(eq, s), hasLength(8));
    });

    test('the stems of "4" and "+" are not a sideways "="', () {
      // Previously these parallel vertical strokes became an "=" and the
      // answer was written rotated 90° in the middle of the page.
      final upToPlus = strokes.take(13).toList();
      expect(HandwritingMathEngine.detectAngleInvariantEqualSign(upToPlus)?.consumedStrokeIds,
          isNot(containsAll([strokes[9].id, strokes[12].id])));
    });
  });

  group('answer placement', () {
    test('"2 + 2 =": right of the "=", same size and line as the digits', () {
      final s = strokes.take(6).toList();
      final eq = HandwritingMathEngine.justFinishedEqualSign(s)!;
      expect(eq.consumedStrokeIds, {for (final i in firstEquals) s[i].id});
      final line = HandwritingMathEngine.lineBefore(eq, s);
      expect(line.map((x) => x.id), [for (var i = 0; i < 4; i++) s[i].id]);

      final at = HandwritingMathEngine.placeAnswer(eq, line);
      final digits = line.first.bounds.expandToInclude(line[3].bounds);
      final eqRight = s[4].bounds.right > s[5].bounds.right ? s[4].bounds.right : s[5].bounds.right;
      expect(at.topLeft.dx, inInclusiveRange(eqRight + 5, eqRight + 50));
      // The two handwritten "2"s are 71 and 59 px tall.
      expect(at.height, inInclusiveRange(55, 75));
      expect(at.topLeft.dy, closeTo(digits.top, 15));
      expect(at.direction.dx, greaterThan(0.95), reason: 'written along the line');
    });

    test('second "=" uses only its own line', () {
      final s = strokes.take(9).toList();
      final eq = HandwritingMathEngine.justFinishedEqualSign(s)!;
      expect(eq.consumedStrokeIds, {for (final i in secondEquals) s[i].id});
      final line = HandwritingMathEngine.lineBefore(eq, s);
      expect(line.map((x) => x.id), [s[6].id], reason: 'just the "y"');
      final at = HandwritingMathEngine.placeAnswer(eq, line);
      expect(at.topLeft.dy, greaterThan(s[0].bounds.bottom), reason: 'not on line 1');
    });
  });

  group('readings to arithmetic', () {
    test('plain arithmetic is accepted and normalised', () {
      expect(HandwritingMathEngine.arithmeticFromReading('2+2'), '2+2');
      expect(HandwritingMathEngine.arithmeticFromReading('2 + 2 ='), '2+2');
      expect(HandwritingMathEngine.arithmeticFromReading('3x4'), '3*4');
      expect(HandwritingMathEngine.arithmeticFromReading('12 ÷ 4'), '12/4');
      expect(HandwritingMathEngine.arithmeticFromReading('1O + 5'), '10+5');
      expect(HandwritingMathEngine.arithmeticFromReading('7 − 2'), '7-2');
    });

    test('variables, words and bare numbers go to the AI', () {
      expect(HandwritingMathEngine.arithmeticFromReading('y'), isNull);
      expect(HandwritingMathEngine.arithmeticFromReading('2x+1'), isNull);
      expect(HandwritingMathEngine.arithmeticFromReading('12'), isNull);
      expect(HandwritingMathEngine.arithmeticFromReading('area'), isNull);
    });

    test('a top reading that needs the AI is not overruled by a lower guess', () {
      final s = strokes.take(9).toList();
      final eq = HandwritingMathEngine.justFinishedEqualSign(s)!;
      final at = HandwritingMathEngine.placeAnswer(eq, HandwritingMathEngine.lineBefore(eq, s));
      expect(HandwritingMathEngine.solveReadings(['y', '4+3'], at), isNull);
      expect(HandwritingMathEngine.solveReadings(['2+z', '2+2'], at), isNull);
      expect(HandwritingMathEngine.solveReadings(['2+2', '2+7'], at)!.answer, '4');
    });
  });

  group('notifier', () {
    tearDown(() => InkRecognizer.debugOverride = null);

    test('arithmetic read on the device is answered without the AI', () async {
      InkRecognizer.debugOverride = (_) async => ['2+2', '2+z'];
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(whiteboardControllerProvider.notifier);
      n.loadProject(ProjectModel.createEmpty());
      for (final s in strokes.take(6)) {
        n.addStroke(s);
      }
      await Future<void>.delayed(Duration.zero);
      final st = c.read(whiteboardControllerProvider);
      expect(st.handwritingMathResult?.answer, '4');
      expect(st.isCalculatingMath, isFalse);
      expect(st.handwritingMathResult!.insertPosition.dx, greaterThan(strokes[5].bounds.right));
    });

    group('AI only when the pen rests after "="', () {
      late int aiCalls;
      setUp(() {
        aiCalls = 0;
        AiBackend.isSignedIn = true;
        WhiteboardNotifier.aiIdleDelay = const Duration(milliseconds: 40);
        InkRecognizer.debugOverride = (_) async => ['y'];
        AiMathService.debugOverride = (_, at) async {
          aiCalls++;
          return null;
        };
      });
      tearDown(() {
        AiBackend.isSignedIn = false;
        WhiteboardNotifier.aiIdleDelay = const Duration(milliseconds: 1200);
        AiMathService.debugOverride = null;
      });

      ProviderContainer board() {
        final c = ProviderContainer();
        c.read(whiteboardControllerProvider.notifier).loadProject(ProjectModel.createEmpty());
        return c;
      }

      test('"y =" then a pause asks the AI once', () async {
        final c = board();
        addTearDown(c.dispose);
        final n = c.read(whiteboardControllerProvider.notifier);
        for (final s in strokes.take(9)) {
          n.addStroke(s);
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(aiCalls, 1);
      });

      test('writing on after "=" (the answer itself) asks nothing', () async {
        final c = board();
        addTearDown(c.dispose);
        final n = c.read(whiteboardControllerProvider.notifier);
        for (final s in strokes.take(9)) {
          n.addStroke(s);
        }
        n.addStroke(strokes[9]); // the "4" of "4 + 3", written straight away
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(aiCalls, 0);
      });
    });
  });
}
