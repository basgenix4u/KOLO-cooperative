import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_exception.dart';
import '../../../core/api/providers.dart';
import '../../../core/models/money.dart';
import '../../../core/models/withdrawal.dart';
import '../../../core/theme/kolo_theme.dart';
import '../../../shared/widgets/common.dart';
import '../savings_providers.dart';

/// Money out of a programme, to a member's bank account.
///
/// Deliberately slow. It shows who asked, who approved, and what the server says
/// is available, before anyone can type an account number. A payout is the one
/// action in KOLO that cannot be fixed by trying again.
class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({
    super.key,
    required this.programmeId,
    required this.programmeName,
    required this.currency,
    required this.slug,
  });

  final String programmeId;
  final String programmeName;
  final String currency;
  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.kolo;
    final withdrawals = ref.watch(programmeWithdrawalsProvider(programmeId));
    final summary = ref.watch(groupSummaryProvider(slug));

    return Scaffold(
      appBar: AppBar(title: const Text('Payouts')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(programmeWithdrawalsProvider(programmeId));
          ref.invalidate(groupSummaryProvider(slug));
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            const _SandboxNotice(),
            const SizedBox(height: 16),
            _AvailableCard(summary: summary, programmeId: programmeId, currency: currency),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Text('Requests', style: Theme.of(context).textTheme.titleLarge)),
                TextButton.icon(
                  onPressed: () => _startRequest(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Request'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            withdrawals.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => ErrorNotice(
                error: error,
                onRetry: () => ref.invalidate(programmeWithdrawalsProvider(programmeId)),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return EmptyState(
                    icon: Icons.account_balance_outlined,
                    title: 'No payouts yet',
                    message: 'When the group is ready to pay someone, a request appears here and '
                        'needs a second officer to approve it.',
                    action: FilledButton.tonal(
                      onPressed: () => _startRequest(context, ref),
                      child: const Text('Request a payout'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final withdrawal in rows) ...[
                      _WithdrawalTile(
                        withdrawal: withdrawal,
                        onApprove: () => _decide(context, ref, withdrawal, approve: true),
                        onReject: () => _decide(context, ref, withdrawal, approve: false),
                        onSend: () => _sendToBank(context, ref, withdrawal),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            KoloCard(
              color: palette.moneySoft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.gavel_rounded, size: 20, color: palette.moneyInk),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Two people, always',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: palette.text)),
                        const SizedBox(height: 6),
                        Text(
                          'The officer who requests a payout cannot approve it, and the officer '
                          'who approves it cannot be the person being paid. KOLO refuses either '
                          'case on the server, not just here.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startRequest(BuildContext context, WidgetRef ref) async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _RequestSheet(
        programmeId: programmeId,
        programmeName: programmeName,
        currency: currency,
      ),
    );
    if (created == true) {
      ref.invalidate(programmeWithdrawalsProvider(programmeId));
    }
  }

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref,
    Withdrawal withdrawal, {
    required bool approve,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(approve ? 'Approve this payout?' : 'Decline this payout?'),
        content: Text(
          approve
              ? 'You are approving ${withdrawal.amount.format()} to leave the group. '
                  'A different officer still has to send it.'
              : 'The request will be closed and nothing will move.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(approve ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(apiClientProvider).post(
        '/savings/withdrawals/${withdrawal.id}/decide/',
        body: {'approve': approve},
      );
      ref.invalidate(programmeWithdrawalsProvider(withdrawal.programmeId));
      if (context.mounted) {
        await showMessage(
          context,
          approve ? 'Approved. Another officer must now send it.' : 'Declined.',
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        // A separation-of-duties refusal is the interesting case: it needs a
        // sentence the member can act on, not a generic failure.
        await showMessage(
          context,
          error.code == 'self_approval_blocked'
              ? 'You cannot approve this: a different officer has to.'
              : error.userMessage,
          isError: true,
        );
      }
    }
  }

  Future<void> _sendToBank(BuildContext context, WidgetRef ref, Withdrawal withdrawal) async {
    final details = await showModalBottomSheet<_BankDetails>(
      context: context,
      isScrollControlled: true,
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
      if (context.mounted) {
        await showMessage(context, 'Payout sent. It shows as paid once the bank confirms.');
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        await showMessage(context, error.userMessage, isError: true);
      }
    }
  }
}

class _SandboxNotice extends StatelessWidget {
  const _SandboxNotice();

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 16, color: palette.textFaint),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Sandbox: payouts can be requested and approved for real, but no money reaches a '
            'bank account in this environment.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// What the server says the programme can actually pay, from its own ledger.
class _AvailableCard extends StatelessWidget {
  const _AvailableCard({
    required this.summary,
    required this.programmeId,
    required this.currency,
  });

  final AsyncValue<Map<String, dynamic>> summary;
  final String programmeId;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;

    return summary.when(
      loading: () => const KoloCard(
        child: SizedBox(height: 72, child: Center(child: CircularProgressIndicator())),
      ),
      error: (error, _) => KoloCard(child: ErrorNotice(error: error)),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Available to pay out', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(available.format(), style: KoloTheme.moneyLarge(palette.text)),
              const SizedBox(height: 4),
              Text(
                'Held by the group, according to the server ledger',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 10),
              AmountRow(label: 'Collected so far', value: collected.format()),
            ],
          ),
        );
      },
    );
  }
}

