import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/kolo_theme.dart';
import '../../shared/widgets/common.dart';
import '../auth/auth_controller.dart';
import '../savings/savings_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                  backgroundColor: KoloColors.indigo,
                  child: Text(
                    (user?.displayName ?? 'K').characters.first.toUpperCase(),
                    style: const TextStyle(
                      color: KoloColors.white,
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
                                  Text(item.amount.format(), style: KoloTheme.moneySmall),
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
          FilledButton.tonal(
            onPressed: () async {
              await ref.read(authControllerProvider).logout();
              if (context.mounted) context.go('/welcome');
            },
            child: const Text('Sign out'),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'KOLO sandbox build\nNo real money moves in this environment',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: KoloColors.inkFaint, height: 1.5),
            ),
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
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: ok ? KoloColors.success : KoloColors.inkFaint,
        ),
        const SizedBox(width: 8),
        Text('$label ${ok ? 'verified' : 'not verified'}', style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
