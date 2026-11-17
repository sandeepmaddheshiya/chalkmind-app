// End-to-end interaction tests: real pointer gestures and key presses
// through the full WhiteboardScreen (canvas, toolbar, shortcuts, panels).
import 'package:boardflow/app/theme/theme.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/models/tool_type.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:boardflow/features/whiteboard/ui/whiteboard_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> pumpBoard(WidgetTester tester, {Size size = const Size(1400, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  final n = container.read(whiteboardControllerProvider.notifier);
  n.loadProject(ProjectModel.createEmpty(title: 'Test board'));
  n.setAutoMath(false);
  n.setAutoShape(false);

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: BoardTheme.lightTheme(), home: const WhiteboardScreen()),
  ));
  await tester.pump();
  return container;
}

/// Draws with a stylus so drawing works regardless of the current tool's
/// touch handling; [points] are global (screen) coordinates.
Future<void> drag(WidgetTester tester, List<Offset> points, {PointerDeviceKind kind = PointerDeviceKind.stylus}) async {
  final g = await tester.startGesture(points.first, kind: kind);
  for (final p in points.skip(1)) {
    await g.moveTo(p);
    await tester.pump(const Duration(milliseconds: 8));
  }
  await g.up();
  await tester.pump();
}

List<Offset> lineAcross(Offset a, Offset b, [int n = 12]) => [for (int i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];

Future<void> key(WidgetTester tester, LogicalKeyboardKey k, {bool ctrl = false, bool shift = false}) async {
  if (ctrl) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(k);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (ctrl) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

void main() {
  testWidgets('drawing with the pen commits a stroke; Ctrl+Z / Ctrl+Shift+Z undo and redo', (tester) async {
    final c = await pumpBoard(tester);
    await drag(tester, lineAcross(const Offset(300, 300), const Offset(500, 340)));
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes.length, 1);

    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes, isEmpty);
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true, shift: true);
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes.length, 1);
    await tester.pump(const Duration(seconds: 1)); // flush autosave debounce
  });

  testWidgets('select-drag moves the stroke once on release and is undoable', (tester) async {
    final c = await pumpBoard(tester);
    await drag(tester, lineAcross(const Offset(300, 300), const Offset(500, 300)));
    final before = c.read(whiteboardControllerProvider).project.currentPage.strokes.single.bounds;

    await key(tester, LogicalKeyboardKey.keyV);
    expect(c.read(whiteboardControllerProvider).currentTool, ToolType.select);
    await drag(tester, lineAcross(const Offset(400, 300), const Offset(400, 420), 6), kind: PointerDeviceKind.mouse);

    final after = c.read(whiteboardControllerProvider).project.currentPage.strokes.single.bounds;
    // 120 screen pixels, in page units at the fitted zoom.
    final zoom = c.read(whiteboardControllerProvider).zoomScale;
    expect(after.top - before.top, closeTo(120 / zoom, 2));
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    final undone = c.read(whiteboardControllerProvider).project.currentPage.strokes.single.bounds;
    expect(undone.top, closeTo(before.top, 0.5));
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('eraser swipe removes strokes as one undo step', (tester) async {
    final c = await pumpBoard(tester);
    for (int i = 0; i < 4; i++) {
      final x = 300.0 + i * 40;
      await drag(tester, lineAcross(Offset(x, 250), Offset(x, 400)));
    }
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes.length, 4);

    await key(tester, LogicalKeyboardKey.keyE);
    await drag(tester, [const Offset(280, 320), const Offset(460, 320)], kind: PointerDeviceKind.mouse);
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes, isEmpty);

    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes.length, 4);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Ctrl+A then Delete clears content; Ctrl+D duplicates', (tester) async {
    final c = await pumpBoard(tester);
    await drag(tester, lineAcross(const Offset(300, 300), const Offset(400, 300)));
    await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
    await key(tester, LogicalKeyboardKey.keyD, ctrl: true);
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes.length, 2);
    await key(tester, LogicalKeyboardKey.keyA, ctrl: true);
    await key(tester, LogicalKeyboardKey.delete);
    expect(c.read(whiteboardControllerProvider).project.currentPage.strokes, isEmpty);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('text tool adds text; tapping it again edits it', (tester) async {
    final c = await pumpBoard(tester);
    await key(tester, LogicalKeyboardKey.keyT);
    await tester.tapAt(const Offset(400, 400), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Area = πr²');
    await tester.tap(find.text('Add to Board'));
    await tester.pumpAndSettle();
    final texts = c.read(whiteboardControllerProvider).project.currentPage.texts;
    expect(texts.single.text, 'Area = πr²');

    // Canvas sits under the app bar with an identity transform, so the
    // screen<->canvas offset is the difference from the first tap.
    final toScreen = const Offset(400, 400) - texts.single.position;
    await tester.tapAt(texts.single.bounds.center + toScreen, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(find.text('Edit Text'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Area = π × r²');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.read(whiteboardControllerProvider).project.currentPage.texts.single.text, 'Area = π × r²');
    await key(tester, LogicalKeyboardKey.keyZ, ctrl: true);
    expect(c.read(whiteboardControllerProvider).project.currentPage.texts.single.text, 'Area = πr²');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('single-letter shortcuts are ignored while typing in a text field', (tester) async {
    final c = await pumpBoard(tester);
    await key(tester, LogicalKeyboardKey.keyK, ctrl: true); // open assistant
    expect(find.text('AI Assistant'), findsOneWidget);
    expect(find.textContaining("Sign in with Google to use AI. It's free."), findsOneWidget);
    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(c.read(whiteboardControllerProvider).currentTool, ToolType.pen, reason: 'E typed, tool unchanged');
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('assistant while signed out asks to sign in instead of failing silently', (tester) async {
    await pumpBoard(tester);
    await key(tester, LogicalKeyboardKey.keyK, ctrl: true);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Explain'));
    await tester.pump();
    expect(find.textContaining('Sign in with Google to use AI features'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('pressing E twice toggles whole-stroke and partial eraser', (tester) async {
    final c = await pumpBoard(tester);
    await key(tester, LogicalKeyboardKey.keyE);
    expect(c.read(whiteboardControllerProvider).currentTool, ToolType.strokeEraser);
    await key(tester, LogicalKeyboardKey.keyE);
    expect(c.read(whiteboardControllerProvider).currentTool, ToolType.areaEraser);
  });

  for (final size in const [Size(390, 844), Size(820, 1180), Size(1400, 900)]) {
    testWidgets('layout has no overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await pumpBoard(tester, size: size);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await key(tester, LogicalKeyboardKey.keyK, ctrl: true);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }
}