class _WithdrawalTile extends StatelessWidget {
  const _WithdrawalTile({
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
    final palette = context.kolo;

    return KoloCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  withdrawal.amount.format(),
                  style: KoloTheme.moneyMedium(palette.text),
                ),
              ),
              StatusPill(status: withdrawal.status),
            ],
          ),
          const SizedBox(height: 6),
          Text(Withdrawal.labelForReason(withdrawal.reason),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.person_outline_rounded, size: 15, color: palette.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Requested by '
                  '${withdrawal.requestedByName.isEmpty ? 'a member' : withdrawal.requestedByName}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (withdrawal.approvalsCount > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.verified_outlined, size: 15, color: palette.success),
                const SizedBox(width: 6),
                Text(
                  '${withdrawal.approvalsCount} approval'
                  '${withdrawal.approvalsCount == 1 ? '' : 's'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ],
          if (withdrawal.awaitsApproval) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: onReject, child: const Text('Decline')),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(onPressed: onApprove, child: const Text('Approve')),
                ),
              ],
            ),
          ],
          if (withdrawal.canBeExecuted) ...[
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: onSend,
              child: const Text('Send to bank account'),
            ),
          ],
          if (withdrawal.isPaid && withdrawal.executedAt != null) ...[
            const SizedBox(height: 8),
            Text('Paid on ${_formatDate(withdrawal.executedAt!)}',
                style: Theme.of(context).textTheme.bodySmall),
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
          _error = error.code == 'permission_denied'
              ? 'Only an officer can request a payout.'
              : error.userMessage;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request a payout', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              'From ${widget.programmeName}. A second officer will need to approve it.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount (${widget.currency})',
                hintText: '10,000',
              ),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              value: _reason,
              decoration: const InputDecoration(labelText: 'Reason'),
              items: const [
                DropdownMenuItem(value: 'rotation_payout', child: Text('Rotation payout')),
                DropdownMenuItem(value: 'member_exit', child: Text('Member leaving the group')),
                DropdownMenuItem(value: 'goal_reached', child: Text('Programme goal reached')),
                DropdownMenuItem(value: 'emergency', child: Text('Emergency')),
                DropdownMenuItem(value: 'other', child: Text('Other')),
              ],
              onChanged: (value) => setState(() => _reason = value ?? _reason),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: 500,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                hintText: 'Why this money is leaving',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded, size: 16, color: palette.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: TextStyle(color: palette.danger, fontSize: 13, height: 1.4),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send for approval'),
            ),
            const SizedBox(height: 8),
          ],
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
    final palette = context.kolo;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where should the money go?',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 6),
            Text(
              '${widget.withdrawal.amount.format()} will be sent to this account.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _bankSearch,
              decoration: const InputDecoration(
                labelText: 'Bank',
                hintText: 'Search by name or code',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final bank in _banks.take(6))
                  ChoiceChip(
                    label: Text(bank.name),
                    selected: _bankCode == bank.code,
                    onSelected: (_) => setState(() => _bankCode = bank.code),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _accountNumber,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
              decoration: const InputDecoration(
                labelText: 'Account number',
                hintText: '0123456789',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _accountName,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Account name',
                hintText: 'As it appears with the bank',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!, style: TextStyle(color: palette.danger, fontSize: 13, height: 1.4)),
            ],
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_outline_rounded, size: 15, color: palette.textFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Check the number twice. Money sent to the wrong account has to be recovered '
                    'from the bank, not from KOLO.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _submit, child: const Text('Send payout')),
          ],
        ),
      ),
    );
  }
}
