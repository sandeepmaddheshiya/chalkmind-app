import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-configurable AI provider settings.
///
/// The API key is never stored in source code. It is resolved from:
///  1. a key built into the app at compile time from the git-ignored
///     `dart_defines.json` (`--dart-define-from-file=dart_defines.json`).
///     When present, users never see or enter a key; or
///  2. (only when no key is built in) a key entered in Smart Recognition &
///     AI settings, for development builds.
/// If neither is present, AI features say so instead of silently failing.
@immutable
class AiConfig {
  static const String defaultModel = 'google/gemini-2.5-flash';
  static const String defaultFallbackModel = 'google/gemini-2.5-flash-lite';
  static const String _buildTimeKey = String.fromEnvironment(
    'OPENROUTER_API_KEY',
  );

  final String userApiKey;
  final String model;

  const AiConfig({this.userApiKey = '', this.model = defaultModel});

  /// True when this build has a key compiled in: the app then hides all key
  /// settings and messages from users.
  static bool get hasBuiltInKey => _buildTimeKey.isNotEmpty;

  String get apiKey => hasBuiltInKey ? _buildTimeKey : userApiKey.trim();
  bool get isConfigured => apiKey.isNotEmpty;
  bool get usesBuildTimeKey => hasBuiltInKey;

  /// Primary model first, then a cheaper fallback (deduplicated).
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
        userApiKey: prefs.getString(_keyPref) ?? '',
        model: prefs.getString(_modelPref) ?? AiConfig.defaultModel,
      );
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
