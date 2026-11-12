import '../../../core/models/money.dart';

/// A request to move money out of a programme to a member's bank account.
///
/// The client never decides whether this is allowed. Whether a withdrawal may be
/// requested, who may approve it, whether the requester may also approve it, and
/// whether the money is really there are all answered by the server; this type
/// only carries the answer back.
class Withdrawal {
  const Withdrawal({
    required this.id,
    required this.programmeId,
    required this.amount,
    required this.reason,
    required this.status,
    required this.note,
    required this.requestedByName,
    required this.approvalsCount,
    required this.createdAt,
    this.executedAt,
  });

  final String id;
  final String programmeId;
  final Money amount;
  final String reason;
  final String status;
  final String note;
  final String requestedByName;
  final int approvalsCount;
  final DateTime createdAt;
  final DateTime? executedAt;

  bool get isPaid => status == 'paid';

  /// Waiting on a second officer. The requester cannot be that officer.
  bool get awaitsApproval => status == 'pending_approval';

  /// Approved but not yet sent: the point at which a bank account is needed.
  bool get canBeExecuted => status == 'approved';

  bool get isFinished => const {'paid', 'rejected', 'cancelled', 'failed'}.contains(status);

  factory Withdrawal.fromJson(Map<String, dynamic> json) {
    final currency = (json['currency'] as String?) ?? 'NGN';
    final minor = json['amount_minor'];
    return Withdrawal(
      id: '${json['id']}',
      programmeId: '${json['programme_id'] ?? ''}',
      // Amounts arrive as integers in minor units and stay that way.
      amount: Money(minor is int ? minor : int.tryParse('$minor') ?? 0, currency),
      reason: (json['reason'] as String?) ?? 'other',
      status: (json['status'] as String?) ?? 'draft',
      note: (json['note'] as String?) ?? '',
      requestedByName: (json['requested_by_name'] as String?) ?? '',
      approvalsCount: json['approvals_count'] is int ? json['approvals_count'] as int : 0,
      createdAt: DateTime.tryParse('${json['created_at']}')?.toLocal() ?? DateTime.now(),
      executedAt: json['executed_at'] == null
          ? null
          : DateTime.tryParse('${json['executed_at']}')?.toLocal(),
    );
  }

  /// A shortlist for the bank picker. Paying to any Nigerian bank matters more
  /// than a complete directory, and a hard-coded full list rots as banks merge;
  /// the code stays free text so anything else can still be entered.
  static const List<({String code, String name})> commonBanks = [
    (code: '044', name: 'Access Bank'),
    (code: '058', name: 'Guaranty Trust Bank'),
    (code: '011', name: 'First Bank of Nigeria'),
    (code: '057', name: 'Zenith Bank'),
    (code: '033', name: 'United Bank for Africa'),
    (code: '232', name: 'Sterling Bank'),
    (code: '032', name: 'Union Bank'),
    (code: '035', name: 'Wema Bank'),
    (code: '999', name: 'Kuda Microfinance Bank'),
    (code: '50515', name: 'Moniepoint MFB'),
  ];

  static String labelForReason(String reason) => switch (reason) {
        'member_exit' => 'Member leaving the group',
        'goal_reached' => 'Programme goal reached',
        'emergency' => 'Emergency',
        'rotation_payout' => 'Rotation payout',
        'loan_disbursement' => 'Loan disbursement',
        _ => 'Other',
      };
}
