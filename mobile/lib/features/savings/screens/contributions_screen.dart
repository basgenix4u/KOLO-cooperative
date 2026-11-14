import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/models/models.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';

import '../savings_providers.dart';

/// Everything this member owes and everything they have paid.
///
/// This is also the destination for a "pay" deep link. The link carries no
/// amount — a URL is not a source of truth for money — so the member is shown
/// what the server says they owe and chooses from that.
///
/// Layout order is deliberate: what is owed, then what has been paid. A member
/// opening this screen is usually checking whether they owe something. History is
/// the second question, and gets the second position.
class ContributionsScreen extends ConsumerWidget {
  const ContributionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final obligations = ref.watch(myObligationsProvider);
    final history = ref.watch(myContributionsProvider);

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(myObligationsProvider);
            ref.invalidate(myContributionsProvider);
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: KoloSpace.hero),
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
                child: KoloPageHeader(
                  eyebrow: 'What you owe, and what you have paid',
                  title: 'Money',
                ),
              ),
              const SizedBox(height: KoloSpace.section),

              // --- Owed ------------------------------------------------------
              KoloSectionHeader(
                title: 'Due now',
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, 0, KoloSpace.page, KoloSpace.md),
                action: obligations.maybeWhen(
                  data: (rows) => rows.isEmpty
                      ? null
                      : Text(
                          rows.length == 1 ? '1 payment' : '${rows.length} payments',
                          style: context.text.bodySmall,
                        ),
                  orElse: () => null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: switch (obligations) {
                  AsyncValue(hasError: true, :final error?) => KoloErrorState(
                      message: _friendly(error),
                      title: 'We could not load what you owe',
                      onRetry: () => ref.invalidate(myObligationsProvider),
                    ),
                  AsyncValue(isLoading: true, hasValue: false) =>
                    const KoloSkeletonCard(height: 96),
                  AsyncValue(:final value?) => value.isEmpty
                      ? _AllSettled(
                          onSeeHistory: () => _scrollToHistory(context),
                        )
                      : Column(
                          children: [
                            for (final obligation in value) ...[
                              _ObligationCard(obligation: obligation),
                              const SizedBox(height: KoloSpace.md),
                            ],
                          ],
                        ),
                  _ => const SizedBox.shrink(),
                },
              ),

              const SizedBox(height: KoloSpace.section),

              // --- Paid ------------------------------------------------------
              KoloSectionHeader(
                title: 'History',
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, 0, KoloSpace.page, KoloSpace.md),
                action: history.maybeWhen(
                  data: (rows) => rows.isEmpty
                      ? null
                      : Text('All time', style: context.text.bodySmall),
                  orElse: () => null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: switch (history) {
                  AsyncValue(hasError: true, :final error?) => KoloErrorState(
                      message: _friendly(error),
                      title: 'History did not load',
                      onRetry: () => ref.invalidate(myContributionsProvider),
                    ),
                  AsyncValue(isLoading: true, hasValue: false) =>
                    const KoloSkeletonCard(height: 140),
                  AsyncValue(:final value?) => value.isEmpty
                      ? KoloEmptyState(
                          icon: Icons.receipt_long_outlined,
                          title: 'Nothing paid yet',
                          message: 'When you pay into a programme, every payment appears '
                              'here with the reference the server issued. That reference is '
                              'what an officer can look up if there is ever a question.',
                        )
                      : KoloCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: KoloSpace.lg, vertical: KoloSpace.xs),
                          child: Column(
                            children: [
                              for (var i = 0; i < value.length; i++)
                                KoloActivityRow(
                                  title: value[i].programmeName.isEmpty
                                      ? 'Contribution'
                                      : value[i].programmeName,
                                  subtitle: _historySubtitle(value[i]),
                                  amount: value[i].amount,
                                  status: value[i].status,
                                  showDivider: i < value.length - 1,
                                ),
                            ],
                          ),
                        ),
                  _ => const SizedBox.shrink(),
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static void _scrollToHistory(BuildContext context) {
    // The history section is below; a nudge is enough to show there is more.
    Scrollable.ensureVisible(
      context,
      duration: KoloMotion.base,
      curve: KoloMotion.enter,
    );
  }

  /// The reference is the important part of a past payment: it is the thing an
  /// officer can search for when money and records disagree, so it gets the
  /// line to itself rather than being truncated behind a date.
  static String _historySubtitle(Contribution contribution) {
    if (contribution.reference.isNotEmpty) return contribution.reference;
    if (contribution.createdAt != null) {
      return DateFormat('d MMM yyyy').format(contribution.createdAt!);
    }
    return koloHumanise(contribution.status);
  }

  static String _friendly(Object error) {
    final text = error.toString();
    if (text.contains('network') || text.contains('SocketException')) {
      return 'KOLO could not be reached. Check your connection and pull down to try again.';
    }
    return 'Pull down to try again. If this keeps happening, tell an officer.';
  }
}

