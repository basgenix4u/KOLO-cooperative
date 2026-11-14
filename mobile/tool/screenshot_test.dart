import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

final _programme = Programme(
  id: 'prg_1',
  groupSlug: 'berkley-square-ajo',
  name: 'Monthly rotation',
  type: 'rotating',
  status: 'active',
  currency: 'NGN',
  contributionAmount: Money(5000000, 'NGN'),
  collected: Money(17500000, 'NGN'),
  expected: Money(24000000, 'NGN'),
  target: Money(24000000, 'NGN'),
  participantCount: 12,
  progressPercent: 72.9,
  frequency: 'monthly',
);

final _detailGroup = GroupSummary(
  id: 'grp_1',
  name: 'Berkley Square Ajo',
  slug: 'berkley-square-ajo',
  category: 'family',
  visibility: 'private',
  currency: 'NGN',
  memberCount: 12,
  myRole: 'treasurer',
  requiresApproval: true,
);

final _moneyObligations = [
  Obligation(
    id: 'obl_1',
    programmeId: 'prg_1',
    programmeName: 'Monthly rotation',
    dueDate: DateTime.now().add(const Duration(days: 3)),
    amount: const Money(5000000, 'NGN'),
    paid: const Money(0, 'NGN'),
    outstanding: const Money(5000000, 'NGN'),
    status: 'pending',
  ),
  Obligation(
    id: 'obl_2',
    programmeId: 'prg_2',
    programmeName: 'School fees fund',
    dueDate: DateTime.now().subtract(const Duration(days: 6)),
    amount: const Money(8000000, 'NGN'),
    paid: const Money(3000000, 'NGN'),
    outstanding: const Money(5000000, 'NGN'),
    status: 'overdue',
  ),
  Obligation(
    id: 'obl_3',
    programmeId: 'prg_3',
    programmeName: 'Emergency fund',
    dueDate: DateTime.now().add(const Duration(days: 21)),
    amount: const Money(2000000, 'NGN'),
    paid: const Money(500000, 'NGN'),
    outstanding: const Money(1500000, 'NGN'),
    status: 'pending',
  ),
];

final _moneyHistory = [
  Contribution(
    id: 'c1', reference: 'KOLO-7F3A21', programmeName: 'Monthly rotation',
    amount: const Money(5000000, 'NGN'), status: 'confirmed',
    createdAt: DateTime.now().subtract(const Duration(days: 30)),
  ),
  Contribution(
    id: 'c2', reference: 'KOLO-9B12C4', programmeName: 'School fees fund',
    amount: const Money(3000000, 'NGN'), status: 'confirmed',
    createdAt: DateTime.now().subtract(const Duration(days: 12)),
  ),
  Contribution(
    id: 'c3', reference: 'KOLO-2D88E0', programmeName: 'Monthly rotation',
    amount: const Money(5000000, 'NGN'), status: 'processing',
    createdAt: DateTime.now().subtract(const Duration(days: 2)),
  ),
];

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
      groupProvider('berkley-square-ajo').overrideWith((ref) async => _detailGroup),
      groupProgrammesProvider('berkley-square-ajo')
          .overrideWith((ref) async => [_programme]),
      programmeProvider('prg_1').overrideWith((ref) async => _programme),
      // The contribute route stacks on top of programme detail, which fetches
      // cycles on build. Without this it opens a real socket and leaves a timer.
      programmeCyclesProvider('prg_1').overrideWith((ref) async => <RotationCycle>[]),
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
  String? route,
}) async {
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.runAsync(_loadFonts);
  await tester.pumpWidget(_app(mode: mode, signedIn: signedIn));
  await tester.pumpAndSettle(const Duration(seconds: 2));

  // Navigate *after* mount. Passing an initial location instead lets GoRouter's
  // redirect run against the pre-mount state, which bounces straight to
  // /welcome and silently photographs the wrong screen.
  if (route != null) {
    final router = GoRouter.of(tester.element(find.byType(Navigator).first));
    router.go(route);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  }

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
  testWidgets('login light', (t) async {
    await _shoot(t, '05_login', mode: ThemeMode.light, signedIn: false,
        route: '/login');
  });
  testWidgets('register light', (t) async {
    await _shoot(t, '06_register', mode: ThemeMode.light, signedIn: false,
        route: '/register');
  });
  testWidgets('verify light', (t) async {
    await _shoot(t, '07_verify', mode: ThemeMode.light, signedIn: false,
        route: '/verify?email=abdulbasit%40example.com');
  });
  testWidgets('login dark', (t) async {
    await _shoot(t, '08_login_dark', mode: ThemeMode.dark, signedIn: false,
        route: '/login');
  });
  testWidgets('contribute light', (t) async {
    await _shoot(t, '14_contribute', mode: ThemeMode.light, signedIn: true,
        route: '/programmes/prg_1/contribute?obligation=obl_1&amount=5000000');
  });
  testWidgets('contribute small screen', (t) async {
    await _shoot(t, '15_contribute_small', mode: ThemeMode.light, signedIn: true,
        size: const Size(320, 640), dpr: 2,
        route: '/programmes/prg_1/contribute?obligation=obl_1&amount=5000000');
  });
  testWidgets('money light', (t) async {
    await _shoot(t, '12_money', mode: ThemeMode.light, signedIn: true,
        route: '/money');
  });
  testWidgets('money dark', (t) async {
    await _shoot(t, '13_money_dark', mode: ThemeMode.dark, signedIn: true,
        route: '/money');
  });
  testWidgets('group detail light', (t) async {
    await _shoot(t, '10_group_detail', mode: ThemeMode.light, signedIn: true,
        route: '/groups/berkley-square-ajo');
  });
  testWidgets('group detail dark', (t) async {
    await _shoot(t, '11_group_detail_dark', mode: ThemeMode.dark, signedIn: true,
        route: '/groups/berkley-square-ajo');
  });
  testWidgets('register small screen', (t) async {
    await _shoot(t, '09_register_small', mode: ThemeMode.light, signedIn: false,
        size: const Size(320, 640), dpr: 2, route: '/register');
  });
}
