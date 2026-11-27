import 'package:intl/intl.dart';

/// Locale-aware date and time formatting helpers for Nudge.
abstract final class DateFormatters {
  static const String _locale = 'es';

  static final DateFormat _timeFormat = DateFormat('HH:mm', _locale);
  static final DateFormat _shortDateFormat = DateFormat('d MMM yyyy', _locale);
  static final DateFormat _fullDateFormat =
      DateFormat('EEEE d \'de\' MMMM', _locale);
  static final DateFormat _dayNumberFormat = DateFormat('d', _locale);
  static final DateFormat _weekdayShortFormat = DateFormat('EEE', _locale);
  static final DateFormat _monthYearFormat = DateFormat('MMMM yyyy', _locale);
  static final DateFormat _compactDateTimeFormat =
      DateFormat('d MMM, HH:mm', _locale);

  /// Formats a [DateTime] as 24-hour time (`HH:mm`).
  static String formatTime(DateTime dateTime) =>
      _timeFormat.format(dateTime.toLocal());

  /// Formats a [DateTime] as a concise date (`27 nov 2026`).
  static String formatShortDate(DateTime dateTime) =>
      _shortDateFormat.format(dateTime.toLocal());

  /// Formats a [DateTime] with capitalized weekday and full month name.
  static String formatFullDate(DateTime dateTime) =>
      _capitalize(_fullDateFormat.format(dateTime.toLocal()));

  /// Formats the day-of-month number (`27`).
  static String formatDayNumber(DateTime dateTime) =>
      _dayNumberFormat.format(dateTime.toLocal());

  /// Formats an abbreviated uppercase-initial weekday (`Lun`, `Mar`).
  static String formatWeekdayShort(DateTime dateTime) {
    final formatted =
        _weekdayShortFormat.format(dateTime.toLocal()).replaceAll('.', '');
    return _capitalize(formatted);
  }

  /// Formats month and year (`Noviembre 2026`).
  static String formatMonthYear(DateTime dateTime) =>
      _capitalize(_monthYearFormat.format(dateTime.toLocal()));

  /// Formats compact date and time (`27 nov, 14:30`).
  static String formatCompactDateTime(DateTime dateTime) =>
      _compactDateTimeFormat.format(dateTime.toLocal());

  /// Formats a time range (`10:00 - 11:00`).
  static String formatTimeRange(DateTime start, DateTime end) =>
      '${formatTime(start)} - ${formatTime(end)}';

  /// Returns whether two [DateTime] instances fall on the same local calendar day.
  static bool isSameDay(DateTime a, DateTime b) {
    final localA = a.toLocal();
    final localB = b.toLocal();
    return localA.year == localB.year &&
        localA.month == localB.month &&
        localA.day == localB.day;
  }

  /// Returns `00:00:00.000` in local time for [date].
  static DateTime startOfDay(DateTime date) {
    final local = date.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Returns the exclusive end boundary (start of next local day) for [date].
  static DateTime endOfDay(DateTime date) {
    final start = startOfDay(date);
    return DateTime(start.year, start.month, start.day + 1);
  }

  /// Returns `[tomorrowStart, dayAfterTomorrowStart)` in local time.
  static ({DateTime start, DateTime end}) tomorrowRange([DateTime? now]) {
    final base = startOfDay(now ?? DateTime.now());
    final tomorrowStart = DateTime(base.year, base.month, base.day + 1);
    final tomorrowEnd = DateTime(base.year, base.month, base.day + 2);
    return (start: tomorrowStart, end: tomorrowEnd);
  }

  static String _capitalize(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1);
  }
}
