import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../savings/savings_providers.dart';

/// The cooperative memberships tab.
///
/// Where the dashboard is about *position*, this screen is about *belonging*:
/// which circles the member is in, what each one is currently doing, and the two
/// ways to add another (find one, or start one). Only four per screen are shown
/// per group card's own hierarchy — name, role, size — with the financial detail
/// one tap away rather than crammed in here.
class GroupsTab extends ConsumerWidget {
  const GroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsFreshProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.colors.text,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(myGroupsFreshProvider);
            await ref.read(myGroupsFreshProvider.future);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: KoloPageHeader(
                  eyebrow: 'Cooperatives',
                  title: 'Your groups',
                  actions: [
                    _HeaderAction(
                      icon: Icons.qr_code_scanner_rounded,
                      tooltip: 'Join with a code',
                      onTap: () => context.push('/groups/join'),
                    ),
                  ],
                ),
              ),

              // Two ways in, presented as peers: a member may be invited to an
              // existing circle or may be the one convening a new one.
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, 0, KoloSpace.page, KoloSpace.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: _EntryTile(
                          icon: Icons.search_rounded,
                          label: 'Find a group',
                          onTap: () => context.push('/groups/join'),
                        ),
                      ),
                      const SizedBox(width: KoloSpace.md),
                      Expanded(
                        child: _EntryTile(
                          icon: Icons.add_rounded,
                          label: 'Start a group',
                          onTap: () => context.push('/groups/new'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              ...switch (groups) {
                AsyncValue(hasError: true) => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(KoloSpace.page),
                        child: KoloErrorState(
                          title: 'Your groups did not load',
                          message:
                              'We could not reach KOLO. Nothing has changed on your account.',
                          isOffline: true,
                          onRetry: () => ref.invalidate(myGroupsFreshProvider),
                        ),
                      ),
                    ),
                  ],
                AsyncValue(hasValue: false, isLoading: true) => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.all(KoloSpace.page),
                        child: Column(
                          children: const [
                            KoloSkeletonCard(lines: 3),
                            SizedBox(height: KoloSpace.md),
                            KoloSkeletonCard(lines: 3),
                            SizedBox(height: KoloSpace.md),
                            KoloSkeletonCard(lines: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                AsyncValue(:final value?) => value.value.isEmpty
                    ? [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.all(KoloSpace.page),
                            child: KoloEmptyState(
                              icon: Icons.groups_2_outlined,
                              title: 'No groups yet',
                              message:
                                  'Ajo and esusu work on trust between people who already know '
                                  'each other. Start a circle with the people you save with today, '
                                  'or join one that is already running.',
                              action: FilledButton(
                                onPressed: () => context.push('/groups/new'),
                                child: const Text('Start a group'),
                              ),
                            ),
                          ),
                        ),
                      ]
                    : [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(
                            KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
                          sliver: SliverList.separated(
                            itemCount: value.value.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: KoloSpace.md),
                            itemBuilder: (context, i) =>
                                _MembershipCard(group: value.value[i]),
                          ),
                        ),
                      ],
                _ => [const SliverToBoxAdapter(child: SizedBox.shrink())],
              },

              const SliverToBoxAdapter(child: SizedBox(height: KoloSpace.hero)),
            ],
          ),
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
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(KoloRadius.sm),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(KoloRadius.sm),
              border: Border.all(color: c.hairline),
            ),
            child: Icon(icon, size: 19, color: c.text),
          ),
        ),
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(KoloRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: KoloSpace.md, vertical: KoloSpace.md),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(KoloRadius.md),
            border: Border.all(color: c.hairline),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: c.text),
              const SizedBox(width: KoloSpace.sm + 2),
              Flexible(
                child: Text(
                  label,
                  style: context.text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A membership card.
///
/// The left edge carries a citrus rule when the member holds an office in the
/// group (founder, admin, treasurer) — a quiet signal of responsibility that
/// does not require reading a label to notice.
class _MembershipCard extends StatelessWidget {
  const _MembershipCard({required this.group});

  final GroupSummary group;

  bool get _isOfficer =>
      const {'founder', 'admin', 'treasurer', 'owner'}.contains(group.myRole.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final private = group.visibility != 'public';

    return KoloCard(
      onTap: () => context.push('/groups/${group.slug}'),
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isOfficer)
              Container(width: 3, color: c.accent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(KoloSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            group.name,
                            style: context.text.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (private)
                          Icon(Icons.lock_outline_rounded, size: 13, color: c.textFaint),
                      ],
                    ),
                    const SizedBox(height: KoloSpace.sm + 2),
                    Row(
                      children: [
                        KoloStatusPill(
                          status: 'active',
                          label: group.myRole.isEmpty
                              ? 'Member'
                              : group.myRole[0].toUpperCase() + group.myRole.substring(1),
                          compact: true,
                        ),
                        const SizedBox(width: KoloSpace.sm),
                        Expanded(
                          child: Text(
                            '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'}',
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, size: 18, color: c.textFaint),
                      ],
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
}
