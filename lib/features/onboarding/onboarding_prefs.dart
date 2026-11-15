import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers whether the welcome onboarding and the board tutorial were seen.
///
/// Reads fail safe: if preferences are unavailable, nothing is forced on the
/// user (onboarding and the tutorial are simply not auto-shown).
class OnboardingPrefs {
  static const _onboardingKey = 'onboarding.completed.v1';
  static const _tutorialKey = 'tutorial.board.completed.v1';

  static Future<bool> _get(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(key) ?? false;
    } catch (e) {
      debugPrint('OnboardingPrefs: unavailable ($e)');
      return true; // treat as already seen
    }
  }

  static Future<void> _set(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (e) {
      debugPrint('OnboardingPrefs: could not save ($e)');
    }
  }

  static Future<bool> isOnboardingDone() => _get(_onboardingKey);
  static Future<void> markOnboardingDone() => _set(_onboardingKey, true);

  static Future<bool> isTutorialDone() => _get(_tutorialKey);
  static Future<void> markTutorialDone() => _set(_tutorialKey, true);
}
