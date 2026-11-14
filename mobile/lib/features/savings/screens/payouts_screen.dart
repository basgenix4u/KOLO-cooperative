import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/money.dart';
import '../../../core/models/withdrawal.dart';
import '../../../design/components.dart';
import '../../../design/navigation.dart';
import '../../../design/tokens.dart';
import '../../../design/typography.dart';
import '../savings_providers.dart';

/// Moving group money out.
///
/// KOLO exists because a treasurer with a notebook can quietly move money. The
/// two-person rule is the product, so this screen does not merely enforce it —
/// it shows it. Every payout carries a signature track: "requested by" and
/// "approved by", with the second slot visibly empty until it is filled. That
/// emptiness is the whole point.
///
/// The client never decides any of this. Whether a payout may be requested, who
/// may approve it, whether the requester may also approve it, and whether the
/// money is really there are answered by the server; this screen renders the
/// answer and states the refusal in a sentence the officer can act on.
class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({
    super.key,
    required this.programmeId,
    required this.programmeName,
    required this.currency,
    required this.slug,
  });

  final String programmeId;

  /// Supplied by the router when the member navigated from programme detail.
  /// A cold deep link or a web refresh has no `extra`, so these fall back to the
  /// programme the server returns — otherwise the ledger lookup quietly fails and
  /// the screen claims the balance is unknown.
  final String programmeName;
  final String currency;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final programme = ref.watch(programmeProvider(programmeId)).value;

    final resolvedName =
        programmeName != 'Programme' && programmeName.isNotEmpty
            ? programmeName
            : (programme?.name ?? 'Programme');
    final resolvedCurrency =
        programme?.currency.isNotEmpty == true ? programme!.currency : currency;
    final resolvedSlug =
        slug.isNotEmpty ? slug : (programme?.groupSlug ?? '');

    final withdrawals = ref.watch(programmeWithdrawalsProvider(programmeId));
    final summary = ref.watch(groupSummaryProvider(resolvedSlug));

    return Scaffold(
      backgroundColor: c.ground,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(programmeWithdrawalsProvider(programmeId));
            ref.invalidate(groupSummaryProvider(resolvedSlug));
            ref.invalidate(programmeProvider(programmeId));
          },
          child: ListView(
            padding: const EdgeInsets.only(bottom: KoloSpace.hero),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.sm, KoloSpace.page, 0),
                child: Row(
                  children: [
                    KoloBackButton(onTap: () => Navigator.of(context).maybePop()),
                    const Spacer(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
                child: KoloPageHeader(
                  eyebrow: resolvedName,
                  title: 'Payouts',
                ),
              ),
              const SizedBox(height: KoloSpace.xl),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: _AvailableCard(
                  summary: summary,
                  programmeId: programmeId,
                  currency: resolvedCurrency,
                  onRequest: () => _startRequest(context, ref),
                ),
              ),

              // The rule, stated before any payout exists. An officer reading
              // this knows what they are taking on before they start.
              const Padding(
                padding: EdgeInsets.fromLTRB(
                    KoloSpace.page, KoloSpace.md, KoloSpace.page, 0),
                child: KoloNotice(
                  message: 'Sandbox: payouts can be requested and approved for real, '
                      'but no money reaches a bank account in this environment.',
                  tone: KoloNoticeTone.neutral,
                  icon: Icons.science_outlined,
                ),
              ),

              const SizedBox(height: KoloSpace.section),

              KoloSectionHeader(
                title: 'Requests',
                inset: false,
                padding: const EdgeInsets.fromLTRB(
                    KoloSpace.page, 0, KoloSpace.page, KoloSpace.md),
                action: withdrawals.maybeWhen(
                  data: (rows) => rows.isEmpty
                      ? null
                      : TextButton.icon(
                          onPressed: () => _startRequest(context, ref),
                          icon: const Icon(Icons.add_rounded, size: 17),
                          label: const Text('Request'),
                        ),
                  orElse: () => null,
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: switch (withdrawals) {
                  AsyncValue(hasError: true, :final error?) => KoloErrorState(
                      message: _friendly(error),
                      title: 'Payouts did not load',
                      onRetry: () => ref.invalidate(programmeWithdrawalsProvider(programmeId)),
                    ),
                  AsyncValue(isLoading: true, hasValue: false) => Column(
                      children: const [
                        KoloSkeletonCard(height: 168),
                        SizedBox(height: KoloSpace.md),
                        KoloSkeletonCard(height: 168),
                      ],
                    ),
                  AsyncValue(:final value?) => value.isEmpty
                      ? KoloEmptyState(
                          icon: Icons.account_balance_outlined,
                          title: 'No payouts yet',
                          message: 'When the group is ready to pay someone, a request '
                              'appears here. It needs a second officer before any money '
                              'moves.',
                          action: FilledButton(
                            onPressed: () => _startRequest(context, ref),
                            child: const Text('Request a payout'),
                          ),
                        )
                      : Column(
                          children: [
                            for (final withdrawal in value) ...[
                              _PayoutCard(
                                withdrawal: withdrawal,
                                onApprove: () =>
                                    _decide(context, ref, withdrawal, approve: true),
                                onReject: () =>
                                    _decide(context, ref, withdrawal, approve: false),
                                onSend: () => _sendToBank(context, ref, withdrawal),
                              ),
                              const SizedBox(height: KoloSpace.md),
                            ],
                          ],
                        ),
                  _ => const SizedBox.shrink(),
                },
              ),

              const SizedBox(height: KoloSpace.section),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: KoloSpace.page),
                child: _TwoPeopleCard(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _friendly(Object error) {
    final text = error.toString();
    if (text.contains('network') || text.contains('SocketException')) {
      return 'KOLO could not be reached. Check your connection and pull down to try again.';
    }
    if (text.contains('not_a_member') || text.contains('403')) {
      return 'Only officers of this group can see its payouts.';
    }
    return 'Pull down to try again.';
  }

  Future<void> _startRequest(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      builder: (_) => _RequestSheet(
        programmeId: programmeId,
        programmeName: programmeName,
        currency: currency,
      ),
    );
    if (created == true) {
      ref.invalidate(programmeWithdrawalsProvider(programmeId));
      ref.invalidate(groupSummaryProvider(slug));
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Withdrawal withdrawal, {
    required bool approve,
  }) async {
    final ok = await koloConfirm(
      context,
      title: approve ? 'Approve this payout?' : 'Decline this payout?',
      message: approve
          ? 'You are signing off ${withdrawal.amount.format()} leaving the group. '
              'A different officer still has to send it — approving does not move money.'
          : 'The request is closed and nothing moves. The officer who raised it will '
              'see that it was declined.',
      confirmLabel: approve ? 'Approve' : 'Decline',
      destructive: !approve,
    );
    if (ok != true || !context.mounted) return;

    try {
      await ref.read(apiClientProvider).post(
        '/savings/withdrawals/${withdrawal.id}/decide/',
        body: {'approve': approve},
      );
      ref.invalidate(programmeWithdrawalsProvider(withdrawal.programmeId));
      if (context.mounted) {
        koloToast(context,
            approve ? 'Approved. Another officer must now send it.' : 'Declined.');
      }
    } on ApiException catch (error) {
      if (!context.mounted) return;
      // A separation-of-duties refusal is the interesting case: it needs a
      // sentence the officer can act on, not "something went wrong".
      koloToast(
        context,
        switch (error.code) {
          'self_approval_blocked' =>
            'You requested this payout, so someone else has to approve it.',
          'approver_cannot_execute' =>
            'The person being paid cannot approve their own payout.',
          'insufficient_funds' =>
            'The group does not hold that much right now.',
          _ => error.userMessage,
        },
        isError: true,
      );
    }
  }

  Future<void> _sendToBank(
      BuildContext context, WidgetRef ref, Withdrawal withdrawal) async {
    final details = await showModalBottomSheet<_BankDetails>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      builder: (_) => _BankSheet(withdrawal: withdrawal),
    );
    if (details == null || !context.mounted) return;

    try {
      await ref.read(apiClientProvider).post(
        '/savings/withdrawals/${withdrawal.id}/execute/',
        body: {
          'account_number': details.accountNumber,
          'bank_code': details.bankCode,
          'account_name': details.accountName,
        },
        // Safe to replay: the server keys the ledger movement on the withdrawal.
        idempotencyKey: 'payout-${withdrawal.id}',
      );
      ref.invalidate(programmeWithdrawalsProvider(withdrawal.programmeId));
      ref.invalidate(groupSummaryProvider(slug));
      if (context.mounted) {
        koloToast(context, 'Payout sent. It shows as paid once the bank confirms.');
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        koloToast(
          context,
          switch (error.code) {
            'withdrawal_not_approved' =>
              'This payout needs a second officer to approve it first.',
            'pool_underfunded' =>
              'The group no longer holds enough to cover this payout.',
            _ => error.userMessage,
          },
          isError: true,
        );
      }
    }
  }
}

