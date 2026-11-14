import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';

import '../../savings/savings_providers.dart';

/// A group's home.
///
/// The screen answers, in order: which group is this and what am I here, what
/// money is in play, what programmes are running, and what can I do about it.
/// Officer powers are surfaced where they are used rather than collected in a
/// settings drawer nobody opens.
class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupProvider(slug));
    final programmes = ref.watch(groupProgrammesProvider(slug));

    return Scaffold(
      backgroundColor: context.colors.ground,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupProvider(slug));
          ref.invalidate(groupProgrammesProvider(slug));
        },
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: context.colors.ground,
              surfaceTintColor: Colors.transparent,
              leading: Padding(
                padding: const EdgeInsets.only(left: KoloSpace.sm),
                child: Center(
                  child: KoloBackButton(
                    onTap: () => context.canPop() ? context.pop() : context.go('/groups'),
                  ),
                ),
              ),
              leadingWidth: 60,
              actions: [
                _HeaderAction(
                  icon: Icons.forum_outlined,
                  tooltip: 'Group chat',
                  onTap: () => context.push('/groups/$slug/chat'),
                ),
                _HeaderAction(
                  icon: Icons.how_to_vote_outlined,
                  tooltip: 'Proposals',
                  onTap: () => context.push('/groups/$slug/vote'),
                ),
                const SizedBox(width: KoloSpace.sm),
              ],
              title: group.maybeWhen(
                data: (g) => Text(g.name, style: context.text.titleMedium),
                orElse: () => const SizedBox.shrink(),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                KoloSpace.page, 0, KoloSpace.page, KoloSpace.hero),
              sliver: SliverList.list(
                children: [
                  ...switch (group) {
                    AsyncValue(hasError: true, :final error?) => [
                        KoloErrorState(
                          message: _friendly(error),
                          onRetry: () => ref.invalidate(groupProvider(slug)),
                        ),
                      ],
                    AsyncValue(isLoading: true, hasValue: false) => [
                        const KoloSkeletonCard(height: 150),
                      ],
                    AsyncValue(:final value?) => [
                        _GroupHeadline(group: value),
                        const SizedBox(height: KoloSpace.section),
                        _ActionsRow(group: value),
                      ],
                    _ => const [SizedBox.shrink()],
                  },
                  const SizedBox(height: KoloSpace.section),
                  KoloSectionHeader(
                    title: 'Programmes',
                    inset: false,
                    action: group.value?.iAmOfficer == true
                        ? TextButton(
                            onPressed: () => _showOfficerInfo(context),
                            child: const Text('Officer tools'),
                          )
                        : null,
                  ),
                  const SizedBox(height: KoloSpace.md),
                  ...switch (programmes) {
                    AsyncValue(hasError: true, :final error?) => [
                        KoloErrorState(
                          message: _friendly(error),
                          title: 'Programmes did not load',
                          onRetry: () => ref.invalidate(groupProgrammesProvider(slug)),
                        ),
                      ],
                    AsyncValue(isLoading: true, hasValue: false) => [
                        const KoloSkeletonCard(height: 108),
                        const SizedBox(height: KoloSpace.md),
                        const KoloSkeletonCard(height: 108),
                      ],
                    AsyncValue(:final value?) => value.isEmpty
                        ? [
                            KoloEmptyState(
                              icon: Icons.savings_outlined,
                              title: 'No programmes yet',
                              message:
                                  'A programme is what holds the money: who contributes, '
                                  'how often, and the order payouts go out. An officer creates '
                                  'the first one.',
                              action: null,
                            ),
                          ]
                        : [
                            for (final p in value) ...[
                              _ProgrammeTile(programme: p),
                              const SizedBox(height: KoloSpace.md),
                            ],
                          ],
                    _ => const [SizedBox.shrink()],
                  },
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _friendly(Object error) {
    final text = error.toString();
    if (text.contains('not_a_member') || text.contains('403')) {
      return 'You are not a member of this group. Ask an officer for an invitation.';
    }
    if (text.contains('network') || text.contains('SocketException')) {
      return 'KOLO could not be reached. Check your connection.';
    }
    return 'This group could not be loaded. Pull down to try again.';
  }

  void _showOfficerInfo(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: context.colors.surface,
      builder: (sheetContext) => KoloSheet(
        title: 'Officer tools',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Recording a cash contribution and paying out a rotation are officer '
              'actions. They are kept in the app and signed with your account, so a '
              'payout always shows who approved it.',
              style: Theme.of(sheetContext).textTheme.bodyMedium,
            ),
            const SizedBox(height: KoloSpace.lg),
            KoloNotice(
              message:
                  'A payout needs two different officers: one to approve it, another to '
                  'execute it. The person receiving it cannot approve or execute their own '
                  'payout.',
              tone: KoloNoticeTone.warning,
              icon: Icons.shield_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 21),
      color: c.textSoft,
    );
  }
}

