import 'package:intl/intl.dart';

/// Beldex uses 9 decimal places: 1 BDX = 1e9 atomic units.
const int atomicUnitsPerBdx = 1000000000;

final _grouped = NumberFormat('#,##0.#########', 'en_US');
final _fixed4 = NumberFormat('#,##0.0000', 'en_US');
final _int = NumberFormat('#,##0', 'en_US');

/// 1234567 -> "1,234,567".
String groupDigits(int value) => _int.format(value);

/// Formats atomic units as a human readable BDX amount.
String formatBdx(int atomic, {bool round = false}) {
  final value = atomic / atomicUnitsPerBdx;
  return round ? _fixed4.format(value) : _grouped.format(value);
}

/// Parses a user-entered decimal BDX string into atomic units without
/// going through floating point, so 0.1 + 0.2 style errors can't happen.
int? parseBdx(String input) {
  final text = input.trim().replaceAll(',', '');
  if (!RegExp(r'^\d*(\.\d{0,9})?$').hasMatch(text) || text.isEmpty || text == '.') {
    return null;
  }
  final parts = text.split('.');
  final whole = int.parse(parts[0].isEmpty ? '0' : parts[0]);
  final fraction = parts.length > 1 ? parts[1].padRight(9, '0') : '000000000';
  return whole * atomicUnitsPerBdx + int.parse(fraction);
}

final _dateTime = DateFormat('d MMM yyyy, HH:mm');
final _date = DateFormat('MMMM d, yyyy');

String formatTimestamp(int unixSeconds) => _dateTime.format(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));

String formatDate(int unixSeconds) => _date.format(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));

/// Shortens long identifiers for display: `abcdef…123456`.
String shorten(String value, {int head = 12, int tail = 12}) {
  if (value.length <= head + tail + 1) return value;
  return '${value.substring(0, head)}…${value.substring(value.length - tail)}';
}

/// Operator fee of a master node as a percentage.
double operatorFeePercent(num portionsForOperator) => portionsForOperator / 18446744073709551612.0 * 100;

/// Accepts seconds, milliseconds or microseconds and returns milliseconds.
int toMillis(Object? value) {
  if (value == null) return DateTime.now().millisecondsSinceEpoch;
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed.millisecondsSinceEpoch;
    value = num.tryParse(value) ?? 0;
  }
  final n = (value as num).toInt();
  final digits = n.abs().toString().length;
  if (digits >= 16) return n ~/ 1000;
  if (digits <= 10) return n * 1000;
  return n;
}