/// What the server says the programme can actually pay, from its own ledger —
/// not a client-side sum of contributions.
class _AvailableCard extends StatelessWidget {
  const _AvailableCard({
    required this.summary,
    required this.programmeId,
    required this.currency,
    required this.onRequest,
  });

  final AsyncValue<Map<String, dynamic>> summary;
  final String programmeId;
  final String currency;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;

    return summary.when(
      loading: () => const KoloSkeletonCard(height: 132),
      error: (error, _) => KoloCard(
        child: KoloNotice(
          message: 'The group ledger could not be read, so the available balance is '
              'unknown. Do not start a payout until it loads.',
          tone: KoloNoticeTone.warning,
          icon: Icons.warning_amber_rounded,
        ),
      ),
      data: (data) {
        final programmes = (data['programmes'] as List?) ?? const [];
        Map<String, dynamic>? mine;
        for (final row in programmes.whereType<Map>()) {
          if ('${row['id']}' == programmeId) {
            mine = row.cast<String, dynamic>();
            break;
          }
        }

        int asInt(Object? value) =>
            value is int ? value : int.tryParse('${value ?? 0}') ?? 0;

        final available = Money(asInt(mine?['available_minor']), currency);
        final collected = Money(asInt(mine?['collected_minor']), currency);

        return KoloCard(
          color: c.surfaceRaised,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('AVAILABLE TO PAY OUT', style: KoloType.eyebrow(c)),
                  const Spacer(),
                  Icon(Icons.verified_user_outlined, size: 15, color: c.textFaint),
                ],
              ),
              const SizedBox(height: KoloSpace.md),
              KoloAmount(money: available, size: 34),
              const SizedBox(height: KoloSpace.sm),
              Text(
                'Held by the group, according to the server ledger',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: KoloSpace.lg),
              Divider(color: c.hairline, height: 1),
              const SizedBox(height: KoloSpace.md),
              Row(
                children: [
                  Text('Collected so far', style: context.text.bodySmall),
                  const Spacer(),
                  Text(collected.format(), style: context.text.titleSmall),
                ],
              ),
              const SizedBox(height: KoloSpace.lg),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: FilledButton.icon(
                  onPressed: available.minor > 0 ? onRequest : null,
                  icon: const Icon(Icons.arrow_outward_rounded, size: 18),
                  label: const Text('Request a payout'),
                ),
              ),
              if (available.minor <= 0) ...[
                const SizedBox(height: KoloSpace.sm),
                Text(
                  'Nothing can be paid out until the group has collected something.',
                  style: context.text.bodySmall,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// One payout, with its signature track.
///
/// The visual signature of this app is the two-slot track: requested, then
/// approved. A member can see at a glance whether one person or two have signed.
class _PayoutCard extends StatelessWidget {
  const _PayoutCard({
    required this.withdrawal,
    required this.onApprove,
    required this.onReject,
    required this.onSend,
  });

  final Withdrawal withdrawal;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final declined = withdrawal.status == 'rejected' || withdrawal.status == 'cancelled';
    final paid = withdrawal.isPaid;

    return KoloCard(
      border: withdrawal.awaitsApproval ? c.accent.withValues(alpha: 0.42) : null,
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
                      Withdrawal.labelForReason(withdrawal.reason),
                      style: context.text.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: KoloSpace.xs + 1),
                    KoloAmount(
                      money: withdrawal.amount,
                      size: 27,
                      color: declined ? c.textSoft : c.text,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: KoloSpace.sm),
              KoloStatusPill(status: withdrawal.status, compact: true),
            ],
          ),

          if (withdrawal.note.isNotEmpty) ...[
            const SizedBox(height: KoloSpace.sm + 2),
            Text(
              withdrawal.note,
              style: context.text.bodySmall?.copyWith(color: c.textSoft),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          const SizedBox(height: KoloSpace.lg),
          _SignatureTrack(withdrawal: withdrawal),

          if (withdrawal.awaitsApproval) ...[
            const SizedBox(height: KoloSpace.lg),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: OutlinedButton(
                      onPressed: onReject,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: KoloSpace.sm),
                      ),
                      child: const Text('Decline', maxLines: 1),
                    ),
                  ),
                ),
                const SizedBox(width: KoloSpace.sm),
                Expanded(
                  child: SizedBox(
                    height: 46,
                    child: FilledButton(
                      onPressed: onApprove,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: KoloSpace.sm),
                      ),
                      child: const Text('Approve', maxLines: 1),
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (withdrawal.canBeExecuted) ...[
            const SizedBox(height: KoloSpace.lg),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: onSend,
                icon: const Icon(Icons.account_balance_outlined, size: 18),
                label: const Text('Send to a bank account'),
              ),
            ),
          ],

          if (paid && withdrawal.executedAt != null) ...[
            const SizedBox(height: KoloSpace.md),
            Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: c.settled),
                const SizedBox(width: KoloSpace.xs + 1),
                Text(
                  'Paid ${_formatDate(withdrawal.executedAt!)}',
                  style: context.text.bodySmall?.copyWith(color: c.settled),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDate(DateTime value) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${value.day} ${months[value.month - 1]} ${value.year}';
  }
}

