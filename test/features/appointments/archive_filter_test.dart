import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nudge/features/appointments/domain/archive_filter.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

AppointmentEntity _appt({
  required int id,
  required String client,
  required String title,
  String? notes,
  required DateTime start,
  DateTime? end,
  AppointmentSyncStatus status = AppointmentSyncStatus.synced,
}) {
  return AppointmentEntity(
    id: id,
    syncId: 'sync-$id',
    clientId: id,
    clientName: client,
    clientRawPhone: '5512345678',
    clientPhoneE164: '5215512345678',
    title: title,
    notes: notes,
    startTime: start,
    endTime: end ?? start.add(const Duration(hours: 1)),
    reminderSent: true,
    syncStatus: status,
    lastModified: start,
  );
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  group('ArchiveFilter', () {
    // Saturday 2026-11-28 15:00
    final now = DateTime(2026, 11, 28, 15, 0);

    final sampleAppointments = <AppointmentEntity>[
      _appt(
        id: 1,
        client: 'Ana López',
        title: 'Terapia',
        notes: 'Primera sesión del año anterior',
        start: DateTime(2025, 11, 10, 10, 0),
      ),
      _appt(
        id: 2,
        client: 'Carlos Ruiz',
        title: 'Control mensual',
        start: DateTime(2026, 10, 15, 12, 0),
      ),
      _appt(
        id: 3,
        client: 'Beatriz Gómez',
        title: 'Limpieza',
        notes: 'Requiere seguimiento',
        start: DateTime(2026, 11, 23, 9, 0), // Monday of current week
      ),
      _appt(
        id: 4,
        client: 'David Torres',
        title: 'Consulta',
        start: DateTime(2026, 11, 28, 13, 0), // Ended 14:00 (< 15:00)
      ),
      _appt(
        id: 5,
        client: 'Elena Soto',
        title: 'Sesión activa',
        start: DateTime(2026, 11, 28, 14, 30),
        end: DateTime(2026, 11, 28, 15, 30), // Not finished yet
      ),
      _appt(
        id: 6,
        client: 'Fabián Ortiz',
        title: 'Cita futura',
        start: DateTime(2026, 11, 29, 10, 0),
      ),
      _appt(
        id: 7,
        client: 'Gabriela Núñez',
        title: 'Borrada',
        start: DateTime(2026, 11, 20, 10, 0),
        status: AppointmentSyncStatus.pendingDelete,
      ),
    ];

    test('allCurrentYear returns only concluded non-deleted appointments from current year sorted newest first', () {
      final result = ArchiveFilter.filterPast(
        allAppointments: sampleAppointments,
        mode: ArchivePeriodMode.allCurrentYear,
        anchorDate: now,
        now: now,
      );

      expect(result.map((e) => e.id).toList(), <int>[4, 3, 2]);
    });

    test('week mode filters Monday-Sunday cleanly and prevents stepping into future week', () {
      final currentWeek = ArchiveFilter.filterPast(
        allAppointments: sampleAppointments,
        mode: ArchivePeriodMode.week,
        anchorDate: now,
        now: now,
      );
      expect(currentWeek.map((e) => e.id).toList(), <int>[4, 3]);
      expect(
        ArchiveFilter.canStepForward(
          mode: ArchivePeriodMode.week,
          anchorDate: now,
          now: now,
        ),
        isFalse,
      );

      final prevWeekAnchor = ArchiveFilter.stepPeriod(
        mode: ArchivePeriodMode.week,
        anchorDate: now,
        delta: -1,
      );
      expect(
        ArchiveFilter.canStepForward(
          mode: ArchivePeriodMode.week,
          anchorDate: prevWeekAnchor,
          now: now,
        ),
        isTrue,
      );
    });

    test('month and year modes filter and step across boundaries cleanly', () {
      final octAnchor = ArchiveFilter.stepPeriod(
        mode: ArchivePeriodMode.month,
        anchorDate: now,
        delta: -1,
      );
      final octResult = ArchiveFilter.filterPast(
        allAppointments: sampleAppointments,
        mode: ArchivePeriodMode.month,
        anchorDate: octAnchor,
        now: now,
      );
      expect(octResult.map((e) => e.id).toList(), <int>[2]);

      final prevYearAnchor = ArchiveFilter.stepPeriod(
        mode: ArchivePeriodMode.year,
        anchorDate: now,
        delta: -1,
      );
      final year2025 = ArchiveFilter.filterPast(
        allAppointments: sampleAppointments,
        mode: ArchivePeriodMode.year,
        anchorDate: prevYearAnchor,
        now: now,
      );
      expect(year2025.map((e) => e.id).toList(), <int>[1]);

      final groupedByMonth = ArchiveFilter.groupAppointments(
        ArchiveFilter.filterPast(
          allAppointments: sampleAppointments,
          mode: ArchivePeriodMode.year,
          anchorDate: now,
          now: now,
        ),
        ArchivePeriodMode.year,
      );
      expect(groupedByMonth, hasLength(2));
      expect(groupedByMonth[0].date, DateTime(2026, 11));
      expect(groupedByMonth[1].date, DateTime(2026, 10));
    });

    test('searchQuery matches client name, service title, and notes case-insensitively', () {
      final byNotes = ArchiveFilter.filterPast(
        allAppointments: sampleAppointments,
        mode: ArchivePeriodMode.allCurrentYear,
        anchorDate: now,
        now: now,
        searchQuery: 'SEGUIMIENTO',
      );
      expect(byNotes.map((e) => e.id).toList(), <int>[3]);

      final byTitle = ArchiveFilter.filterPast(
        allAppointments: sampleAppointments,
        mode: ArchivePeriodMode.allCurrentYear,
        anchorDate: now,
        now: now,
        searchQuery: 'mensual',
      );
      expect(byTitle.map((e) => e.id).toList(), <int>[2]);
    });
  });
}
