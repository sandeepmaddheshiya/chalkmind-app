import 'dart:async';
import 'dart:convert';

import 'package:boardflow/core/ai/ai_config.dart';
import 'package:boardflow/core/ai/openrouter_client.dart';
import 'package:boardflow/core/backend/account.dart';
import 'package:boardflow/core/backend/api_client.dart';
import 'package:boardflow/core/backend/backend.dart';
import 'package:boardflow/core/backend/billing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';

const _base = 'https://api.test';

Map<String, dynamic> _tokens(
  String access,
  String refresh, {
  Duration ttl = const Duration(hours: 1),
}) => {
  'accessToken': access,
  'accessExpiresAt': DateTime.now().add(ttl).toUtc().toIso8601String(),
  'refreshToken': refresh,
  'refreshExpiresAt': DateTime.now()
      .add(const Duration(days: 60))
      .toUtc()
      .toIso8601String(),
  'me': _me(),
};

Map<String, dynamic> _me({
  String tier = 'free',
  int used = 0,
  int limit = 10,
}) => {
  'user': {'id': 'u1', 'email': 'a@b.c', 'name': 'Ann'},
  'billingKey': 'bk1',
  'plan': {'tier': tier, 'autoRenewing': false},
  'quota': {'used': used, 'limit': limit, 'resetsAt': '2026-11-16T00:00:00Z'},
  'aiEnabled': true,
  'products': ['chalkmind_plus'],
};

