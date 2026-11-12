import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../savings/savings_providers.dart';

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(slug));
    final programmes = ref.watch(groupProgrammesProvider(slug));

    return Scaffold(
      appBar: AppBar(
        title: Text(group.valueOrNull?.name ?? 'Group'),
        actions: [
          IconButton(
            tooltip: 'Group chat',
            onPressed: () => context.push('/groups/$slug/chat'),
            icon: const Icon(Icons.forum_outlined),
          ),
          IconButton(
            tooltip: 'Proposals and votes',
            onPressed: () => context.push('/groups/$slug/vote'),
            icon: const Icon(Icons.how_to_vote_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupProvider(slug));
          ref.invalidate(groupProgrammesProvider(slug));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            group.when(
              data: (value) => _GroupHeader(group: value),
              loading: () => const SizedBox(height: 80),
              error: (error, _) => ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(groupProvider(slug)),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Programmes', style: Theme.of(context).textTheme.titleLarge),
                if (group.valueOrNull?.iAmOfficer == true)
                  TextButton.icon(
                    onPressed: () => _showProgrammeInfo(context),
                    icon: const Icon(Icons.info_outline, size: 18),
                    label: const Text('Officer tools'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            ...switch (programmes) {
              AsyncValue(hasError: true, :final error?) => [
                  ErrorNotice(error: error, onRetry: () => ref.invalidate(groupProgrammesProvider(slug))),
                ],
              AsyncValue(isLoading: true, hasValue: false) => [
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
              AsyncValue(:final value?) => value.isEmpty
                  ? [
                      const EmptyState(
                        icon: Icons.savings_outlined,
                        title: 'No programmes yet',
                        message: 'A programme is where contributions and payouts happen. '
                            'Your officers create the first one.',
                      ),
                    ]
                  : value.map((programme) => _ProgrammeTile(programme: programme)).toList(),
              _ => const [SizedBox.shrink()],
            },
          ],
        ),
      ),
    );
  }

  void _showProgrammeInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        final palette = context.kolo;
        return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Officer tools', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(
              'Recording a cash contribution and approving a rotation payout are officer '
              'actions. They are kept in the app and signed with your account, so a payout '
              'always shows who approved it.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: palette.moneySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: palette.warning),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'A payout needs two different officers: one to approve it, another to '
                      'execute it. The person receiving it cannot approve or execute it.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: palette.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group});

  final GroupSummary group;

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
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                  child: Text(
                    group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                    style: TextStyle(
                      color: palette.surface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(group.name, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        StatusPill(status: group.myRole, label: 'You: ${humanise(group.myRole)}'),
                        const SizedBox(width: 8),
                        if (group.isPrivate)
                          Icon(Icons.lock_outline, size: 14, color: palette.textFaint),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat(label: 'Members', value: '${group.memberCount}'),
              _Stat(label: 'Currency', value: group.currency),
              _Stat(label: 'Category', value: humanise(group.category)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _ProgrammeTile extends StatelessWidget {
  const _ProgrammeTile({required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    final target = programme.target.minor > 0 ? programme.target : programme.expected;
    final percent = target.minor > 0
        ? (programme.collected.minor / target.minor * 100).clamp(0, 100).toDouble()
        : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: KoloCard(
        onTap: () => context.push('/programmes/${programme.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(programme.name, style: Theme.of(context).textTheme.titleMedium),
                ),
                StatusPill(status: programme.status),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${humanise(programme.type)} · ${programme.participantCount} participating · '
              '${programme.contributionAmount.format()}/month',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            CollectionProgress(percent: percent),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${programme.collected.format()} collected',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSoft,
                        fontWeight: FontWeight.w600,
                      ),
                ),
                Text(
                  'of ${target.format()}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
