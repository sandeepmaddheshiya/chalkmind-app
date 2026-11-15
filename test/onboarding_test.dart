import 'package:boardflow/app/app.dart';
import 'package:boardflow/app/theme/theme.dart';
import 'package:boardflow/features/onboarding/onboarding_prefs.dart';
import 'package:boardflow/features/onboarding/onboarding_screen.dart';
import 'package:boardflow/features/whiteboard/models/project_model.dart';
import 'package:boardflow/features/whiteboard/state/whiteboard_notifier.dart';
import 'package:boardflow/features/whiteboard/ui/whiteboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('Welcome onboarding', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('walks through all pages and remembers completion', (tester) async {
      setSize(tester, const Size(820, 1180));
      bool done = false;
      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onDone: () => done = true)));
      expect(find.text('Welcome to Chalkmind'), findsOneWidget);
      expect(find.text('1 of 5'), findsOneWidget);

      for (final title in ['Write naturally', 'Smart maths & shapes', 'Your AI tutor', 'Bring your PDFs']) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);
        if (title == 'Your AI tutor') {
          expect(find.textContaining('AI features send only what you choose'), findsOneWidget,
              reason: 'AI data disclosure is shown');
        }
      }
      expect(find.text('Skip'), findsNothing, reason: 'no skip on the last page');
      await tester.tap(find.text('Get started'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(await OnboardingPrefs.isOnboardingDone(), isTrue);
    });

    testWidgets('primary button sits at the bottom right with readable text', (tester) async {
      for (final size in const [Size(360, 640), Size(800, 1280)]) {
        setSize(tester, size);
        await tester.pumpWidget(MaterialApp(
          theme: BoardTheme.darkTheme(),
          home: OnboardingScreen(onDone: () {}),
        ));
        final button = tester.getRect(find.widgetWithText(FilledButton, 'Next'));
        expect(button.right, greaterThan(size.width - 40), reason: 'right-aligned at ${size.width}');
        final style = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Next')).style!;
        expect(style.foregroundColor!.resolve({}), Colors.white, reason: 'white text on coloured button');
      }
    });

    testWidgets('Back returns to the previous page; Skip finishes', (tester) async {
      setSize(tester, const Size(390, 844));
      bool done = false;
      await tester.pumpWidget(MaterialApp(home: OnboardingScreen(onDone: () => done = true)));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome to Chalkmind'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(await OnboardingPrefs.isOnboardingDone(), isTrue);
    });

    for (final size in const [Size(360, 640), Size(390, 844), Size(1280, 800), Size(820, 1180)]) {
      testWidgets('every page fits at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
        setSize(tester, size);
        await tester.pumpWidget(MaterialApp(
          theme: BoardTheme.lightTheme(),
          home: OnboardingScreen(onDone: () {}),
        ));
        for (int i = 0; i < 5; i++) {
          expect(tester.takeException(), isNull, reason: 'page ${i + 1}');
          if (i < 4) {
            await tester.tap(find.text('Next'));
            await tester.pumpAndSettle();
          }
        }
      });
    }

    testWidgets('first launch shows onboarding, then the home screen', (tester) async {
      setSize(tester, const Size(820, 1180));
      await tester.pumpWidget(const ProviderScope(child: ChalkmindApp(showOnboarding: true)));
      expect(find.text('Welcome to Chalkmind'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      // (The home screen shows a loading spinner in tests: no file storage.)
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('New Board'), findsOneWidget);
    });
  });

  group('Board tutorial', () {
    Future<ProviderContainer> pumpBoard(WidgetTester tester, Size size) async {
      setSize(tester, size);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(whiteboardControllerProvider.notifier).loadProject(ProjectModel.createEmpty());
      await tester.pumpWidget(UncontrolledProviderScope(
        container: c,
        child: MaterialApp(theme: BoardTheme.lightTheme(), home: const WhiteboardScreen()),
      ));
      return c;
    }

    Future<void> waitForTour(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
    }

    testWidgets('starts once on the first board, steps through real controls', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpBoard(tester, const Size(1280, 900));
      await waitForTour(tester);
      expect(find.text('Quick tour'), findsOneWidget);

      final titles = <String>['Quick tour'];
      while (find.text('Done').evaluate().isEmpty) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final t in [
          'Your toolbar', 'Write and draw', 'Highlighter', 'Eraser', 'Shapes', 'Select',
          'Undo & redo', 'AI Assistant', 'More actions', 'Pages & zoom', 'Try it now',
        ]) {
          if (find.text(t).evaluate().isNotEmpty && !titles.contains(t)) titles.add(t);
        }
      }
      expect(titles, containsAllInOrder(['Your toolbar', 'Eraser', 'AI Assistant', 'Pages & zoom', 'Try it now']));
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('Try it now'), findsNothing);
      expect(await OnboardingPrefs.isTutorialDone(), isTrue);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('does not start again once seen; can be replayed from the menu', (tester) async {
      SharedPreferences.setMockInitialValues({'tutorial.board.completed.v1': true});
      await pumpBoard(tester, const Size(1280, 900));
      await waitForTour(tester);
      expect(find.text('Quick tour'), findsNothing);

      await tester.tap(find.byTooltip('Show tutorial'));
      await tester.pumpAndSettle();
      expect(find.text('Quick tour'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(find.text('Quick tour'), findsNothing);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('Back goes to the previous step', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpBoard(tester, const Size(1280, 900));
      await waitForTour(tester);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Your toolbar'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Quick tour'), findsOneWidget);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('runs to the end on a phone without layout errors', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await pumpBoard(tester, const Size(390, 844));
      await waitForTour(tester);
      expect(find.text('Quick tour'), findsOneWidget);
      int steps = 1;
      while (find.text('Done').evaluate().isEmpty && steps < 20) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'step $steps');
        steps++;
      }
      expect(find.text('Done'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
