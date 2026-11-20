import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kolo/design/components.dart';
import 'package:kolo/design/navigation.dart';
import 'package:kolo/features/chat/screens/messages_screen.dart';

import 'fixtures.dart';
import 'parity_test.dart' show renderWithTabBar;

/// The design's own rects for SCR-075, read out of the rendered reference.
const _design = {
  'search': (20.0, 116.0, 350.0, 46.0),
  'title': (20.0, 69.5, null, 34.5),
  'eyebrow': (20.0, 52.0, null, 14.5),
  'notice': (20.0, 545.9, 350.0, 82.3),
  'tabbar': (0.0, 766.0, 390.0, 78.0),
};

void main() {
  testWidgets('the header, search, notice and tab bar sit where the design puts them', (tester) async {
    await renderWithTabBar(
      tester,
      const SafeArea(bottom: false, child: MessagesScreen()),
      index: 2,
      unread: 5,
    );

    void near(String name, Finder f, double tolerance) {
      final (x, y, w, h) = _design[name]!;
      final r = tester.getRect(f.first);
      expect(r.left, closeTo(x, tolerance), reason: '$name left');
      expect(r.top, closeTo(y, tolerance), reason: '$name top');
      if (w != null) expect(r.width, closeTo(w, tolerance), reason: '$name width');
      expect(r.height, closeTo(h, tolerance + 2), reason: '$name height');
    }

    near('search', find.byType(KoloSearchField), 2);
    near('title', find.text('Conversations'), 3);
    near('eyebrow', find.text('MESSAGES'), 2);
    near('notice', find.byType(KoloNote), 3);
    near('tabbar', find.byType(KoloBottomNav), 3);
  });

  testWidgets('geometry dump', (tester) async {
    await renderWithTabBar(
      tester,
      const SafeArea(bottom: false, child: MessagesScreen()),
      index: 2,
      unread: 5,
    );

    void dump(String name, Finder f) {
      final found = f.evaluate();
      if (found.isEmpty) {
        debugPrint('MISS $name');
        return;
      }
      final r = tester.getRect(f.first);
      debugPrint('RECT $name x=${r.left.toStringAsFixed(1)} '
          'y=${r.top.toStringAsFixed(1)} w=${r.width.toStringAsFixed(1)} '
          'h=${r.height.toStringAsFixed(1)} bottom=${r.bottom.toStringAsFixed(1)}');
    }

    dump('search', find.byType(KoloSearchField));
    dump('title', find.text('Conversations'));
    dump('eyebrow', find.text('MESSAGES'));
    dump('first-row', find.text('Ajo Imani'));
    dump('notice', find.byType(KoloNote));
    dump('tabbar', find.byType(KoloBottomNav));
  });
}
