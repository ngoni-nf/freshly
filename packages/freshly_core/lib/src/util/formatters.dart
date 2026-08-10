import 'package:intl/intl.dart';

String formatDistance(double km) =>
    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

String formatEta(int? minutes) {
  if (minutes == null) return '--';
  if (minutes < 1) return 'Arriving';
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String formatDuration(int minutes) {
  if (minutes < 60) return '$minutes min';
  final h = minutes ~/ 60;
  final m = minutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String formatSlot(DateTime when) {
  final now = DateTime.now();
  final isToday = when.year == now.year && when.month == now.month && when.day == now.day;
  final tomorrow = now.add(const Duration(days: 1));
  final isTomorrow =
      when.year == tomorrow.year && when.month == tomorrow.month && when.day == tomorrow.day;
  final time = DateFormat('HH:mm').format(when);
  if (isToday) return 'Today, $time';
  if (isTomorrow) return 'Tomorrow, $time';
  return DateFormat('EEE d MMM, HH:mm').format(when);
}

String formatCountdown(Duration d) {
  if (d.isNegative) return '0:00';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Masks a phone number for display in chat headers, where the real number is
/// deliberately never exposed to the counterparty.
String maskPhone(String e164) {
  if (e164.length < 6) return e164;
  return '${e164.substring(0, 4)}•••${e164.substring(e164.length - 2)}';
}
