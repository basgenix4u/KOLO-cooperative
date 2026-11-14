import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/models/models.dart';
import '../../../core/models/money.dart';
import '../../../core/offline/offline_cache.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../../auth/auth_controller.dart';
import '../../savings/savings_providers.dart';

/// The member's financial position, in one screen.
///
/// The structure follows the single question a savings-group member opens the
/// app to answer: *where do I stand, and what do I owe?* Everything on screen is
/// ordered against that.
///
///   1. Position   — one hero figure: what is committed across every group.
///   2. Obligation — what is due, if anything. This is the only element that
///                   earns citrus, because it is the only one that asks the
///                   member to act.
///   3. Groups     — where the money is, at a glance.
///   4. Activity   — what actually happened, most recent first.
///
/// Deliberately absent: charts of spending trends (there are none — this is a
/// savings product, not a current account), promotional cards, and any figure
/// the backend does not actually return.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final groupsFresh = ref.watch(myGroupsFreshProvider);
    final obligations = ref.watch(myObligationsProvider);
    final contributions = ref.watch(myContributionsProvider);

    final profile = session.value;
    final name = profile?.fullName.trim().split(' ').firstOrNull ?? 'there';

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color: context.colors.text,
          backgroundColor: context.colors.surface,
          onRefresh: () async {
            ref.invalidate(myGroupsFreshProvider);
            ref.invalidate(myObligationsProvider);
            ref.invalidate(myContributionsProvider);
            // Wait for the refresh to land so the spinner is honest about how
            // long the work took.
            await ref.read(myGroupsFreshProvider.future);
          },
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _Greeting(name: name)),

              // --- 1. Position ------------------------------------------
              SliverToBoxAdapter(
                child: _PositionCard(
                  obligations: obligations,
                  groups: groupsFresh,
                ),
              ),

              // --- 2. Obligation ---------------------------------------
              SliverToBoxAdapter(
                child: obligations.maybeWhen(
                  data: (rows) => rows.isEmpty
                      ? const SizedBox.shrink()
                      : _ObligationCard(rows: rows),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),

              // Cached-data honesty. If the list on screen is a saved copy the
              // member is told so, and told how old it is.
              SliverToBoxAdapter(
                child: groupsFresh.maybeWhen(
                  data: (fresh) => fresh.fromCache
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(
                            KoloSpace.page, KoloSpace.lg, KoloSpace.page, 0),
                          child: KoloNotice(
                            icon: Icons.cloud_off_rounded,
                            tone: KoloNoticeTone.warning,
                            message:
                                'Showing a saved copy from ${fresh.ageLabel}. Pull down to refresh.',
                          ),
                        )
                      : const SizedBox.shrink(),
                  orElse: () => const SizedBox.shrink(),
                ),
              ),

              // --- 3. Groups -------------------------------------------
              SliverToBoxAdapter(
                child: KoloSectionHeader(
                  eyebrow: 'Your cooperatives',
                  title: 'Where you save',
                  action: TextButton(
                    onPressed: () => context.push('/groups/join'),
                    child: const Text('Find a group'),
                  ),
                ),
              ),
              ..._groupSlivers(context, ref, groupsFresh),

              // --- 4. Activity -----------------------------------------
              SliverToBoxAdapter(
                child: KoloSectionHeader(
                  eyebrow: 'Recent',
                  title: 'Money movement',
                  action: TextButton(
                    onPressed: () => context.push('/contributions'),
                    child: const Text('See all'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                  child: _ActivityCard(contributions: contributions),
                ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: KoloSpace.hero)),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _groupSlivers(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<Fresh<List<GroupSummary>>> groups,
  ) {
    return switch (groups) {
      AsyncValue(hasError: true, :final error?) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
              child: KoloErrorState(
                title: 'Could not load your groups',
                message: _friendly(error),
                isOffline: true,
                onRetry: () => ref.invalidate(myGroupsFreshProvider),
              ),
            ),
          ),
        ],
      AsyncValue(hasValue: false, isLoading: true) => [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
              child: Column(
                children: const [
                  KoloSkeletonCard(),
                  SizedBox(height: KoloSpace.md),
                  KoloSkeletonCard(),
                ],
              ),
            ),
          ),
        ],
      AsyncValue(:final value?) => value.value.isEmpty
          ? [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                  child: KoloCard(
                    child: KoloEmptyState(
                      icon: Icons.groups_2_outlined,
                      title: 'You are not in a group yet',
                      message:
                          'A cooperative is how ajo and esusu work in practice: a small '
                          'circle, a fixed contribution, a turn for everyone. Join one, or '
                          'start one with people you already trust.',
                      action: FilledButton(
                        onPressed: () => context.push('/groups/join'),
                        child: const Text('Find your first group'),
                      ),
                    ),
                  ),
                ),
              ),
            ]
          : [
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                sliver: SliverList.separated(
                  itemCount: value.value.length,
                  separatorBuilder: (_, __) => const SizedBox(height: KoloSpace.md),
                  itemBuilder: (context, i) => _GroupCard(group: value.value[i]),
                ),
              ),
            ],
      _ => [const SliverToBoxAdapter(child: SizedBox.shrink())],
    };
  }
}

