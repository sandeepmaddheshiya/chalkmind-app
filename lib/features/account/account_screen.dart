import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/backend/account.dart';
import '../../core/backend/backend.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/theme/theme.dart';
import 'account_sheets.dart';
import 'account_style.dart';

/// Avatar button for app bars: opens the account screen.
class AccountButton extends ConsumerWidget {
  const AccountButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(accountProvider.select((s) => s.me));
    return IconButton(
      tooltip: me == null ? 'Sign in' : 'Account',
      onPressed: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AccountScreen())),
      icon: me == null
          ? const Icon(Icons.account_circle_outlined, size: 24)
          : Stack(
              clipBehavior: Clip.none,
              children: [
                _Avatar(me: me, radius: 13),
                if (me.plan.isPlus)
                  Positioned(
                    right: -4,
                    bottom: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '+',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0B3B35),
                          height: 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Me me;
  final double radius;
  const _Avatar({required this.me, required this.radius});

  @override
  Widget build(BuildContext context) {
    final initial = (me.name.isNotEmpty ? me.name : me.email).characters.first
        .toUpperCase();
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF0F766E),
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
    final pic = me.picture;
    if (pic == null || pic.isEmpty) return fallback;
    return ClipOval(
      child: Image.network(
        pic,
        width: radius * 2,
        height: radius * 2,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(accountProvider.notifier).refresh());
  }

  Future<void> _confirmSignOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your boards stay on this device. AI features need you to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(accountProvider.notifier).signOut();
  }

  Future<void> _confirmDelete(Me me) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This permanently deletes your Chalkmind account (${me.email}), '
              'usage history, reports and feedback. Boards saved on this device are not affected.',
            ),
            if (me.plan.isPlaySubscription) ...[
              const SizedBox(height: 12),
              const Text(
                'Deleting your account does not cancel your Google Play subscription. '
                'Cancel it in Google Play first to stop future charges.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              TextButton(
                onPressed: () => openManageSubscription(me.plan.productId),
                child: const Text('Open Google Play subscriptions'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final err = await ref.read(accountProvider.notifier).deleteAccount();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(err ?? 'Your account was deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider);
    final me = account.me;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(account: account),
                  if (me != null) ...[
                    const SizedBox(height: 16),
                    _UsageCard(me: me),
                  ],
                  const SizedBox(height: 22),
                  const _SectionLabel('Help & legal'),
                  _Group(
                    isDark: isDark,
                    children: [
                      _Tile(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Send feedback',
                        subtitle: 'Ideas, problems, anything',
                        onTap: () => showFeedbackDialog(context),
                      ),
                      _Tile(
                        icon: Icons.privacy_tip_outlined,
                        title: 'Privacy policy',
                        external: true,
                        onTap: () => openExternal(BackendConfig.privacyUrl),
                      ),
                      _Tile(
                        icon: Icons.description_outlined,
                        title: 'Terms of use',
                        external: true,
                        onTap: () => openExternal(BackendConfig.termsUrl),
                      ),
                    ],
                  ),
                  if (me != null) ...[
                    const SizedBox(height: 22),
                    const _SectionLabel('Account'),
                    _Group(
                      isDark: isDark,
                      children: [
                        _Tile(
                          icon: Icons.logout_rounded,
                          title: 'Sign out',
                          subtitle: 'Your boards stay on this device',
                          enabled: !account.busy,
                          onTap: _confirmSignOut,
                        ),
                        _Tile(
                          icon: Icons.delete_forever_outlined,
                          title: 'Delete account',
                          subtitle: 'Permanently remove your account data',
                          danger: true,
                          enabled: !account.busy,
                          onTap: () => _confirmDelete(me),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 24),
                  const _VersionLine(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand header: avatar, name and plan, or the sign-in call to action.
class _Header extends ConsumerStatefulWidget {
  final AccountState account;
  const _Header({required this.account});

  @override
  ConsumerState<_Header> createState() => _HeaderState();
}

class _HeaderState extends ConsumerState<_Header> {
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    LegalConsent.accepted().then((v) {
      if (mounted && v) setState(() => _agreed = true);
    });
  }

  Future<void> _signIn() async {
    await LegalConsent.setAccepted(true);
    await ref.read(accountProvider.notifier).signInWithGoogle();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    final me = account.me;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AccountColors.headerGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: me == null ? _signedOut(account) : _signedIn(me),
    );
  }

  Widget _signedIn(Me me) {
    final plan = me.plan;
    final date = DateFormat.yMMMd();
    String planText;
    if (!plan.isPlus) {
      planText = 'Free plan';
    } else if (plan.isTrial) {
      planText = 'Plus · free trial';
    } else {
      planText = 'Plus';
    }
    String? planNote;
    if (plan.isPlus && plan.expiresAt != null) {
      final d = date.format(plan.expiresAt!);
      planNote = plan.isTrial
          ? (plan.autoRenewing ? 'Trial ends $d, then renews' : 'Trial ends $d')
          : plan.source == 'grant'
          ? 'Until $d'
          : (plan.autoRenewing ? 'Renews $d' : 'Ends $d');
    }
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: plan.isPlus
                  ? AccountColors.yellow
                  : AccountColors.chalkDim.withValues(alpha: 0.4),
              width: 2,
            ),
          ),
          child: _Avatar(me: me, radius: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                me.name.isEmpty ? me.email : me.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AccountColors.chalk,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                me.email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AccountColors.chalkDim,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: plan.isPlus
                          ? AccountColors.yellow
                          : Colors.white.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          plan.isPlus
                              ? Icons.workspace_premium_rounded
                              : Icons.person_outline_rounded,
                          size: 14,
                          color: plan.isPlus
                              ? AccountColors.onYellow
                              : AccountColors.chalk,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          planText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: plan.isPlus
                                ? AccountColors.onYellow
                                : AccountColors.chalk,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (planNote != null)
                    Text(
                      planNote,
                      style: const TextStyle(
                        color: AccountColors.chalkDim,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _signedOut(AccountState account) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
                border: Border.all(
                  color: AccountColors.chalkDim.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                color: AccountColors.chalk,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Guest',
                    style: TextStyle(
                      color: AccountColors.chalk,
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Sign in to unlock AI solving, hints and explanations.',
                    style: TextStyle(
                      color: AccountColors.chalkDim,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AgreementCheckbox(
          value: _agreed,
          onChanged: (v) => setState(() => _agreed = v),
          onOpen: openExternal,
          textColor: AccountColors.chalkDim,
          linkColor: AccountColors.yellow,
        ),
        const SizedBox(height: 8),
        GoogleButton(busy: account.busy, onPressed: _agreed ? _signIn : null),
        if (account.error != null) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: AccountColors.yellow,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  account.error!,
                  style: const TextStyle(
                    color: AccountColors.chalk,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _UsageCard extends StatelessWidget {
  final Me me;
  const _UsageCard({required this.me});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final q = me.quota;
    final plan = me.plan;
    final ratio = q.limit == 0 ? 1.0 : (q.used / q.limit).clamp(0.0, 1.0);
    final low = q.limit > 0 && q.remaining <= (q.limit * 0.2).ceil();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AccountColors.panel(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AccountColors.border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'AI answers today',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '${q.used}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextSpan(
                      text: ' / ${q.limit}',
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: AccountColors.border(isDark),
              color: low ? BoardTheme.warning : theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            me.aiEnabled
                ? '${q.remaining} left · resets daily at midnight UTC'
                : 'AI is paused for maintenance right now.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: me.aiEnabled
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
          if (!plan.isPlus) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AccountColors.yellow,
                  foregroundColor: AccountColors.onYellow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () => showPaywall(context),
                icon: const Icon(Icons.workspace_premium_rounded),
                label: const Text(
                  'Get Plus: try it free',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
            ),
          ] else if (plan.isPlaySubscription) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => openManageSubscription(plan.productId),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Manage subscription'),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _Group extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _Group({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: AccountColors.panel(isDark),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AccountColors.border(isDark)),
    ),
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(height: 1, indent: 60, color: AccountColors.border(isDark)),
          children[i],
        ],
      ],
    ),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final bool danger;
  final bool external;
  final bool enabled;

  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
    this.external = false,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.primary;
    return ListTile(
      enabled: enabled,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
          color: danger ? theme.colorScheme.error : null,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Icon(
        external ? Icons.open_in_new_rounded : Icons.chevron_right_rounded,
        size: external ? 16 : 20,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _VersionLine extends StatelessWidget {
  const _VersionLine();

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform().catchError(
      (_) => PackageInfo(
        appName: 'Chalkmind',
        packageName: '',
        version: '',
        buildNumber: '',
      ),
    ),
    builder: (context, snap) {
      final v = snap.data?.version ?? '';
      return Text(
        v.isEmpty ? 'Chalkmind' : 'Chalkmind $v',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    },
  );
}
