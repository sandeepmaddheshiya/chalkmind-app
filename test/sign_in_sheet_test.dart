// The sign-in sheet must open after a failed sign-in (it used to clear the
// old error while building, which Riverpod forbids, and the sheet broke).
import 'package:boardflow/core/backend/account.dart';
import 'package:boardflow/features/account/account_sheets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('sign-in sheet opens after a failed sign-in and clears the error', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    // In tests sign-in is unavailable, so this leaves an error behind.
    await tester.runAsync(() => c.read(accountProvider.notifier).signInWithGoogle());
    expect(c.read(accountProvider).error, isNotNull, reason: 'precondition');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: c,
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(onPressed: () => showSignInSheet(context), child: const Text('open')),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Google'), findsWidgets, reason: 'sheet is shown');
    expect(c.read(accountProvider).error, isNull, reason: 'old error cleared');
  });
}
