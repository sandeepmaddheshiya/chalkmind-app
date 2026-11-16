import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../backend/backend.dart';
import 'ai_config.dart';

enum AiErrorKind {
  /// Not signed in (server mode) or no developer key (developer mode).
  notConfigured,
  unauthorized,
  rateLimited,
  network,
  timeout,
  badResponse,
  cancelled,

  /// Today's AI requests for the user's plan are used up.
  quotaExceeded,

  /// AI paused by the operator, or the provider is down.
  unavailable,

  /// The account was suspended.
  accountSuspended,
}

class AiException implements Exception {
  final AiErrorKind kind;
  final String message;
  const AiException(this.kind, this.message);

  /// Short message suitable for showing to a teacher or student.
  String get userMessage {
    switch (kind) {
      case AiErrorKind.notConfigured:
        return 'Sign in with Google to use AI features.';
      case AiErrorKind.unauthorized:
        return 'The AI provider rejected the developer key. Check it in Smart Recognition & AI settings.';
      case AiErrorKind.rateLimited:
        return "You're sending AI requests too quickly. Try again in a moment.";
      case AiErrorKind.network:
        return 'Could not reach the AI service. Check your internet connection.';
      case AiErrorKind.quotaExceeded:
        return "You've used today's free AI requests. Upgrade to Plus for more.";
      case AiErrorKind.unavailable:
        return 'The AI service is unavailable right now. Please try again later.';
      case AiErrorKind.accountSuspended:
        return 'This account has been suspended.';
      case AiErrorKind.timeout:
        return 'The AI took too long to respond. Try again.';
      case AiErrorKind.badResponse:
        return 'The AI returned an unexpected response. Try again.';
      case AiErrorKind.cancelled:
        return 'Cancelled.';
    }
  }

  @override
  String toString() => 'AiException($kind): $message';
}

/// Cancels an in-flight AI request by closing its HTTP client.
class AiCancelToken {
  http.Client? _client;
  bool _cancelled = false;
  bool get isCancelled => _cancelled;

  void _attach(http.Client c) {
    if (_cancelled) {
      c.close();
    } else {
      _client = c;
    }
  }

  void cancel() {
    _cancelled = true;
    _client?.close();
    _client = null;
  }
}

/// Builds an OpenAI-compatible user message with optional PNG image.
Map<String, dynamic> aiUserMessage(String text, {String? base64Png}) => {
  'role': 'user',
  'content': [
    {'type': 'text', 'text': text},
    if (base64Png != null)
      {
        'type': 'image_url',
        'image_url': {'url': 'data:image/png;base64,$base64Png'},
      },
  ],
};

/// Single shared client for every AI feature (math solver, assistant,
/// diagram generation, PDF look-up).
///
/// Release builds talk to the Chalkmind server (`/v1/ai/chat`), which holds
/// the provider key, chooses the model, applies plan limits and falls back
/// between models itself. Debug builds with a developer key talk to
/// OpenRouter directly.
class OpenRouterClient {
  static const _openRouterEndpoint =
      'https://openrouter.ai/api/v1/chat/completions';
  static String get _backendEndpoint => '${BackendConfig.baseUrl}/v1/ai/chat';

  /// Factory for tests to inject a mock HTTP client.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  final AiConfig config;
  const OpenRouterClient(this.config);

  bool get _direct => config.usesDeveloperKey;

  Future<Map<String, String>> _headers({bool forceRefresh = false}) async {
    if (_direct) {
      return {
        'Authorization': 'Bearer ${config.apiKey}',
        'Content-Type': 'application/json',
        // App attribution for OpenRouter (identifies Chalkmind's requests).
        'HTTP-Referer': 'https://chalkmind.tech',
        'X-Title': 'Chalkmind',
      };
    }
    final token = forceRefresh
        ? await AiBackend.refreshAccessToken?.call()
        : await AiBackend.accessToken?.call();
    if (token == null) {
      throw const AiException(AiErrorKind.notConfigured, 'not signed in');
    }
    return {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    };
  }

  /// Developer mode tries each model; the server handles fallback itself.
  List<String?> get _candidates =>
      _direct ? config.modelCandidates : const <String?>[null];

  Uri get _uri => Uri.parse(_direct ? _openRouterEndpoint : _backendEndpoint);

  static bool _isRetryableStatus(int code) =>
      code == 404 || code == 408 || code == 429 || code >= 500;

