import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api_client.dart';
import 'backend.dart';

class Plan {
  final String tier; // free | plus
  final String? source; // trial | subscription | grant
  final DateTime? expiresAt;
  final bool autoRenewing;
  final String? productId;
  final String? basePlanId;

  const Plan({
    this.tier = 'free',
    this.source,
    this.expiresAt,
    this.autoRenewing = false,
    this.productId,
    this.basePlanId,
  });

  bool get isPlus => tier == 'plus';
  bool get isTrial => source == 'trial';
  bool get isPlaySubscription => source == 'trial' || source == 'subscription';

  factory Plan.fromJson(Map<String, dynamic> j) => Plan(
    tier: j['tier'] as String? ?? 'free',
    source: j['source'] as String?,
    expiresAt: _date(j['expiresAt']),
    autoRenewing: j['autoRenewing'] as bool? ?? false,
    productId: j['productId'] as String?,
    basePlanId: j['basePlanId'] as String?,
  );
}

class Quota {
  final int used;
  final int limit;
  final DateTime? resetsAt;

  const Quota({this.used = 0, this.limit = 0, this.resetsAt});

  int get remaining => (limit - used).clamp(0, limit);

  factory Quota.fromJson(Map<String, dynamic> j) => Quota(
    used: (j['used'] as num?)?.toInt() ?? 0,
    limit: (j['limit'] as num?)?.toInt() ?? 0,
    resetsAt: _date(j['resetsAt']),
  );

  Quota copyWith({int? used, int? limit}) => Quota(
    used: used ?? this.used,
    limit: limit ?? this.limit,
    resetsAt: resetsAt,
  );
}

/// The signed-in account as reported by `GET /v1/me`.
class Me {
  final String userId;
  final String email;
  final String name;
  final String? picture;
  final String billingKey;
  final Plan plan;
  final Quota quota;
  final bool aiEnabled;
  final Map<String, dynamic> raw;

  const Me({
    required this.userId,
    required this.email,
    required this.name,
    this.picture,
    required this.billingKey,
    required this.plan,
    required this.quota,
    required this.aiEnabled,
    this.raw = const {},
  });

  factory Me.fromJson(Map<String, dynamic> j) {
    final u = (j['user'] as Map<String, dynamic>?) ?? const {};
    return Me(
      userId: u['id'] as String? ?? '',
      email: u['email'] as String? ?? '',
      name: u['name'] as String? ?? '',
      picture: u['picture'] as String?,
      billingKey: j['billingKey'] as String? ?? '',
      plan: Plan.fromJson((j['plan'] as Map<String, dynamic>?) ?? const {}),
      quota: Quota.fromJson((j['quota'] as Map<String, dynamic>?) ?? const {}),
      aiEnabled: j['aiEnabled'] as bool? ?? true,
      raw: j,
    );
  }

  Me withQuota(Quota q) => Me(
    userId: userId,
    email: email,
    name: name,
    picture: picture,
    billingKey: billingKey,
    plan: plan,
    quota: q,
    aiEnabled: aiEnabled,
    raw: raw,
  );
}

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

@immutable
class AccountState {
  /// False until the stored session has been checked at startup.
  final bool ready;
  final Me? me;
  final bool busy;
  final String? error;

  const AccountState({
    this.ready = false,
    this.me,
    this.busy = false,
    this.error,
  });

  bool get signedIn => me != null;

  AccountState copyWith({
    bool? ready,
    Me? Function()? me,
    bool? busy,
    String? Function()? error,
  }) => AccountState(
    ready: ready ?? this.ready,
    me: me != null ? me() : this.me,
    busy: busy ?? this.busy,
    error: error != null ? error() : this.error,
  );
}

/// Whether Google sign-in can work in this build.
bool get googleSignInAvailable =>
    !kIsWeb &&
    Platform.isAndroid &&
    BackendConfig.googleServerClientId.isNotEmpty;

class AccountNotifier extends Notifier<AccountState> {
  static const _meKey = 'chalkmind.me';

  /// Overridable in tests.
  static ApiClient Function() apiFactory = ApiClient.new;

  late final ApiClient api = apiFactory();
  bool _googleInitialized = false;

  @override
  AccountState build() {
    api.onSessionEnded = _sessionEnded;
    AiBackend.accessToken = api.accessToken;
    AiBackend.refreshAccessToken = api.refresh;
    AiBackend.onRequestCompleted = _countRequest;
    AiBackend.onQuotaExceeded = _quotaExceeded;
    ref.onDispose(() {
      AiBackend.accessToken = null;
      AiBackend.refreshAccessToken = null;
      AiBackend.onRequestCompleted = null;
      AiBackend.onQuotaExceeded = null;
      AiBackend.isSignedIn = false;
    });
    Future.microtask(_restore);
    return const AccountState();
  }

  void _set(AccountState s) {
    if (!ref.mounted) return;
    state = s;
    AiBackend.isSignedIn = s.signedIn;
  }

  /// Restores the stored session instantly (cached summary), then refreshes
  /// it from the server in the background.
  Future<void> _restore() async {
    Me? cached;
    try {
      if (await api.hasSession()) {
        final raw = await api.store.read(_meKey);
        if (raw != null) {
          cached = Me.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        }
      }
    } catch (e) {
      debugPrint('Account: restore failed: $e');
    }
    _set(state.copyWith(ready: true, me: () => cached));
    if (cached != null) unawaited(refresh());
  }

  Future<void> _cache(Me me) async {
    try {
      await api.store.write(_meKey, jsonEncode(me.raw));
    } catch (_) {}
  }