/// Greeting and the two top-level actions. Small on purpose: it must not
/// compete with the balance for attention.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoloSpace.page, KoloSpace.lg, KoloSpace.page, KoloSpace.lg),
      child: Row(
        children: [
          const KoloMark(size: 22),
          const SizedBox(width: KoloSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _partOfDay(),
                  style: TextStyle(
                    fontFamily: KoloType.family,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: c.textFaint,
                  ),
                ),
                Text(
                  name,
                  style: context.text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _IconAction(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Notifications',
            onTap: () => context.push('/notifications'),
          ),
          const SizedBox(width: KoloSpace.sm),
          _IconAction(
            icon: Icons.person_outline_rounded,
            tooltip: 'Your account',
            onTap: () => context.push('/profile'),
          ),
        ],
      ),
    );
  }

  static String _partOfDay() {
    final h = DateTime.now().hour;
    if (h < 12) return 'GOOD MORNING';
    if (h < 17) return 'GOOD AFTERNOON';
    return 'GOOD EVENING';
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.tooltip, required this.onTap});

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

/// The hero: total committed across every cooperative, with the count of active
/// groups and any overdue amount directly beneath it.
///
/// Midnight Ink fills, citrus only for the number. Inverting the card is what
/// makes the position unmistakable at arm's length on a phone held in daylight.
class _PositionCard extends StatelessWidget {
  const _PositionCard({required this.obligations, required this.groups});

  final AsyncValue<List<Obligation>> obligations;
  final AsyncValue<Fresh<List<GroupSummary>>> groups;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groupCount = groups.value?.value.length ?? 0;

    // Total committed = everything paid across current obligations plus what is
    // still outstanding. Summed in minor units, never as a double.
    var total = const Money(0, 'NGN');
    var overdue = const Money(0, 'NGN');
    var hasData = false;
    obligations.whenData((rows) {
      hasData = true;
      for (final row in rows) {
        total = total + row.paid;
        if (row.isOverdue) overdue = overdue + row.outstanding;
      }
    });

