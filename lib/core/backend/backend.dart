import 'dart:async';

/// Build-time backend settings (from `--dart-define-from-file`).
class BackendConfig {
  BackendConfig._();

  /// Chalkmind API (AI proxy, accounts, purchases).
  static const String baseUrl = String.fromEnvironment(
    'CHALKMIND_API_URL',
    defaultValue: 'https://api.chalkmind.tech',
  );

  /// OAuth "Web application" client ID. Google issues ID tokens for this
  /// audience, which the server verifies. Empty = sign-in disabled.
  static const String googleServerClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  /// Google Play subscription product.
  static const String plusProductId = 'chalkmind_plus';
  static const String packageName = 'tech.chalkmind.app';

  static const String privacyUrl = 'https://chalkmind.tech/privacy.html';
  static const String termsUrl = 'https://chalkmind.tech/terms.html';

  static Uri manageSubscriptionUri([String productId = plusProductId]) =>
      Uri.parse(
        'https://play.google.com/store/account/subscriptions'
        '?sku=$productId&package=$packageName',
      );
}

/// Why an AI request needs the user's attention (shown app-wide).
enum AiGateReason { signInRequired, quotaExceeded, accountSuspended }

/// Glue between the AI client (plain Dart, no Riverpod) and the account
/// layer. The account notifier installs the callbacks at startup.
class AiBackend {
  AiBackend._();

  /// Returns a valid access token, refreshing it if needed; null when
  /// signed out.
  static Future<String?> Function()? accessToken;

  /// Forces a token refresh after a 401; null when the session is gone.
  static Future<String?> Function()? refreshAccessToken;

  /// Called after each successful AI request (to update the usage meter).
  static void Function()? onRequestCompleted;

  /// Called with the server's quota payload when the daily limit is hit.
  static void Function(Map<String, dynamic> body)? onQuotaExceeded;

  /// Whether a user is signed in (kept current by the account notifier).
  static bool isSignedIn = false;

  static final StreamController<AiGateReason> _gate =
      StreamController<AiGateReason>.broadcast();

  /// The app root listens and shows the sign-in sheet or paywall.
  static Stream<AiGateReason> get gateEvents => _gate.stream;

  static DateTime _lastGate = DateTime.fromMillisecondsSinceEpoch(0);

  /// Asks the UI to prompt the user (debounced so repeated failures don't
  /// stack sheets).
  static void requestGate(AiGateReason reason) {
    final now = DateTime.now();
    if (now.difference(_lastGate) < const Duration(seconds: 2)) return;
    _lastGate = now;
    _gate.add(reason);
  }
}