  AiException _statusError(int code, String body, {bool interactive = true}) {
    if (!_direct) return _backendError(code, body, interactive: interactive);
    if (code == 401 || code == 403) {
      return AiException(AiErrorKind.unauthorized, 'HTTP $code');
    }
    if (code == 429) return AiException(AiErrorKind.rateLimited, 'HTTP 429');
    final snippet = body.length > 200 ? body.substring(0, 200) : body;
    return AiException(AiErrorKind.badResponse, 'HTTP $code: $snippet');
  }

  /// Maps the server's `{"error":{"code":...}}` answers.
  static AiException _backendError(
    int code,
    String body, {
    bool interactive = true,
  }) {
    Map<String, dynamic> json = const {};
    try {
      final d = jsonDecode(body);
      if (d is Map<String, dynamic>) json = d;
    } catch (_) {}
    final err = json['error'];
    final errCode = err is Map<String, dynamic> ? err['code'] as String? : null;
    switch (errCode) {
      case 'quota_exceeded':
        AiBackend.onQuotaExceeded?.call(json);
        if (interactive) AiBackend.requestGate(AiGateReason.quotaExceeded);
        return const AiException(AiErrorKind.quotaExceeded, 'quota');
      case 'rate_limited':
        return const AiException(AiErrorKind.rateLimited, 'rate limited');
      case 'account_banned':
        if (interactive) AiBackend.requestGate(AiGateReason.accountSuspended);
        return const AiException(AiErrorKind.accountSuspended, 'banned');
      case 'ai_disabled':
      case 'ai_unavailable':
        return AiException(AiErrorKind.unavailable, errCode!);
      case 'ai_timeout':
        return const AiException(AiErrorKind.timeout, 'server timeout');
    }
    if (code == 401) {
      if (interactive) AiBackend.requestGate(AiGateReason.signInRequired);
      return const AiException(AiErrorKind.notConfigured, 'session expired');
    }
    if (code == 429) {
      return const AiException(AiErrorKind.rateLimited, 'HTTP 429');
    }
    if (code >= 500) return AiException(AiErrorKind.unavailable, 'HTTP $code');
    return AiException(AiErrorKind.badResponse, 'HTTP $code');
  }

  void _ensureConfigured(bool interactive) {
    if (_direct) return;
    if (!AiBackend.isSignedIn) {
      if (interactive) AiBackend.requestGate(AiGateReason.signInRequired);
      throw const AiException(AiErrorKind.notConfigured, 'not signed in');
    }
  }

  Map<String, dynamic> _body({
    required String? model,
    required List<Map<String, dynamic>> messages,
    required double temperature,
    required int? maxTokens,
    required String action,
    bool stream = false,
    Map<String, dynamic>? responseFormat,
  }) => {
    'model': ?model,
    'messages': messages,
    'temperature': temperature,
    if (stream) 'stream': true,
    'max_tokens': ?maxTokens,
    'response_format': ?responseFormat,
    if (!_direct) 'action': action,
  };

  /// Sends one request; in server mode a 401 triggers a token refresh and
  /// one retry.
  Future<http.StreamedResponse> _send(
    http.Client client,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    Future<http.StreamedResponse> once(bool refresh) async {
      final req = http.Request('POST', _uri)
        ..headers.addAll(await _headers(forceRefresh: refresh))
        ..body = jsonEncode(body);
      return client.send(req).timeout(timeout);
    }

    final res = await once(false);
    if (_direct || res.statusCode != 401) return res;
    await res.stream.drain<void>();
    return once(true);
  }

