import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/backend/account.dart';
import '../core/backend/billing.dart';
import '../features/account/account_sheets.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'theme/theme.dart';

class ChalkmindApp extends ConsumerWidget {
  /// Show the welcome onboarding first (first launch only).
  final bool showOnboarding;

  const ChalkmindApp({super.key, this.showOnboarding = false});

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Start the account session and the Play purchase listener at launch
    // (pending purchases are delivered on startup).
    ref.watch(accountProvider.select((s) => s.ready));
    ref.watch(billingProvider.select((s) => s.available));
    return MaterialApp(
      title: 'Chalkmind',
      navigatorKey: navigatorKey,
      builder: (context, child) => AiGateListener(
        navigatorKey: navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
      debugShowCheckedModeBanner: false,
      theme: BoardTheme.lightTheme(),
      darkTheme: BoardTheme.darkTheme(),
      themeMode: ThemeMode.system,
      home: showOnboarding ? const _FirstLaunch() : const HomeScreen(),
    );
  }
}

/// Onboarding on first launch, then the home screen.
class _FirstLaunch extends StatefulWidget {
  const _FirstLaunch();

  @override
  State<_FirstLaunch> createState() => _FirstLaunchState();
}

class _FirstLaunchState extends State<_FirstLaunch> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _done
          ? const HomeScreen()
          : OnboardingScreen(onDone: () => setState(() => _done = true)),
    );
  }
}
