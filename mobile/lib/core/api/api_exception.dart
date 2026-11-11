import 'package:dio/dio.dart';

/// A failure the server described. Carries the backend's stable `code` so the
/// UI can react to *why* something failed rather than matching on prose.
class ApiException implements Exception {
  ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details = const {},
    this.fieldErrors = const {},
  });

  /// Stable machine code, e.g. `payout_underfunded`, `lending_disabled`.
  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic> details;
  final Map<String, List<String>> fieldErrors;

  bool get isAuthError => statusCode == 401 || code == 'not_authenticated';

  /// True when the server asked us to slow down. The UI should say "try again
  /// in N seconds" rather than showing a failure the member cannot act on.
  bool get isRateLimited => statusCode == 429 || code == 'throttled';

  /// How long the server asked us to wait, when it said so.
  int? get retryAfterSeconds {
    final fromDetails = details['retry_after_seconds'];
    if (fromDetails is int) return fromDetails;
    if (fromDetails is String) return int.tryParse(fromDetails);
    // The throttled body carries the wait inside the prose, e.g.
    // "Expected available in 42 seconds."
    final match = RegExp(r'in (\d+) seconds?').firstMatch(message);
    return match == null ? null : int.tryParse(match.group(1)!);
  }
  bool get isNetworkError => code == 'network_error';
  bool get isOffline => code == 'offline';

  /// Money refusals deserve their own presentation: a member must be told the
  /// truth about why nothing moved.
  bool get isFinancialRefusal => const {
        'insufficient_funds',
        'payout_underfunded',
        'pool_underfunded',
        'self_approval_blocked',
        'second_approver_required',
        'lending_disabled',
        'amount_invalid',
      }.contains(code);

  factory ApiException.fromResponse(Response<dynamic> response) {
    final data = response.data;
    if (data is Map && data['error'] is Map) {
      final error = data['error'] as Map;
      return ApiException(
        code: (error['code'] as String?) ?? 'unknown_error',
        message: (error['message'] as String?) ?? 'Something went wrong.',
        statusCode: response.statusCode,
        details: (error['details'] as Map?)?.cast<String, dynamic>() ?? const {},
        fieldErrors: (error['fields'] as Map?)?.map(
              (key, value) => MapEntry(
                '$key',
                (value is List ? value : [value]).map((e) => '$e').toList(),
              ),
            ) ??
            const {},
      );
    }
    return ApiException(
      code: response.statusCode == 401 ? 'not_authenticated' : 'unknown_error',
      message: 'Something went wrong. Please try again.',
      statusCode: response.statusCode,
    );
  }

  /// The message to put in front of a member. Server messages are written for
  /// people already; this only covers cases where they are not.
  String get userMessage {
    if (isNetworkError || isOffline) {
      return 'You appear to be offline. Your last saved data is still here.';
    }
    if (fieldErrors.isNotEmpty) {
      return fieldErrors.values.first.first;
    }
    return message;
  }

  @override
  String toString() => 'ApiException($code, $message)';
}
