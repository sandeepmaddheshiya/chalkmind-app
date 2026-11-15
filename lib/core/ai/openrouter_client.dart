import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ai_config.dart';

enum AiErrorKind {
  notConfigured,
  unauthorized,
  rateLimited,
  network,
  timeout,
  badResponse,
  cancelled,
}

class AiException implements Exception {
  final AiErrorKind kind;
  final String message;
  const AiException(this.kind, this.message);

  /// Short message suitable for showing to a teacher or student.
  String get userMessage {
    switch (kind) {
      case AiErrorKind.notConfigured:
        return 'AI is not set up. Add an OpenRouter API key in Smart Recognition & AI settings.';
      case AiErrorKind.unauthorized:
        return AiConfig.hasBuiltInKey
            ? 'The AI service is unavailable right now. Please try again later.'
            : 'The AI provider rejected the API key. Check it in Smart Recognition & AI settings.';
      case AiErrorKind.rateLimited:
        return 'The AI provider is rate-limiting requests. Try again in a moment.';
      case AiErrorKind.network:
        return 'Could not reach the AI provider. Check your internet connection.';
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
/// diagram generation). Talks to OpenRouter's OpenAI-compatible API.
class OpenRouterClient {
  static const _endpoint = 'https://openrouter.ai/api/v1/chat/completions';

  /// Factory for tests to inject a mock HTTP client.
  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  final AiConfig config;
  const OpenRouterClient(this.config);

  Map<String, String> _headers() => {
    'Authorization': 'Bearer ${config.apiKey}',
    'Content-Type': 'application/json',
    // App attribution for OpenRouter (identifies Chalkmind's requests).
    'HTTP-Referer': 'https://chalkmind.tech',
    'X-Title': 'Chalkmind',
  };

  static bool _isRetryableStatus(int code) =>
      code == 404 || code == 408 || code == 429 || code >= 500;

  static AiException _statusError(int code, String body) {
    if (code == 401 || code == 403) {
      return AiException(AiErrorKind.unauthorized, 'HTTP $code');
    }
    if (code == 429) return AiException(AiErrorKind.rateLimited, 'HTTP 429');
    final snippet = body.length > 200 ? body.substring(0, 200) : body;
    return AiException(AiErrorKind.badResponse, 'HTTP $code: $snippet');
  }

  void _ensureConfigured() {
    if (!config.isConfigured) {
      throw const AiException(AiErrorKind.notConfigured, 'No API key');
    }
  }

  /// Non-streaming completion. Falls back to the next model only for
  /// retryable failures (model missing, rate limit, server error, timeout);
  /// auth failures stop immediately.
  Future<String> complete({
    required List<Map<String, dynamic>> messages,
    double temperature = 0.2,
    int? maxTokens,
    Duration timeout = const Duration(seconds: 25),
    AiCancelToken? cancelToken,
    Map<String, dynamic>? responseFormat,
  }) async {
    _ensureConfigured();
    AiException? lastError;
    for (final model in config.modelCandidates) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AiException(AiErrorKind.cancelled, 'cancelled');
      }
      final client = clientFactory();
      cancelToken?._attach(client);
      try {
        final response = await client
            .post(
              Uri.parse(_endpoint),
              headers: _headers(),
              body: jsonEncode({
                'model': model,
                'messages': messages,
                'temperature': temperature,
                'max_tokens': ?maxTokens,
                'response_format': ?responseFormat,
              }),
            )
            .timeout(timeout);
        if (response.statusCode == 200) {
          final content = _extractContent(utf8.decode(response.bodyBytes));
          if (content != null && content.trim().isNotEmpty) return content;
          lastError = const AiException(
            AiErrorKind.badResponse,
            'empty content',
          );
          continue;
        }
        final err = _statusError(response.statusCode, response.body);
        if (!_isRetryableStatus(response.statusCode)) throw err;
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
  }) async* {
    _ensureConfigured();
    AiException? lastError;
    for (final model in config.modelCandidates) {
      if (cancelToken?.isCancelled ?? false) return;
      final client = clientFactory();
      cancelToken?._attach(client);
      bool yieldedAny = false;
      try {
        final request = http.Request('POST', Uri.parse(_endpoint))
          ..headers.addAll(_headers())
          ..body = jsonEncode({
            'model': model,
            'messages': messages,
            'temperature': temperature,
            'stream': true,
            'max_tokens': ?maxTokens,
          });
        final response = await client.send(request).timeout(firstByteTimeout);
        if (response.statusCode != 200) {
          final body = await response.stream.bytesToString();
          final err = _statusError(response.statusCode, body);
          if (!_isRetryableStatus(response.statusCode)) throw err;
          lastError = err;
          continue;
        }
        await for (final delta in parseSseDeltas(response.stream)) {
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
