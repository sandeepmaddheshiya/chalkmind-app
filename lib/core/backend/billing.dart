import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

import 'account.dart';
import 'api_client.dart';
import 'backend.dart';

/// One purchasable Plus plan (a base plan, with its free-trial offer when
/// the user is eligible: Google only returns offers they qualify for).
class PlanOffer {
  final GooglePlayProductDetails details;
  final String basePlanId;
  final String? offerId;

  /// Price of the recurring phase, formatted by Google ("₹199.00").
  final String price;

  /// Recurring price in micros of [currencyCode].
  final int priceMicros;
  final String currencyCode;

  /// ISO-8601 period of the recurring phase ("P1M", "P1Y").
  final String period;

  /// Length of the free trial in days, or null.
  final int? trialDays;

  const PlanOffer({
    required this.details,
    required this.basePlanId,
    required this.offerId,
    required this.price,
    required this.priceMicros,
    required this.currencyCode,
    required this.period,
    required this.trialDays,
  });

  bool get isYearly => period.endsWith('Y');
  String get periodLabel =>
      isYearly ? 'year' : (period == 'P1W' ? 'week' : 'month');
}

/// Builds plan offers from Play product details: one per base plan,
/// preferring the free-trial offer.
@visibleForTesting
List<PlanOffer> offersFrom(List<GooglePlayProductDetails> products) {
  final byPlan = <String, PlanOffer>{};
  for (final p in products) {
    final idx = p.subscriptionIndex;
    final subs = p.productDetails.subscriptionOfferDetails;
    if (idx == null || subs == null || idx >= subs.length) continue;
    final offer = subs[idx];
    if (offer.pricingPhases.isEmpty) continue;
    final recurring = offer.pricingPhases.last;
    int? trial;
    for (final phase in offer.pricingPhases) {
      if (phase.priceAmountMicros == 0) {
        trial =
            isoPeriodDays(phase.billingPeriod) *
            (phase.billingCycleCount == 0 ? 1 : phase.billingCycleCount);
        break;
      }
    }
    final candidate = PlanOffer(
      details: p,
      basePlanId: offer.basePlanId,
      offerId: offer.offerId,
      price: recurring.formattedPrice,
      priceMicros: recurring.priceAmountMicros,
      currencyCode: recurring.priceCurrencyCode,
      period: recurring.billingPeriod,
      trialDays: trial,
    );
    final existing = byPlan[offer.basePlanId];
    if (existing == null || (existing.trialDays == null && trial != null)) {
      byPlan[offer.basePlanId] = candidate;
    }
  }
  final list = byPlan.values.toList()
    ..sort((a, b) => (a.isYearly ? 1 : 0).compareTo(b.isYearly ? 1 : 0));
  return list;
}

/// Days in an ISO-8601 period such as P7D, P1W, P1M, P3M or P1Y.
@visibleForTesting
int isoPeriodDays(String period) {
  final m = RegExp(
    r'^P(?:(\d+)Y)?(?:(\d+)M)?(?:(\d+)W)?(?:(\d+)D)?$',
  ).firstMatch(period);
  if (m == null) return 0;
  int g(int i) => int.tryParse(m.group(i) ?? '') ?? 0;
  return g(1) * 365 + g(2) * 30 + g(3) * 7 + g(4);
}

@immutable
class BillingState {
  final bool available;
  final bool loading;
  final List<PlanOffer> offers;
  final bool purchasing;
  final String? error;

  /// Set after a purchase was verified (the paywall closes on it).
  final int successCount;

  const BillingState({
    this.available = false,
    this.loading = false,
    this.offers = const [],
    this.purchasing = false,
    this.error,
    this.successCount = 0,
  });

  BillingState copyWith({
    bool? available,
    bool? loading,
    List<PlanOffer>? offers,
    bool? purchasing,
    String? Function()? error,
    int? successCount,
  }) => BillingState(
    available: available ?? this.available,
    loading: loading ?? this.loading,
    offers: offers ?? this.offers,
    purchasing: purchasing ?? this.purchasing,
    error: error != null ? error() : this.error,
    successCount: successCount ?? this.successCount,
  );
}

bool get playBillingSupported => !kIsWeb && Platform.isAndroid;

/// Google Play subscriptions. Purchases are verified and linked to the
/// account by the server before Plus is unlocked.
class BillingNotifier extends Notifier<BillingState> {
  StreamSubscription<List<PurchaseDetails>>? _sub;

  /// Purchases that arrived while signed out; verified after sign-in.
  final List<PurchaseDetails> _waiting = [];