  /// Non-streaming completion. In developer mode, falls back to the next
  /// model only for retryable failures; auth failures stop immediately.
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    double temperature = 0.2,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 25),
    AiCancelToken? cancelToken,
    Map<String, dynamic>? responseFormat,
    String action = 'other',
    bool interactive = true,
  }) async {
    _ensureConfigured(interactive);
    // The server may try a second model, so allow it more time.
    final effectiveTimeout = _direct
        ? timeout
        : timeout + const Duration(seconds: 25);
    AiException? lastError;
    for (final model in _candidates) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AiException(AiErrorKind.cancelled, 'cancelled');
      }
      final client = clientFactory();
      cancelToken?._attach(client);
      try {
        final response = await http.Response.fromStream(
          await _send(
            client,
            _body(
              model: model,
              messages: messages,
              temperature: temperature,
              maxTokens: maxTokens,
              action: action,
              responseFormat: responseFormat,
            ),
            effectiveTimeout,
          ),
        ).timeout(effectiveTimeout);
        if (response.statusCode == 200) {
          final content = _extractContent(utf8.decode(response.bodyBytes));
          if (content != null && content.trim().isNotEmpty) {
            if (!_direct) AiBackend.onRequestCompleted?.call();
            return content;
          }
          lastError = const AiException(
            AiErrorKind.badResponse,
            'empty content',
          );
          continue;
        }
        final err = _statusError(
          response.statusCode,
          utf8.decode(response.bodyBytes),
          interactive: interactive,
        );
        if (!_direct || !_isRetryableStatus(response.statusCode)) throw err;
        lastError = err;
      } on AiException {
        rethrow;
      } on TimeoutException {
        lastError = const AiException(AiErrorKind.timeout, 'timeout');
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) {
          throw const AiException(AiErrorKind.cancelled, 'cancelled');
        }
        lastError = AiException(AiErrorKind.network, e.toString());
      } finally {
        client.close();
      }
    }
    throw lastError ?? const AiException(AiErrorKind.badResponse, 'no models');
  }

  /// Streaming completion via server-sent events. Yields text deltas as they
  /// arrive so the UI can show the first tokens immediately.
  Stream<String> stream({
    required List<Map<String, dynamic>> messages,
    double temperature = 0.3,
    int? maxTokens,
    Duration firstByteTimeout = const Duration(seconds: 20),
    AiCancelToken? cancelToken,
    String action = 'other',
    bool interactive = true,
  }) async* {
    _ensureConfigured(interactive);
    final effectiveTimeout = _direct
        ? firstByteTimeout
        : firstByteTimeout + const Duration(seconds: 25);
    AiException? lastError;
    for (final model in _candidates) {
      if (cancelToken?.isCancelled ?? false) return;
      final client = clientFactory();
      cancelToken?._attach(client);
      bool yieldedAny = false;
      try {
        final response = await _send(
          client,
          _body(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            action: action,
            stream: true,
          ),
          effectiveTimeout,
        );
        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          final err = _statusError(
            response.statusCode,
            body,
            interactive: interactive,
          );
          if (!_direct || !_isRetryableStatus(response.statusCode)) throw err;
          lastError = err;
          continue;
        }
        await for (final delta in parseSseDeltas(response.stream)) {
          if (!yieldedAny && !_direct) AiBackend.onRequestCompleted?.call();
          yieldedAny = true;
          yield delta;
        }
        if (yieldedAny) return;
        lastError = const AiException(AiErrorKind.badResponse, 'empty stream');
      } on AiException {
        rethrow;
      } on TimeoutException {
        lastError = const AiException(AiErrorKind.timeout, 'timeout');
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) return;
        // A failure mid-stream after content was shown must not silently
        // restart on another model (it would duplicate text).
        if (yieldedAny) throw AiException(AiErrorKind.network, e.toString());
        lastError = AiException(AiErrorKind.network, e.toString());
      } finally {
        client.close();
      }
    }
    throw lastError ?? const AiException(AiErrorKind.badResponse, 'no models');
  }

  static String? _extractContent(String body) {
    try {
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final choices = decoded['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) return null;
      final message =
          (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>?;
      return message?['content'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Parses an OpenAI-style SSE byte stream into content deltas.
  @visibleForTesting
  static Stream<String> parseSseDeltas(Stream<List<int>> bytes) async* {
    final lines = bytes.transform(utf8.decoder).transform(const LineSplitter());
    await for (final raw in lines) {
      final line = raw.trim();
      if (!line.startsWith('data:')) continue; // comments / keep-alives
      final data = line.substring(5).trim();
      if (data == '[DONE]') return;
      try {
        final json = jsonDecode(data) as Map<String, dynamic>;
        if (json['error'] != null) {
          throw AiException(AiErrorKind.badResponse, json['error'].toString());
        }
        final choices = json['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) continue;
        final delta =
            (choices.first as Map<String, dynamic>)['delta']
                as Map<String, dynamic>?;
        final content = delta?['content'] as String?;
        if (content != null && content.isNotEmpty) yield content;
      } on FormatException {
        continue;
      }
    }
  }
}
