import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../savings_providers.dart';

/// What this member owes and what they have paid, in one place.
///
/// This is the destination for a "pay" deep link. The link carries no amount:
/// a URL is not a source of truth for money, so the member is shown what the
/// server says they owe and chooses from that.
class ContributionsScreen extends ConsumerWidget {
  const ContributionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final obligations = ref.watch(myObligationsProvider);
    final history = ref.watch(myContributionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Contributions')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myObligationsProvider);
          ref.invalidate(myContributionsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Text('Due now', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            obligations.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(myObligationsProvider),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: KoloCard(
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              color: palette.success, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Nothing outstanding. You are up to date.',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final obligation in rows) ...[
                      _ObligationTile(obligation: obligation),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text('History', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            history.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(myContributionsProvider),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No payments yet',
                    message: 'Once you pay into a programme, every payment appears here with the '
                        'reference the server issued.',
                  );
                }
                return KoloCard(
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0) const Divider(height: 20),
                        _HistoryRow(contribution: rows[i]),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ObligationTile extends StatelessWidget {
  const _ObligationTile({required this.obligation});

  final Obligation obligation;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    final overdue = obligation.isOverdue;

    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(obligation.programmeName, style: Theme.of(context).textTheme.titleMedium),
              ),
              if (overdue)
                Icon(Icons.schedule_rounded, size: 18, color: palette.danger)
              else
                Icon(Icons.event_available_outlined, size: 18, color: palette.textFaint),
            ],
          ),
          const SizedBox(height: 8),
          Text(obligation.outstanding.format(), style: KoloTheme.moneyMedium(palette.text)),
          const SizedBox(height: 2),
          Text(
            overdue
                ? 'Overdue — it was due ${_formatDate(obligation.dueDate)}'
                : 'Due ${_formatDate(obligation.dueDate)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: overdue ? palette.danger : null,
                ),
          ),
          if (obligation.paid.minor > 0) ...[
            const SizedBox(height: 6),
            Text('${obligation.paid.format()} already paid',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: obligation.programmeId.isEmpty
                ? null
                : () => context.push(
                      '/programmes/${obligation.programmeId}/contribute'
                      '?obligation=${obligation.id}'
                      '&amount=${obligation.outstanding.minor}',
                    ),
            child: const Text('Pay now'),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.contribution});

  final Contribution contribution;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Row(
      children: [
        Icon(
          contribution.isConfirmed ? Icons.check_circle_rounded : Icons.hourglass_bottom_rounded,
          size: 18,
          color: contribution.isConfirmed ? palette.success : palette.textFaint,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(contribution.programmeName, style: Theme.of(context).textTheme.bodyMedium),
              Text(
                contribution.reference.isEmpty ? humanise(contribution.status) : contribution.reference,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(contribution.amount.format(), style: KoloTheme.moneySmall(palette.text)),
      ],
    );
  }
}

String _formatDate(DateTime? value) {
  if (value == null) return 'no date set';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${value.day} ${months[value.month - 1]}';
}
