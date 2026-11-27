import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/reminders/domain/reminder_template.dart';
import 'package:url_launcher/url_launcher.dart';

/// Persists and streams customizable WhatsApp templates from Drift SQLite.
class ReminderTemplatesRepository {
  ReminderTemplatesRepository(this._db);

  final AppDatabase _db;

  Stream<List<ReminderTemplateEntity>> watchTemplates() {
    final query = _db.select(_db.reminderTemplates)
      ..orderBy([
        (t) => OrderingTerm.desc(t.id),
      ]);

    return query.watch().map(
          (List<ReminderTemplate> rows) => rows
              .map(
                (ReminderTemplate row) => ReminderTemplateEntity(
                  id: row.id,
                  name: row.name,
                  body: row.body,
                  updatedAt: row.updatedAt.toLocal(),
                ),
              )
              .toList(growable: false),
        );
  }

  Future<void> saveTemplate({
    required String templateId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('La plantilla no puede quedar vacía.');
    }

    await (_db.update(_db.reminderTemplates)
          ..where((t) => t.id.equals(templateId)))
        .write(
      ReminderTemplatesCompanion(
        body: Value(trimmed),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> restoreDefault(String templateId) {
    return saveTemplate(
      templateId: templateId,
      body: ReminderTemplateEngine.defaultBodyFor(templateId),
    );
  }
}

/// Builds and launches zero-API WhatsApp `wa.me` deep links.
class WhatsAppLauncherService {
  const WhatsAppLauncherService();

  /// Generates a valid `https://wa.me/<digits>?text=<encoded>` URI.
  static Uri buildWhatsAppUri({
    required String phoneE164Digits,
    required String message,
  }) {
    final cleanDigits = phoneE164Digits.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanDigits.length < 7 || cleanDigits.length > 15) {
      throw ArgumentError.value(
        phoneE164Digits,
        'phoneE164Digits',
        'El número E.164 no es válido para WhatsApp.',
      );
    }

    final encodedText = Uri.encodeComponent(message.trim());
    return Uri.parse('https://wa.me/$cleanDigits?text=$encodedText');
  }

  Future<bool> launchMessage({
    required String phoneE164Digits,
    required String message,
  }) async {
    final uri = buildWhatsAppUri(
      phoneE164Digits: phoneE164Digits,
      message: message,
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<bool> sendAppointmentReminder({
    required AppointmentEntity appointment,
    required String templateBody,
  }) {
    final rendered = ReminderTemplateEngine.renderForAppointment(
      templateBody: templateBody,
      appointment: appointment,
    );
    return launchMessage(
      phoneE164Digits: appointment.clientPhoneE164,
      message: rendered,
    );
  }
}

final reminderTemplatesRepositoryProvider =
    Provider<ReminderTemplatesRepository>((Ref ref) {
  return ReminderTemplatesRepository(ref.watch(appDatabaseProvider));
});

final reminderTemplatesProvider =
    StreamProvider<List<ReminderTemplateEntity>>((Ref ref) {
  return ref.watch(reminderTemplatesRepositoryProvider).watchTemplates();
});

final tomorrowTemplateBodyProvider = Provider<String>((Ref ref) {
  final templates = ref.watch(reminderTemplatesProvider).valueOrNull;
  if (templates == null) {
    return AppConstants.defaultTomorrowReminderBody;
  }
  return templates
          .where((t) => t.id == AppConstants.tomorrowTemplateId)
          .firstOrNull
          ?.body ??
      AppConstants.defaultTomorrowReminderBody;
});

final confirmationTemplateBodyProvider = Provider<String>((Ref ref) {
  final templates = ref.watch(reminderTemplatesProvider).valueOrNull;
  if (templates == null) {
    return AppConstants.defaultConfirmationBody;
  }
  return templates
          .where((t) => t.id == AppConstants.confirmationTemplateId)
          .firstOrNull
          ?.body ??
      AppConstants.defaultConfirmationBody;
});

final whatsappLauncherServiceProvider = Provider<WhatsAppLauncherService>((
  Ref ref,
) {
  return const WhatsAppLauncherService();
});
