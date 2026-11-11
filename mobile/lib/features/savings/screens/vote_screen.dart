import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
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

    return Scaffold(
      appBar: AppBar(title: const Text('Decisions')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(groupProposalsProvider(slug)),
        child: switch (proposals) {
          AsyncValue(hasError: true, :final error?) => Padding(
              padding: const EdgeInsets.all(20),
              child: ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(groupProposalsProvider(slug)),
              ),
            ),
          AsyncValue(isLoading: true, hasValue: false) =>
            const Center(child: CircularProgressIndicator()),
          AsyncValue(:final value?) => value.isEmpty
              ? const EmptyState(
                  icon: Icons.how_to_vote_outlined,
                  title: 'Nothing being voted on',
                  message: 'When your group needs to decide something — a new contribution amount, '
                      'a member leaving early — it appears here for everyone to vote.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  itemCount: value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) =>
                      _ProposalCard(proposal: value[index], slug: slug),
                ),
          _ => const SizedBox.shrink(),
        },
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
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(inFavour ? 'Vote in favour?' : 'Vote against?'),
        content: const Text(
          'Your vote counts as soon as you confirm and cannot be changed. '
          'On a secret ballot, nobody — including KOLO staff — can see how you voted.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(moneyActionsProvider).vote(
            proposalId: widget.proposal.id,
            inFavour: inFavour,
          );
      if (!mounted) return;
      showMessage(context, 'Your vote is recorded.');
    } on ApiException catch (error) {
      if (!mounted) return;
      showMessage(context, error.userMessage, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                const Icon(Icons.visibility_off_outlined, size: 15, color: KoloColors.inkFaint),
                const SizedBox(width: 5),
                Text('Secret ballot', style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(width: 10),
              ],
              const Spacer(),
              StatusPill(status: proposal.status),
            ],
          ),
          const SizedBox(height: 10),
          Text(proposal.title, style: Theme.of(context).textTheme.titleMedium),
          if (proposal.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(proposal.description, style: Theme.of(context).textTheme.bodyMedium),
          ],
          const SizedBox(height: 16),
          // Tally. On a secret ballot this is all anyone sees.
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Expanded(
                  flex: (forShare * 1000).round().clamp(1, 1000),
                  child: Container(height: 8, color: KoloColors.success),
                ),
                Expanded(
                  flex: ((1 - forShare) * 1000).round().clamp(1, 1000),
                  child: Container(height: 8, color: KoloColors.dangerSoft),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${proposal.votesFor} for',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: KoloColors.success,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                '${proposal.votesAgainst} against',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (proposal.isOpen && !proposal.iHaveVoted) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy ? null : () => _vote(false),
                    child: const Text('Against'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : () => _vote(true),
                    child: const Text('In favour'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Your vote cannot be changed once cast.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (proposal.iHaveVoted)
            Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: KoloColors.success),
                const SizedBox(width: 6),
                Text(
                  'You have voted',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: KoloColors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            )
          else
            Text(
              'Voting has closed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
