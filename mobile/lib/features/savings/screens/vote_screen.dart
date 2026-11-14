import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../savings_providers.dart';

/// Decisions the group makes together.
///
/// A secret ballot shows the tally but never who voted which way — because the
/// server never stores that link, not because the app hides it.
class VoteScreen extends ConsumerWidget {
  const VoteScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proposals = ref.watch(groupProposalsProvider(slug));

    final c = context.colors;
    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(groupProposalsProvider(slug)),
          child: switch (proposals) {
            AsyncValue(hasError: true, :final error?) => ListView(
                children: [
                  KoloErrorState(
                    message: error.toString().contains('network')
                        ? 'KOLO could not be reached. Check your connection.'
                        : 'The proposals could not be loaded.',
                    title: 'Decisions did not load',
                    onRetry: () => ref.invalidate(groupProposalsProvider(slug)),
                  ),
                ],
              ),
            AsyncValue(isLoading: true, hasValue: false) => Padding(
                padding: const EdgeInsets.all(KoloSpace.page),
                child: Column(
                  children: const [
                    KoloSkeletonCard(height: 168),
                    SizedBox(height: KoloSpace.md),
                    KoloSkeletonCard(height: 168),
                  ],
                ),
              ),
            AsyncValue(:final value?) => value.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: KoloSpace.hero),
                      KoloEmptyState(
                        icon: Icons.how_to_vote_outlined,
                        title: 'Nothing being voted on',
                        message: 'When your group needs to decide something — a new '
                            'contribution amount, a member leaving early — it appears here '
                            'for everyone to vote.',
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                        KoloSpace.page, KoloSpace.sm, KoloSpace.page, KoloSpace.hero),
                    children: [
                      Row(
                        children: [
                          KoloBackButton(
                              onTap: () => Navigator.of(context).maybePop()),
                          const Spacer(),
                        ],
                      ),
                      const SizedBox(height: KoloSpace.md),
                      const KoloPageHeader(
                        eyebrow: 'What the group is deciding',
                        title: 'Decisions',
                      ),
                      const SizedBox(height: KoloSpace.xl),
                      for (final proposal in value) ...[
                        _ProposalCard(proposal: proposal, slug: slug),
                        const SizedBox(height: KoloSpace.md),
                      ],
                    ],
                  ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }
}

class _ProposalCard extends ConsumerStatefulWidget {
  const _ProposalCard({required this.proposal, required this.slug});

  final Proposal proposal;
  final String slug;

  @override
  ConsumerState<_ProposalCard> createState() => _ProposalCardState();
}

class _ProposalCardState extends ConsumerState<_ProposalCard> {
  bool _busy = false;

  Future<void> _vote(bool inFavour) async {
    final confirm = await koloConfirm(
      context,
      title: inFavour ? 'Vote in favour?' : 'Vote against?',
      message: 'Your vote counts as soon as you confirm and cannot be changed. '
          'On a secret ballot nobody — including KOLO staff — can see how you voted.',
      confirmLabel: 'Cast my vote',
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(moneyActionsProvider).vote(
            proposalId: widget.proposal.id,
            inFavour: inFavour,
          );
      if (!mounted) return;
      koloToast(context, 'Your vote is recorded.');
    } on ApiException catch (error) {
      if (!mounted) return;
      koloToast(context, error.userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final proposal = widget.proposal;
    final total = proposal.totalVotes;
    final forShare = total == 0 ? 0.0 : proposal.votesFor / total;

    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (proposal.isSecret) ...[
                Icon(Icons.visibility_off_outlined, size: 13, color: c.textFaint),
                const SizedBox(width: KoloSpace.xs + 1),
                Text('Secret ballot', style: context.text.bodySmall),
              ],
              const Spacer(),
              KoloStatusPill(status: proposal.status, compact: true),
            ],
          ),
          const SizedBox(height: KoloSpace.md),
          Text(proposal.title, style: context.text.titleMedium),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: KoloSpace.xs + 1),
            Text(
              proposal.description,
              style: context.text.bodySmall?.copyWith(color: c.textSoft, height: 1.45),
            ),
          ],
          const SizedBox(height: KoloSpace.lg),

          // The tally. On a secret ballot this is all anyone ever sees — the
          // server does not store who voted which way, so there is nothing to
          // reveal later either.
          ClipRRect(
            borderRadius: BorderRadius.circular(KoloRadius.full),
            child: Row(
              children: [
                Expanded(
                  flex: (forShare * 1000).round().clamp(1, 1000),
                  child: Container(height: 7, color: c.settled),
                ),
                Expanded(
                  flex: ((1 - forShare) * 1000).round().clamp(1, 1000),
                  child: Container(height: 7, color: c.failedWash),
                ),
              ],
            ),
          ),
          const SizedBox(height: KoloSpace.sm),
          Row(
            children: [
              Text(
                '${proposal.votesFor} for',
                style: context.text.bodySmall?.copyWith(
                  color: c.settled,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '${proposal.votesAgainst} against',
                style: context.text.bodySmall?.copyWith(color: c.textSoft),
              ),
            ],
          ),
          const SizedBox(height: KoloSpace.lg),
          if (proposal.isOpen && !proposal.iHaveVoted) ...[
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => _vote(false),
                      child: const Text('Against', maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: KoloSpace.sm),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: _busy ? null : () => _vote(true),
                      child: const Text('In favour', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: KoloSpace.sm),
            Text(
              'Your vote cannot be changed once cast.',
              style: context.text.bodySmall?.copyWith(color: c.textFaint),
            ),
          ] else if (proposal.iHaveVoted)
            Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 15, color: c.settled),
                const SizedBox(width: KoloSpace.xs + 2),
                Text(
                  'You have voted',
                  style: context.text.bodySmall?.copyWith(
                    color: c.settled,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            Text(
              'Voting has closed.',
              style: context.text.bodySmall?.copyWith(color: c.textFaint),
            ),
        ],
      ),
    );
  }
}
