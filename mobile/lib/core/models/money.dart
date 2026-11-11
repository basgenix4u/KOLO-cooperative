import 'package:intl/intl.dart';

/// Money, represented the only way that is safe to do arithmetic on: as an
/// integer number of minor units (kobo, cents) plus its currency.
///
/// Real money in a savings app must never touch `double`. `0.1 + 0.2` is not
/// `0.3` in binary floating point, and a group that loses a kobo per member per
/// cycle loses trust long before it loses money. Every amount in this app is an
/// [int] until the moment it is formatted for a human.
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  /// Amount in minor units. 10,000 NGN is `Money(1000000, 'NGN')`.
  final int minor;
  final String currency;

  static const int _minorPerMajor = 100;

  /// Currencies whose minor unit is not 1/100. Listed rather than guessed.
  static const Set<String> _zeroDecimalCurrencies = {'JPY', 'KRW', 'VND', 'XOF', 'XAF', 'CLP'};

  /// How many minor units make one major unit.
  int get _scale => Money._scaleFor(currency);

  static int _decimalPlacesFor(String currency) =>
      _zeroDecimalCurrencies.contains(currency) ? 0 : 2;

  /// Decimal places for this instance's currency.
  int get decimalPlaces => Money._decimalPlacesFor(currency);

  static int _scaleFor(String currency) =>
      _zeroDecimalCurrencies.contains(currency) ? 1 : _minorPerMajor;

  int get major => minor ~/ _scale;
  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;
  Money get abs => Money(minor.abs(), currency);

  Money operator +(Money other) {
    _assertSameCurrency(other, '+');
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other, '-');
    return Money(minor - other.minor, currency);
  }

  Money operator *(int factor) => Money(minor * factor, currency);

  bool operator >(Money other) {
    _assertSameCurrency(other, '>');
    return minor > other.minor;
  }

  bool operator <(Money other) {
    _assertSameCurrency(other, '<');
    return minor < other.minor;
  }

  bool operator >=(Money other) {
    _assertSameCurrency(other, '>=');
    return minor >= other.minor;
  }

  bool operator <=(Money other) {
    _assertSameCurrency(other, '<=');
    return minor <= other.minor;
  }

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other, 'compareTo');
    return minor.compareTo(other.minor);
  }

  void _assertSameCurrency(Money other, String operation) {
    if (other.currency != currency) {
      // Mixing currencies without an explicit rate is a bug every time, so it
      // throws here rather than producing a plausible-looking wrong number.
      throw ArgumentError(
        'Cannot $operation $currency and ${other.currency} without a conversion rate',
      );
    }
  }

  /// Parses user input like "10,000.50" or "10 000" into minor units.
  ///
  /// Returns null when the text is not a valid amount — a caller must not be
  /// able to submit a silently rounded or truncated figure.
  static Money? tryParse(String raw, String currency) {
    final cleaned = raw.replaceAll(RegExp(r'[\s,]'), '');
    if (cleaned.isEmpty) return null;
    final pattern = RegExp(r'^-?\d+(\.\d{1,2})?$');
    if (!pattern.hasMatch(cleaned)) return null;
    // Longer than any real balance; refuse rather than throw on int overflow.
    if (cleaned.length > 15) return null;

    final negative = cleaned.startsWith('-');
    final unsigned = negative ? cleaned.substring(1) : cleaned;
    final parts = unsigned.split('.');
    final whole = int.tryParse(parts.first);
    if (whole == null) return null;

    final scale = Money._scaleFor(currency);
    final places = Money._decimalPlacesFor(currency);
    var fraction = 0;
    if (parts.length > 1 && places > 0) {
      // "10.5" means 10 naira 50 kobo, not 10 naira 5 kobo: pad the fraction to
      // the currency's precision, then scale it into minor units.
      final padded = parts[1].padRight(places, '0');
      fraction = int.parse(padded);
    }
    final total = whole * scale + fraction;
    return Money(negative ? -total : total, currency);
  }

  /// "₦10,000.00" — grouped, with the symbol the member expects.
  String format({bool withSymbol = true, bool compact = false}) {
    final scale = _scale;
    final value = minor / scale;
    final formatter = NumberFormat.currency(
      locale: _localeFor(currency),
      symbol: withSymbol ? symbolFor(currency) : '',
      decimalDigits: decimalPlaces,
    );
    return formatter.format(value).trim();
  }

  /// "10,000" — no decimals, for tight spaces like chart labels.
  String formatShort() {
    final scale = _scale;
    final majorUnits = minor ~/ scale;
    if (majorUnits.abs() >= 1000000) {
      final millions = majorUnits / 1000000;
      return '${millions.toStringAsFixed(1)}M';
    }
    if (majorUnits.abs() >= 1000) {
      final thousands = majorUnits / 1000;
      return '${thousands.toStringAsFixed(1)}k';
    }
    return NumberFormat.decimalPattern(_localeFor(currency)).format(majorUnits);
  }

  static String symbolFor(String currency) => switch (currency) {
        'NGN' => '₦',
        'USD' => r'$',
        'GBP' => '£',
        'EUR' => '€',
        'KES' => 'KSh',
        'GHS' => 'GH₵',
        'ZAR' => 'R',
        _ => currency,
      };

  static String _localeFor(String currency) => switch (currency) {
        'NGN' => 'en_NG',
        'GBP' => 'en_GB',
        'EUR' => 'de_DE',
        'KES' => 'en_KE',
        'GHS' => 'en_GH',
        'ZAR' => 'en_ZA',
        _ => 'en_US',
      };

  /// Parses the API's representation. Amounts arriving from the server are
  /// integers in minor units plus a currency string.
  factory Money.fromJson(Map<String, dynamic> json, {String field = 'amount_minor'}) {
    final amount = json[field];
    return Money(
      amount is int ? amount : int.parse('$amount'),
      (json['currency'] as String?)?.toUpperCase() ?? 'NGN',
    );
  }

  @override
  String toString() => '${Money(minor, currency).format()} [$minor $currency]';
}
