import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boardflow/app/app.dart';

void main() {
  testWidgets('BoardFlow app smoke test loads home screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: BoardFlowApp(),
      ),
    );

    // Verify Home screen header displays BoardFlow brand and actions
    expect(find.text('BoardFlow'), findsOneWidget);
    expect(find.text('Whiteboard & Studio'), findsOneWidget);
    expect(find.text('New Board'), findsOneWidget);
  });
}
