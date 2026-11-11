import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kolo_theme.dart';
import '../../core/theme/theme_mode.dart';
import '../../shared/widgets/common.dart';
import '../auth/auth_controller.dart';
import '../savings/savings_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final session = ref.watch(sessionProvider);
    final contributions = ref.watch(myContributionsProvider);
    final user = session.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          KoloCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: palette.accent,
                  child: Text(
                    (user?.displayName ?? 'K').characters.first.toUpperCase(),
                    style: TextStyle(
                      color: palette.surface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.fullName.isNotEmpty == true ? user!.fullName : 'Member',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(user?.email ?? '', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          KoloCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Verification', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _Verified(ok: user?.isEmailVerified == true, label: 'Email'),
                const SizedBox(height: 8),
                _Verified(ok: user?.isPhoneVerified == true, label: 'Phone'),
                const SizedBox(height: 12),
                Text(
                  'Your account level is ${humanise(user?.verificationLevel ?? 'unverified')}. '
                  'KOLO only asks for identity documents when a feature needs them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text('Recent contributions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          contributions.when(
            data: (rows) => rows.isEmpty
                ? KoloCard(
                    child: Text(
                      'No contributions yet.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : Column(
                    children: rows.take(8).map((item) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: KoloCard(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.programmeName.isEmpty ? 'Contribution' : item.programmeName,
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.reference,
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(item.amount.format(), style: KoloTheme.moneySmall(context.kolo.textSoft)),
                                  const SizedBox(height: 4),
                                  StatusPill(status: item.status),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => ErrorNotice(error: error),
          ),
          const SizedBox(height: 24),
          const _AppearanceSection(),
          const SizedBox(height: 24),
          FilledButton.tonal(
            onPressed: () async {
              await ref.read(authControllerProvider).logout();
              if (context.mounted) context.go('/welcome');
            },
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'KOLO sandbox build\nNo real money moves in this environment',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: palette.textFaint, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Appearance sits with the account rather than buried in a submenu: it is the
/// one setting a member is likely to change on their first evening.
class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final current = ref.watch(themeModeProvider);

    return KoloCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.contrast_rounded, size: 20, color: palette.textSoft),
              const SizedBox(width: 10),
              Text('Appearance', style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'KOLO follows your phone by default.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          for (final mode in ThemeMode.values)
            RadioListTile<ThemeMode>(
              value: mode,
              groupValue: current,
              onChanged: (value) {
                if (value != null) ref.read(themeModeProvider.notifier).set(value);
              },
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: palette.accent,
              title: Text(themeModeLabel(mode), style: Theme.of(context).textTheme.bodyLarge),
              subtitle: switch (mode) {
                ThemeMode.system => const Text('Uses your phone\'s light or dark setting'),
                ThemeMode.light => const Text('Always the light Ink & Citrus palette'),
                ThemeMode.dark => const Text('Always the night palette'),
              },
            ),
        ],
      ),
    );
  }
}

class _Verified extends StatelessWidget {
  const _Verified({required this.ok, required this.label});

  final bool ok;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: ok ? palette.success : palette.textFaint,
        ),
        const SizedBox(width: 8),
        Text('$label ${ok ? 'verified' : 'not verified'}', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
