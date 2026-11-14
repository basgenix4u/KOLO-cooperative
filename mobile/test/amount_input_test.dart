import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kolo/core/models/money.dart';
import 'package:kolo/features/savings/screens/contribute_screen.dart';

/// The amount field formats thousands while the member types. It is the last
/// thing standing between a typed number and a payment, so it gets real tests
/// rather than a visual check.
void main() {
  TextEditingValue apply(String before, String after) {
    const formatter = AmountGroupingFormatter();
    return formatter.formatEditUpdate(
      TextEditingValue(
        text: before,
        selection: TextSelection.collapsed(offset: before.length),
      ),
      TextEditingValue(
        text: after,
        selection: TextSelection.collapsed(offset: after.length),
      ),
    );
  }

  group('grouping', () {
    test('groups thousands', () {
      expect(apply('', '50000').text, '50,000');
      expect(apply('', '1000000').text, '1,000,000');
      expect(apply('', '999').text, '999');
      expect(apply('', '1000').text, '1,000');
    });

    test('keeps decimals and caps them at two places', () {
      expect(apply('', '50,000.5').text, '50,000.5');
      expect(apply('', '50,000.55').text, '50,000.55');
      expect(apply('', '50,000.555').text, '50,000.55');
    });

    test('allows a lone decimal point and trailing zero', () {
      expect(apply('', '0.').text, '0.');
      expect(apply('', '1.0').text, '1.0');
    });

    test('collapses stray symbols and extra dots', () {
      expect(apply('', '12a3b4').text, '1,234');
      expect(apply('', '1.2.3').text, '1.23');
    });

    test('drops leading zeros but keeps a single zero', () {
      expect(apply('', '007').text, '7');
      expect(apply('', '0').text, '0');
    });

    test('empty input stays empty rather than becoming zero', () {
      expect(apply('50', '').text, '');
    });

    test('deleting a separator does not strand the caret', () {
      // Deleting the comma from "1,000" leaves "1000", which re-groups.
      final result = apply('1,000', '1000');
      expect(result.text, '1,000');
      expect(result.selection.baseOffset, lessThanOrEqualTo(result.text.length));
    });

    test('a prefilled amount is grouped like typed input', () {
      // The suggested amount comes from the server, not the keyboard, so it has
      // to be grouped by the same rules or the screen shows two formats.
      expect(groupMinorUnits(5000000), '50,000.00');
      expect(groupMinorUnits(2500000), '25,000.00');
      expect(groupMinorUnits(0), '0.00');
      expect(groupMinorUnits(123456789), '1,234,567.89');
    });

    test('every grouped string parses to the amount that was typed', () {
      // The critical property: what is displayed and what is charged agree.
      for (final typed in ['50000', '50000.5', '50000.55', '12345678', '1000000']) {
        final shown = apply('', typed).text;
        final parsed = Money.tryParse(shown, 'NGN');
        expect(parsed, isNotNull, reason: '"$shown" must parse');
        expect(
          parsed!.minor,
          Money.tryParse(typed, 'NGN')!.minor,
          reason: '"$shown" must equal the typed "$typed"',
        );
      }
    });
  });
}
