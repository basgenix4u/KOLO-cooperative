import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kolo/features/auth/screens/welcome_screen.dart';

import 'fixtures.dart';
import 'parity_test.dart' show renderScreen;

/// SCR-002's own rects, measured from the rendered reference.
const _design = {
  'pill': (161.0, 16.0),
  'h1a': (203.0, 82.0),
  'body': (387.0, 132.0),
  'btn1': (684.5, 23.2),
  'btn2': (748.5, 23.2),
  'footer': (802.8, 15.2),
};

void main() {
  testWidgets('the welcome screen sits where the design puts it', (tester) async {
    await renderScreen(tester, const WelcomeScreen());

    void near(String name, Finder f) {
      final (y, h) = _design[name]!;
      final r = tester.getRect(f.first);
      expect(r.top, closeTo(y, 3), reason: '$name top');
      expect(r.height, closeTo(h, 5), reason: '$name height');
    }

    near('pill', find.text('TWO SIGNATURES, EVERY PAYOUT'));
    near('h1a', find.text('Saved\ntogether.'));
    near('body', find.textContaining('Ajo, esusu'));
    near('btn1', find.text('Get started'));
    near('btn2', find.text('I already have an account'));
    near('footer', find.textContaining('Sandbox build'));
  });

  testWidgets('welcome geometry', (tester) async {
    await renderScreen(tester, const WelcomeScreen());
    void dump(String name, Finder f) {
      final r = tester.getRect(f.first);
      debugPrint('RECT $name y=${r.top.toStringAsFixed(1)} h=${r.height.toStringAsFixed(1)} w=${r.width.toStringAsFixed(1)}');
    }

    dump('pill', find.text('TWO SIGNATURES, EVERY PAYOUT'));
    dump('h1a', find.text('Saved\ntogether.'));
    dump('h1b', find.text('Counted\nproperly.'));
    dump('body', find.textContaining('Ajo, esusu'));
    dump('btn1', find.text('Get started'));
    dump('btn2', find.text('I already have an account'));
    dump('footer', find.textContaining('Sandbox build'));
  });
}
