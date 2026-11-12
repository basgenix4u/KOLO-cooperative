import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/api/providers.dart';
import '../../core/models/models.dart';
import '../../core/models/withdrawal.dart';

/// The member's groups.
final myGroupsProvider = FutureProvider<List<GroupSummary>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/groups/');
  return rows.map(GroupSummary.fromJson).toList();
});

final groupProvider = FutureProvider.family<GroupSummary, String>((ref, slug) async {
  final client = ref.watch(apiClientProvider);
  final data = await client.get('/groups/$slug/');
  return GroupSummary.fromJson(data);
});

/// Programmes inside one group. Filtered server-side, so a member never
/// receives a programme they are not part of.
final groupProgrammesProvider = FutureProvider.family<List<Programme>, String>((ref, slug) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/savings/programmes/', query: {'group': slug});
  return rows.map(Programme.fromJson).toList();
});

final programmeProvider = FutureProvider.family<Programme, String>((ref, id) async {
  final client = ref.watch(apiClientProvider);
  final data = await client.get('/savings/programmes/$id/');
  return Programme.fromJson(data);
});

final programmeCyclesProvider = FutureProvider.family<List<RotationCycle>, String>((ref, id) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/savings/programmes/$id/cycles/');
  return rows.map((row) {
    // Cycle payloads carry no currency of their own; borrow the programme's.
    return RotationCycle.fromJson({...row, 'currency': row['currency'] ?? 'NGN'});
  }).toList();
});

/// What this member owes, across every group.
final myObligationsProvider = FutureProvider<List<Obligation>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/savings/obligations/', query: {'status': 'open'});
  return rows.map(Obligation.fromJson).toList();
});

final myContributionsProvider = FutureProvider<List<Contribution>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/savings/contributions/');
  return rows.map(Contribution.fromJson).toList();
});

/// Group-level money, for officers only. The server enforces that; this
/// provider simply surfaces the refusal if a non-officer reaches the screen.
final groupSummaryProvider = FutureProvider.family<Map<String, dynamic>, String>((ref, slug) async {
  final client = ref.watch(apiClientProvider);
  return client.get('/savings/groups/$slug/summary/');
});

final groupProposalsProvider = FutureProvider.family<List<Proposal>, String>((ref, slug) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/governance/groups/$slug/proposals/');
  return rows.map(Proposal.fromJson).toList();
});

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/notifications/');
  return rows.map(AppNotification.fromJson).toList();
});

/// Actions that move money.
///
/// Every method here is intentionally explicit about what it returns: the app
/// shows the member the server's own reference, because that is what they would
/// quote to support if something went wrong.
class MoneyActions {
  MoneyActions(this._ref);

  final Ref _ref;
  ApiClient get _client => _ref.read(apiClientProvider);

  /// Starts a contribution. The idempotency key is generated on the client so a
  /// retry after a dropped connection cannot charge the member twice.
  Future<({String reference, String checkoutUrl, String contributionId})> contribute({
    required String programmeId,
    required int amountMinor,
    String? obligationId,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? 'contrib-$programmeId-${DateTime.now().microsecondsSinceEpoch}';
    final data = await _client.post(
      '/savings/programmes/$programmeId/contributions/',
      body: {
        'amount_minor': amountMinor,
        if (obligationId != null) 'obligation_id': obligationId,
        'idempotency_key': key,
      },
      idempotencyKey: key,
    );

    final contribution = (data['contribution'] as Map?)?.cast<String, dynamic>() ?? const {};
    final payment = (data['payment'] as Map?)?.cast<String, dynamic>() ?? const {};
    return (
      reference: '${payment['reference'] ?? ''}',
      checkoutUrl: '${payment['checkout_url'] ?? ''}',
      contributionId: '${contribution['id'] ?? ''}',
    );
  }

  /// Asks the server to re-check with the provider. Never trusts the client's
  /// claim that a payment went through.
  Future<String> verifyPayment(String reference) async {
    final data = await _client.post('/payments/verify/', body: {'reference': reference});
    return '${data['status'] ?? 'processing'}';
  }

  Future<void> vote({required String proposalId, required bool inFavour}) async {
    await _client.post('/governance/proposals/$proposalId/vote/', body: {'in_favour': inFavour});
    _ref.invalidate(groupProposalsProvider);
  }

  Future<void> recordOfflineContribution({
    required String programmeId,
    required String participationId,
    required int amountMinor,
    String note = '',
  }) async {
    await _client.post('/savings/programmes/$programmeId/contributions/offline/', body: {
      'participation_id': participationId,
      'amount_minor': amountMinor,
      if (note.isNotEmpty) 'note': note,
    });
  }

  Future<void> openNextCycle(String programmeId) async {
    await _client.post('/savings/programmes/$programmeId/cycles/');
    _ref.invalidate(programmeCyclesProvider(programmeId));
  }

  Future<void> approvePayout(String cycleId, String programmeId) async {
    await _client.post('/savings/cycles/$cycleId/approve/');
    _ref.invalidate(programmeCyclesProvider(programmeId));
  }

  Future<void> executePayout(String cycleId, String programmeId) async {
    await _client.post('/savings/cycles/$cycleId/execute/');
    _ref.invalidate(programmeCyclesProvider(programmeId));
  }

  Future<void> markAllNotificationsRead() async {
    await _client.post('/notifications/read/');
    _ref.invalidate(notificationsProvider);
  }
}

final moneyActionsProvider = Provider<MoneyActions>((ref) => MoneyActions(ref));


/// Money leaving a programme. Officers only: the server refuses the rest, and
/// this surfaces that refusal rather than hiding the list.
final programmeWithdrawalsProvider =
    FutureProvider.family<List<Withdrawal>, String>((ref, programmeId) async {
  final client = ref.watch(apiClientProvider);
  final rows = await client.getList('/savings/programmes/$programmeId/withdrawals/');
  return rows.map(Withdrawal.fromJson).toList();
});