http.Response _json(int status, Object body) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  group('ApiClient', () {
    test('sign-in stores tokens; requests carry the bearer token', () async {
      final store = MemoryTokenStore();
      final seen = <String>[];
      final api = ApiClient(
        baseUrl: _base,
        store: store,
        clientFactory: () => MockClient((r) async {
          seen.add(
            '${r.method} ${r.url.path} ${r.headers['Authorization'] ?? ''}',
          );
          if (r.url.path == '/v1/auth/google') {
            return _json(200, _tokens('A1', 'R1'));
          }
          return _json(200, _me(used: 2));
        }),
      );
      final me = await api.signInWithGoogle('google-id-token');
      expect(Me.fromJson(me).billingKey, 'bk1');
      expect(await api.hasSession(), isTrue);
      final res = await api.get('/v1/me');
      expect(Me.fromJson(res).quota.used, 2);
      expect(seen.last, 'GET /v1/me Bearer A1');

      // A new client instance restores the session from storage.
      final again = ApiClient(
        baseUrl: _base,
        store: store,
        clientFactory: () => MockClient((r) async => _json(200, {})),
      );
      expect(await again.accessToken(), 'A1');
    });

    test(
      'an expiring access token is refreshed once for concurrent callers',
      () async {
        var refreshes = 0;
        final store = MemoryTokenStore();
        store.values['chalkmind.tokens'] = jsonEncode({
          'accessToken': 'OLD',
          'accessExpiresAt': DateTime.now()
              .add(const Duration(seconds: 10))
              .toUtc()
              .toIso8601String(),
          'refreshToken': 'R1',
        });
        final api = ApiClient(
          baseUrl: _base,
          store: store,
          clientFactory: () => MockClient((r) async {
            if (r.url.path == '/v1/auth/refresh') {
              refreshes++;
              expect(jsonDecode(r.body)['refreshToken'], 'R1');
              await Future<void>.delayed(const Duration(milliseconds: 20));
              return _json(200, _tokens('NEW', 'R2'));
            }
            return _json(200, {});
          }),
        );
        final results = await Future.wait([
          api.accessToken(),
          api.accessToken(),
          api.accessToken(),
        ]);
        expect(results, ['NEW', 'NEW', 'NEW']);
        expect(refreshes, 1);
        expect(
          jsonDecode(store.values['chalkmind.tokens']!)['refreshToken'],
          'R2',
        );
      },
    );

    test(
      'a 401 is retried after refreshing; a rejected refresh ends the session',
      () async {
        final store = MemoryTokenStore();
        var meCalls = 0;
        var refreshOk = true;
        ApiException? ended;
        final api = ApiClient(
          baseUrl: _base,
          store: store,
          clientFactory: () => MockClient((r) async {
            if (r.url.path == '/v1/auth/google') {
              return _json(200, _tokens('A1', 'R1'));
            }
            if (r.url.path == '/v1/auth/refresh') {
              return refreshOk
                  ? _json(200, _tokens('A2', 'R2'))
                  : _json(401, {
                      'error': {
                        'code': 'session_expired',
                        'message': 'Session expired.',
                      },
                    });
            }
            meCalls++;
            if (r.headers['Authorization'] == 'Bearer A1') {
              return _json(401, {
                'error': {'code': 'token_expired', 'message': 'x'},
              });
            }
            return _json(200, _me());
          }),
        )..onSessionEnded = (e) => ended = e;
        await api.signInWithGoogle('t');
        await api.get('/v1/me');
        expect(meCalls, 2, reason: 'retried with the refreshed token');

        // Server revokes the session.
        refreshOk = false;
        store.values['chalkmind.tokens'] = jsonEncode({
          'accessToken': 'A1',
          'accessExpiresAt': DateTime.now()
              .add(const Duration(hours: 1))
              .toUtc()
              .toIso8601String(),
          'refreshToken': 'R2',
        });
        final fresh = ApiClient(
          baseUrl: _base,
          store: store,
          clientFactory: api.clientFactory,
        )..onSessionEnded = (e) => ended = e;
        await expectLater(fresh.get('/v1/me'), throwsA(isA<ApiException>()));
        expect(ended?.code, 'session_expired');
        expect(await fresh.hasSession(), isFalse);
      },
    );

    test('server errors and network failures become ApiException', () async {
      final api = ApiClient(
        baseUrl: _base,
        store: MemoryTokenStore(),
        clientFactory: () => MockClient((r) async {
          if (r.url.path == '/v1/feedback') {
            return _json(400, {
              'error': {
                'code': 'bad_request',
                'message': 'message is required.',
              },
            });
          }
          throw const SocketExceptionLike();
        }),
      );
      await expectLater(
        api.postOptionalAuth('/v1/feedback', {}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'bad_request'),
        ),
      );
      await expectLater(
        api.getPublic('/v1/config/public'),
        throwsA(
          isA<ApiException>().having((e) => e.isNetwork, 'network', isTrue),
        ),
      );
      await expectLater(
        api.get('/v1/me'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 401)),
      );
    });
  });

  group('AI through the Chalkmind server', () {
    late List<http.Request> requests;
    late List<AiGateReason> gates;
    late StreamSubscription<AiGateReason> sub;
    var completed = 0;
    Map<String, dynamic>? quotaBody;

    setUp(() {
      requests = [];
      gates = [];
      completed = 0;
      quotaBody = null;
      sub = AiBackend.gateEvents.listen(gates.add);
      AiBackend.isSignedIn = true;
      AiBackend.accessToken = () async => 'ACCESS';
      AiBackend.refreshAccessToken = () async => 'REFRESHED';
      AiBackend.onRequestCompleted = () => completed++;
      AiBackend.onQuotaExceeded = (b) => quotaBody = b;
    });

    tearDown(() async {
      await sub.cancel();
      AiBackend.isSignedIn = false;
      AiBackend.accessToken = null;
      AiBackend.refreshAccessToken = null;
      AiBackend.onRequestCompleted = null;
      AiBackend.onQuotaExceeded = null;
      OpenRouterClient.clientFactory = http.Client.new;
      // Let the gate debounce expire between tests.
      await Future<void>.delayed(const Duration(milliseconds: 1));
    });

    test(
      'requests go to the server with the bearer token and action, no model',
      () async {
        OpenRouterClient.clientFactory = () => MockClient((r) async {
          requests.add(r);
          return _json(200, {
            'choices': [
              {
                'message': {'content': 'x = 4'},
              },
            ],
          });
        });
        const config = AiConfig();
        expect(config.usesBackend, isTrue);
        final out = await const OpenRouterClient(
          config,
        ).complete(messages: [aiUserMessage('2x = 8')], action: 'solve');
        expect(out, 'x = 4');
        final r = requests.single;
        expect(r.url.toString(), '${BackendConfig.baseUrl}/v1/ai/chat');
        expect(r.headers['Authorization'], 'Bearer ACCESS');
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        expect(body.containsKey('model'), isFalse);
        expect(body['action'], 'solve');
        expect(completed, 1);
      },
    );

    test(
      'an expired token is refreshed and the request retried once',
      () async {
        OpenRouterClient.clientFactory = () => MockClient((r) async {
          requests.add(r);
          if (r.headers['Authorization'] == 'Bearer ACCESS') {
            return _json(401, {
              'error': {'code': 'token_expired', 'message': 'x'},
            });
          }
          return _json(200, {
            'choices': [
              {
                'message': {'content': 'ok'},
              },
            ],
          });
        });
        expect(
          await const OpenRouterClient(AiConfig()).complete(messages: const []),
          'ok',
        );
        expect(requests.map((r) => r.headers['Authorization']), [
          'Bearer ACCESS',
          'Bearer REFRESHED',
        ]);
      },
    );

    test(
      'daily limit: quota error, paywall request and updated quota',
      () async {
        OpenRouterClient.clientFactory = () => MockClient(
          (r) async => _json(429, {
            'error': {'code': 'quota_exceeded', 'message': 'limit'},
            'plan': 'free',
            'quota': {
              'used': 10,
              'limit': 10,
              'resetsAt': '2026-11-16T00:00:00Z',
            },
          }),
        );
        await expectLater(
          const OpenRouterClient(AiConfig()).complete(messages: const []),
          throwsA(
            isA<AiException>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.quotaExceeded,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(gates, [AiGateReason.quotaExceeded]);
        expect((quotaBody!['quota'] as Map)['limit'], 10);
      },
    );

    test(
      'signed out: no request is sent; interactive calls ask for sign-in',
      () async {
        AiBackend.isSignedIn = false;
        OpenRouterClient.clientFactory = () => MockClient((r) async {
          requests.add(r);
          return _json(200, {});
        });
        await expectLater(
          const OpenRouterClient(
            AiConfig(),
          ).complete(messages: const [], interactive: false),
          throwsA(
            isA<AiException>().having(
              (e) => e.kind,
              'kind',
              AiErrorKind.notConfigured,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          gates,
          isEmpty,
          reason: 'background auto-solve must not pop a sheet',
        );
        await Future<void>.delayed(const Duration(seconds: 2));
        await expectLater(
          const OpenRouterClient(
            AiConfig(),
          ).stream(messages: const []).toList(),
          throwsA(isA<AiException>()),
        );
        await Future<void>.delayed(Duration.zero);
        expect(gates, [AiGateReason.signInRequired]);
        expect(requests, isEmpty);
      },
    );

    test('AI paused by the operator maps to "unavailable"', () async {
      OpenRouterClient.clientFactory = () => MockClient(
        (r) async => _json(503, {
          'error': {'code': 'ai_disabled', 'message': 'paused'},
        }),
      );
      await expectLater(
        const OpenRouterClient(AiConfig()).complete(messages: const []),
        throwsA(
          isA<AiException>().having(
            (e) => e.kind,
            'kind',
            AiErrorKind.unavailable,
          ),
        ),
      );
    });

    test('streams are relayed and count once', () async {
      OpenRouterClient.clientFactory = () => MockClient.streaming((
        req,
        _,
      ) async {
        return http.StreamedResponse(
          Stream.fromIterable([
            utf8.encode('data: {"choices":[{"delta":{"content":"Hel"}}]}\n\n'),
            utf8.encode(
              'data: {"choices":[{"delta":{"content":"lo"}}]}\n\ndata: [DONE]\n\n',
            ),
          ]),
          200,
        );
      });
      final parts = await const OpenRouterClient(
        AiConfig(),
      ).stream(messages: const [], action: 'assistant_explain').toList();
      expect(parts.join(), 'Hello');
      expect(completed, 1);
    });
  });

  group('Play plans', () {
    PricingPhaseWrapper phase(String period, int micros, String price) =>
        PricingPhaseWrapper(
          billingCycleCount: micros == 0 ? 1 : 0,
          billingPeriod: period,
          formattedPrice: price,
          priceAmountMicros: micros,
          priceCurrencyCode: 'INR',
          recurrenceMode: micros == 0
              ? RecurrenceMode.finiteRecurring
              : RecurrenceMode.infiniteRecurring,
        );

    test(
      'one offer per base plan, preferring the free trial; monthly first',
      () {
        final product = ProductDetailsWrapper(
          description: 'd',
          name: 'Chalkmind Plus',
          productId: 'chalkmind_plus',
          productType: ProductType.subs,
          title: 'Chalkmind Plus',
          subscriptionOfferDetails: [
            SubscriptionOfferDetailsWrapper(
              basePlanId: 'yearly',
              offerTags: const [],
              offerIdToken: 'y',
              pricingPhases: [phase('P1Y', 1499000000, '₹1,499')],
            ),
            SubscriptionOfferDetailsWrapper(
              basePlanId: 'monthly',
              offerTags: const [],
              offerIdToken: 'm',
              pricingPhases: [phase('P1M', 199000000, '₹199')],
            ),
            SubscriptionOfferDetailsWrapper(
              basePlanId: 'monthly',
              offerId: 'trial-7d',
              offerTags: const [],
              offerIdToken: 'mt',
              pricingPhases: [
                phase('P1W', 0, 'Free'),
                phase('P1M', 199000000, '₹199'),
              ],
            ),
          ],
        );
        final offers = offersFrom(
          GooglePlayProductDetails.fromProductDetails(product),
        );
        expect(offers.map((o) => o.basePlanId), ['monthly', 'yearly']);
        expect(offers[0].trialDays, 7);
        expect(offers[0].offerId, 'trial-7d');
        expect(offers[0].details.offerToken, 'mt');
        expect(offers[0].price, '₹199');
        expect(offers[0].periodLabel, 'month');
        expect(offers[1].trialDays, isNull);
        expect(offers[1].isYearly, isTrue);
      },
    );

    test('ISO periods', () {
      expect(isoPeriodDays('P7D'), 7);
      expect(isoPeriodDays('P1W'), 7);
      expect(isoPeriodDays('P1M'), 30);
      expect(isoPeriodDays('P1Y'), 365);
      expect(isoPeriodDays('bogus'), 0);
    });
  });

  test('Me parses plan and quota', () {
    final me = Me.fromJson({
      ..._me(tier: 'plus', used: 3, limit: 300),
      'plan': {
        'tier': 'plus',
        'source': 'trial',
        'expiresAt': '2026-11-22T10:00:00Z',
        'autoRenewing': true,
      },
    });
    expect(me.plan.isPlus, isTrue);
    expect(me.plan.isTrial, isTrue);
    expect(me.plan.isPlaySubscription, isTrue);
    expect(me.quota.remaining, 297);
    expect(me.withQuota(me.quota.copyWith(used: 300)).quota.remaining, 0);
  });
}

class SocketExceptionLike implements Exception {
  const SocketExceptionLike();
}
