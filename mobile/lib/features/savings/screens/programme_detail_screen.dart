import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../savings_providers.dart';

/// The programme screen: what is collected, whose turn is next, and — always —
/// whether the payout is actually funded yet.
class ProgrammeDetailScreen extends ConsumerWidget {
  const ProgrammeDetailScreen({super.key, required this.programmeId});

  final String programmeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final programme = ref.watch(programmeProvider(programmeId));
    final cycles = ref.watch(programmeCyclesProvider(programmeId));

    return Scaffold(
      appBar: AppBar(
        title: Text(programme.valueOrNull?.name ?? 'Programme'),
        actions: [
          // Money out gets its own screen: a payout needs an account number and
          // a second officer, which does not belong in a header button.
          IconButton(
            tooltip: 'Payouts',
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: programme.valueOrNull == null
                ? null
                : () => context.push(
                      '/programmes/$programmeId/payouts',
                      extra: {
                        'name': programme.valueOrNull!.name,
                        'currency': programme.valueOrNull!.currency,
                        'slug': programme.valueOrNull!.groupSlug,
                      },
                    ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(programmeProvider(programmeId));
          ref.invalidate(programmeCyclesProvider(programmeId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            programme.when(
              data: (value) => _ProgrammeSummary(programme: value),
              loading: () => const SizedBox(height: 120),
              error: (error, _) => ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(programmeProvider(programmeId)),
              ),
            ),
            const SizedBox(height: 24),
            Text('This cycle', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            ...switch (cycles) {
              AsyncValue(hasError: true, :final error?) => [ErrorNotice(error: error)],
              AsyncValue(isLoading: true, hasValue: false) => [
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              AsyncValue(:final value?) => value.isEmpty
                  ? [
                      const EmptyState(
                        icon: Icons.event_repeat_outlined,
                        title: 'No cycle open',
                        message: 'A cycle opens when the programme starts collecting.',
                      ),
                    ]
                  : [for (final cycle in value) _CycleCard(cycle: cycle, programmeId: programmeId)],
              _ => const [SizedBox.shrink()],
            },
            const SizedBox(height: 20),
            programme.when(
              data: (value) => value.isActive
                  ? FilledButton(
                      onPressed: () => context.push('/programmes/$programmeId/contribute'),
                      child: const Text('Make a contribution'),
                    )
                  : Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: palette.ground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'This programme is ${humanise(value.status).toLowerCase()}, so it is not '
                        'collecting right now.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgrammeSummary extends StatelessWidget {
  const _ProgrammeSummary({required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(programme.name, style: Theme.of(context).textTheme.titleLarge),
              ),
              StatusPill(status: programme.status),
            ],
          ),
          const SizedBox(height: 18),
          Text('Collected so far', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(programme.collected.format(), style: KoloTheme.moneyLarge(context.kolo.text)),
          const SizedBox(height: 6),
          Text(
            'of ${(programme.target.minor > 0 ? programme.target : programme.expected).format()} expected',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          const Divider(),
          const SizedBox(height: 8),
          AmountRow(
            label: 'Contribution per member',
            value: programme.contributionAmount.format(),
          ),
          AmountRow(label: 'Frequency', value: humanise(programme.frequency)),
          AmountRow(label: 'Participants', value: '${programme.participantCount}'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: palette.ground,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.verified_outlined, size: 16, color: palette.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'This figure counts money that has actually been confirmed — not what members '
                    'have promised.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CycleCard extends ConsumerStatefulWidget {
  const _CycleCard({required this.cycle, required this.programmeId});

  final RotationCycle cycle;
  final String programmeId;

  @override
  ConsumerState<_CycleCard> createState() => _CycleCardState();
}

class _CycleCardState extends ConsumerState<_CycleCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ref.invalidate(programmeCyclesProvider(widget.programmeId));
        ref.invalidate(programmeProvider(widget.programmeId));
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      // A refusal here is the system working: show the server's own words.
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(error.isFinancialRefusal ? 'Not yet' : 'Could not complete'),
          content: Text(error.userMessage),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Understood')),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    final cycle = widget.cycle;
    final percent = cycle.payoutAmount.minor > 0
        ? (cycle.collectedTotal.minor / cycle.payoutAmount.minor * 100).clamp(0, 100).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: KoloCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Cycle ${cycle.sequence} · ${cycle.beneficiaryName}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                StatusPill(status: cycle.status),
              ],
            ),
            const SizedBox(height: 14),
            CollectionProgress(percent: percent, height: 10),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cycle.collectedTotal.format(), style: KoloTheme.moneyMedium(context.kolo.text)),
                Text(
                  'of ${cycle.payoutAmount.format()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // The honest line: what is still missing, in money.
            if (!cycle.isPaid && cycle.shortfall.minor > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: palette.moneySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${cycle.shortfall.format()} still to collect before this payout can be made. '
                  'KOLO will not pay out money the group has not received.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.text),
                ),
              ),
            if (cycle.isPaid)
              Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 16, color: palette.success),
                  const SizedBox(width: 6),
                  Text(
                    'Paid${cycle.paidAt != null ? ' on ${_date(cycle.paidAt!)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: palette.success,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            if (!cycle.isPaid && cycle.isFullyFunded) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => ref
                                    .read(moneyActionsProvider)
                                    .approvePayout(cycle.id, widget.programmeId),
                              ),
                      child: const Text('Approve'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                                () => ref
                                    .read(moneyActionsProvider)
                                    .executePayout(cycle.id, widget.programmeId),
                              ),
                      child: const Text('Pay out'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Approving and paying out must be done by two different officers.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _date(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${value.day} ${months[value.month - 1]}';
  }
}
