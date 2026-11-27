import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Input payload used when creating or updating an appointment.
class AppointmentInput {
  const AppointmentInput({
    required this.clientName,
    required this.clientRawPhone,
    required this.clientPhoneE164,
    this.clientGoogleContactId,
    required this.title,
    this.notes,
    required this.startTime,
    required this.endTime,
  });

  final String clientName;
  final String clientRawPhone;
  final String clientPhoneE164;
  final String? clientGoogleContactId;
  final String title;
  final String? notes;
  final DateTime startTime;
  final DateTime endTime;
}

/// Summary returned after running a synchronization pass with Google Calendar.
class SyncResult {
  const SyncResult({
    this.pushedCreated = 0,
    this.pushedUpdated = 0,
    this.pushedDeleted = 0,
    this.pulledUpserted = 0,
    this.pulledDeleted = 0,
    this.usedFullResync = false,
    this.syncedAt,
    this.skippedReason,
    this.errorMessage,
  });

  final int pushedCreated;
  final int pushedUpdated;
  final int pushedDeleted;
  final int pulledUpserted;
  final int pulledDeleted;
  final bool usedFullResync;
  final DateTime? syncedAt;
  final String? skippedReason;
  final String? errorMessage;

  bool get hasError => errorMessage != null;
  bool get wasSkipped => skippedReason != null;
}

/// Offline-first repository managing appointments and Google Calendar sync.
abstract interface class AppointmentsRepository {
  Stream<List<AppointmentEntity>> watchAppointmentsForDay(DateTime day);

  Stream<List<AppointmentEntity>> watchAppointmentsForRange(
    DateTime startInclusive,
    DateTime endExclusive,
  );

  Stream<Set<DateTime>> watchAppointmentDatesInRange(
    DateTime startInclusive,
    DateTime endExclusive,
  );

  Stream<int> watchPendingSyncCount();

  Future<DateTime?> getLastSyncTimestamp();

  Future<AppointmentEntity> createAppointment(AppointmentInput input);

  Future<AppointmentEntity> updateAppointment(
    AppointmentEntity existing,
    AppointmentInput input,
  );

  Future<void> deleteAppointment(AppointmentEntity appointment);

  Future<void> markReminderSent(int appointmentId, {bool sent = true});

  Future<SyncResult> synchronize();

  Future<int> applyCloudSnapshot(List<CloudAppointmentDocument> documents);
}