/// The identity block: who this group is, what the member's standing is, and the
/// two figures that matter — how many people are in it and what currency the
/// money is kept in.
class _GroupHeadline extends StatelessWidget {
  const _GroupHeadline({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.accent,
                borderRadius: BorderRadius.circular(KoloRadius.lg),
              ),
              alignment: Alignment.center,
              child: Text(
                group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                style: TextStyle(
                  fontFamily: KoloType.family,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: c.accentOn,
                ),
              ),
            ),
            const SizedBox(width: KoloSpace.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your standing',
                    style: KoloType.eyebrow(c),
                  ),
                  const SizedBox(height: KoloSpace.xs + 2),
                  Text(
                    _capitalise(koloHumanise(group.myRole)),
                    style: context.text.headlineSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: KoloSpace.sm),
                  Wrap(
                    spacing: KoloSpace.sm,
                    runSpacing: KoloSpace.sm,
                    children: [
                      KoloStatusPill(
                        status: group.isPrivate ? 'restricted' : 'active',
                        label: group.isPrivate ? 'Private' : 'Public',
                        compact: true,
                      ),
                      if (group.requiresApproval)
                        KoloStatusPill(
                          status: 'pending',
                          label: 'Approval needed',
                          compact: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: KoloSpace.xl),
        Row(
          children: [
            _Fact(
              icon: Icons.people_alt_outlined,
              value: '${group.memberCount}',
              label: group.memberCount == 1 ? 'member' : 'members',
            ),
            _Fact(
              icon: Icons.payments_outlined,
              value: group.currency,
              label: 'currency',
            ),
            _Fact(
              icon: Icons.category_outlined,
              value: _capitalise(koloHumanise(group.category)),
              label: 'type',
            ),
          ],
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: c.textFaint),
          const SizedBox(height: KoloSpace.sm),
          Text(
            value,
            style: context.text.titleMedium,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(label, style: context.text.bodySmall),
        ],
      ),
    );
  }
}

/// The things a member actually comes here to do. Two primary actions at most;
/// conversation and governance live in the header where they belong.
class _ActionsRow extends StatelessWidget {
  const _ActionsRow({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 50,
            child: FilledButton.icon(
              onPressed: () => context.push('/contributions'),
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('Contribute'),
            ),
          ),
        ),
        const SizedBox(width: KoloSpace.md),
        Expanded(
          child: SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/groups/${group.slug}/vote'),
              icon: const Icon(Icons.how_to_vote_outlined, size: 18),
              label: const Text('Vote'),
            ),
          ),
        ),
      ],
    );
  }
}

class _ProgrammeTile extends StatelessWidget {
  const _ProgrammeTile({required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final target = programme.target.minor > 0 ? programme.target : programme.expected;
    final percent = programme.progressPercent > 0
        ? programme.progressPercent
        : (target.minor > 0
            ? (programme.collected.minor / target.minor * 100).clamp(0, 100).toDouble()
            : 0.0);

    return KoloCard(
      onTap: () => context.push('/programmes/${programme.id}'),
      padding: const EdgeInsets.all(KoloSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      programme.name,
                      style: context.text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_capitalise(koloHumanise(programme.type))} · '
                      '${programme.participantCount} participating',
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KoloSpace.sm),
              KoloStatusPill(status: programme.status, compact: true),
            ],
          ),
          const SizedBox(height: KoloSpace.lg),
          KoloProgress(value: percent / 100),
          const SizedBox(height: KoloSpace.sm + 2),
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: programme.collected.format(),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: c.text,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      TextSpan(
                        text: ' of ${target.format()}',
                        style: TextStyle(color: c.textSoft),
                      ),
                    ],
                  ),
                  style: context.text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: KoloSpace.sm),
              Text(
                programme.contributionAmount.format(),
                style: KoloType.money(c, size: 12.5, color: c.textSoft),
              ),
              Text(
                '/${_shortFrequency(programme.frequency)}',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _shortFrequency(String frequency) => switch (frequency.toLowerCase()) {
        'weekly' => 'wk',
        'daily' => 'day',
        'biweekly' => '2wk',
        'quarterly' => 'qtr',
        _ => 'mo',
      };
}

String _capitalise(String value) =>
    value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);
