import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart';

import 'package:kolo/core/api/api_client.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/core/api/token_store.dart';

class _NullTokenStore extends TokenStore {
  @override
  Future<String?> accessToken() async => null;

  @override
  Future<String?> refreshToken() async => null;

  @override
  Future<bool> get hasSession async => false;
}

/// Answers every request from a fixed table instead of the network.
///
/// The parity renders must show real screens — real widgets, real providers,
/// real parsing — with only the transport pinned. A stubbed repository would
/// hide exactly the bugs these renders exist to catch.
class AdapterStub implements HttpClientAdapter {
  AdapterStub(this.routes);

  final Map<String, Object> routes;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.uri.path;
    final hit = routes.entries
        .where((e) => path.endsWith(e.key))
        .map((e) => e.value)
        .firstOrNull;
    return ResponseBody.fromString(
      hit == null ? '{"data": []}' : _encodeList(hit),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  /// List endpoints answer `{"data": [ … ]}`; anything else answers the object.
  String _encodeList(Object value) {
    if (value is List) return '{"data": [${value.map(_json).join(',')}]}';
    return '{"data": ${_json(value)}}';
  }

  String _json(Object? value) {
    if (value == null) return 'null';
    if (value is String) return '"${value.replaceAll('"', r'\"')}"';
    if (value is num || value is bool) return '$value';
    if (value is List) return '[${value.map(_json).join(',')}]';
    if (value is Map) {
      return '{${value.entries.map((e) => '"${e.key}":${_json(e.value)}').join(',')}}';
    }
    return 'null';
  }

  @override
  void close({bool force = false}) {}
}

/// A real [ApiClient] over the stub transport, wired exactly as the app does.
ApiClient fixtureClient(Map<String, Object> routes) => ApiClient(
      tokens: _NullTokenStore(),
      dio: Dio()..httpClientAdapter = AdapterStub(routes),
    );

List<Override> fixtureOverrides(Map<String, Object> routes) => [
      tokenStoreProvider.overrideWithValue(_NullTokenStore()),
      apiClientProvider.overrideWithValue(fixtureClient(routes)),
    ];

const memberJson = <String, dynamic>{
  'id': '0f1a2b3c-0000-4000-8000-000000000001',
  'full_name': 'Ada Obi',
  'first_name': 'Ada',
  'phone': '08031234567',
  'email': 'ada@example.com',
  'role': 'member',
  'is_verified': true,
  'initials': 'AO',
};

const conversationFixtures = <Map<String, dynamic>>[
  {
    'id': '0f1a2b3c-0000-4000-8000-0000000000c1',
    'kind': 'group',
    'group_id': 'ajo-imani',
    'title': 'Ajo Imani',
    'is_locked': false,
    'unread': 3,
    'last_message': {
      'body': 'Reminder — cycle 8 closes on Friday, please pay before noon.',
      'sender_name': 'Fatima',
      'created_at': '2026-11-05T09:22:00Z',
    },
  },
  {
    'id': '0f1a2b3c-0000-4000-8000-0000000000c2',
    'kind': 'group',
    'group_id': 'market-osusu',
    'title': 'Market Osusu',
    'is_locked': false,
    'unread': 0,
    'last_message': {
      'body': 'Paid, thank you',
      'sender_name': 'You',
      'created_at': '2026-11-04T17:40:00Z',
    },
  },
  {
    'id': '0f1a2b3c-0000-4000-8000-0000000000c3',
    'kind': 'group',
    'group_id': 'ajo-imani-officers',
    'title': 'Officers only',
    'is_locked': true,
    'unread': 2,
    'last_message': {
      'body': 'The payout needs a third signature before it can go out.',
      'sender_name': 'Chidi',
      'created_at': '2026-11-04T14:05:00Z',
    },
  },
  {
    'id': '0f1a2b3c-0000-4000-8000-0000000000c4',
    'kind': 'direct',
    'group_id': null,
    'title': 'Ngozi Eze',
    'is_locked': false,
    'unread': 0,
    'last_message': {
      'body': 'Thank you for approving the request',
      'sender_name': 'Ngozi',
      'created_at': '2026-11-02T10:12:00Z',
    },
  },
  {
    'id': '0f1a2b3c-0000-4000-8000-0000000000c5',
    'kind': 'group',
    'group_id': 'abuja-builders',
    'title': 'Abuja Builders',
    'is_locked': false,
    'unread': 0,
    'last_message': {
      'body': 'Announcement: meeting moved to Sunday',
      'sender_name': 'KOLO',
      'created_at': '2026-11-01T08:00:00Z',
    },
  },
];

final defaultRoutes = <String, Object>{
  '/comms/conversations/': conversationFixtures,
};

/// Loads the real Inter faces into the test engine.
///
/// Without this every glyph is drawn as a filled box, which makes a parity
/// render useless: a golden full of rectangles cannot be compared to the design.
Future<void> loadKoloFonts() async {
  final loader = FontLoader('Inter');
  for (final weight in [400, 500, 600, 700, 800]) {
    loader.addFont(rootBundle.load('assets/fonts/Inter-$weight.ttf'));
  }
  await loader.load();

  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('assets/fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}
