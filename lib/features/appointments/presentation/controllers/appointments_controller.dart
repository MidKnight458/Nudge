import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/features/appointments/data/appointments_repository_impl.dart';
import 'package:nudge/features/appointments/data/google_calendar_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';

final localAppointmentsDatasourceProvider =
    Provider<LocalAppointmentsDatasource>((Ref ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalAppointmentsDatasource(db);
});

final googleCalendarDatasourceProvider =
    Provider<GoogleCalendarDatasource>((Ref ref) {
  final authRepository = ref.watch(authRepositoryProvider);
  return GoogleCalendarDatasourceImpl(authRepository);
});

final appointmentsRepositoryProvider =
    Provider<AppointmentsRepository>((Ref ref) {
  return AppointmentsRepositoryImpl(
    localDatasource: ref.watch(localAppointmentsDatasourceProvider),
    remoteDatasource: ref.watch(googleCalendarDatasourceProvider),
    connectivityService: ref.watch(connectivityServiceProvider),
    authRepository: ref.watch(authRepositoryProvider),
  );
});

/// Currently selected calendar day in `AgendaScreen`.
final selectedDateProvider = StateProvider<DateTime>((Ref ref) {
  return DateFormatters.startOfDay(DateTime.now());
});

/// Reactive list of appointments for [selectedDateProvider].
final selectedDayAppointmentsProvider =
    StreamProvider<List<AppointmentEntity>>((Ref ref) {
  final selectedDate = ref.watch(selectedDateProvider);
  final repository = ref.watch(appointmentsRepositoryProvider);
  return repository.watchAppointmentsForDay(selectedDate);
});

/// Reactive list of all appointments scheduled for tomorrow.
final tomorrowAppointmentsProvider =
    StreamProvider<List<AppointmentEntity>>((Ref ref) {
  final repository = ref.watch(appointmentsRepositoryProvider);
  final range = DateFormatters.tomorrowRange();
  return repository.watchAppointmentsForRange(range.start, range.end);
});

/// Reactive set of dates within a 35-day window around [selectedDateProvider]
/// that have at least one scheduled appointment.
final agendaMarkedDatesProvider = StreamProvider<Set<DateTime>>((Ref ref) {
  final selectedDate = ref.watch(selectedDateProvider);
  final repository = ref.watch(appointmentsRepositoryProvider);
  final start = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day - 14,
  );
  final end = DateTime(
    selectedDate.year,
    selectedDate.month,
    selectedDate.day + 21,
  );
  return repository.watchAppointmentDatesInRange(start, end);
});

/// Reactive count of pending local mutations awaiting Calendar sync.
final pendingSyncCountProvider = StreamProvider<int>((Ref ref) {
  final repository = ref.watch(appointmentsRepositoryProvider);
  return repository.watchPendingSyncCount();
});

/// Controller exposing offline-first CRUD actions for appointments.
class AppointmentsController extends Notifier<void> {
  @override
  void build() {}

  AppointmentsRepository get _repository =>
      ref.read(appointmentsRepositoryProvider);

  Future<AppointmentEntity> createAppointment(AppointmentInput input) {
    return _repository.createAppointment(input);
  }

  Future<AppointmentEntity> updateAppointment(
    AppointmentEntity existing,
    AppointmentInput input,
  ) {
    return _repository.updateAppointment(existing, input);
  }

  Future<void> deleteAppointment(AppointmentEntity appointment) {
    return _repository.deleteAppointment(appointment);
  }

  Future<void> markReminderSent(int appointmentId, {bool sent = true}) {
    return _repository.markReminderSent(appointmentId, sent: sent);
  }
}

final appointmentsControllerProvider =
    NotifierProvider<AppointmentsController, void>(AppointmentsController.new);
