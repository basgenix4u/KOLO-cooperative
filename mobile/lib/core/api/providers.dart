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
final sessionExpiredProvider = StateProvider<bool>((ref) => false);
