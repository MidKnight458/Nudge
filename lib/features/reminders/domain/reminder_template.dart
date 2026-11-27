import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Supported template placeholders for WhatsApp reminder messages.
abstract final class ReminderTemplateVariables {
  static const String cliente = '{cliente}';
  static const String fecha = '{fecha}';
  static const String hora = '{hora}';
  static const String servicio = '{servicio}';

  static const List<String> all = <String>[cliente, fecha, hora, servicio];
}

/// Domain model for an editable WhatsApp reminder template.
class ReminderTemplateEntity {
  const ReminderTemplateEntity({
    required this.id,
    required this.name,
    required this.body,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String body;
  final DateTime updatedAt;

  bool get isTomorrowTemplate => id == AppConstants.tomorrowTemplateId;
}

/// Renders dynamic WhatsApp reminder templates using appointment details.
abstract final class ReminderTemplateEngine {
  static String defaultBodyFor(String templateId) {
    if (templateId == AppConstants.confirmationTemplateId) {
      return AppConstants.defaultConfirmationBody;
    }
    return AppConstants.defaultTomorrowReminderBody;
  }

  static String render({
    required String templateBody,
    required String clientName,
    required DateTime appointmentStart,
    required String serviceTitle,
  }) {
    final formattedDate = DateFormatters.formatShortDate(appointmentStart);
    final formattedTime = DateFormatters.formatTime(appointmentStart);

    return templateBody
        .replaceAll(ReminderTemplateVariables.cliente, clientName.trim())
        .replaceAll(ReminderTemplateVariables.fecha, formattedDate)
        .replaceAll(ReminderTemplateVariables.hora, formattedTime)
        .replaceAll(ReminderTemplateVariables.servicio, serviceTitle.trim());
  }

  static String renderForAppointment({
    required String templateBody,
    required AppointmentEntity appointment,
  }) {
    return render(
      templateBody: templateBody,
      clientName: appointment.clientName,
      appointmentStart: appointment.startTime,
      serviceTitle: appointment.title,
    );
  }
}
