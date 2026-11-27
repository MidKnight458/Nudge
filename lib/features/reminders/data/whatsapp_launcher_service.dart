import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/reminders/domain/reminder_template.dart';
import 'package:url_launcher/url_launcher.dart';

/// Persists and streams customizable WhatsApp templates from Drift SQLite,
/// synchronizing changes across devices via Cloud Firestore.
class ReminderTemplatesRepository {
  ReminderTemplatesRepository(
    this._db, {
    FirestoreSyncDatasource? firestoreDatasource,
    String? Function()? currentUserId,
    Future<bool> Function()? isOnline,
  }) : _cloud = firestoreDatasource,
       _userIdProvider = currentUserId,
       _onlineCheck = isOnline;

  final AppDatabase _db;
  final FirestoreSyncDatasource? _cloud;
  final String? Function()? _userIdProvider;
  final Future<bool> Function()? _onlineCheck;

  Stream<List<ReminderTemplateEntity>> watchTemplates() {
    final query = _db.select(_db.reminderTemplates)
      ..orderBy([(t) => OrderingTerm.desc(t.id)]);

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

    final nowUtc = DateTime.now().toUtc();
    await (_db.update(
      _db.reminderTemplates,
    )..where((t) => t.id.equals(templateId))).write(
      ReminderTemplatesCompanion(
        body: Value(trimmed),
        updatedAt: Value(nowUtc),
      ),
    );

    final row = await (_db.select(
      _db.reminderTemplates,
    )..where((t) => t.id.equals(templateId))).getSingleOrNull();
    if (row == null) {
      return;
    }

    await _pushTemplateToCloud(row);
  }

  Future<void> restoreDefault(String templateId) {
    return saveTemplate(
      templateId: templateId,
      body: ReminderTemplateEngine.defaultBodyFor(templateId),
    );
  }

  /// Applies incoming Cloud Firestore templates when newer than local copies.
  Future<void> applyCloudTemplates(
    List<CloudTemplateDocument> cloudTemplates,
  ) async {
    if (cloudTemplates.isEmpty) {
      return;
    }

    await _db.transaction(() async {
      for (final remote in cloudTemplates) {
        final cleanBody = remote.body.trim();
        if (remote.id.isEmpty || cleanBody.isEmpty) {
          continue;
        }

        final local = await (_db.select(
          _db.reminderTemplates,
        )..where((t) => t.id.equals(remote.id))).getSingleOrNull();

        if (local == null) {
          await _db
              .into(_db.reminderTemplates)
              .insert(
                ReminderTemplatesCompanion.insert(
                  id: remote.id,
                  name: remote.name.isNotEmpty ? remote.name : remote.id,
                  body: cleanBody,
                  updatedAt: remote.updatedAt.toUtc(),
                ),
                mode: InsertMode.insertOrReplace,
              );
          continue;
        }

        final remoteUtc = remote.updatedAt.toUtc();
        final localUtc = local.updatedAt.toUtc();
        if (remoteUtc.isAfter(localUtc) && cleanBody != local.body) {
          await (_db.update(
            _db.reminderTemplates,
          )..where((t) => t.id.equals(remote.id))).write(
            ReminderTemplatesCompanion(
              name: remote.name.isNotEmpty
                  ? Value(remote.name)
                  : const Value.absent(),
              body: Value(cleanBody),
              updatedAt: Value(remoteUtc),
            ),
          );
        }
      }
    });
  }

  /// Reconciles local templates with Firestore when signed in and online.
  Future<void> syncWithCloud() async {
    final firestore = _cloud;
    final uid = _userIdProvider?.call();
    if (firestore == null || uid == null || uid.isEmpty) {
      return;
    }
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(true));
    if (!online) {
      return;
    }

    final remoteList = await firestore.fetchTemplates(uid);
    final remoteById = <String, CloudTemplateDocument>{
      for (final item in remoteList) item.id: item,
    };

    await applyCloudTemplates(remoteList);

    final localRows = await _db.select(_db.reminderTemplates).get();
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    for (final local in localRows) {
      final remote = remoteById[local.id];
      final localUtc = local.updatedAt.toUtc();
      final isCustomized =
          local.body.trim() != ReminderTemplateEngine.defaultBodyFor(local.id);

      final shouldUpload = remote == null
          ? isCustomized || localUtc.isAfter(epoch)
          : localUtc.isAfter(remote.updatedAt.toUtc()) &&
                local.body.trim() != remote.body.trim();

      if (shouldUpload) {
        await firestore.upsertTemplate(
          uid,
          CloudTemplateDocument(
            id: local.id,
            name: local.name,
            body: local.body,
            updatedAt: localUtc,
          ),
        );
      }
    }
  }

  Future<void> _pushTemplateToCloud(ReminderTemplate row) async {
    final firestore = _cloud;
    final uid = _userIdProvider?.call();
    if (firestore == null || uid == null || uid.isEmpty) {
      return;
    }
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(true));
    if (!online) {
      return;
    }

    try {
      await firestore.upsertTemplate(
        uid,
        CloudTemplateDocument(
          id: row.id,
          name: row.name,
          body: row.body,
          updatedAt: row.updatedAt.toUtc(),
        ),
      );
    } catch (_) {
      // Next reconnect/sync will reconcile local template updatedAt against cloud.
    }
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
      return ReminderTemplatesRepository(
        ref.watch(appDatabaseProvider),
        firestoreDatasource: ref.watch(firestoreSyncDatasourceProvider),
        currentUserId: () => ref.read(authControllerProvider).user?.id,
        isOnline: () => ref.read(connectivityServiceProvider).isOnline,
      );
    });

final reminderTemplatesProvider = StreamProvider<List<ReminderTemplateEntity>>((
  Ref ref,
) {
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
