import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_exception.dart';
import '../../core/models/models.dart';
import '../../design/components.dart';
import '../../design/navigation.dart';
import '../../design/tokens.dart';
import '../../design/typography.dart';
import '../savings/savings_providers.dart';

/// Everything the group has told this member.
///
/// Notification centres fail in two ways: they bury the one thing that needs
/// action among twenty that do not, and they show a wall of identical rows with
/// no sense of when. So: unread items are marked with a citrus rail rather than
/// a background wash, the kind of event is carried by an icon and a word rather
/// than colour alone, and everything is grouped by day.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final notifications = ref.watch(notificationsProvider);
    final unread = notifications.maybeWhen(
      data: (rows) => rows.where((n) => n.isUnread).length,
      orElse: () => 0,
    );

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.page, KoloSpace.sm, KoloSpace.page, 0),
              child: Row(
                children: [
                  KoloBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const Spacer(),
                  if (unread > 0)
                    TextButton(
                      onPressed: () async {
                        try {
                          await ref
                              .read(moneyActionsProvider)
                              .markAllNotificationsRead();
                          ref.invalidate(notificationsProvider);
                        } on ApiException catch (error) {
                          if (context.mounted) {
                            koloToast(context, error.userMessage, isError: true);
                          }
                        }
                      },
                      child: const Text('Mark all read'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: switch (notifications) {
                  AsyncValue(hasError: true, :final error?) => ListView(
                      children: [
                        KoloErrorState(
                          message: error.toString().contains('network')
                              ? 'KOLO could not be reached. Check your connection.'
                              : 'Notifications could not be loaded.',
                          title: 'Nothing to show',
                          onRetry: () => ref.invalidate(notificationsProvider),
                        ),
                      ],
                    ),
                  AsyncValue(isLoading: true, hasValue: false) => const Padding(
                      padding: EdgeInsets.all(KoloSpace.page),
                      child: Column(
                        children: [
                          KoloSkeletonCard(height: 76),
                          SizedBox(height: KoloSpace.sm),
                          KoloSkeletonCard(height: 76),
                          SizedBox(height: KoloSpace.sm),
                          KoloSkeletonCard(height: 76),
                        ],
                      ),
                    ),
                  AsyncValue(:final value?) => value.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: KoloSpace.hero),
                            KoloEmptyState(
                              icon: Icons.notifications_none_rounded,
                              title: 'Nothing to catch up on',
                              message: 'Contributions, payouts and votes will appear '
                                  'here as they happen. We only send what needs your '
                                  'attention.',
                            ),
                          ],
                        )
                      : _Grouped(items: value),
                  _ => const SizedBox.shrink(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Grouped by day, because "when" is half of what a notification means. The new
/// ones sit under Today; everything else is folded by date.
class _Grouped extends StatelessWidget {
  const _Grouped({required this.items});

  final List<AppNotification> items;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final buckets = <String, List<AppNotification>>{};
    for (final item in items) {
      buckets.putIfAbsent(_bucket(item.createdAt), () => []).add(item);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          KoloSpace.page, KoloSpace.md, KoloSpace.page, KoloSpace.hero),
      children: [
        KoloPageHeader(
          eyebrow: '${items.where((i) => i.isUnread).length} unread of ${items.length}',
          title: 'Notifications',
        ),
        const SizedBox(height: KoloSpace.section),
        for (final entry in buckets.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: KoloSpace.md),
            child: Text(entry.key.toUpperCase(), style: KoloType.eyebrow(c)),
          ),
          for (final item in entry.value) ...[
            _NotificationRow(item: item),
            const SizedBox(height: KoloSpace.sm),
          ],
          const SizedBox(height: KoloSpace.md),
        ],
      ],
    );
  }

  static String _bucket(DateTime? at) {
    if (at == null) return 'Earlier';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    if (diff <= 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff <= 7) return 'This week';
    return 'Earlier';
  }
}

class _NotificationRow extends StatelessWidget {
  const _NotificationRow({required this.item});

  final AppNotification item;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (icon, label) = _kind(item.kind);

    return KoloCard(
      padding: EdgeInsets.zero,
      color: item.isUnread ? c.surfaceRaised : c.surface,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The unread marker is a rail, not a tinted background. A whole row
            // washed in colour competes with the text; a 3px rail does not.
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: item.isUnread ? c.accent : Colors.transparent,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(KoloRadius.lg),
                ),
              ),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  KoloSpace.md, KoloSpace.md, KoloSpace.lg, KoloSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: item.isUnread ? c.accentWash : c.surfaceSunken,
                      borderRadius: BorderRadius.circular(KoloRadius.sm + 2),
                    ),
                    child: Icon(icon, size: 17,
                        color: item.isUnread ? c.accentText : c.textSoft),
                  ),
                  const SizedBox(width: KoloSpace.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // The kind is stated in words as well as an icon, so
                            // the meaning survives without colour.
                            Text(
                              label.toUpperCase(),
                              style: KoloType.eyebrow(c).copyWith(fontSize: 9.5),
                            ),
                            const Spacer(),
                            Text(
                              _when(item.createdAt),
                              style: context.text.bodySmall?.copyWith(color: c.textFaint),
                            ),
                          ],
                        ),
                        const SizedBox(height: KoloSpace.xs + 1),
                        Text(
                          item.title,
                          style: context.text.titleSmall?.copyWith(
                            fontWeight:
                                item.isUnread ? FontWeight.w700 : FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            item.body,
                            style: context.text.bodySmall?.copyWith(height: 1.45),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ),
          ],
        ),
      ),
    );
  }

  static (IconData, String) _kind(String kind) => switch (kind) {
        'contribution' => (Icons.south_west_rounded, 'Payment in'),
        'payout' => (Icons.north_east_rounded, 'Payout'),
        'loan' => (Icons.account_balance_wallet_outlined, 'Loan'),
        'governance' => (Icons.how_to_vote_outlined, 'Vote'),
        'security' => (Icons.shield_outlined, 'Security'),
        'invitation' => (Icons.mail_outline_rounded, 'Invitation'),
        'reminder' => (Icons.alarm_rounded, 'Reminder'),
        _ => (Icons.notifications_none_rounded, 'Update'),
      };

  static String _when(DateTime? at) {
    if (at == null) return '';
    final now = DateTime.now();
    final diff = now.difference(at);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    if (diff.inDays < 7) return '${diff.inDays}d';
    return DateFormat('d MMM').format(at);
  }
}
