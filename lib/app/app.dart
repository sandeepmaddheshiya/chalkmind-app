import 'package:flutter/material.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import 'theme/theme.dart';

class ChalkwiseApp extends StatelessWidget {
  /// Show the welcome onboarding first (first launch only).
  final bool showOnboarding;

  const ChalkwiseApp({super.key, this.showOnboarding = false});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chalkwise',
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