    final currency = obligations.value?.isNotEmpty == true
        ? obligations.value!.first.amount.currency
        : (groups.value?.value.isNotEmpty == true ? 'NGN' : 'NGN');
    final shown = Money(total.minor, currency);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(KoloSpace.xl),
        decoration: BoxDecoration(
          color: c.isDark ? c.surface : const Color(0xFF101820),
          borderRadius: BorderRadius.circular(KoloRadius.xl),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'CONTRIBUTED',
                  style: TextStyle(
                    fontFamily: KoloType.family,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
                const Spacer(),
                if (groupCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: KoloSpace.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: KoloBrand.citrus.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(KoloRadius.full),
                    ),
                    child: Text(
                      '$groupCount ${groupCount == 1 ? 'group' : 'groups'}',
                      style: TextStyle(
                        fontFamily: KoloType.family,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: KoloBrand.citrus,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: KoloSpace.md),
            if (hasData)
              KoloAmount(
                money: shown,
                size: 38,
                color: Colors.white,
                weight: FontWeight.w700,
              )
            else
              const KoloSkeleton(width: 180, height: 34, radius: 8),
            const SizedBox(height: KoloSpace.lg),
            // Divider inside the inverted card, tinted rather than a hairline.
            Container(height: 1, color: Colors.white.withValues(alpha: 0.10)),
            const SizedBox(height: KoloSpace.md),
            Row(
              children: [
                Expanded(
                  child: _InvertedMetric(
                    label: 'Outstanding',
                    value: overdue.minor > 0 ? overdue.format() : 'Nothing due',
                    highlight: overdue.minor > 0,
                  ),
                ),
                Container(
                  width: 1,
                  height: 26,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                const SizedBox(width: KoloSpace.lg),
                Expanded(
                  child: _InvertedMetric(
                    label: 'Groups',
                    value: hasData || groupCount > 0 ? '$groupCount active' : '—',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InvertedMetric extends StatelessWidget {
  const _InvertedMetric({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
            color: Colors.white.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: KoloType.family,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: highlight ? KoloBrand.citrus : Colors.white,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// What the member owes, and the single action that resolves it.
///
/// This is the only card that gets a citrus accent: it is the one thing on the
/// screen that is waiting on them.
class _ObligationCard extends StatelessWidget {
  const _ObligationCard({required this.rows});

  final List<Obligation> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overdue = rows.where((r) => r.isOverdue).toList();
    final next = rows.first;
    final urgent = overdue.isNotEmpty;
    final effective = urgent ? overdue.first : next;
    final totalDue = rows.fold<Money>(
      const Money(0, 'NGN'),
      (sum, r) => sum + r.outstanding,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        KoloSpace.page, KoloSpace.lg, KoloSpace.page, 0),
      child: KoloCard(
        color: urgent ? c.failedWash : c.accentWash,
        border: urgent
            ? c.failed.withValues(alpha: 0.28)
            : c.accent.withValues(alpha: 0.55),
        padding: const EdgeInsets.all(KoloSpace.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  urgent ? Icons.priority_high_rounded : Icons.event_available_rounded,
                  size: 15,
                  color: urgent ? c.failed : c.text,
                ),
                const SizedBox(width: KoloSpace.sm),
                Expanded(
                  child: Text(
                    urgent ? 'Overdue contribution' : 'Due next',
                    style: TextStyle(
                      fontFamily: KoloType.family,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: urgent ? c.failed : c.text,
                    ),
                  ),
                ),
                if (rows.length > 1)
                  Text(
                    '${rows.length} open',
                    style: context.text.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: KoloSpace.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        effective.programmeName,
                        style: context.text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dueLabel(effective.dueDate, urgent),
                        style: context.text.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: KoloSpace.md),
                KoloAmountSmall(
                  money: effective.outstanding,
                  size: 17,
                  color: urgent ? c.failed : c.text,
                ),
              ],
            ),
            const SizedBox(height: KoloSpace.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: rows.length > 1
                    ? () => context.push('/contributions')
                    : () => context.push('/programmes/${effective.programmeId}/contribute'),
                child: Text(
                  rows.length > 1 ? 'Pay $totalDue' : 'Contribute ${effective.outstanding.format()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _dueLabel(DateTime? due, bool overdue) {
    if (due == null) return overdue ? 'Past due' : 'No date set';
    final now = DateTime.now();
    final days = DateTime(due.year, due.month, due.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) return '${-days} ${-days == 1 ? 'day' : 'days'} late';
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    if (days <= 14) return 'Due in $days days';
    return 'Due ${due.day}/${due.month}/${due.year}';
  }
}

/// A membership, told as a financial object rather than a social one: name,
/// role, how many people, and how the money is going.
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final GroupSummary group;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isRestricted = group.visibility == 'restricted' || group.visibility == 'private';

    return KoloCard(
      onTap: () => context.push('/groups/${group.slug}'),
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
                      group.name,
                      style: context.text.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          isRestricted ? Icons.lock_outline_rounded : Icons.public_rounded,
                          size: 11,
                          color: c.textFaint,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            _capitalise(group.visibility),
                            style: context.text.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (group.category.isNotEmpty) ...[
                          Text(' · ', style: context.text.bodySmall),
                          Flexible(
                            child: Text(
                              _capitalise(group.category),
                              style: context.text.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KoloSpace.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  KoloStatusPill(status: 'active', label: _capitalise(group.myRole), compact: true),
                  const SizedBox(height: 5),
                  Text(
                    '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'}',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: KoloSpace.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: KoloSpace.md, vertical: KoloSpace.sm + 2),
            decoration: BoxDecoration(
              color: c.surfaceSunken,
              borderRadius: BorderRadius.circular(KoloRadius.sm),
            ),
            child: Row(
              children: [
                Text(
                  'Open group',
                  style: context.text.bodySmall?.copyWith(
                    color: c.text, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Icon(Icons.arrow_forward_rounded, size: 14, color: c.textSoft),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _capitalise(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// Recent money movement. Contributions only — this product has no card
/// spending, so inventing an activity feed would be dishonest.
class _ActivityCard extends StatelessWidget {
  const _ActivityCard({required this.contributions});

  final AsyncValue<List<Contribution>> contributions;

  @override
  Widget build(BuildContext context) {
    return KoloCard(
      padding: const EdgeInsets.symmetric(
        horizontal: KoloSpace.lg, vertical: KoloSpace.xs),
      child: switch (contributions) {
        AsyncValue(hasError: true) => Padding(
            padding: const EdgeInsets.symmetric(vertical: KoloSpace.lg),
            child: KoloErrorState(
              title: 'Could not load activity',
              message: 'Your contribution history is unavailable right now.',
              isOffline: true,
            ),
          ),
        AsyncValue(hasValue: false, isLoading: true) => Column(
            children: const [
              KoloSkeleton(width: 120, height: 12),
              SizedBox(height: KoloSpace.lg),
              KoloSkeleton(height: 40, radius: 8),
            ],
          ),
        AsyncValue(:final value?) => value.isEmpty
            ? const KoloEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No contributions yet',
                message:
                    'Once you make your first contribution it will appear here with its '
                    'reference and status.',
              )
            : Column(
                children: [
                  for (var i = 0; i < value.length && i < 4; i++)
                    KoloActivityRow(
                      title: value[i].programmeName,
                      subtitle: _when(value[i].createdAt),
                      status: value[i].status,
                      amount: value[i].amount,
                      icon: Icons.south_west_rounded,
                      showDivider: i < value.length - 1 && i < 3,
                      onTap: () => context.push('/contributions'),
                    ),
                ],
              ),
        _ => const SizedBox.shrink(),
      },
    );
  }

  static String _when(DateTime? at) {
    if (at == null) return 'Date unknown';
    final local = at.toLocal();
    final months = const [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    final sameDay = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (sameDay) {
      final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
      final m = local.minute.toString().padLeft(2, '0');
      return '$h:$m ${local.hour < 12 ? 'am' : 'pm'}';
    }
    return '${local.day} ${months[local.month - 1]}';
  }
}

/// Turns a raw exception into something a member can act on.
String _friendly(Object error) {
  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('Connection') ||
      text.contains('timeout')) {
    return 'We could not reach KOLO. Check your connection and try again.';
  }
  if (text.contains('401') || text.contains('Unauthorised')) {
    return 'Your session has expired. Sign in again to continue.';
  }
  return 'Something went wrong on our side. Nothing has been charged. Try again.';
}
