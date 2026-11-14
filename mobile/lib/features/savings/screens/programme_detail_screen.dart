import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';

import '../savings_providers.dart';

/// The programme screen: what is collected, whose turn is next, and — always —
/// whether the payout is actually funded yet.
class ProgrammeDetailScreen extends ConsumerWidget {
  const ProgrammeDetailScreen({super.key, required this.programmeId});

  final String programmeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.colors;
    final programme = ref.watch(programmeProvider(programmeId));
    final cycles = ref.watch(programmeCyclesProvider(programmeId));

    return Scaffold(
      backgroundColor: palette.ground,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(programmeProvider(programmeId));
          ref.invalidate(programmeCyclesProvider(programmeId));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              KoloSpace.page, KoloSpace.sm, KoloSpace.page, KoloSpace.hero),
          children: [
            Row(
              children: [
                KoloBackButton(onTap: () => Navigator.of(context).maybePop()),
                const Spacer(),
                // Money out gets its own screen: a payout needs an account number
                // and a second officer, which does not belong in a header button.
                if (programme.value != null)
                  TextButton.icon(
                    onPressed: () => context.push(
                      '/programmes/$programmeId/payouts',
                      extra: {
                        'name': programme.value!.name,
                        'currency': programme.value!.currency,
                        'slug': programme.value!.groupSlug,
                      },
                    ),
                    icon: const Icon(Icons.account_balance_outlined, size: 17),
                    label: const Text('Payouts'),
                  ),
              ],
            ),
            const SizedBox(height: KoloSpace.md),
            programme.when(
              data: (value) => _ProgrammeSummary(programme: value),
              loading: () => const KoloSkeletonCard(height: 220),
              error: (error, _) => KoloErrorState(
                message: 'This programme could not be loaded. Pull down to try again.',
                title: 'Programme did not load',
                onRetry: () => ref.invalidate(programmeProvider(programmeId)),
              ),
            ),
            const SizedBox(height: KoloSpace.section),
            Text('This cycle', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: KoloSpace.md),
            ...switch (cycles) {
              AsyncValue(hasError: true) => [
                  const KoloNotice(
                    message: 'The cycles for this programme could not be loaded.',
                    tone: KoloNoticeTone.warning,
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
              AsyncValue(isLoading: true, hasValue: false) => [
                  const KoloSkeletonCard(height: 132),
                ],
              AsyncValue(:final value?) => value.isEmpty
                  ? [
                      const KoloEmptyState(
                        icon: Icons.event_repeat_outlined,
                        title: 'No cycle open',
                        message: 'A cycle opens when the programme starts collecting.',
                      ),
                    ]
                  : [for (final cycle in value) _CycleCard(cycle: cycle, programmeId: programmeId)],
              _ => const [SizedBox.shrink()],
            },
            const SizedBox(height: KoloSpace.xl),
            programme.when(
              data: (value) => value.isActive
                  ? SizedBox(
                      height: 52,
                      child: FilledButton(
                        onPressed: () =>
                            context.push('/programmes/$programmeId/contribute'),
                        child: const Text('Make a contribution'),
                      ),
                    )
                  : KoloNotice(
                      message: 'This programme is ${koloHumanise(value.status).toLowerCase()}, '
                          'so it is not collecting right now.',
                      tone: KoloNoticeTone.neutral,
                      icon: Icons.pause_circle_outline_rounded,
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
    final c = context.colors;
    final target = programme.target.minor > 0 ? programme.target : programme.expected;
    final percent = target.minor > 0
        ? (programme.collected.minor / target.minor * 100).clamp(0, 100).toDouble()
        : 0.0;

    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(programme.name, style: Theme.of(context).textTheme.headlineSmall),
              ),
              const SizedBox(width: KoloSpace.sm),
              KoloStatusPill(status: programme.status, compact: true),
            ],
          ),
          const SizedBox(height: KoloSpace.xl),
          Text('COLLECTED SO FAR', style: KoloType.eyebrow(c)),
          const SizedBox(height: KoloSpace.sm),
          KoloAmount(money: programme.collected, size: 32),
          const SizedBox(height: KoloSpace.xs),
          Text('of ${target.format()} expected', style: context.text.bodySmall),
          const SizedBox(height: KoloSpace.lg),
          KoloProgress(
            value: percent / 100,
            height: 7,
            semanticLabel: 'Collected',
          ),
          const SizedBox(height: KoloSpace.xl),
          Divider(color: c.hairline, height: 1),
          const SizedBox(height: KoloSpace.lg),
          _FactRow(
            label: 'Contribution per member',
            value: programme.contributionAmount.format(),
          ),
          const SizedBox(height: KoloSpace.sm + 2),
          _FactRow(label: 'Frequency', value: koloHumanise(programme.frequency)),
          const SizedBox(height: KoloSpace.sm + 2),
          _FactRow(label: 'Participants', value: '${programme.participantCount}'),
          const SizedBox(height: KoloSpace.lg),
          KoloNotice(
            message: 'This figure counts money that has actually been confirmed — not '
                'what members have promised.',
            tone: KoloNoticeTone.neutral,
            icon: Icons.verified_outlined,
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
      koloToast(
        context,
        error.isFinancialRefusal
            ? 'Not yet — ${error.userMessage}'
            : error.userMessage,
        isError: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cycle = widget.cycle;
    final percent = cycle.payoutAmount.minor > 0
        ? (cycle.collectedTotal.minor / cycle.payoutAmount.minor * 100).clamp(0, 100).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: KoloSpace.md),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                KoloStatusPill(status: cycle.status, compact: true),
              ],
            ),
            const SizedBox(height: 14),
            KoloProgress(value: percent / 100, height: 7, semanticLabel: 'Cycle funding'),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(cycle.collectedTotal.format(), style: KoloType.money(c, size: 15, weight: FontWeight.w600)),
                Text(
                  'of ${cycle.payoutAmount.format()}',
                  style: context.text.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // The honest line: what is still missing, in money.
            if (!cycle.isPaid && cycle.shortfall.minor > 0)
              KoloNotice(
                message: '${cycle.shortfall.format()} still to collect before this payout '
                    'can be made. KOLO will not pay out money the group has not received.',
                tone: KoloNoticeTone.warning,
                icon: Icons.savings_outlined,
              ),
            if (cycle.isPaid)
              Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 15, color: c.settled),
                  const SizedBox(width: KoloSpace.xs + 2),
                  Text(
                    'Paid${cycle.paidAt != null ? ' on ${_date(cycle.paidAt!)}' : ''}',
                    style: context.text.bodySmall?.copyWith(
                      color: c.settled,
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
                    child: SizedBox(
                      height: 46,
                      child: OutlinedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => ref
                                      .read(moneyActionsProvider)
                                      .approvePayout(cycle.id, widget.programmeId),
                                ),
                        child: const Text('Approve', maxLines: 1),
                      ),
                    ),
                  ),
                  const SizedBox(width: KoloSpace.sm),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                  () => ref
                                      .read(moneyActionsProvider)
                                      .executePayout(cycle.id, widget.programmeId),
                                ),
                        child: const Text('Pay out', maxLines: 1),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: KoloSpace.sm),
              Text(
                'Approving and paying out must be done by two different officers.',
                style: context.text.bodySmall?.copyWith(color: c.textFaint),
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

class _FactRow extends StatelessWidget {
  const _FactRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: context.text.bodySmall),
        ),
        const SizedBox(width: KoloSpace.md),
        Text(value, style: context.text.titleSmall),
      ],
    );
  }
}
