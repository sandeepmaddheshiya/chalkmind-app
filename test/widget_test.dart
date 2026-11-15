import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/app/app.dart';

void main() {
  testWidgets('Chalkmind app smoke test loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: ChalkmindApp(),
      ),
    );

    // Verify Home screen header displays Chalkmind brand and actions
    expect(find.text('Chalkmind'), findsOneWidget);
    expect(find.text('AI Whiteboard'), findsOneWidget);
    expect(find.text('New Board'), findsOneWidget);
  });
}
