import 'money.dart';

/// Domain models, parsed from the API's snake_case payloads.
///
/// Each model keeps the server's own status strings rather than inventing a
/// client-side enum. If the backend introduces a status this build does not
/// know, the app shows the raw status instead of crashing or — worse — treating
/// an unknown state as a happy one.

class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.phone,
    required this.fullName,
    required this.avatarUrl,
    required this.preferredCurrency,
    required this.isEmailVerified,
    required this.isPhoneVerified,
    required this.verificationLevel,
    required this.status,
  });

  final String id;
  final String email;
  final String phone;
  final String fullName;
  final String avatarUrl;
  final String preferredCurrency;
  final bool isEmailVerified;
  final bool isPhoneVerified;
  final String verificationLevel;
  final String status;

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim().split(' ').first;
    if (email.isNotEmpty) return email.split('@').first;
    return 'there';
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: '${json['id'] ?? ''}',
        email: '${json['email'] ?? ''}',
        phone: '${json['phone'] ?? ''}',
        fullName: '${json['full_name'] ?? ''}',
        avatarUrl: '${json['avatar_url'] ?? ''}',
        preferredCurrency: '${json['preferred_currency'] ?? 'NGN'}',
        isEmailVerified: json['is_email_verified'] == true,
        isPhoneVerified: json['is_phone_verified'] == true,
        verificationLevel: '${json['verification_level'] ?? 'unverified'}',
        status: '${json['status'] ?? 'active'}',
      );
}

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.slug,
    required this.category,
    required this.visibility,
    required this.currency,
    required this.memberCount,
    required this.myRole,
    required this.requiresApproval,
  });

  final String id;
  final String name;
  final String slug;
  final String category;
  final String visibility;
  final String currency;
  final int memberCount;
  final String myRole;
  final bool requiresApproval;

  bool get isPrivate => visibility == 'private';
  bool get iAmOfficer => const {'owner', 'founder', 'admin', 'treasurer', 'secretary', 'moderator'}
      .contains(myRole);

  factory GroupSummary.fromJson(Map<String, dynamic> json) => GroupSummary(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? 'Group'}',
        slug: '${json['slug'] ?? ''}',
        category: '${json['category'] ?? ''}',
        visibility: '${json['visibility'] ?? 'restricted'}',
        currency: '${json['currency'] ?? 'NGN'}',
        memberCount: (json['member_count'] as num?)?.toInt() ?? 0,
        myRole: '${json['my_role'] ?? json['role'] ?? 'member'}',
        requiresApproval: json['requires_approval'] != false,
      );
}

class Programme {
  const Programme({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.currency,
    required this.contributionAmount,
    required this.collected,
    required this.expected,
    required this.target,
    required this.participantCount,
    required this.progressPercent,
    required this.frequency,
    this.groupSlug = '',
  });

  final String id;

  /// Which group this programme belongs to. Needed to ask for group-level
  /// figures beside it, such as the pool a payout would draw from.
  final String groupSlug;
  final String name;
  final String type;
  final String status;
  final String currency;
  final Money contributionAmount;
  final Money collected;
  final Money expected;
  final Money target;
  final int participantCount;
  final double progressPercent;
  final String frequency;

  bool get isRotational => type == 'rotational';
  bool get isActive => status == 'active';

  /// Progress is computed from verified money only. It is deliberately not
  /// derived from the schedule, which would show a group as further along than
  /// its bank account actually is.
  factory Programme.fromJson(Map<String, dynamic> json) {
    final currency = '${json['currency'] ?? 'NGN'}';
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    return Programme(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? 'Programme'}',
      type: '${json['type'] ?? 'rotational'}',
      status: '${json['status'] ?? 'draft'}',
      currency: currency,
      contributionAmount: Money(asInt('contribution_amount_minor'), currency),
      collected: Money(asInt('collected_minor'), currency),
      expected: Money(asInt('expected_minor'), currency),
      target: Money(asInt('target_amount_minor'), currency),
      participantCount: asInt('participant_count'),
      progressPercent: (json['progress_percent'] as num?)?.toDouble() ?? 0,
      frequency: '${json['frequency'] ?? 'monthly'}',
      groupSlug: '${json['group_slug'] ?? ''}',
    );
  }
}

class RotationCycle {
  const RotationCycle({
    required this.id,
    required this.sequence,
    required this.status,
    required this.beneficiaryName,
    required this.expectedTotal,
    required this.collectedTotal,
    required this.payoutAmount,
    required this.shortfall,
    required this.periodEnd,
    required this.paidAt,
  });

  final String id;
  final int sequence;
  final String status;
  final String beneficiaryName;
  final Money expectedTotal;
  final Money collectedTotal;
  final Money payoutAmount;
  final Money shortfall;
  final DateTime? periodEnd;
  final DateTime? paidAt;

  bool get isPaid => status == 'paid';

  /// The one number a member actually cares about: is there enough yet?
  bool get isFullyFunded => shortfall.isZero && collectedTotal >= payoutAmount;

  factory RotationCycle.fromJson(Map<String, dynamic> json) {
    final currency = '${json['currency'] ?? 'NGN'}';
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    return RotationCycle(
      id: '${json['id'] ?? ''}',
      sequence: asInt('sequence'),
      status: '${json['status'] ?? 'scheduled'}',
      beneficiaryName: '${json['beneficiary_name'] ?? 'Not assigned'}',
      expectedTotal: Money(asInt('expected_total_minor'), currency),
      collectedTotal: Money(asInt('collected_total_minor'), currency),
      payoutAmount: Money(asInt('payout_amount_minor'), currency),
      shortfall: Money(asInt('shortfall_minor'), currency),
      periodEnd: DateTime.tryParse('${json['period_end'] ?? ''}'),
      paidAt: DateTime.tryParse('${json['paid_at'] ?? ''}'),
    );
  }
}