  @override
  BillingState build() {
    if (!playBillingSupported) return const BillingState();
    _sub = InAppPurchase.instance.purchaseStream.listen(
      _onPurchases,
      onError: (Object e) => debugPrint('Billing: purchase stream error: $e'),
    );
    ref.onDispose(() => _sub?.cancel());
    ref.listen(accountProvider.select((s) => s.signedIn), (prev, signedIn) {
      if (signedIn && _waiting.isNotEmpty) {
        final pending = List.of(_waiting);
        _waiting.clear();
        unawaited(_onPurchases(pending));
      }
    });
    return const BillingState();
  }

  /// Loads plans and prices from Google Play.
  Future<void> loadOffers() async {
    if (!playBillingSupported || state.loading) return;
    state = state.copyWith(loading: true, error: () => null);
    try {
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        state = state.copyWith(
          loading: false,
          available: false,
          error: () => 'Google Play is not available on this device.',
        );
        return;
      }
      final res = await InAppPurchase.instance.queryProductDetails({
        BackendConfig.plusProductId,
      });
      final offers = offersFrom(
        res.productDetails.whereType<GooglePlayProductDetails>().toList(),
      );
      state = state.copyWith(
        loading: false,
        available: true,
        offers: offers,
        error: () => offers.isEmpty
            ? "Google Play didn't return any plans. Check your connection and try again."
            : null,
      );
    } catch (e) {
      debugPrint('Billing: load failed: $e');
      state = state.copyWith(
        loading: false,
        error: () => 'Could not load plans from Google Play.',
      );
    }
  }

  /// Starts the Google Play purchase flow.
  Future<void> buy(PlanOffer offer) async {
    final me = ref.read(accountProvider).me;
    if (me == null) {
      AiBackend.requestGate(AiGateReason.signInRequired);
      return;
    }
    state = state.copyWith(purchasing: true, error: () => null);
    try {
      final started = await InAppPurchase.instance.buyNonConsumable(
        purchaseParam: GooglePlayPurchaseParam(
          productDetails: offer.details,
          // Becomes obfuscatedExternalAccountId: the server checks it so a
          // purchase can only unlock the account that made it.
          applicationUserName: me.billingKey,
        ),
      );
      if (!started) {
        state = state.copyWith(purchasing: false);
      }
    } catch (e) {
      debugPrint('Billing: buy failed: $e');
      state = state.copyWith(
        purchasing: false,
        error: () => 'Could not start the purchase. Try again.',
      );
    }
  }

  /// Re-checks existing Google Play subscriptions for this account.
  Future<void> restore() async {
    final me = ref.read(accountProvider).me;
    if (me == null || !playBillingSupported) return;
    state = state.copyWith(purchasing: true, error: () => null);
    try {
      await InAppPurchase.instance.restorePurchases(
        applicationUserName: me.billingKey,
      );
      // Results arrive on the purchase stream; stop the spinner if none.
      Future.delayed(const Duration(seconds: 6), () {
        if (ref.mounted && state.purchasing) {
          state = state.copyWith(purchasing: false);
          unawaited(ref.read(accountProvider.notifier).refresh());
        }
      });
    } catch (e) {
      state = state.copyWith(
        purchasing: false,
        error: () => 'Could not restore purchases.',
      );
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          state = state.copyWith(purchasing: true);
        case PurchaseStatus.canceled:
          state = state.copyWith(purchasing: false);
          await _complete(p);
        case PurchaseStatus.error:
          state = state.copyWith(
            purchasing: false,
            error: () => 'The purchase did not go through.',
          );
          await _complete(p);
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _verify(p);
      }
    }
  }

  Future<void> _verify(PurchaseDetails p) async {
    final account = ref.read(accountProvider.notifier);
    if (!ref.read(accountProvider).signedIn) {
      _waiting.add(p);
      state = state.copyWith(purchasing: false);
      return;
    }
    try {
      final me = await account.api.post('/v1/billing/play/verify', {
        'purchaseToken': p.verificationData.serverVerificationData,
        'productId': p.productID,
      });
      account.applyMe(me);
      await _complete(p);
      state = state.copyWith(
        purchasing: false,
        successCount: p.status == PurchaseStatus.purchased
            ? state.successCount + 1
            : state.successCount,
      );
    } on ApiException catch (e) {
      debugPrint('Billing: verify failed: $e');
      // A purchase made by a different Chalkmind account on this Google
      // account shows up on restore; ignore it quietly.
      if (e.code == 'purchase_other_account' &&
          p.status == PurchaseStatus.restored) {
        state = state.copyWith(purchasing: false);
        return;
      }
      state = state.copyWith(purchasing: false, error: () => e.userMessage);
    }
  }

  Future<void> _complete(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await InAppPurchase.instance.completePurchase(p);
    } catch (e) {
      // The server acknowledges too; a second acknowledgement may fail.
      debugPrint('Billing: completePurchase: $e');
    }
  }

  void clearError() => state = state.copyWith(error: () => null);
}

final billingProvider = NotifierProvider<BillingNotifier, BillingState>(
  BillingNotifier.new,
);
