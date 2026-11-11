import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/models/money.dart';

/// Money is the one type in this app that must never be approximately right.
void main() {
  group('integer arithmetic', () {
    test('addition is exact where doubles are not', () {
      // The classic float failure: 0.1 + 0.2 != 0.3. In minor units it is exact.
      const a = Money(10, 'NGN');
      const b = Money(20, 'NGN');
      expect((a + b).minor, 30);

      // Ten thousand contributions of one kobo must be exactly 100 naira.
      var total = const Money(0, 'NGN');
      for (var i = 0; i < 10000; i++) {
        total = total + const Money(1, 'NGN');
      }
      expect(total.minor, 10000);
      expect(total.format(), contains('100'));
    });

    test('subtraction can go negative and stays exact', () {
      expect((const Money(500, 'NGN') - const Money(800, 'NGN')).minor, -300);
    });

    test('multiplication is integer-only', () {
      expect((const Money(3333, 'NGN') * 3).minor, 9999);
    });

    test('comparisons work on minor units', () {
      expect(const Money(1000, 'NGN') > const Money(999, 'NGN'), isTrue);
      expect(const Money(1000, 'NGN') <= const Money(1000, 'NGN'), isTrue);
    });

    test('equality distinguishes currency', () {
      expect(const Money(100, 'NGN') == const Money(100, 'NGN'), isTrue);
      expect(const Money(100, 'NGN') == const Money(100, 'USD'), isFalse);
    });
  });

  group('currency safety', () {
    test('adding different currencies throws instead of guessing', () {
      expect(
        () => const Money(100, 'NGN') + const Money(100, 'USD'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('comparing different currencies throws', () {
      expect(
        () => const Money(100, 'NGN') > const Money(100, 'USD'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('zero-decimal currencies are not divided by 100', () {
      // 1000 JPY is one thousand yen, not ten.
      expect(const Money(1000, 'JPY').major, 1000);
    });
  });

  group('parsing member input', () {
    test('plain whole numbers', () {
      expect(Money.tryParse('10000', 'NGN')?.minor, 1000000);
    });

    test('thousands separators are ignored, not rejected', () {
      expect(Money.tryParse('10,000', 'NGN')?.minor, 1000000);
      expect(Money.tryParse('1,234,567.89', 'NGN')?.minor, 123456789);
    });

    test('decimals become minor units exactly', () {
      expect(Money.tryParse('10.5', 'NGN')?.minor, 1050);
      expect(Money.tryParse('10.05', 'NGN')?.minor, 1005);
      expect(Money.tryParse('0.01', 'NGN')?.minor, 1);
    });

    test('a single decimal place is scaled, not truncated', () {
      expect(Money.tryParse('0.1', 'NGN')?.minor, 10);
    });

    test('refuses input with more precision than the currency allows', () {
      // Silently rounding a member's figure is how balances drift.
      expect(Money.tryParse('10.555', 'NGN'), isNull);
    });

    test('refuses nonsense rather than guessing', () {
      expect(Money.tryParse('', 'NGN'), isNull);
      expect(Money.tryParse('abc', 'NGN'), isNull);
      expect(Money.tryParse('10.0.0', 'NGN'), isNull);
      expect(Money.tryParse('-', 'NGN'), isNull);
    });

    test('accepts a leading minus for adjustments', () {
      expect(Money.tryParse('-500', 'NGN')?.minor, -50000);
    });

    test('spaces are tolerated because people type them', () {
      expect(Money.tryParse('10 000', 'NGN')?.minor, 1000000);
    });
  });

  group('API round trip', () {
    test('reads the backend representation', () {
      final money = Money.fromJson({'amount_minor': 250000, 'currency': 'NGN'});
      expect(money.minor, 250000);
      expect(money.currency, 'NGN');
    });

    test('reads an amount sent as a string', () {
      final money = Money.fromJson({'amount_minor': '250000', 'currency': 'ngn'});
      expect(money.minor, 250000);
      expect(money.currency, 'NGN');
    });

    test('defaults to the deployment currency when absent', () {
      expect(Money.fromJson({'amount_minor': 100}).currency, 'NGN');
    });
  });

  group('formatting', () {
    test('uses the currency symbol a member expects', () {
      expect(const Money(1000000, 'NGN').format(), contains('₦'));
      expect(const Money(1000000, 'USD').format(), contains(r'$'));
      expect(const Money(1000000, 'GBP').format(), contains('£'));
    });

    test('groups thousands', () {
      expect(const Money(123456700, 'NGN').format(), contains('1,234,567'));
    });

    test('short form is for chart labels, not receipts', () {
      expect(const Money(150000000, 'NGN').formatShort(), '1.5M');
      expect(const Money(1500000, 'NGN').formatShort(), '15.0k');
      expect(const Money(50000, 'NGN').formatShort(), '500');
    });
  });
}
