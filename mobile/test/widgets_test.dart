import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/api/api_exception.dart';
import 'package:kolo/core/models/models.dart';
import 'package:kolo/core/models/money.dart';
import 'package:kolo/core/theme/kolo_theme.dart';
import 'package:kolo/shared/widgets/common.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: KoloTheme.light(),
      home: Scaffold(body: child),
    );

void main() {
  group('financial refusals are explained, not alarmed', () {
    testWidgets('an underfunded payout is shown as information, not an error', (tester) async {
      final error = ApiException(
        code: 'payout_underfunded',
        message: 'Only what has actually been collected can be paid out.',
        details: {'shortfall_minor': 100000},
      );

      await tester.pumpWidget(_wrap(ErrorNotice(error: error)));

      expect(
        find.text('Only what has actually been collected can be paid out.'),
        findsOneWidget,
      );
      // No "try again": retrying an underfunded payout cannot help, and offering
      // it would suggest the refusal was a glitch.
      expect(find.text('Try again'), findsNothing);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    });

    testWidgets('a network failure offers a retry', (tester) async {
      final error = ApiException(code: 'offline', message: 'unreachable');
      var retried = false;

      await tester.pumpWidget(_wrap(ErrorNotice(error: error, onRetry: () => retried = true)));
      expect(find.textContaining('offline'), findsOneWidget);

      await tester.tap(find.text('Try again'));
      expect(retried, isTrue);
    });

    testWidgets('field errors from the server are surfaced verbatim', (tester) async {
      final error = ApiException(
        code: 'validation_error',
        message: 'Check the form',
        fieldErrors: const {
          'amount_minor': ['Enter an amount greater than zero'],
        },
      );
      await tester.pumpWidget(_wrap(ErrorNotice(error: error)));
      expect(find.text('Enter an amount greater than zero'), findsOneWidget);
    });
  });

  group('status pills', () {
    testWidgets('known statuses are humanised', (tester) async {
      await tester.pumpWidget(_wrap(const StatusPill(status: 'payout_pending_approval')));
      expect(find.text('Payout pending approval'), findsOneWidget);
    });

    testWidgets('an unknown status is shown rather than hidden', (tester) async {
      // If the backend adds a state this build does not know, showing it is
      // safer than defaulting to something that looks successful.
      await tester.pumpWidget(_wrap(const StatusPill(status: 'quarantined')));
      expect(find.text('Quarantined'), findsOneWidget);
    });
  });

  group('money rendering', () {
    testWidgets('amount rows align label and value', (tester) async {
      await tester.pumpWidget(_wrap(
        const AmountRow(label: 'Contribution', value: '₦10,000.00'),
      ));
      expect(find.text('Contribution'), findsOneWidget);
      expect(find.text('₦10,000.00'), findsOneWidget);
    });

    testWidgets('progress is clamped so a bar never overfills', (tester) async {
      await tester.pumpWidget(_wrap(const CollectionProgress(percent: 250)));
      final indicator = tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(indicator.value, 1.0);
    });

    testWidgets('a shortfall shows the real missing amount', (tester) async {
      final programme = Programme.fromJson(const {
        'id': 'p1',
        'name': 'Monthly Ajo',
        'type': 'rotational',
        'status': 'active',
        'currency': 'NGN',
        'contribution_amount_minor': 1000000,
        'collected_minor': 3000000,
        'expected_minor': 4000000,
        'target_amount_minor': 4000000,
        'participant_count': 4,
        'progress_percent': 75.0,
        'frequency': 'monthly',
      });

      expect(programme.collected.minor, 3000000);
      expect(programme.collected.format(), contains('30,000'));
      expect(programme.contributionAmount.format(), contains('10,000'));

      final missing = programme.expected - programme.collected;
      expect(missing.minor, 1000000);
      expect(missing.format(), contains('10,000'));
    });
  });

  group('empty states', () {
    testWidgets('say what to do next', (tester) async {
      await tester.pumpWidget(_wrap(
        EmptyState(
          icon: Icons.groups_outlined,
          title: 'No groups yet',
          message: 'Join a savings group or start your own.',
          action: FilledButton(onPressed: () {}, child: const Text('Start a group')),
        ),
      ));
      expect(find.text('No groups yet'), findsOneWidget);
      expect(find.text('Start a group'), findsOneWidget);
    });
  });

  group('money model integration', () {
    test('a contribution total across currency boundaries would throw', () {
      const a = Money(1000000, 'NGN');
      const b = Money(2000000, 'NGN');
      expect((a + b).format(), contains('30,000'));

      expect(() => a + const Money(100, 'GHS'), throwsA(isA<ArgumentError>()));
    });

    test('parsing then formatting round-trips a realistic amount', () {
      final parsed = Money.tryParse('25,000.50', 'NGN');
      expect(parsed, isNotNull);
      expect(parsed!.minor, 2500050);
      expect(parsed.format(), contains('25,000'));
    });
  });
}