/// Nothing owed is good news, so it is stated warmly rather than as an empty
/// box. It still gives the member somewhere to go.
class _AllSettled extends StatelessWidget {
  const _AllSettled({required this.onSeeHistory});

  final VoidCallback onSeeHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KoloCard(
      color: c.settledWash,
      border: c.settled.withValues(alpha: 0.22),
      padding: const EdgeInsets.all(KoloSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.task_alt_rounded, size: 20, color: c.settled),
          const SizedBox(width: KoloSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You are up to date',
                  style: context.text.titleSmall?.copyWith(color: c.settled),
                ),
                const SizedBox(height: 3),
                Text(
                  'Nothing is due right now. Your next contribution will appear here '
                  'when a programme schedules it.',
                  style: context.text.bodySmall?.copyWith(
                    color: c.textSoft,
                    height: 1.45,
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

/// One amount owed.
///
/// The figure dominates, the due date sits directly beneath it because the two
/// are read together, and the action repeats the amount so there is no doubt
/// what is about to be paid.
class _ObligationCard extends StatelessWidget {
  const _ObligationCard({required this.obligation});

  final Obligation obligation;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final overdue = obligation.isOverdue;
    final partiallyPaid = obligation.paid.minor > 0 && obligation.outstanding.minor > 0;
    final tone = overdue ? c.failed : c.text;

    return KoloCard(
      border: overdue ? c.failed.withValues(alpha: 0.3) : null,
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
                      obligation.programmeName.isEmpty
                          ? 'Contribution'
                          : obligation.programmeName,
                      style: context.text.bodySmall?.copyWith(color: c.textSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: KoloSpace.sm),
                    KoloAmount(
                      money: obligation.outstanding,
                      size: 26,
                      color: tone,
                    ),
                    const SizedBox(height: KoloSpace.sm),
                    Row(
                      children: [
                        Icon(
                          overdue
                              ? Icons.warning_amber_rounded
                              : Icons.event_outlined,
                          size: 13,
                          color: overdue ? c.failed : c.textSoft,
                        ),
                        const SizedBox(width: KoloSpace.xs + 1),
                        Flexible(
                          child: Text(
                            _dueLine(obligation),
                            style: context.text.bodySmall?.copyWith(
                              color: overdue ? c.failed : c.textSoft,
                              fontWeight: overdue ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KoloSpace.md),
              // "Pending" beside "Due in 3 days" says the same thing twice. The
              // pill is reserved for a state the date cannot express.
              if (obligation.status == 'processing' ||
                  obligation.status == 'awaiting_payment')
                KoloStatusPill(status: obligation.status, compact: true),
            ],
          ),
          if (partiallyPaid) ...[
            const SizedBox(height: KoloSpace.md),
            // Progress on a part-paid obligation, with the numbers stated. A bar
            // alone would ask the member to do arithmetic.
            KoloProgress(
              value: obligation.amount.minor == 0
                  ? 0
                  : obligation.paid.minor / obligation.amount.minor,
              color: c.text,
              height: 4,
              semanticLabel: 'Part paid',
            ),
            const SizedBox(height: KoloSpace.sm),
            Text(
              '${obligation.paid.format()} of ${obligation.amount.format()} paid',
              style: context.text.bodySmall,
            ),
          ],
          const SizedBox(height: KoloSpace.lg),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: FilledButton(
              onPressed: obligation.programmeId.isEmpty
                  ? null
                  : () => context.push(
                        '/programmes/${obligation.programmeId}/contribute'
                        '?obligation=${obligation.id}'
                        '&amount=${obligation.outstanding.minor}',
                      ),
              child: Text('Pay ${obligation.outstanding.format()}'),
            ),
          ),
        ],
      ),
    );
  }

  /// Due dates are relative where that is more useful than a calendar date:
  /// "due in 3 days" is actionable, "due 8 Nov" needs a mental calculation.
  static String _dueLine(Obligation obligation) {
    final due = obligation.dueDate;
    if (due == null) return 'No due date set';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(due.year, due.month, due.day);
    final days = target.difference(today).inDays;

    if (days < 0) {
      final late = -days;
      return late == 1 ? 'Overdue by a day' : 'Overdue by $late days';
    }
    if (days == 0) return 'Due today';
    if (days == 1) return 'Due tomorrow';
    if (days <= 7) return 'Due in $days days';
    return 'Due ${DateFormat('d MMM').format(due)}';
  }
}