  /// Applies a fresh `me` payload from the server.
  void applyMe(Map<String, dynamic> json) {
    final me = Me.fromJson(json);
    _set(state.copyWith(me: () => me, error: () => null));
    unawaited(_cache(me));
  }

  /// Reloads plan and quota. Silent on network errors.
  Future<void> refresh() async {
    if (!await api.hasSession()) return;
    try {
      applyMe(await api.get('/v1/me'));
    } on ApiException catch (e) {
      debugPrint('Account: refresh failed: $e');
    }
  }

  Future<void> _ensureGoogle() async {
    if (_googleInitialized) return;
    await GoogleSignIn.instance.initialize(
      serverClientId: BackendConfig.googleServerClientId,
    );
    _googleInitialized = true;
  }

  /// Google sign-in, then exchange of the ID token with the server.
  /// Returns true on success; failures set [AccountState.error].
  Future<bool> signInWithGoogle() async {
    if (!googleSignInAvailable) {
      _set(
        state.copyWith(
          error: () => kIsWeb || !Platform.isAndroid
            ? 'Google sign-in is available in the Android app.'
            : "Google sign-in isn't set up in this build yet (missing Google client ID).",
        ),
      );
      return false;
    }
    _set(state.copyWith(busy: true, error: () => null));
    try {
      await _ensureGoogle();
      final account = await GoogleSignIn.instance.authenticate();
      final idToken = account.authentication.idToken;
      if (idToken == null) {
        throw const ApiException(
          0,
          'no_id_token',
          'Google did not return a sign-in token.',
        );
      }
      final me = await api.signInWithGoogle(idToken);
      applyMe(me);
      _set(state.copyWith(busy: false));
      return true;
    } on GoogleSignInException catch (e) {
      final cancelled = e.code == GoogleSignInExceptionCode.canceled;
      debugPrint('Account: Google sign-in failed: ${e.code} ${e.description}');
      _set(
        state.copyWith(
          busy: false,
          error: () => cancelled ? null : 'Google sign-in failed. Try again.',
        ),
      );
      return false;
    } on ApiException catch (e) {
      _set(state.copyWith(busy: false, error: () => e.userMessage));
      return false;
    } catch (e) {
      debugPrint('Account: sign-in error: $e');
      _set(
        state.copyWith(busy: false, error: () => 'Sign-in failed. Try again.'),
      );
      return false;
    }
  }

  Future<void> signOut() async {
    _set(state.copyWith(busy: true));
    await api.signOut();
    await _forgetLocal();
    try {
      if (googleSignInAvailable) {
        await _ensureGoogle();
        await GoogleSignIn.instance.signOut();
      }
    } catch (_) {}
    _set(const AccountState(ready: true));
  }

  /// Deletes the account and its server data. Returns an error message,
  /// or null on success.
  Future<String?> deleteAccount() async {
    _set(state.copyWith(busy: true, error: () => null));
    try {
      await api.delete('/v1/me');
    } on ApiException catch (e) {
      _set(state.copyWith(busy: false));
      return e.userMessage;
    }
    await api.clearSession();
    await _forgetLocal();
    try {
      if (googleSignInAvailable) {
        await _ensureGoogle();
        await GoogleSignIn.instance.disconnect();
      }
    } catch (_) {}
    _set(const AccountState(ready: true));
    return null;
  }

  Future<void> _forgetLocal() async {
    try {
      await api.store.delete(_meKey);
    } catch (_) {}
  }

  void _sessionEnded(ApiException reason) {
    unawaited(_forgetLocal());
    _set(
      AccountState(
        ready: true,
        error: reason.code == 'account_banned'
            ? 'This account has been suspended.'
            : 'You were signed out. Sign in again to use AI.',
      ),
    );
  }

  void _countRequest() {
    final me = state.me;
    if (me == null) return;
    _set(
      state.copyWith(
        me: () => me.withQuota(me.quota.copyWith(used: me.quota.used + 1)),
      ),
    );
  }

  void _quotaExceeded(Map<String, dynamic> body) {
    final me = state.me;
    final q = body['quota'];
    if (me == null || q is! Map<String, dynamic>) return;
    _set(state.copyWith(me: () => me.withQuota(Quota.fromJson(q))));
  }

  void clearError() => _set(state.copyWith(error: () => null));

  Map<String, dynamic>? _publicConfig;

  /// Public server settings (daily limits for the paywall); cached.
  Future<Map<String, dynamic>?> publicConfig() async {
    if (_publicConfig != null) return _publicConfig;
    try {
      _publicConfig = await api.getPublic('/v1/config/public');
    } on ApiException catch (e) {
      debugPrint('Account: public config: $e');
    }
    return _publicConfig;
  }

  /// Sends app feedback (signed in or not).
  Future<void> sendFeedback({
    required String message,
    int? rating,
    String? email,
    String? appVersion,
    String? device,
  }) => api.postOptionalAuth('/v1/feedback', {
    'message': message,
    'rating': ?rating,
    'email': ?email,
    'appVersion': ?appVersion,
    'device': ?device,
  });

  /// Reports an AI answer for review.
  Future<void> reportAnswer({
    required String action,
    required String reason,
    required String answer,
    String? prompt,
  }) => api.post('/v1/reports', {
    'action': action,
    'reason': reason,
    'answer': answer,
    'prompt': ?prompt,
  });
}

final accountProvider = NotifierProvider<AccountNotifier, AccountState>(
  AccountNotifier.new,
);
