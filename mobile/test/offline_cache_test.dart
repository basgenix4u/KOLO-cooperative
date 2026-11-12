import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/offline/offline_cache.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An offline cache is a way to show somebody something that is no longer true.
/// These tests are mostly about the ways that must not happen.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineCache cache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    cache = OfflineCache(await SharedPreferences.getInstance());
  });

  test('a written entry reads back with its timestamp', () async {
    await cache.write('/groups/', 'member-a', [
      {'id': 'g1', 'name': 'Ajo Ilorin'},
    ]);

    final entry = cache.read('/groups/', 'member-a');
    expect(entry, isNotNull);
    expect((entry!.payload as List).first['name'], 'Ajo Ilorin');
    expect(entry.storedAt.isBefore(DateTime.now().toUtc().add(const Duration(seconds: 1))), isTrue);
  });

  test('one member cannot read another member\'s saved data', () async {
    // The ordinary case is a shared handset. Groups, names and balances belong
    // to a person, not to the phone.
    await cache.write('/groups/', 'member-a', [
      {'id': 'g1'},
    ]);

    expect(cache.read('/groups/', 'member-b'), isNull);
  });

  test('signing in as somebody else wipes the previous member\'s copies', () async {
    await cache.bindTo('member-a');
    await cache.write('/groups/', 'member-a', [
      {'id': 'g1'},
    ]);

    await cache.bindTo('member-b');

    expect(cache.read('/groups/', 'member-a'), isNull,
        reason: 'the previous member\'s data must not survive a new sign-in');
  });

  test('signing in again as the same member keeps their copies', () async {
    await cache.bindTo('member-a');
    await cache.write('/groups/', 'member-a', [
      {'id': 'g1'},
    ]);

    await cache.bindTo('member-a');

    expect(cache.read('/groups/', 'member-a'), isNotNull);
  });

  test('a corrupt entry is treated as no entry rather than crashing a screen', () async {
    SharedPreferences.setMockInitialValues({'kolo.cache.member-a./groups/': 'not json'});
    final broken = OfflineCache(await SharedPreferences.getInstance());

    expect(broken.read('/groups/', 'member-a'), isNull);
  });

  test('an entry older than the maximum age is not served', () async {
    SharedPreferences.setMockInitialValues({
      'kolo.cache.member-a./groups/':
          '{"at":"${DateTime.now().toUtc().subtract(const Duration(days: 2)).toIso8601String()}",'
          '"payload":[{"id":"g1"}]}',
    });
    final stale = OfflineCache(await SharedPreferences.getInstance());

    expect(stale.read('/groups/', 'member-a'), isNull);
  });

  test('the age label never claims to be live', () {
    final now = DateTime.now().toUtc();

    expect(const Fresh(1).ageLabel, '');
    expect(Fresh(1, fromCache: true, storedAt: now).ageLabel, 'Saved a moment ago');
    expect(
      Fresh(1, fromCache: true, storedAt: now.subtract(const Duration(minutes: 20))).ageLabel,
      'Saved 20 min ago',
    );
    expect(
      Fresh(1, fromCache: true, storedAt: now.subtract(const Duration(hours: 5))).ageLabel,
      'Saved 5 h ago',
    );
  });

  group('transport failures are the only ones served from cache', () {
    test('a connection problem is', () {
      expect(CachedListReader.isTransportFailureForTest('SocketException: failed host lookup'),
          isTrue);
      expect(CachedListReader.isTransportFailureForTest('Connection timed out'), isTrue);
    });

    test('a server refusal is not', () {
      // Handing a member an older copy of something they have just been told
      // they cannot see would be a permission bypass dressed as convenience.
      expect(CachedListReader.isTransportFailureForTest('403 missing_permission'), isFalse);
      expect(CachedListReader.isTransportFailureForTest('401 token_not_valid'), isFalse);
      expect(CachedListReader.isTransportFailureForTest('500 server_error'), isFalse);
    });
  });
}
