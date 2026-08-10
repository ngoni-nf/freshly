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
