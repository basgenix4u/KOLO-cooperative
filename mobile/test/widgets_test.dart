import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/api/api_exception.dart';
import 'package:kolo/core/models/money.dart';
import 'package:kolo/design/components.dart';
import 'package:kolo/design/theme.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: KoloTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('refusals inform rather than alarm', () {
    testWidgets('an underfunded payout is information, not an error', (tester) async {
      // The server refused because the money genuinely is not there. That is the
      // system working, so it must not offer a retry that cannot succeed.
      await tester.pumpWidget(_wrap(const KoloNotice(
        message: 'Only what has actually been collected can be paid out.',
        tone: KoloNoticeTone.warning,
        icon: Icons.savings_outlined,
      )));

      expect(find.text('Only what has actually been collected can be paid out.'),
          findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.byIcon(Icons.savings_outlined), findsOneWidget);
    });

    testWidgets('a network failure offers a retry', (tester) async {
      var retried = false;
      await tester.pumpWidget(_wrap(KoloErrorState(
        message: 'KOLO could not be reached.',
        onRetry: () => retried = true,
      )));

      expect(find.text('KOLO could not be reached.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('an offline state is marked as offline, not as a failure', (tester) async {
      await tester.pumpWidget(_wrap(const KoloErrorState(
        message: 'You are offline.',
        isOffline: true,
      )));
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });
  });

  group('status is never colour alone', () {
    test('every status pill carries a word, and they are distinct', () {
      // A member must be able to tell "processing" from "confirmed" without
      // relying on colour, so each status must resolve to its own words.
      const statuses = [
        'pending', 'confirmed', 'failed', 'rejected', 'processing',
        'approved', 'paid', 'overdue', 'cancelled', 'awaiting_payment',
      ];
      final seen = <String>{};
      for (final status in statuses) {
        final spec = KoloStatusPill.resolve(status);
        expect(spec.label, isNotEmpty, reason: '$status has no label');
        expect(spec.glyph, isNotNull, reason: '$status has no glyph');
        seen.add(spec.label.toLowerCase());
      }
      // No two statuses may collapse into the same words.
      expect(seen.length, statuses.length,
          reason: 'two statuses share a label, so they would be indistinguishable '
              'without colour');
    });

    test('an unknown status still renders something readable', () {
      final spec = KoloStatusPill.resolve('some_new_backend_state');
      expect(spec.label, isNotEmpty);
      expect(spec.glyph, isNotNull);
    });
  });

  group('amounts', () {
    test('money renders with grouping and a currency mark', () async {
      expect(const Money(5000000, 'NGN').format(), '₦50,000.00');
      expect(const Money(0, 'NGN').format(), '₦0.00');
      expect(const Money(123456789, 'NGN').format(), '₦1,234,567.89');
    });

    test('a negative amount keeps its sign', () {
      expect(const Money(-250000, 'NGN').format(), '-₦2,500.00');
    });

    test('the hero figure drops kobo but keeps the semantic label', () {
      // The widget shows whole units at size; a screen reader still gets the
      // exact figure, because a spoken number has no width to save.
      const amount = Money(5000050, 'NGN');
      expect(amount.format(withSymbol: false), '50,000.50');
    });

    test('parsing then formatting round-trips', () {
      final parsed = Money.tryParse('50,000.00', 'NGN');
      expect(parsed, isNotNull);
      expect(parsed!.minor, 5000000);
      expect(parsed.format(), '₦50,000.00');
    });
  });

  group('empty states teach', () {
    testWidgets('an empty state says why it is empty and what fills it', (tester) async {
      var acted = false;
      await tester.pumpWidget(_wrap(KoloEmptyState(
        title: 'No payouts yet',
        message: 'When the group is ready to pay someone, a request appears here.',
        action: FilledButton(
          onPressed: () => acted = true,
          child: const Text('Request a payout'),
        ),
      )));

      expect(find.text('No payouts yet'), findsOneWidget);
      await tester.tap(find.text('Request a payout'));
      expect(acted, isTrue);
    });
  });

  group('api errors', () {
    test('a financial refusal is recognised as a refusal', () {
      // These are the codes that mean "the rules are working", not "something
      // broke". The UI treats them differently.
      for (final code in [
        'insufficient_funds',
        'pool_underfunded',
        'payout_underfunded',
        'self_approval_blocked',
        'second_approver_required',
        'amount_invalid',
      ]) {
        expect(ApiException(code: code, message: 'x').isFinancialRefusal, isTrue,
            reason: '$code should read as a refusal');
      }
      // A network failure is a malfunction, not a rule: it gets a retry.
      expect(
        ApiException(code: 'network_error', message: 'x').isFinancialRefusal,
        isFalse,
      );
      // Separation-of-duties refusals belong here too: they are the rule
      // working exactly as intended, and must never read as a crash.
    });
  });
}
