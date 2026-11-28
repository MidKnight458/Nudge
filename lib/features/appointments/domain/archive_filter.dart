import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Period filtering modes supported by [ArchiveScreen].
enum ArchivePeriodMode { allCurrentYear, week, month, year }

/// Logical date/month section grouping archived appointments.
class ArchiveSection {
  const ArchiveSection({
    required this.title,
    required this.date,
    required this.appointments,
  });

  final String title;
  final DateTime date;
  final List<AppointmentEntity> appointments;
}

/// Pure filtering, stepping, and grouping rules for past appointments.
abstract final class ArchiveFilter {
  /// Returns local Monday `00:00:00` for the week containing [date].
  static DateTime startOfWeek(DateTime date) {
    final day = DateFormatters.startOfDay(date);
    return DateTime(day.year, day.month, day.day - (day.weekday - 1));
  }

  /// Returns local Sunday `00:00:00` for the week containing [date].
  static DateTime endOfWeekInclusive(DateTime date) {
    final monday = startOfWeek(date);
    return DateTime(monday.year, monday.month, monday.day + 6);
  }

  /// Filters past appointments (`endTime < now`) according to [mode], [anchorDate],
  /// and optional case-insensitive [searchQuery], ordered newest first.
  static List<AppointmentEntity> filterPast({
    required List<AppointmentEntity> allAppointments,
    required ArchivePeriodMode mode,
    required DateTime anchorDate,
    required DateTime now,
    String searchQuery = '',
  }) {
    final localNow = now.toLocal();
    final normalizedAnchor = DateFormatters.startOfDay(anchorDate);
    final query = searchQuery.trim().toLowerCase();

    DateTime? weekStart;
    DateTime? weekEndExclusive;
    if (mode == ArchivePeriodMode.week) {
      weekStart = startOfWeek(normalizedAnchor);
      weekEndExclusive = DateTime(
        weekStart.year,
        weekStart.month,
        weekStart.day + 7,
      );
    }

    final filtered = allAppointments
        .where((AppointmentEntity appt) {
          if (appt.syncStatus == AppointmentSyncStatus.pendingDelete) {
            return false;
          }
          final startLocal = appt.startTime.toLocal();
          final endLocal = appt.endTime.toLocal();
          if (!endLocal.isBefore(localNow)) {
            return false;
          }

          final matchesPeriod = switch (mode) {
            ArchivePeriodMode.allCurrentYear =>
              startLocal.year == localNow.year,
            ArchivePeriodMode.week =>
              !startLocal.isBefore(weekStart!) &&
                  startLocal.isBefore(weekEndExclusive!),
            ArchivePeriodMode.month =>
              startLocal.year == normalizedAnchor.year &&
                  startLocal.month == normalizedAnchor.month,
            ArchivePeriodMode.year => startLocal.year == normalizedAnchor.year,
          };
          if (!matchesPeriod) {
            return false;
          }

          if (query.isEmpty) {
            return true;
          }
          final inClient = appt.clientName.toLowerCase().contains(query);
          final inTitle = appt.title.toLowerCase().contains(query);
          final inNotes =
              appt.notes != null && appt.notes!.toLowerCase().contains(query);
          return inClient || inTitle || inNotes;
        })
        .toList(growable: false);

    final sorted = List<AppointmentEntity>.of(filtered);
    sorted.sort((AppointmentEntity a, AppointmentEntity b) {
      final timeCmp = b.startTime.compareTo(a.startTime);
      if (timeCmp != 0) {
        return timeCmp;
      }
      return b.id.compareTo(a.id);
    });
    return sorted;
  }

  /// Groups filtered past appointments by month (for [ArchivePeriodMode.year])
  /// or by local calendar day (for all other modes).
  static List<ArchiveSection> groupAppointments(
    List<AppointmentEntity> filtered,
    ArchivePeriodMode mode,
  ) {
    if (filtered.isEmpty) {
      return const <ArchiveSection>[];
    }

    final sections = <ArchiveSection>[];
    DateTime? currentKey;
    var bucket = <AppointmentEntity>[];

    for (final appt in filtered) {
      final startLocal = appt.startTime.toLocal();
      final keyDate = mode == ArchivePeriodMode.year
          ? DateTime(startLocal.year, startLocal.month)
          : DateFormatters.startOfDay(startLocal);

      if (currentKey == null || keyDate != currentKey) {
        if (currentKey != null && bucket.isNotEmpty) {
          sections.add(
            ArchiveSection(
              title: mode == ArchivePeriodMode.year
                  ? DateFormatters.formatMonthYear(currentKey)
                  : DateFormatters.formatFullDate(currentKey),
              date: currentKey,
              appointments: List<AppointmentEntity>.unmodifiable(bucket),
            ),
          );
        }
        currentKey = keyDate;
        bucket = <AppointmentEntity>[appt];
      } else {
        bucket.add(appt);
      }
    }

    if (currentKey != null && bucket.isNotEmpty) {
      sections.add(
        ArchiveSection(
          title: mode == ArchivePeriodMode.year
              ? DateFormatters.formatMonthYear(currentKey)
              : DateFormatters.formatFullDate(currentKey),
          date: currentKey,
          appointments: List<AppointmentEntity>.unmodifiable(bucket),
        ),
      );
    }

    return sections;
  }

  /// Returns whether stepping forward by one period keeps the period up to [now].
  static bool canStepForward({
    required ArchivePeriodMode mode,
    required DateTime anchorDate,
    required DateTime now,
  }) {
    final localNow = now.toLocal();
    return switch (mode) {
      ArchivePeriodMode.allCurrentYear => false,
      ArchivePeriodMode.week => startOfWeek(
        anchorDate,
      ).isBefore(startOfWeek(localNow)),
      ArchivePeriodMode.month =>
        anchorDate.year < localNow.year ||
            (anchorDate.year == localNow.year &&
                anchorDate.month < localNow.month),
      ArchivePeriodMode.year => anchorDate.year < localNow.year,
    };
  }

  /// Advances or rewinds [anchorDate] by [delta] units of [mode].
  static DateTime stepPeriod({
    required ArchivePeriodMode mode,
    required DateTime anchorDate,
    required int delta,
  }) {
    return switch (mode) {
      ArchivePeriodMode.allCurrentYear => DateFormatters.startOfDay(anchorDate),
      ArchivePeriodMode.week => DateTime(
        anchorDate.year,
        anchorDate.month,
        anchorDate.day + (7 * delta),
      ),
      ArchivePeriodMode.month => DateTime(
        anchorDate.year,
        anchorDate.month + delta,
        1,
      ),
      ArchivePeriodMode.year => DateTime(anchorDate.year + delta, 1, 1),
    };
  }
}
