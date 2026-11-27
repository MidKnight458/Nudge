/// Application-wide constants for Nudge.
abstract final class AppConstants {
  static const String appName = 'Nudge';
  static const String packageId = 'com.patoh.nudge';

  /// Material You fallback seed color (Google Pixel Blue).
  static const int fallbackSeedColorValue = 0xFF1A73E8;

  /// Android contact account type used to prioritize Google Contacts.
  static const String googleAccountType = 'com.google';

  /// Google Calendar API v3 read/write events scope.
  static const String calendarScope =
      'https://www.googleapis.com/auth/calendar.events';

  /// Primary Google Calendar identifier.
  static const String primaryCalendarId = 'primary';

  /// Sync status values persisted in Drift's `Appointments.syncStatus` column.
  static const String syncStatusSynced = 'synced';
  static const String syncStatusPendingCreate = 'pending_create';
  static const String syncStatusPendingUpdate = 'pending_update';
  static const String syncStatusPendingDelete = 'pending_delete';

  /// Structured metadata header injected into Google Calendar event descriptions.
  static const String metadataHeader = '[Nudge]';
  static const String metadataClientKey = 'cliente:';
  static const String metadataPhoneKey = 'telefono:';

  /// Default WhatsApp template identifiers and bodies.
  static const String tomorrowTemplateId = 'tomorrow_reminder';
  static const String tomorrowTemplateName = 'Recordatorio de mañana';
  static const String defaultTomorrowReminderBody =
      'Hola {cliente}, te recordamos tu cita de {servicio} mañana a las {hora}. '
      'Por favor confírmanos si podrás asistir.';

  static const String confirmationTemplateId = 'confirmation';
  static const String confirmationTemplateName = 'Confirmación de cita';
  static const String defaultConfirmationBody =
      'Hola {cliente}, tu cita de {servicio} quedó agendada para el {fecha} '
      'a las {hora}. ¡Te esperamos!';

  /// Default initial sync lookback window when no `syncToken` is stored.
  static const Duration initialSyncLookback = Duration(days: 30);

  /// Default appointment duration when creating a new entry.
  static const Duration defaultAppointmentDuration = Duration(hours: 1);
}