class Obligation {
  const Obligation({
    required this.id,
    required this.programmeName,
    required this.dueDate,
    required this.amount,
    required this.paid,
    required this.outstanding,
    required this.status,
  });

  final String id;
  final String programmeName;
  final DateTime? dueDate;
  final Money amount;
  final Money paid;
  final Money outstanding;
  final String status;

  bool get isOverdue => status == 'overdue';

  factory Obligation.fromJson(Map<String, dynamic> json) {
    final currency = '${json['currency'] ?? 'NGN'}';
    int asInt(String key) => (json[key] as num?)?.toInt() ?? 0;
    return Obligation(
      id: '${json['id'] ?? ''}',
      programmeName: '${json['programme_name'] ?? ''}',
      dueDate: DateTime.tryParse('${json['due_date'] ?? ''}'),
      amount: Money(asInt('amount_minor'), currency),
      paid: Money(asInt('paid_minor'), currency),
      outstanding: Money(asInt('outstanding_minor'), currency),
      status: '${json['status'] ?? 'pending'}',
    );
  }
}

class Contribution {
  const Contribution({
    required this.id,
    required this.reference,
    required this.programmeName,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String reference;
  final String programmeName;
  final Money amount;
  final String status;
  final DateTime? createdAt;

  bool get isConfirmed => const {'confirmed', 'settled'}.contains(status);

  factory Contribution.fromJson(Map<String, dynamic> json) {
    final currency = '${json['currency'] ?? 'NGN'}';
    return Contribution(
      id: '${json['id'] ?? ''}',
      reference: '${json['reference'] ?? ''}',
      programmeName: '${json['programme_name'] ?? ''}',
      amount: Money((json['amount_minor'] as num?)?.toInt() ?? 0, currency),
      status: '${json['status'] ?? 'initiated'}',
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
    );
  }
}

class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.reference,
    required this.status,
    required this.amount,
    required this.checkoutUrl,
  });

  final String id;
  final String reference;
  final String status;
  final Money amount;
  final String checkoutUrl;

  bool get isDone => status == 'succeeded';

  factory PaymentIntent.fromJson(Map<String, dynamic> json) {
    final currency = '${json['currency'] ?? 'NGN'}';
    return PaymentIntent(
      id: '${json['id'] ?? ''}',
      reference: '${json['reference'] ?? ''}',
      status: '${json['status'] ?? 'awaiting_payment'}',
      amount: Money((json['amount_minor'] as num?)?.toInt() ?? 0, currency),
      checkoutUrl: '${json['checkout_url'] ?? ''}',
    );
  }
}

class Proposal {
  const Proposal({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.isSecret,
    required this.votesFor,
    required this.votesAgainst,
    required this.iHaveVoted,
    required this.closesAt,
    required this.resolutionText,
  });

  final String id;
  final String title;
  final String description;
  final String status;
  final bool isSecret;
  final int votesFor;
  final int votesAgainst;
  final bool iHaveVoted;
  final DateTime? closesAt;
  final String resolutionText;

  bool get isOpen => status == 'open';
  int get totalVotes => votesFor + votesAgainst;

  factory Proposal.fromJson(Map<String, dynamic> json) => Proposal(
        id: '${json['id'] ?? ''}',
        title: '${json['title'] ?? ''}',
        description: '${json['description'] ?? ''}',
        status: '${json['status'] ?? 'draft'}',
        isSecret: json['is_secret'] == true,
        votesFor: (json['votes_for'] as num?)?.toInt() ?? 0,
        votesAgainst: (json['votes_against'] as num?)?.toInt() ?? 0,
        iHaveVoted: json['my_vote'] == true,
        closesAt: DateTime.tryParse('${json['closes_at'] ?? ''}'),
        resolutionText: '${json['resolution_text'] ?? ''}',
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.body,
    required this.senderName,
    required this.senderId,
    required this.createdAt,
    required this.isDeleted,
    this.isPending = false,
  });

  final String id;
  final String body;
  final String senderName;
  final String senderId;
  final DateTime? createdAt;
  final bool isDeleted;

  /// Set while a message is still being sent, so the bubble can show it as
  /// pending rather than pretending it is delivered.
  final bool isPending;

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: '${json['id'] ?? ''}',
        body: '${json['body'] ?? ''}',
        senderName: '${json['sender_name'] ?? 'Member'}',
        senderId: '${json['sender_id'] ?? ''}',
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
        isDeleted: json['is_deleted'] == true,
      );
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.readAt,
    required this.createdAt,
  });

  final String id;
  final String kind;
  final String title;
  final String body;
  final DateTime? readAt;
  final DateTime? createdAt;

  bool get isUnread => readAt == null;

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: '${json['id'] ?? ''}',
        kind: '${json['kind'] ?? 'system'}',
        title: '${json['title'] ?? ''}',
        body: '${json['body'] ?? ''}',
        readAt: DateTime.tryParse('${json['read_at'] ?? ''}'),
        createdAt: DateTime.tryParse('${json['created_at'] ?? ''}'),
      );
}
