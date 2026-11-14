import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/models.dart';
import '../../design/components.dart';
import '../../design/navigation.dart';
import '../../design/tokens.dart';
import '../auth/auth_controller.dart';
import '../savings/savings_providers.dart';
import '../../core/theme/theme_mode.dart';
import '../../shared/widgets/common.dart' show humanise;

/// The account tab.
///
/// Ordered by how often it is opened: who you are, whether your account can hold
/// money, what you have paid, then the settings nobody visits often. Verification
/// sits high because an unverified account is the thing that quietly blocks a
/// member from acting, and finding that out mid-payment is worse than reading it
/// here.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final session = ref.watch(sessionProvider);
    final contributions = ref.watch(myContributionsProvider);
    final user = session.value;

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(sessionProvider);
            ref.invalidate(myContributionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: KoloSpace.hero),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
                child: KoloPageHeader(
                  eyebrow: 'Your account',
                  title: 'Account',
                  actions: [
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () => context.push('/notifications'),
                      icon: const Icon(Icons.notifications_none_rounded, size: 22),
                      color: c.textSoft,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: KoloSpace.xl),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: _Identity(user: user),
              ),

              const SizedBox(height: KoloSpace.md),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: _VerificationCard(user: user),
              ),

              const SizedBox(height: KoloSpace.section),
              KoloSectionHeader(
                title: 'Recent payments',
                inset: false,
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, 0, KoloSpace.page, KoloSpace.md),
                action: TextButton(
                  onPressed: () => context.go('/money'),
                  child: const Text('See all'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: switch (contributions) {
                  AsyncValue(hasError: true) => KoloCard(
                      child: KoloNotice(
                        message: 'Your payments could not be loaded. Pull down to try again.',
                        tone: KoloNoticeTone.warning,
                        icon: Icons.warning_amber_rounded,
                      ),
                    ),
                  AsyncValue(isLoading: true, hasValue: false) =>
                    const KoloSkeletonCard(height: 120),
                  AsyncValue(:final value?) => value.isEmpty
                      ? const KoloEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'No payments yet',
                          message: 'Your first contribution will show up here, with the '
                              'reference the server issued for it.',
                        )
                      : KoloCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: KoloSpace.lg, vertical: KoloSpace.xs),
                          child: Column(
                            children: [
                              for (var i = 0; i < value.take(4).length; i++)
                                KoloActivityRow(
                                  title: value[i].programmeName.isEmpty
                                      ? 'Contribution'
                                      : value[i].programmeName,
                                  subtitle: value[i].reference.isEmpty
                                      ? humanise(value[i].status)
                                      : value[i].reference,
                                  amount: value[i].amount,
                                  status: value[i].status,
                                  showDivider: i < value.take(4).length - 1,
                                ),
                            ],
                          ),
                        ),
                  _ => const SizedBox.shrink(),
                },
              ),

              const SizedBox(height: KoloSpace.section),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: _AppearanceSection(),
              ),

              const SizedBox(height: KoloSpace.section),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: Column(
                  children: [
                    _LinkRow(
                      icon: Icons.notifications_none_rounded,
                      label: 'Notifications',
                      onTap: () => context.push('/notifications'),
                    ),
                    const SizedBox(height: KoloSpace.sm),
                    _LinkRow(
                      icon: Icons.info_outline_rounded,
                      label: 'About this build',
                      onTap: () => _showAbout(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: KoloSpace.section),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: SizedBox(
                  height: 50,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await koloConfirm(
                        context,
                        title: 'Sign out?',
                        message: 'You will need your password to sign back in. '
                            'Nothing happens to your groups or your money.',
                        confirmLabel: 'Sign out',
                        destructive: true,
                      );
                      if (ok != true || !context.mounted) return;
                      await ref.read(authControllerProvider).logout();
                      if (context.mounted) context.go('/welcome');
                    },
                    icon: const Icon(Icons.logout_rounded, size: 18),
                    label: const Text('Sign out'),
                  ),
                ),
              ),
              const SizedBox(height: KoloSpace.lg),
              Center(
                child: Text(
                  'KOLO · sandbox build',
                  style: context.text.bodySmall?.copyWith(color: c.textFaint),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showAbout(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (sheetContext) => KoloSheet(
        title: 'About this build',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This is a sandbox build of KOLO. Contributions, approvals and payouts '
              'are recorded for real, but no money reaches a bank account.',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: KoloSpace.lg),
            Text(
              'Ajo, esusu and adashe are how a great many people save. KOLO does the '
              'bookkeeping: every contribution gets a reference, every payout needs two '
              'people, and every naira is accounted for.',
              style: Theme.of(sheetContext).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Identity extends StatelessWidget {
  const _Identity({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final name = user?.fullName.isNotEmpty == true ? user!.fullName : 'Member';
    return Row(
      children: [
        KoloAvatar(name: name, size: 58, highlight: true),
        const SizedBox(width: KoloSpace.lg),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: context.text.headlineSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                user?.email ?? '',
                style: context.text.bodySmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if ((user?.phone ?? '').isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(user!.phone, style: context.text.bodySmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Verification is a gate, not a badge. It says what the account cannot do until
/// it is done, because that is the consequence a member actually cares about.
class _VerificationCard extends StatelessWidget {
  const _VerificationCard({required this.user});

  final UserProfile? user;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final emailOk = user?.isEmailVerified == true;
    final phoneOk = user?.isPhoneVerified == true;
    final fullyVerified = emailOk && phoneOk;

    return KoloCard(
      color: fullyVerified ? c.settledWash : c.pendingWash,
      border: fullyVerified
          ? c.settled.withValues(alpha: 0.22)
          : c.pending.withValues(alpha: 0.26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                fullyVerified ? Icons.verified_user_rounded : Icons.gpp_maybe_outlined,
                size: 17,
                color: fullyVerified ? c.settled : c.pending,
              ),
              const SizedBox(width: KoloSpace.sm),
              Expanded(
                child: Text(
                  fullyVerified ? 'Account fully verified' : 'Your account is limited',
                  style: context.text.titleSmall?.copyWith(
                    color: fullyVerified ? c.settled : c.pending,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: KoloSpace.md),
          _Check(ok: emailOk, label: 'Email confirmed'),
          const SizedBox(height: KoloSpace.sm),
          _Check(ok: phoneOk, label: 'Phone confirmed'),
          if (!fullyVerified) ...[
            const SizedBox(height: KoloSpace.md),
            Text(
              'Until both are confirmed your account cannot hold or send money. '
              'Your group can still see you as a member.',
              style: context.text.bodySmall?.copyWith(color: c.textSoft, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 15,
          color: ok ? c.settled : c.textFaint,
        ),
        const SizedBox(width: KoloSpace.sm),
        Text(
          label,
          style: context.text.bodySmall?.copyWith(
            color: ok ? c.text : c.textSoft,
            fontWeight: ok ? FontWeight.w500 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        Text(
          ok ? 'Done' : 'Not yet',
          style: context.text.bodySmall?.copyWith(
            color: ok ? c.settled : c.textFaint,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final mode = ref.watch(themeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: KoloSpace.md),
          child: Text('Appearance', style: context.text.titleLarge),
        ),
        // Segmented rather than a cycling button: three options deserve three
        // targets, and the current one should be visible without tapping.
        Container(
          padding: const EdgeInsets.all(KoloSpace.xs),
          decoration: BoxDecoration(
            color: c.surfaceSunken,
            borderRadius: BorderRadius.circular(KoloRadius.md),
          ),
          child: Row(
            children: [
              for (final option in const [
                (ThemeMode.system, 'System', Icons.brightness_auto_rounded),
                (ThemeMode.light, 'Light', Icons.light_mode_rounded),
                (ThemeMode.dark, 'Dark', Icons.dark_mode_rounded),
              ])
                Expanded(
                  child: Semantics(
                    selected: mode == option.$1,
                    button: true,
                    child: InkWell(
                      onTap: () => ref.read(themeModeProvider.notifier).set(option.$1),
                      borderRadius: BorderRadius.circular(KoloRadius.sm),
                      child: AnimatedContainer(
                        duration: KoloMotion.fast,
                        padding: const EdgeInsets.symmetric(vertical: KoloSpace.sm + 2),
                        decoration: BoxDecoration(
                          color: mode == option.$1 ? c.surfaceRaised : Colors.transparent,
                          borderRadius: BorderRadius.circular(KoloRadius.sm),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              option.$3,
                              size: 17,
                              color: mode == option.$1 ? c.text : c.textSoft,
                            ),
                            const SizedBox(height: KoloSpace.xs),
                            Text(
                              option.$2,
                              style: context.text.labelSmall?.copyWith(
                                color: mode == option.$1 ? c.text : c.textSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: KoloSpace.sm),
        Text(
          themeModeLabel(mode),
          style: context.text.bodySmall?.copyWith(color: c.textFaint),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(KoloRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoloRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: KoloSpace.lg, vertical: KoloSpace.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(KoloRadius.md),
            border: Border.all(color: c.hairline, width: 1),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: c.textSoft),
              const SizedBox(width: KoloSpace.md),
              Expanded(child: Text(label, style: context.text.titleSmall)),
              Icon(Icons.chevron_right_rounded, size: 18, color: c.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}