/// Two slots. One filled, one waiting — or both filled, and the money has gone.
///
/// This is the one place the two-person rule becomes something a member can see
/// rather than something they are told. An empty second slot is the point of the
/// whole product, so it is drawn as an outline, not hidden until it fills.
class _SignatureTrack extends StatelessWidget {
  const _SignatureTrack({required this.withdrawal});

  final Withdrawal withdrawal;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final approved = withdrawal.approvalsCount > 0 ||
        withdrawal.status == 'approved' ||
        withdrawal.isPaid;
    final declined = withdrawal.status == 'rejected' || withdrawal.status == 'cancelled';

    return Semantics(
      label: 'Requested by ${withdrawal.requestedByName.isEmpty ? 'an officer' : withdrawal.requestedByName}. '
          '${approved ? 'Approved by a second officer.' : 'Not yet approved.'}',
      child: Row(
        children: [
          Expanded(
            child: _Slot(
              filled: true,
              icon: Icons.draw_outlined,
              label: 'REQUESTED',
              value: withdrawal.requestedByName.isEmpty
                  ? 'An officer'
                  : withdrawal.requestedByName,
            ),
          ),
          // The connector. Dashed while waiting, solid once both have signed.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: KoloSpace.sm),
            child: Icon(
              approved ? Icons.check_rounded : Icons.more_horiz_rounded,
              size: 15,
              color: approved ? c.settled : c.textFaint,
            ),
          ),
          Expanded(
            child: _Slot(
              filled: approved,
              icon: approved
                  ? Icons.verified_outlined
                  : declined
                      ? Icons.block_outlined
                      : Icons.hourglass_empty_rounded,
              label: declined ? 'DECLINED' : 'APPROVED',
              value: approved
                  ? 'A second officer'
                  : declined
                      ? 'Closed'
                      : 'Waiting',
              pending: !approved && !declined,
              declined: declined,
            ),
          ),
        ],
      ),
    );
  }
}

