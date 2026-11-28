import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';
import 'package:nudge/features/settings/domain/app_preferences.dart';

class _InMemorySettingsFirestore implements FirestoreSyncDatasource {
  CloudSettingsDocument? storedSettings;

  @override
  Future<CloudSettingsDocument?> fetchSettings(String userId) async =>
      storedSettings;

  @override
  Future<void> upsertSettings(
    String userId,
    CloudSettingsDocument document,
  ) async {
    storedSettings = document;
  }

  @override
  Stream<CloudSettingsDocument?> watchSettings(String userId) =>
      const Stream<CloudSettingsDocument?>.empty();

  @override
  Future<List<CloudAppointmentDocument>> fetchAppointments(
    String userId,
  ) async => const <CloudAppointmentDocument>[];

  @override
  Stream<List<CloudAppointmentDocument>> watchAppointments(String userId) =>
      const Stream<List<CloudAppointmentDocument>>.empty();

  @override
  Future<void> upsertAppointment(
    String userId,
    CloudAppointmentDocument document,
  ) async {}

  @override
  Future<void> markAppointmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
    String? googleCalendarEventId,
  }) async {}

  @override
  Future<List<CloudTemplateDocument>> fetchTemplates(String userId) async =>
      const <CloudTemplateDocument>[];

  @override
  Stream<List<CloudTemplateDocument>> watchTemplates(String userId) =>
      const Stream<List<CloudTemplateDocument>>.empty();

  @override
  Future<void> upsertTemplate(
    String userId,
    CloudTemplateDocument document,
  ) async {}

  @override
  Future<List<CloudClientDocument>> fetchClients(String userId) async =>
      const <CloudClientDocument>[];

  @override
  Stream<List<CloudClientDocument>> watchClients(String userId) =>
      const Stream<List<CloudClientDocument>>.empty();

  @override
  Future<void> upsertClient(
    String userId,
    CloudClientDocument document,
  ) async {}

  @override
  Future<void> markClientDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
  }) async {}

  @override
  Future<List<CloudAttachmentDocument>> fetchClientAttachments(
    String userId,
  ) async => const <CloudAttachmentDocument>[];

  @override
  Stream<List<CloudAttachmentDocument>> watchClientAttachments(String userId) =>
      const Stream<List<CloudAttachmentDocument>>.empty();

  @override
  Future<void> upsertClientAttachment(
    String userId,
    CloudAttachmentDocument document,
  ) async {}

  @override
  Future<void> markClientAttachmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
  }) async {}
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('ScheduleConfig', () {
    test('generateSlots creates sorted 30-minute intervals like 16:30, 17:00, 17:30', () {
      final slots = ScheduleConfig.generateSlots(
        startMinutes: 16 * 60 + 30,
        endMinutes: 17 * 60 + 30,
        intervalMinutes: 30,
      );

      expect(slots, <int>[990, 1020, 1050]);
      expect(slots.map(ScheduleConfig.formatMinutesOfDay).toList(), <String>[
        '16:30',
        '17:00',
        '17:30',
      ]);
    });

    test(
      'availableSlotsForDay hides occupied slot 16:30 leaving 17:00 and 17:30',
      () {
        const config = ScheduleConfig(
          defaultSlotDurationMinutes: 30,
          slotMinutesFromMidnight: <int>[990, 1020, 1050],
        );
        final day = DateTime(2026, 12, 1);
        final taken = AppointmentEntity(
          id: 7,
          syncId: 'appt-1',
          clientId: 1,
          clientName: 'Paciente',
          clientRawPhone: '5512345678',
          clientPhoneE164: '5215512345678',
          title: 'Terapia',
          startTime: DateTime(2026, 12, 1, 16, 30),
          endTime: DateTime(2026, 12, 1, 17, 0),
          reminderSent: false,
          syncStatus: AppointmentSyncStatus.synced,
          lastModified: DateTime(2026, 12, 1, 9, 0),
        );

        final remaining = config.availableSlotsForDay(
          day: day,
          dayAppointments: <AppointmentEntity>[taken],
        );
        expect(remaining, <int>[1020, 1050]);

        // When editing appointment id 7, its own 16:30 slot remains selectable.
        final whileEditing = config.availableSlotsForDay(
          day: day,
          dayAppointments: <AppointmentEntity>[taken],
          excludeAppointmentId: 7,
        );
        expect(whileEditing, <int>[990, 1020, 1050]);
      },
    );
  });

  group('SettingsRepository sync', () {
    test('persists custom labels, services, and schedule and syncs across devices without overwriting cloud with epoch seed', () async {
      final dbA = AppDatabase(NativeDatabase.memory());
      final dbB = AppDatabase(NativeDatabase.memory());
      final cloud = _InMemorySettingsFirestore();

      try {
        final repoA = SettingsRepository(
          dbA,
          firestoreDatasource: cloud,
          currentUserId: () => 'uid_1',
          isOnline: () async => true,
        );
        final repoB = SettingsRepository(
          dbB,
          firestoreDatasource: cloud,
          currentUserId: () => 'uid_1',
          isOnline: () async => true,
        );

        await repoA.saveClientLabels(plural: 'Pacientes', singular: 'Paciente');
        await repoA.saveServices(const <CustomServiceItem>[
          CustomServiceItem(
            id: 'svc_1',
            name: 'Terapia física',
            durationMinutes: 45,
          ),
        ]);
        await repoA.saveSchedule(
          const ScheduleConfig(
            defaultSlotDurationMinutes: 30,
            slotMinutesFromMidnight: <int>[990, 1020, 1050],
          ),
        );

        // Fresh Device B runs initial sync: must pull Device A's settings.
        await repoB.syncWithCloud();

        final prefsB = await repoB.getPreferences();
        expect(prefsB.clientLabelPlural, 'Pacientes');
        expect(prefsB.clientLabelSingular, 'Paciente');
        expect(prefsB.services.single.name, 'Terapia física');
        expect(prefsB.services.single.durationMinutes, 45);
        expect(prefsB.schedule.slotMinutesFromMidnight, <int>[990, 1020, 1050]);
      } finally {
        await dbA.close();
        await dbB.close();
      }
    });
  });
}
