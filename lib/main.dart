import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/app.dart';
import 'core/storage/asset_store.dart';
import 'features/onboarding/onboarding_prefs.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AssetStore.init();
  final showOnboarding = !await OnboardingPrefs.isOnboardingDone();

  // Keep screen responsive for landscape or portrait teaching
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  runApp(ProviderScope(child: ChalkwiseApp(showOnboarding: showOnboarding)));
}
