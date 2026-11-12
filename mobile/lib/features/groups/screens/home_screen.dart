import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../../auth/auth_controller.dart';
import '../../../core/offline/offline_cache.dart';
import '../../savings/savings_providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final session = ref.watch(sessionProvider);
    final groups = ref.watch(myGroupsProvider);
    // Whether what is on screen came from the network or from the last saved
    // copy. The member is told either way; a silent fallback would let a stale
    // list look like a live one.
    final groupsFresh = ref.watch(myGroupsFreshProvider).valueOrNull;
    final obligations = ref.watch(myObligationsProvider);

    final name = session.valueOrNull?.displayName ?? 'there';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myGroupsFreshProvider);
            ref.invalidate(myObligationsProvider);
            ref.invalidate(myContributionsProvider);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hello, $name',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _todayLine(),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => context.push('/notifications'),
                        icon: const Icon(Icons.notifications_none_rounded),
                        tooltip: 'Notifications',
                      ),
                      IconButton(
                        onPressed: () => context.push('/profile'),
                        icon: CircleAvatar(
                          radius: 16,
                          backgroundColor: palette.accent,
                          child: Icon(Icons.person_outline, size: 18, color: palette.surface),
                        ),
                        tooltip: 'Profile',
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: obligations.when(
                    data: (rows) => rows.isEmpty ? const SizedBox.shrink() : _DueCard(obligations: rows),
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Your groups', style: Theme.of(context).textTheme.titleLarge),
                      TextButton.icon(
                        onPressed: () => context.push('/groups/join'),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Join'),
                      ),
                    ],
                  ),
                ),
              ),
              if (groupsFresh != null && groupsFresh.fromCache)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                    child: CachedNotice(
                      ageLabel: groupsFresh.ageLabel,
                      onRetry: () => ref.invalidate(myGroupsFreshProvider),
                    ),
                  ),
                ),
              ...switch (groups) {
                AsyncValue(hasError: true, :final error?) => [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: ErrorNotice(
                          error: error,
                          onRetry: () => ref.invalidate(myGroupsFreshProvider),
                        ),
                      ),
                    ),
                  ],
                AsyncValue(isLoading: true, hasValue: false) => [
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ),
                  ],
                AsyncValue(:final value?) => value.isEmpty
                    ? [
                        SliverToBoxAdapter(
                          child: EmptyState(
                            icon: Icons.groups_outlined,
                            title: 'No groups yet',
                            message:
                                'Join a savings group or start your own. Most people begin with '
                                'the people they already save with.',
                            action: FilledButton.tonal(
                              onPressed: () => context.push('/groups/new'),
                              child: const Text('Start a group'),
                            ),
                          ),
                        ),
                      ]
                    : [
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          sliver: SliverList.separated(
                            itemCount: value.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) => _GroupTile(group: value[index]),
                          ),
                        ),
                      ],
                _ => const [SliverToBoxAdapter(child: SizedBox.shrink())],
              },
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/groups/new'),
        backgroundColor: palette.accent,
        foregroundColor: palette.surface,
        icon: const Icon(Icons.add),
        label: const Text('New group'),
      ),
    );
  }

  static String _todayLine() {
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    final now = DateTime.now();
    return '${days[now.weekday - 1]}, ${now.day} ${months[now.month - 1]}';
  }
}

/// "You owe 10,000 this cycle" — the single most useful thing on the home screen.
class _DueCard extends StatelessWidget {
  const _DueCard({required this.obligations});

  final List<Obligation> obligations;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    final total = obligations.fold<int>(0, (sum, item) => sum + item.outstanding.minor);
    final currency = obligations.first.outstanding.currency;
    final overdue = obligations.where((o) => o.isOverdue).length;

    return Container(
      decoration: BoxDecoration(
        color: palette.accent,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            overdue > 0 ? 'Overdue' : 'Due this cycle',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white.withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _amount(total, currency),
            style: const TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${obligations.length} contribution${obligations.length == 1 ? '' : 's'} '
            'across your groups',
            style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }

  static String _amount(int minor, String currency) {
    final major = minor ~/ 100;
    final decimals = minor % 100;
    final grouped = major.toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'),
          (m) => '${m[1]},',
        );
    return '${_symbol(currency)}$grouped${decimals == 0 ? '' : '.${decimals.toString().padLeft(2, '0')}'}';
  }

  static String _symbol(String currency) => switch (currency) {
        'NGN' => '₦',
        'USD' => r'$',
        'GBP' => '£',
        'EUR' => '€',
        _ => '$currency ',
      };
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return KoloCard(
      onTap: () => context.push('/groups/${group.slug}'),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: palette.ground,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: palette.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        group.name,
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (group.isPrivate) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.lock_outline, size: 14, color: palette.textFaint),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${group.memberCount} member${group.memberCount == 1 ? '' : 's'} · '
                  '${humanise(group.myRole)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: palette.textFaint),
        ],
      ),
    );
  }
}