class _Slot extends StatelessWidget {
  const _Slot({
    required this.filled,
    required this.icon,
    required this.label,
    required this.value,
    this.pending = false,
    this.declined = false,
  });

  final bool filled;
  final IconData icon;
  final String label;
  final String value;
  final bool pending;
  final bool declined;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final tone = declined ? c.failed : (filled ? c.text : c.textSoft);
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: KoloSpace.md, vertical: KoloSpace.sm + 2),
      decoration: BoxDecoration(
        color: filled ? c.surfaceSunken : Colors.transparent,
        borderRadius: BorderRadius.circular(KoloRadius.md),
        // An unfilled slot is an outline. That is deliberate: the missing
        // signature should be visible, not absent.
        border: filled ? null : Border.all(color: c.hairline, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11,
                  color: declined ? c.failed : (filled ? c.textSoft : c.textFaint)),
              const SizedBox(width: KoloSpace.xs),
              Flexible(
                child: Text(
                  label,
                  style: KoloType.eyebrow(c).copyWith(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: declined ? c.failed : c.textFaint,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: context.text.bodySmall?.copyWith(
              color: tone,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Why the rule exists, in the member's terms rather than the auditor's.
class _TwoPeopleCard extends StatelessWidget {
  const _TwoPeopleCard();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return KoloCard(
      padding: const EdgeInsets.all(KoloSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.gavel_rounded, size: 15, color: c.textSoft),
              const SizedBox(width: KoloSpace.sm),
              Text('TWO PEOPLE, ALWAYS', style: KoloType.eyebrow(c)),
            ],
          ),
          const SizedBox(height: KoloSpace.md),
          Text(
            'The officer who requests a payout cannot approve it, and the officer who '
            'approves it cannot be the person being paid. KOLO refuses either case on '
            'the server — this is not a screen the app could be talked out of.',
            style: context.text.bodySmall?.copyWith(color: c.textSoft, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _RequestSheet extends ConsumerStatefulWidget {
  const _RequestSheet({
    required this.programmeId,
    required this.programmeName,
    required this.currency,
  });

  final String programmeId;
  final String programmeName;
  final String currency;

  @override
  ConsumerState<_RequestSheet> createState() => _RequestSheetState();
}

class _RequestSheetState extends ConsumerState<_RequestSheet> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String _reason = 'rotation_payout';
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final money = Money.tryParse(_amount.text, widget.currency);
    if (money == null || money.isZero || money.isNegative) {
      setState(() => _error = 'Enter an amount greater than zero, like 10,000.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiClientProvider).post(
        '/savings/programmes/${widget.programmeId}/withdrawals/',
        body: {
          'amount_minor': money.minor,
          'reason': _reason,
          'note': _note.text.trim(),
        },
        idempotencyKey: 'withdrawal-${widget.programmeId}-${money.minor}-$_reason',
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = switch (error.code) {
            'permission_denied' => 'Only an officer can request a payout.',
            'insufficient_funds' => 'The group does not hold that much right now.',
            'pool_underfunded' => 'That is more than the group has available.',
            _ => error.userMessage,
          };
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          KoloSpace.page, KoloSpace.sm, KoloSpace.page,
          MediaQuery.viewInsetsOf(context).bottom + KoloSpace.page),
      child: SingleChildScrollView(
        child: KoloSheet(
          title: 'Request a payout',
          subtitle: 'From ${widget.programmeName}. A second officer will need to '
              'approve it before anything moves.',
          actions: [
            SizedBox(
              width: double.infinity,
              child: KoloSubmitButton(
                label: 'Send for approval',
                busyLabel: 'Sending…',
                busy: _busy,
                onPressed: _submit,
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AMOUNT', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                style: KoloType.money(c, size: 26, weight: FontWeight.w700),
                decoration: InputDecoration(
                  prefixText: '${Money.symbolFor(widget.currency)}\u2009\u2009',
                  prefixStyle: KoloType.money(c,
                      size: 20, weight: FontWeight.w700, color: c.textSoft),
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: KoloSpace.lg),
              Text('REASON', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              DropdownButtonFormField<String>(
                initialValue: _reason,
                decoration: const InputDecoration(hintText: 'Choose a reason'),
                items: const [
                  DropdownMenuItem(value: 'rotation_payout', child: Text('Rotation payout')),
                  DropdownMenuItem(value: 'member_exit', child: Text('Member leaving the group')),
                  DropdownMenuItem(value: 'goal_reached', child: Text('Programme goal reached')),
                  DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) => setState(() => _reason = value ?? _reason),
              ),
              const SizedBox(height: KoloSpace.lg),
              Text('NOTE', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              TextField(
                controller: _note,
                maxLength: 500,
                maxLines: 2,
                decoration: const InputDecoration(
                  hintText: 'Why this money is leaving — the approver will read this',
                ),
              ),
              if (_error != null)
                KoloNotice(
                  message: _error!,
                  tone: KoloNoticeTone.critical,
                  icon: Icons.error_outline_rounded,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankDetails {
  const _BankDetails({
    required this.accountNumber,
    required this.bankCode,
    required this.accountName,
  });

  final String accountNumber;
  final String bankCode;
  final String accountName;
}

/// Where the money goes. Kept separate from approval, so the officer who signs
/// off is not necessarily the one typing an account number.
class _BankSheet extends StatefulWidget {
  const _BankSheet({required this.withdrawal});

  final Withdrawal withdrawal;

  @override
  State<_BankSheet> createState() => _BankSheetState();
}

class _BankSheetState extends State<_BankSheet> {
  final _accountNumber = TextEditingController();
  final _accountName = TextEditingController();
  final _bankSearch = TextEditingController();
  String _bankCode = Withdrawal.commonBanks.first.code;
  String? _error;
  bool _confirmChecked = false;

  @override
  void dispose() {
    _accountNumber.dispose();
    _accountName.dispose();
    _bankSearch.dispose();
    super.dispose();
  }

  List<({String code, String name})> get _banks {
    final term = _bankSearch.text.trim().toLowerCase();
    if (term.isEmpty) return Withdrawal.commonBanks;
    return Withdrawal.commonBanks
        .where((bank) => bank.name.toLowerCase().contains(term) || bank.code.contains(term))
        .toList();
  }

  void _submit() {
    final number = _accountNumber.text.replaceAll(RegExp(r'\s'), '');
    if (number.length != 10) {
      setState(() => _error = 'A Nigerian account number is ten digits.');
      return;
    }
    if (_accountName.text.trim().length < 3) {
      setState(() => _error = 'Enter the name on the account, as the bank has it.');
      return;
    }
    if (!_confirmChecked) {
      setState(() => _error = 'Tick the box to confirm you have checked the number.');
      return;
    }
    Navigator.pop(
      context,
      _BankDetails(
        accountNumber: number,
        bankCode: _bankCode,
        accountName: _accountName.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          KoloSpace.page, KoloSpace.sm, KoloSpace.page,
          MediaQuery.viewInsetsOf(context).bottom + KoloSpace.page),
      child: SingleChildScrollView(
        child: KoloSheet(
          title: 'Where should the money go?',
          subtitle: '${widget.withdrawal.amount.format()} will be sent to this account.',
          actions: [
            SizedBox(
              width: double.infinity,
              child: KoloSubmitButton(
                label: 'Send payout',
                onPressed: _submit,
              ),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BANK', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              TextField(
                controller: _bankSearch,
                decoration: const InputDecoration(hintText: 'Search by name or code'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: KoloSpace.sm),
              Wrap(
                spacing: KoloSpace.sm,
                runSpacing: KoloSpace.sm,
                children: [
                  for (final bank in _banks.take(6))
                    ChoiceChip(
                      label: Text(bank.name),
                      selected: _bankCode == bank.code,
                      onSelected: (_) => setState(() => _bankCode = bank.code),
                    ),
                ],
              ),
              const SizedBox(height: KoloSpace.lg),
              Text('ACCOUNT NUMBER', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              TextField(
                controller: _accountNumber,
                keyboardType: TextInputType.number,
                style: KoloType.money(c, size: 20, weight: FontWeight.w700),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(hintText: '0123456789'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: KoloSpace.lg),
              Text('NAME ON THE ACCOUNT', style: KoloType.eyebrow(c)),
              const SizedBox(height: KoloSpace.sm),
              TextField(
                controller: _accountName,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(hintText: 'As it appears with the bank'),
              ),
              const SizedBox(height: KoloSpace.lg),
              // A mandatory tick, not a pre-checked box. Money sent to the wrong
              // account has to be recovered from a bank, not from KOLO.
              Semantics(
                checked: _confirmChecked,
                child: InkWell(
                  onTap: () => setState(() {
                    _confirmChecked = !_confirmChecked;
                    if (_confirmChecked) _error = null;
                  }),
                  borderRadius: BorderRadius.circular(KoloRadius.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: _confirmChecked,
                          onChanged: (v) => setState(() => _confirmChecked = v ?? false),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: KoloSpace.md),
                      Expanded(
                        child: Text(
                          'I have checked the account number and the name on it. Money '
                          'sent to the wrong account has to be recovered from the bank.',
                          style: context.text.bodySmall
                              ?.copyWith(color: c.textSoft, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: KoloSpace.md),
                KoloNotice(
                  message: _error!,
                  tone: KoloNoticeTone.critical,
                  icon: Icons.error_outline_rounded,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
