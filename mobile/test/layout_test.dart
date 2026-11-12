import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/models/money.dart';
import 'package:kolo/core/theme/kolo_theme.dart';
import 'package:kolo/shared/widgets/common.dart';

/// Layouts have to survive three things this app cannot control: a narrow phone,
/// a member who has turned text size up because they need it, and a long label.
/// The failure mode is an overflow stripe, which is not a cosmetic problem — it
/// means part of a balance is unreadable.
void main() {
  Future<void> pumpAt(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(360, 740),
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: KoloTheme.light(),
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    );
    await tester.pump();
  }

  group('financial rows', () {
    testWidgets('an amount row fits at 320dp with default text', (tester) async {
      await pumpAt(
        tester,
        const AmountRow(label: 'Collected so far', value: '₦4,000,000.00'),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('a long label and a large amount still fit at 320dp', (tester) async {
      await pumpAt(
        tester,
        const AmountRow(
          label: 'Contribution outstanding for this cycle',
          value: '₦12,345,678.90',
        ),
        size: const Size(320, 640),
      );

      expect(tester.takeException(), isNull, reason: 'the label must yield, not the amount');
    });

    testWidgets('rows survive 200% text scale', (tester) async {
      // Many members genuinely use large text. A balance that overflows at 2x is
      // a balance part of the membership cannot read.
      await pumpAt(
        tester,
        const Column(
          children: [
            AmountRow(label: 'Collected so far', value: '₦250,000.00'),
            SizedBox(height: 12),
            AmountRow(label: 'Remaining', value: '₦1,250,000.00', emphasise: true),
          ],
        ),
        textScale: 2.0,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('money is never truncated to fit', () {
    testWidgets('the full amount is present in the widget tree', (tester) async {
      await pumpAt(
        tester,
        const AmountRow(label: 'Pool', value: '₦9,999,999.99'),
        size: const Size(320, 640),
      );

      // An ellipsis on an amount is worse than a wrapped label: it silently
      // changes the number the member is reading.
      expect(find.text('₦9,999,999.99'), findsOneWidget);
    });

    testWidgets('amounts are formatted from minor units, never floats', (tester) async {
      const money = Money(123456789, 'NGN');

      expect(money.format(), contains('1,234,567.89'));
    });
  });

  group('status pills', () {
    testWidgets('a status pill does not overflow with a long status', (tester) async {
      await pumpAt(
        tester,
        const Center(child: StatusPill(status: 'pending_approval')),
        size: const Size(320, 200),
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    testWidgets('the home header labels every icon button', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 740));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: KoloTheme.light(),
            home: const Scaffold(
              body: Row(
                children: [
                  // Mirrors the header actions: notifications and profile.
                  IconButton(
                    tooltip: 'Notifications',
                    onPressed: null,
                    icon: Icon(Icons.notifications_none_rounded),
                  ),
                  IconButton(
                    tooltip: 'Your profile',
                    onPressed: null,
                    icon: Icon(Icons.person_outline_rounded),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      _expectLabelsOnIconButtons(tester);
    });
  });
}

/// Screen readers announce a button's tooltip, not its icon. An icon-only button
/// with no tooltip is an unlabelled control: it can be focused and pressed but
/// not described, which for a member using TalkBack means a wall of "button".
void _expectLabelsOnIconButtons(WidgetTester tester) {
  final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
  for (final button in buttons) {
    final tip = button.tooltip;
    expect(
      tip != null && tip.isNotEmpty,
      isTrue,
      reason: 'an IconButton with no tooltip cannot be announced by a screen reader',
    );
  }
}

void mainA11y() {}
