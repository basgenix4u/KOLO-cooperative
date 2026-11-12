import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/auth/auth_controller.dart';
import '../api/api_client.dart';
import '../api/providers.dart';
import '../theme/kolo_theme.dart';

/// A read-through cache for GETs, so a member on a bad connection sees their
/// group rather than a spinner.
///
/// Deliberately narrow. Three rules, because a cache that guesses about money is
/// worse than no cache at all:
///
///  1. **Only GETs.** Nothing here can make a payment, approve a payout, or
///     change a member's role. Writes always go to the server or fail loudly.
///  2. **Only display data.** Balances and ledgers are never written here, so no
///     stale figure can be mistaken for an authoritative one. What is cached is
///     what the server already told everyone: names, programmes, lists.
///  3. **Say when it is old.** Every read reports whether it came from the
///     network or the disk, so the UI can label it. A cached number shown as if
///     it were live is the failure mode this whole file exists to avoid.
///
/// Entries expire, and are keyed per signed-in user: a second person signing in
/// on the same handset must not read the first person's groups.
class OfflineCache {
  OfflineCache(this._prefs);

  final SharedPreferences _prefs;

  static const _prefix = 'kolo.cache.';
  static const _userKey = 'kolo.cache.user';

  /// How long an entry stays usable. Long enough to survive a commute, short
  /// enough that a member is never looking at last week's figures.
  static const Duration maxAge = Duration(hours: 12);

  /// Bind the cache to the signed-in user and drop anyone else's entries.
  Future<void> bindTo(String userId) async {
    final previous = _prefs.getString(_userKey);
    if (previous != null && previous != userId) {
      await clear();
    }
    await _prefs.setString(_userKey, userId);
  }

  Future<void> clear() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith(_prefix)).toList();
    for (final key in keys) {
      await _prefs.remove(key);
    }
  }

  String _key(String path, String userId) => '$_prefix$userId.$path';

  Future<void> write(String path, String userId, Object? payload) async {
    await _prefs.setString(
      _key(path, userId),
      jsonEncode({
        'at': DateTime.now().toUtc().toIso8601String(),
        'payload': payload,
      }),
    );
  }

  CachedEntry? read(String path, String userId) {
    final raw = _prefs.getString(_key(path, userId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final at = DateTime.tryParse('${decoded['at']}');
      if (at == null) return null;
      if (DateTime.now().toUtc().difference(at) > maxAge) return null;
      return CachedEntry(payload: decoded['payload'], storedAt: at);
    } catch (_) {
      // A corrupt entry is a missing entry. Never let the cache break a screen.
      return null;
    }
  }
}

class CachedEntry {
  const CachedEntry({required this.payload, required this.storedAt});

  final Object? payload;
  final DateTime storedAt;

  bool get isStale {
    return DateTime.now().toUtc().difference(storedAt) > const Duration(minutes: 2);
  }
}

/// A value plus where it came from. The UI is required to say.
class Fresh<T> {
  const Fresh(this.value, {this.fromCache = false, this.storedAt});

  final T value;
  final bool fromCache;
  final DateTime? storedAt;

  /// A short, honest label for a cached value. Never invents precision.
  String get ageLabel {
    if (!fromCache) return '';
    final at = storedAt;
    if (at == null) return 'Saved copy';
    final age = DateTime.now().toUtc().difference(at);
    if (age.inMinutes < 1) return 'Saved a moment ago';
    if (age.inMinutes < 60) return 'Saved ${age.inMinutes} min ago';
    if (age.inHours < 24) return 'Saved ${age.inHours} h ago';
    return 'Saved copy';
  }
}

/// Reads a list from the network, falls back to the last successful copy when
/// the request fails for transport reasons, and reports which it used.
///
/// A *server refusal* is not a transport failure: if the member is not allowed
/// to see something, the cache must not hand them an older copy of it. Only
/// connection-shaped failures fall back.
class CachedListReader {
  CachedListReader({required this.cache, required this.client, required this.userId});

  final OfflineCache cache;
  final ApiClient client;
  final String userId;

  Future<Fresh<List<Map<String, dynamic>>>> read(String path) async {
    try {
      final rows = await client.getList(path);
      await cache.write(path, userId, rows);
      return Fresh(rows);
    } on Object catch (error) {
      final entry = cache.read(path, userId);
      if (entry == null || !_isTransportFailure(error)) rethrow;
      final payload = entry.payload;
      if (payload is! List) rethrow;
      final rows = payload.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
      return Fresh(rows, fromCache: true, storedAt: entry.storedAt);
    }
  }

  /// Exposed so the rule can be tested directly: it is a security decision, not
  /// an implementation detail.
  static bool isTransportFailureForTest(Object error) => _isTransportFailure(error);

  /// A connectivity problem is worth surviving from cache; a 403 is not, and a
  /// 5xx means the server is answering but unhappy, so neither is served stale.
  static bool _isTransportFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('connection') ||
        text.contains('socket') ||
        text.contains('timeout') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable');
  }
}

/// Preferences handle, loaded once.
final sharedPreferencesProvider = FutureProvider<SharedPreferences>((ref) {
  return SharedPreferences.getInstance();
});

final offlineCacheProvider = FutureProvider<OfflineCache>((ref) async {
  final prefs = await ref.watch(sharedPreferencesProvider.future);
  return OfflineCache(prefs);
});

/// The signed-in user's id, used to scope cache entries. Empty when signed out,
/// which disables the cache rather than mixing two people's data on a shared
/// handset — the ordinary case in the market this is built for.
final cacheUserIdProvider = Provider<String>((ref) {
  final session = ref.watch(sessionProvider).valueOrNull;
  return session?.id ?? '';
});

final cachedListReaderProvider = FutureProvider<CachedListReader>((ref) async {
  final cache = await ref.watch(offlineCacheProvider.future);
  final userId = ref.watch(cacheUserIdProvider);
  final client = ref.watch(apiClientProvider);

  // Signing in as somebody new invalidates whatever the last person cached.
  if (userId.isNotEmpty) {
    unawaited(cache.bindTo(userId));
  }

  return CachedListReader(cache: cache, client: client, userId: userId);
});

/// The label a cached value must wear. A stale balance presented as live is the
/// one failure this whole mechanism could introduce, so it is not optional and
/// not silent: the banner names what is on screen and offers a retry.
class CachedNotice extends StatelessWidget {
  const CachedNotice({super.key, required this.ageLabel, this.onRetry});

  final String ageLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.kolo;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: palette.moneySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 16, color: palette.moneyInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$ageLabel — you are offline, so this may have changed.',
              style: TextStyle(fontSize: 12.5, height: 1.35, color: palette.text),
            ),
          ),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Retry'),
            ),
        ],
      ),
    );
  }
}
