import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_exception.dart';
import '../../core/theme/kolo_theme.dart';
import '../../shared/widgets/common.dart';
import '../savings/savings_providers.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final notifications = ref.watch(notificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await ref.read(moneyActionsProvider).markAllNotificationsRead();
              } on ApiException catch (error) {
                if (context.mounted) showMessage(context, error.userMessage, isError: true);
              }
            },
            child: const Text('Mark all read'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsProvider),
        child: switch (notifications) {
          AsyncValue(hasError: true, :final error?) => Padding(
              padding: const EdgeInsets.all(20),
              child: ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(notificationsProvider),
              ),
            ),
          AsyncValue(isLoading: true, hasValue: false) =>
            const Center(child: CircularProgressIndicator()),
          AsyncValue(:final value?) => value.isEmpty
              ? const EmptyState(
                  icon: Icons.notifications_none_rounded,
                  title: 'Nothing to catch up on',
                  message: 'Contributions, payouts and votes will show up here.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final item = value[index];
                    return KoloCard(
                      color: item.isUnread ? palette.surface : palette.ground,
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: item.isUnread ? palette.accent : palette.divider,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              _iconFor(item.kind),
                              size: 18,
                              color: item.isUnread ? palette.surface : palette.textFaint,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.title,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: item.isUnread ? FontWeight.w700 : FontWeight.w600,
                                    color: palette.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(item.body, style: Theme.of(context).textTheme.bodyMedium),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          _ => const SizedBox.shrink(),
        },
      ),
    );
  }

  static IconData _iconFor(String kind) => switch (kind) {
        'contribution' => Icons.south_west_rounded,
        'payout' => Icons.north_east_rounded,
        'loan' => Icons.account_balance_wallet_outlined,
        'governance' => Icons.how_to_vote_outlined,
        'security' => Icons.shield_outlined,
        _ => Icons.notifications_none_rounded,
      };
}
