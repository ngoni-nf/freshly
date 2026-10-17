import 'package:intl/intl.dart';

/// Money in the Freshly apps mirrors the backend exactly: an integer count of
/// minor units plus a currency. The client never does arithmetic on a double
/// and never re-derives a total — it renders what the server quoted, so what a
/// customer sees and what the gateway authorises can never disagree.
class Money {
  const Money({required this.minor, required this.currency});

  final int minor;
  final String currency;

  static const Map<String, String> _symbols = {
    'ZAR': 'R',
    'USD': r'US$',
    'ZWG': 'ZiG',
  };

  factory Money.fromJson(Map<String, dynamic> json) =>
      Money(minor: json['minor'] as int, currency: json['currency'] as String);

  Map<String, dynamic> toJson() => {'minor': minor, 'currency': currency};

  double get major => minor / 100;

  String format({bool compact = false}) {
    final symbol = _symbols[currency] ?? '$currency ';
    if (compact && minor % 100 == 0) {
      return '$symbol${NumberFormat('#,##0').format(major)}';
    }
    return '$symbol${NumberFormat('#,##0.00').format(major)}';
  }

  @override
  String toString() => format();

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);
}

String formatMinor(int minor, String currency) =>
    Money(minor: minor, currency: currency).format();

/// Basis points of an amount, rounded half away from zero in integer maths —
/// the same rule as `applyBps` on the API, so a fee the app quotes before a
/// cash-out is the fee the server charges.
int applyBps(int amountMinor, int bps) {
  final scaled = amountMinor * bps;
  final sign = scaled < 0 ? -1 : 1;
  return sign * ((scaled.abs() + 5000) ~/ 10000);
}

/// Parses a typed price such as "12", "12.5" or "12.50" into minor units
/// without passing through a double, so "12.35" is 1235 and never 1234.
/// Returns null for anything that is not a non-negative amount with at most
/// two decimals.
int? parseMinor(String input) {
  final match = RegExp(r'^\s*(\d+)(?:[.,](\d{0,2}))?\s*$').firstMatch(input);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final cents = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(cents);
}

/// The inverse of [parseMinor], for pre-filling a price field: 1250 -> "12.50".
String minorToInput(int minor) =>
    '${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')}';
