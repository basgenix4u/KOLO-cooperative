import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'token_store.dart';

/// Dependencies are provided rather than constructed inline so tests can inject
/// fakes and so nothing in the app can accidentally make its own unauthenticated
/// HTTP client.
final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(tokens: ref.watch(tokenStoreProvider));
  return client;
});

/// Set by the app shell so an unrecoverable 401 can send the member to sign-in.
///
/// A [Notifier] rather than a `StateProvider`: `StateProvider` was deprecated in
/// Riverpod 2 and dropped from Riverpod 3's default exports, while `Notifier`
/// has been the supported shape since 2.0. Same behaviour, one type, both
/// versions.
class SessionExpired extends Notifier<bool> {
  @override
  bool build() => false;

  void signal() => state = true;

  /// Called once the member has been sent to sign-in, so the next launch does
  /// not redirect again.
  void clear() => state = false;
}

final sessionExpiredProvider = NotifierProvider<SessionExpired, bool>(SessionExpired.new);
