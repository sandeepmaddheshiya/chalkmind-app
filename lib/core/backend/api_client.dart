import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'backend.dart';

/// An error answer from the Chalkmind API.
class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  final Map<String, dynamic>? body;

  const ApiException(this.status, this.code, this.message, [this.body]);

  bool get isNetwork => status == 0;

  /// Text safe to show to users.
  String get userMessage => isNetwork
      ? 'Could not reach Chalkmind. Check your internet connection.'
      : message;

  @override
  String toString() => 'ApiException($status, $code): $message';
}

/// Tokens issued by the server.
class AuthTokens {
  final String accessToken;
  final DateTime accessExpiresAt;
  final String refreshToken;

  const AuthTokens(this.accessToken, this.accessExpiresAt, this.refreshToken);

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
    j['accessToken'] as String,
    DateTime.parse(j['accessExpiresAt'] as String),
    j['refreshToken'] as String,
  );

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'accessExpiresAt': accessExpiresAt.toUtc().toIso8601String(),
    'refreshToken': refreshToken,
  };
}

/// Persists tokens (and the last account summary) between launches.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android Keystore-backed storage.
class SecureTokenStore implements TokenStore {
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryTokenStore implements TokenStore {
  final Map<String, String> values = {};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// HTTP client for the Chalkmind API with automatic token refresh.
class ApiClient {
  static const _tokensKey = 'chalkmind.tokens';

  final String baseUrl;
  final TokenStore store;
  final http.Client Function() clientFactory;

  /// Called when the session ends server-side (refresh rejected, banned).
  void Function(ApiException reason)? onSessionEnded;

  AuthTokens? _tokens;
  bool _loaded = false;
  Future<String?>? _refreshing;

  ApiClient({
    this.baseUrl = BackendConfig.baseUrl,
    TokenStore? store,
    http.Client Function()? clientFactory,
  }) : store = store ?? SecureTokenStore(),
       clientFactory = clientFactory ?? http.Client.new;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await store.read(_tokensKey);
      if (raw != null) {
        _tokens = AuthTokens.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('ApiClient: could not read tokens: $e');
    }
  }

  Future<bool> hasSession() async {
    await _ensureLoaded();
    return _tokens != null;
  }

  Future<void> _save(AuthTokens? t) async {
    _tokens = t;
    _loaded = true;
    try {
      if (t == null) {
        await store.delete(_tokensKey);
      } else {
        await store.write(_tokensKey, jsonEncode(t.toJson()));
      }
    } catch (e) {
      debugPrint('ApiClient: could not persist tokens: $e');
    }
  }

  /// A valid access token (refreshed when it expires within a minute), or
  /// null when signed out or the session could not be renewed.
  Future<String?> accessToken() async {
    await _ensureLoaded();
    final t = _tokens;
    if (t == null) return null;
    if (t.accessExpiresAt.isAfter(
      DateTime.now().add(const Duration(minutes: 1)),
    )) {
      return t.accessToken;
    }
    return refresh();
  }

  /// Exchanges the refresh token for new tokens. Concurrent callers share
  /// one request (refresh tokens are single-use).
  Future<String?> refresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<String?> _doRefresh() async {
    await _ensureLoaded();
    final t = _tokens;
    if (t == null) return null;
    try {
      final j = await _send(
        'POST',
        '/v1/auth/refresh',
        body: {'refreshToken': t.refreshToken},
        auth: false,
      );
      final tokens = AuthTokens.fromJson(j);
      await _save(tokens);
      return tokens.accessToken;
    } on ApiException catch (e) {
      if (e.status == 401 || e.status == 403) {
        await _save(null);
        onSessionEnded?.call(e);
        return null;
      }
      // Offline etc.: keep the session, the caller fails this time.
      rethrow;
    }
  }

  /// Signs in with a Google ID token. Returns the server's `me` payload.
  Future<Map<String, dynamic>> signInWithGoogle(String idToken) async {
    final j = await _send(
      'POST',
      '/v1/auth/google',
      body: {'idToken': idToken},
      auth: false,
    );
    await _save(AuthTokens.fromJson(j));
    return j['me'] as Map<String, dynamic>;
  }

  /// Revokes the session on the server (best effort) and forgets tokens.
  Future<void> signOut() async {
    await _ensureLoaded();
    final t = _tokens;
    await _save(null);
    if (t != null) {
      try {
        await _send(
          'POST',
          '/v1/auth/logout',
          body: {'refreshToken': t.refreshToken},
          auth: false,
        );
      } catch (_) {}
    }
  }

  /// Forgets the local session without calling the server.
  Future<void> clearSession() => _save(null);

  Future<Map<String, dynamic>> get(String path) => _authed('GET', path);
  Future<Map<String, dynamic>> post(String path, Object body) =>
      _authed('POST', path, body: body);
  Future<Map<String, dynamic>> delete(String path) => _authed('DELETE', path);

  /// Unauthenticated GET.
  Future<Map<String, dynamic>> getPublic(String path) =>
      _send('GET', path, auth: false);

  /// POST that works signed in or out (feedback).
  Future<Map<String, dynamic>> postOptionalAuth(
    String path,
    Object body,
  ) async {
    final token = await accessToken().catchError((_) => null);
    return _send('POST', path, body: body, auth: false, bearer: token);
  }

  Future<Map<String, dynamic>> _authed(
    String method,
    String path, {
    Object? body,
  }) async {
    var token = await accessToken();
    if (token == null) {
      throw const ApiException(401, 'unauthorized', 'Sign in to continue.');
    }
    try {
      return await _send(method, path, body: body, bearer: token);
    } on ApiException catch (e) {
      if (e.status != 401) {
        if (e.code == 'account_banned') onSessionEnded?.call(e);
        rethrow;
      }
      token = await refresh();
      if (token == null) rethrow;
      return _send(method, path, body: body, bearer: token);
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Object? body,
    bool auth = true,
    String? bearer,
  }) async {
    final client = clientFactory();
    try {
      final req = http.Request(method, _uri(path));
      req.headers['Accept'] = 'application/json';
      if (bearer != null) req.headers['Authorization'] = 'Bearer $bearer';
      if (body != null) {
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode(body);
      }
      final res = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 20)),
      ).timeout(const Duration(seconds: 30));
      final text = utf8.decode(res.bodyBytes);
      Map<String, dynamic> json = const {};
      if (text.isNotEmpty) {
        try {
          final decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) json = decoded;
        } on FormatException {
          // Non-JSON (proxy error page); handled below.
        }
      }
      if (res.statusCode >= 200 && res.statusCode < 300) return json;
      throw errorFrom(res.statusCode, json);
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw const ApiException(0, 'timeout', 'The server took too long.');
    } catch (e) {
      throw ApiException(0, 'network', e.toString());
    } finally {
      client.close();
    }
  }

  /// Builds an [ApiException] from the server's `{"error":{code,message}}`.
  static ApiException errorFrom(int status, Map<String, dynamic> json) {
    final err = json['error'];
    if (err is Map<String, dynamic>) {
      return ApiException(
        status,
        err['code'] as String? ?? 'error',
        err['message'] as String? ?? 'Something went wrong.',
        json,
      );
    }
    return ApiException(
      status,
      'http_$status',
      status >= 500
          ? 'Chalkmind is temporarily unavailable. Try again shortly.'
          : 'Request failed ($status).',
      json,
    );
  }
}
