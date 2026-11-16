import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/backend/account.dart';
import '../../core/backend/api_client.dart';
import '../../core/backend/backend.dart';
import '../../core/backend/billing.dart';
import 'account_style.dart';

const _chalkYellow = Color(0xFFFACC15);
const _board = Color(0xFF0B3B35);

Future<void> openExternal(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openExternal: $e');
  }
}

Future<void> openManageSubscription([String? productId]) async {
  try {
    await launchUrl(
      BackendConfig.manageSubscriptionUri(
        productId ?? BackendConfig.plusProductId,
      ),
      mode: LaunchMode.externalApplication,
    );
  } catch (e) {
    debugPrint('openManageSubscription: $e');
  }
}

// ------------------------------------------------------------- sign in

/// Explains why an account is needed and signs in with Google.
/// Returns true when the user is signed in afterwards.
Future<bool> showSignInSheet(BuildContext context, {String? reason}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _SignInSheet(reason: reason),
  );
  return ok ?? false;
}

class _SignInSheet extends ConsumerStatefulWidget {
  final String? reason;
  const _SignInSheet({this.reason});

  @override
  ConsumerState<_SignInSheet> createState() => _SignInSheetState();
}

class _SignInSheetState extends ConsumerState<_SignInSheet> {
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    ref.read(accountProvider.notifier).clearError();
    LegalConsent.accepted().then((v) {
      if (mounted && v) setState(() => _agreed = true);
    });
  }

  Future<void> _signIn() async {
    await LegalConsent.setAccepted(true);
    final ok = await ref.read(accountProvider.notifier).signInWithGoogle();
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    const benefits = [
      (
        Icons.functions_rounded,
        'Solve handwritten maths, science and chemistry',
      ),
      (
        Icons.lightbulb_outline_rounded,
        'Explanations, hints and Check my work',
      ),
      (Icons.menu_book_rounded, 'Look up highlighted words in PDFs'),
    ];
    return SafeArea(
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/brand/chalkmind_logo.png',
                        width: 48,
                        height: 48,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.reason ?? 'Sign in to use AI',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            'Free account · your boards stay on this device',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E232D)
                        : const Color(0xFFF7F8FA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AccountColors.border(isDark)),
                  ),
                  child: Column(
                    children: [
                      for (final (icon, text) in benefits)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: AccountColors.board2.withValues(
                                    alpha: 0.14,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  icon,
                                  size: 18,
                                  color: isDark
                                      ? const Color(0xFF5EEAD4)
                                      : AccountColors.board2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  text,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Drawing, shapes, offline maths and PDFs work without an account.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                AgreementCheckbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v),
                  onOpen: openExternal,
                ),
                const SizedBox(height: 10),
                GoogleButton(
                  busy: account.busy,
                  onPressed: _agreed ? _signIn : null,
                ),
                if (!_agreed)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Tick the box above to continue.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (account.error != null)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.onErrorContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            account.error!,
                            style: TextStyle(
                              color: theme.colorScheme.onErrorContainer,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- paywall

/// Chalkmind Plus purchase sheet (free trial when eligible).
Future<void> showPaywall(BuildContext context, {bool limitReached = false}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaywallSheet(limitReached: limitReached),
  );
}

class _PaywallSheet extends ConsumerStatefulWidget {
  final bool limitReached;
  const _PaywallSheet({required this.limitReached});

  @override
  ConsumerState<_PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends ConsumerState<_PaywallSheet> {
  String? _selected;
  int? _freeLimit;
  int? _plusLimit;
  late final int _successAtOpen;

  @override
  void initState() {
    super.initState();
    _successAtOpen = ref.read(billingProvider).successCount;
    Future.microtask(() async {
      await ref.read(billingProvider.notifier).loadOffers();
      final cfg = await ref.read(accountProvider.notifier).publicConfig();
      if (!mounted) return;
      setState(() {
        _freeLimit = (cfg?['freeDailyLimit'] as num?)?.toInt();
        _plusLimit = (cfg?['plusDailyLimit'] as num?)?.toInt();
      });
    });
  }

  PlanOffer? _current(List<PlanOffer> offers) {
    if (offers.isEmpty) return null;
    return offers.firstWhere(
      (o) => o.basePlanId == _selected,
      orElse: () =>
          offers.firstWhere((o) => o.isYearly, orElse: () => offers.first),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = ref.watch(accountProvider);
    final billing = ref.watch(billingProvider);
    ref.listen(billingProvider.select((b) => b.successCount), (prev, next) {
      if (next > _successAtOpen && mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Welcome to Chalkmind Plus!')),
        );
      }
    });
    final offers = billing.offers;
    final current = _current(offers);
    final monthly = offers.where((o) => !o.isYearly).firstOrNull;
    final me = account.me;

    final benefits = <(IconData, String)>[
      (
        Icons.auto_awesome_rounded,
        _plusLimit != null
            ? 'Up to $_plusLimit AI answers a day${_freeLimit != null ? ' (free: $_freeLimit)' : ''}'
            : 'Many more AI answers every day',
      ),
      (Icons.fact_check_outlined, 'Check my work, hints, quizzes and diagrams'),
      (Icons.menu_book_rounded, 'More PDF look-ups and explanations'),
      (Icons.favorite_outline_rounded, 'Supports an independent education app'),
    ];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.limitReached)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  "You've used today's free AI answers. They reset at midnight UTC.",
                  style: TextStyle(color: theme.colorScheme.onErrorContainer),
                ),
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _chalkYellow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'PLUS',
                    style: TextStyle(
                      color: _board,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Chalkmind Plus',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            for (final (icon, text) in benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(text)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            if (!playBillingSupported)
              Text(
                'Subscriptions are available in the Android app from Google Play.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              )
            else if (me == null) ...[
              Text(
                'Sign in first so your subscription is linked to your account.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => showSignInSheet(context),
                  child: const Text('Sign in'),
                ),
              ),
            ] else if (me.plan.isPlus) ...[
              Text(
                me.plan.isTrial
                    ? "You're on the free trial."
                    : "You're already on Plus. Thank you!",
              ),
              if (me.plan.isPlaySubscription)
                TextButton(
                  onPressed: () => openManageSubscription(me.plan.productId),
                  child: const Text('Manage subscription in Google Play'),
                ),
            ] else if (billing.loading && offers.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (offers.isEmpty)
              Text(
                billing.error ?? 'Plans are not available right now.',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              )
            else ...[
              for (final o in offers)
                _PlanTile(
                  offer: o,
                  selected: identical(o, current),
                  savingsPercent:
                      o.isYearly && monthly != null && monthly.priceMicros > 0
                      ? (100 -
                                (o.priceMicros / (monthly.priceMicros * 12)) *
                                    100)
                            .round()
                      : null,
                  onTap: () => setState(() => _selected = o.basePlanId),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: _chalkYellow,
                    foregroundColor: _board,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: billing.purchasing || current == null
                      ? null
                      : () => ref.read(billingProvider.notifier).buy(current),
                  child: billing.purchasing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _board,
                          ),
                        )
                      : Text(
                          current?.trialDays != null
                              ? 'Start ${current!.trialDays}-day free trial'
                              : 'Subscribe',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
              if (billing.error != null) ...[
                const SizedBox(height: 8),
                Text(
                  billing.error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 10),
              if (current != null)
                Text(
                  current.trialDays != null
                      ? 'Free for ${current.trialDays} days, then ${current.price} per '
                            '${current.periodLabel}. Cancel any time in Google Play before '
                            'the trial ends and you won\'t be charged.'
                      : '${current.price} per ${current.periodLabel}. Renews automatically '
                            'until cancelled in Google Play.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                if (me != null && playBillingSupported)
                  TextButton(
                    onPressed: billing.purchasing
                        ? null
                        : () => ref.read(billingProvider.notifier).restore(),
                    child: const Text('Restore purchases'),
                  ),
                TextButton(
                  onPressed: () => openExternal(BackendConfig.termsUrl),
                  child: const Text('Terms'),
                ),
                TextButton(
                  onPressed: () => openExternal(BackendConfig.privacyUrl),
                  child: const Text('Privacy'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  final PlanOffer offer;
  final bool selected;
  final int? savingsPercent;
  final VoidCallback onTap;

  const _PlanTile({
    required this.offer,
    required this.selected,
    required this.savingsPercent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final border = selected ? theme.colorScheme.primary : theme.dividerColor;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.disabledColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            offer.isYearly ? 'Yearly' : 'Monthly',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (savingsPercent != null &&
                              savingsPercent! > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _chalkYellow,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Save $savingsPercent%',
                                style: const TextStyle(
                                  color: _board,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (offer.trialDays != null)
                        Text(
                          '${offer.trialDays}-day free trial',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  '${offer.price} / ${offer.periodLabel}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ feedback

Future<void> showFeedbackDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (_) => const _FeedbackDialog(),
  );
}

class _FeedbackDialog extends ConsumerStatefulWidget {
  const _FeedbackDialog();

  @override
  ConsumerState<_FeedbackDialog> createState() => _FeedbackDialogState();
}

class _FeedbackDialogState extends ConsumerState<_FeedbackDialog> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  int _rating = 0;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Write a message first.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    String? version;
    try {
      final info = await PackageInfo.fromPlatform();
      version = '${info.version}+${info.buildNumber}';
    } catch (_) {}
    try {
      await ref
          .read(accountProvider.notifier)
          .sendFeedback(
            message: _message.text.trim(),
            rating: _rating == 0 ? null : _rating,
            email: _email.text.trim().isEmpty ? null : _email.text.trim(),
            appVersion: version,
            device: kIsWeb ? 'web' : Platform.operatingSystem,
          );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Thanks! Your feedback was sent.')),
      );
    } on ApiException catch (e) {
      setState(() {
        _sending = false;
        _error = e.userMessage;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(accountProvider.select((s) => s.signedIn));
    return AlertDialog(
      title: const Text('Send feedback'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    tooltip: '$i star${i == 1 ? '' : 's'}',
                    icon: Icon(
                      i <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: const Color(0xFFF59E0B),
                    ),
                    onPressed: () => setState(() => _rating = i),
                  ),
              ],
            ),
            TextField(
              controller: _message,
              maxLines: 5,
              minLines: 3,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'What do you like? What should we improve?',
                border: OutlineInputBorder(),
              ),
            ),
            if (!signedIn)
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email for a reply (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _sending ? null : _send,
          child: const Text('Send'),
        ),
      ],
    );
  }
}

// -------------------------------------------------------- report answer

/// Lets the user flag an AI answer (Google Play requires this for apps
/// with generative AI). Returns true when the report was sent.
Future<bool> reportAiAnswer(
  BuildContext context, {
  required String action,
  required String answer,
  String? prompt,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  if (!container.read(accountProvider).signedIn) {
    await showSignInSheet(context, reason: 'Sign in to report an answer');
    return false;
  }
  const reasons = [
    'Wrong or misleading',
    'Inappropriate or offensive',
    'Unsafe for students',
    'Other',
  ];
  final reason = await showDialog<String>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('Report this answer'),
      children: [
        for (final r in reasons)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(r),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(r),
            ),
          ),
      ],
    ),
  );
  if (reason == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await container
        .read(accountProvider.notifier)
        .reportAnswer(
          action: action,
          reason: reason,
          answer: answer,
          prompt: prompt,
        );
    messenger?.showSnackBar(
      const SnackBar(content: Text('Thanks. We will review this answer.')),
    );
    return true;
  } on ApiException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(e.userMessage)));
    return false;
  }
}

// --------------------------------------------------------- gate listener

/// Shows the sign-in sheet or paywall when an AI request needs it.
class AiGateListener extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  const AiGateListener({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  @override
  State<AiGateListener> createState() => _AiGateListenerState();
}

class _AiGateListenerState extends State<AiGateListener> {
  StreamSubscription<AiGateReason>? _sub;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _sub = AiBackend.gateEvents.listen(_onGate);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _onGate(AiGateReason reason) async {
    final ctx = widget.navigatorKey.currentContext;
    if (ctx == null || _showing) return;
    _showing = true;
    try {
      switch (reason) {
        case AiGateReason.signInRequired:
          await showSignInSheet(ctx);
        case AiGateReason.quotaExceeded:
          await showPaywall(ctx, limitReached: true);
        case AiGateReason.accountSuspended:
          await showDialog<void>(
            context: ctx,
            builder: (d) => AlertDialog(
              title: const Text('Account suspended'),
              content: const Text(
                'AI features are disabled for this account. Contact '
                'support@chalkmind.tech if you think this is a mistake.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(d).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
      }
    } finally {
      _showing = false;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
