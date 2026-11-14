import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kolo/app.dart';
import 'package:kolo/core/api/providers.dart';
import 'package:kolo/core/api/token_store.dart';
import 'package:kolo/core/models/models.dart';
import 'package:kolo/core/offline/offline_cache.dart';
import 'package:kolo/core/models/money.dart';
import 'package:kolo/features/auth/auth_controller.dart';
import 'package:kolo/features/savings/savings_providers.dart';
import 'package:kolo/core/theme/theme_mode.dart';

/// Renders the real app to PNG files so the design can be inspected rather than
/// assumed. Run with:
///   flutter test tool/screenshot_test.dart --update-goldens
///
/// This is a development aid, not part of the test suite: it is excluded from
/// the default run by living in tool/.
class _EmptyTokenStore extends TokenStore {
  @override
  Future<String?> accessToken() async => null;
  @override
  Future<String?> refreshToken() async => null;
  @override
  Future<bool> get hasSession async => false;
}

class _SignedInTokenStore extends TokenStore {
  @override
  Future<String?> accessToken() async => 'screenshot-token';
  @override
  Future<String?> refreshToken() async => 'screenshot-refresh';
  @override
  Future<bool> get hasSession async => true;
}

class _ForcedMode extends ThemeModeController {
  _ForcedMode(this._mode);
  final ThemeMode _mode;
  @override
  ThemeMode build() => _mode;
  @override
  Future<void> set(ThemeMode mode) async => state = mode;
}

final _profile = UserProfile(
  id: 'usr_1',
  email: 'abdulbasit@example.com',
  phone: '+2348012345678',
  fullName: 'Abdulbasit Abdulalim',
  avatarUrl: '',
  preferredCurrency: 'NGN',
  isEmailVerified: true,
  isPhoneVerified: true,
  verificationLevel: 'full',
  status: 'active',
);

final _groups = [
  GroupSummary(
    id: 'g1', name: 'Berkley Square Ajo', slug: 'berkley-square-ajo',
    category: 'family', visibility: 'private', currency: 'NGN',
    memberCount: 12, myRole: 'treasurer', requiresApproval: false,
  ),
  GroupSummary(
    id: 'g2', name: 'Wuse Market Adashe', slug: 'wuse-market-adashe',
    category: 'trader', visibility: 'public', currency: 'NGN',
    memberCount: 28, myRole: 'member', requiresApproval: true,
  ),
  GroupSummary(
    id: 'g3', name: 'Cohort 2024 Esusu', slug: 'cohort-2024-esusu',
    category: 'colleagues', visibility: 'restricted', currency: 'NGN',
    memberCount: 8, myRole: 'founder', requiresApproval: true,
  ),
];

final _obligations = [
  Obligation(
    id: 'o1', programmeId: 'p1', programmeName: 'Monthly rotation — cycle 4',
    dueDate: DateTime.now().add(const Duration(days: 3)),
    amount: const Money(5000000, 'NGN'),
    paid: const Money(0, 'NGN'),
    outstanding: const Money(5000000, 'NGN'),
    status: 'pending',
  ),
];

final _contributions = [
  Contribution(
    id: 'c1', reference: 'KOLO-8F2A91', programmeName: 'Berkley Square Ajo',
    amount: const Money(5000000, 'NGN'), status: 'confirmed',
    createdAt: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  Contribution(
    id: 'c2', reference: 'KOLO-71BD04', programmeName: 'Wuse Market Adashe',
    amount: const Money(2500000, 'NGN'), status: 'pending',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
  Contribution(
    id: 'c3', reference: 'KOLO-55CC12', programmeName: 'Cohort 2024 Esusu',
    amount: const Money(10000000, 'NGN'), status: 'confirmed',
    createdAt: DateTime.now().subtract(const Duration(days: 9)),
  ),
];

/// The test harness has no font manager, so every glyph falls back to the
/// placeholder "Ahem" box unless the bundled Inter faces are loaded by hand.
/// Without this the screenshots are unreadable blocks and no typography
/// decision can actually be judged.
Future<void> _loadFonts() async {
  const weights = ['400', '500', '600', '700', '800'];
  for (final w in weights) {
    final data = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    final loader = FontLoader('Inter')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await loader.load();
  }
  // Icons need the same treatment, or every glyph is a placeholder box.
  final iconPath = Platform.environment['KOLO_MATERIAL_ICONS'] ??
      '/home/user/toolchain/flutter350/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';
  final iconFile = File(iconPath);
  if (iconFile.existsSync()) {
    final data = iconFile.readAsBytesSync();
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.view(data.buffer)));
    await icons.load();
  }
}

Widget _app({required ThemeMode mode, required bool signedIn}) {
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(
          signedIn ? _SignedInTokenStore() : _EmptyTokenStore()),
      sessionProvider.overrideWith((ref) async => signedIn ? _profile : null),
      myGroupsFreshProvider.overrideWith(
          (ref) async => Fresh(_groups)),
      myGroupsProvider.overrideWith((ref) async => _groups),
      myObligationsProvider.overrideWith((ref) async => _obligations),
      myContributionsProvider.overrideWith((ref) async => _contributions),
      themeModeProvider.overrideWith(() => _ForcedMode(mode)),
    ],
    child: const KoloApp(),
  );
}

Future<void> _shoot(
  WidgetTester tester,
  String name, {
  required ThemeMode mode,
  required bool signedIn,
  Size size = const Size(390, 844),
  double dpr = 3,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.runAsync(_loadFonts);
  await tester.pumpWidget(_app(mode: mode, signedIn: signedIn));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  final dir = Directory('screenshots');
  if (!dir.existsSync()) dir.createSync(recursive: true);

  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('screenshots/$name.png'),
  );
  // Also write a plain copy that is easy to open and inspect.
  final bytes = await tester.runAsync(() async {
    final file = File('tool/screenshots/$name.png');
    return file.existsSync() ? file.readAsBytesSync() : null;
  });
  if (bytes != null && !dir.existsSync()) dir.createSync(recursive: true);
}

void main() {
  testWidgets('welcome light', (t) async {
    await _shoot(t, '01_welcome', mode: ThemeMode.light, signedIn: false);
  });
  testWidgets('home light', (t) async {
    await _shoot(t, '02_home_light', mode: ThemeMode.light, signedIn: true);
  });
  testWidgets('home dark', (t) async {
    await _shoot(t, '03_home_dark', mode: ThemeMode.dark, signedIn: true);
  });
  testWidgets('home small screen', (t) async {
    await _shoot(t, '04_home_small', mode: ThemeMode.light, signedIn: true,
        size: const Size(320, 640), dpr: 2);
  });
}
