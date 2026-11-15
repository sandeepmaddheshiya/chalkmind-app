import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/app/app.dart';

void main() {
  testWidgets('Chalkwise app smoke test loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ChalkwiseApp(),
      ),
    );

    // Verify Home screen header displays Chalkwise brand and actions
    expect(find.text('Chalkwise'), findsOneWidget);
    expect(find.text('AI Whiteboard'), findsOneWidget);
    expect(find.text('New Board'), findsOneWidget);
  });
}
