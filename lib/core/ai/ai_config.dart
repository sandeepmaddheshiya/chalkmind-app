import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../backend/backend.dart';

/// AI provider settings.
///
/// Release builds send every AI request through the Chalkmind server
/// (`api.chalkmind.tech`), which holds the provider key, picks the model
/// and enforces the daily limits for the user's plan. The app contains no
/// API key.
///
/// Debug builds can instead call OpenRouter directly with a developer key
/// entered in Smart Recognition & AI settings (useful without a server).
@immutable
class AiConfig {
  static const String defaultModel = 'google/gemini-2.5-flash';
  static const String defaultFallbackModel = 'google/gemini-2.5-flash-lite';

  /// Developer override is never available in release builds.
  static const bool allowDeveloperKey = !kReleaseMode;

  final String userApiKey;
  final String model;

  const AiConfig({this.userApiKey = '', this.model = defaultModel});

  /// True when requests go to OpenRouter directly with a developer key.
  bool get usesDeveloperKey =>
      allowDeveloperKey && userApiKey.trim().isNotEmpty;

  /// True when requests go through the Chalkmind server.
  bool get usesBackend => !usesDeveloperKey;

  String get apiKey => usesDeveloperKey ? userApiKey.trim() : '';

  /// Whether a request can be attempted now: a developer key, or a
  /// signed-in account.
  bool get isConfigured => usesDeveloperKey || AiBackend.isSignedIn;

  /// Developer mode: primary model first, then a cheaper fallback. The
  /// server chooses models itself in backend mode.
  List<String> get modelCandidates {
    final primary = model.trim().isEmpty ? defaultModel : model.trim();
    return {primary, defaultFallbackModel}.toList();
  }

  AiConfig copyWith({String? userApiKey, String? model}) => AiConfig(
    userApiKey: userApiKey ?? this.userApiKey,
    model: model ?? this.model,
  );
}

class AiConfigNotifier extends Notifier<AiConfig> {
  static const _keyPref = 'ai.openrouter.apiKey';
  static const _modelPref = 'ai.openrouter.model';

  @override
  AiConfig build() {
    _load();
    return const AiConfig();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AiConfig(
        userApiKey: AiConfig.allowDeveloperKey
            ? prefs.getString(_keyPref) ?? ''
            : '',
        model: prefs.getString(_modelPref) ?? AiConfig.defaultModel,
      );
      if (!AiConfig.allowDeveloperKey && prefs.containsKey(_keyPref)) {
        // Remove keys saved by older builds.
        await prefs.remove(_keyPref);
      }
    } catch (e) {
      debugPrint('AiConfig: could not load preferences: $e');
    }
  }

  Future<void> update({String? apiKey, String? model}) async {
    state = state.copyWith(userApiKey: apiKey?.trim(), model: model?.trim());
    try {
      final prefs = await SharedPreferences.getInstance();
      if (apiKey != null) await prefs.setString(_keyPref, apiKey.trim());
      if (model != null) await prefs.setString(_modelPref, model.trim());
    } catch (e) {
      debugPrint('AiConfig: could not persist preferences: $e');
    }
  }
}

final aiConfigProvider = NotifierProvider<AiConfigNotifier, AiConfig>(
  AiConfigNotifier.new,
);
