import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// Local client record backed by device Google Contacts or manual entry.
class Clients extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().unique()();
  TextColumn get googleContactId => text().nullable().unique()();
  TextColumn get name => text()();
  TextColumn get rawPhone => text()();
  TextColumn get phoneE164 => text()();
  TextColumn get generalNotes => text().nullable()();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(AppConstants.syncStatusSynced))();
  DateTimeColumn get lastModified => dateTime()();
}

/// Offline-first appointment record synchronized with Firestore and Google Calendar.
class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().unique()();
  TextColumn get googleCalendarEventId => text().nullable().unique()();
  IntColumn get clientId =>
      integer().references(Clients, #id, onDelete: KeyAction.cascade)();
  TextColumn get title => text()();
  TextColumn get notes => text().nullable()();
  DateTimeColumn get startTime => dateTime()();
  DateTimeColumn get endTime => dateTime()();
  BoolColumn get reminderSent => boolean().withDefault(const Constant(false))();
  TextColumn get syncStatus =>
      text().withDefault(const Constant(AppConstants.syncStatusSynced))();
  DateTimeColumn get lastModified => dateTime()();
}

/// File attachment (image or PDF) associated with a [Clients] row and
/// synchronized via Google Drive + Cloud Firestore metadata.
class ClientAttachments extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text().unique()();
  IntColumn get clientId =>
      integer().references(Clients, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get mimeType => text()();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  TextColumn get localPath => text().nullable()();
  TextColumn get driveFileId => text().nullable()();
  TextColumn get syncStatus => text().withDefault(
    const Constant(AppConstants.syncStatusPendingCreate),
  )();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get lastModified => dateTime()();
}

/// Singleton settings row storing custom client labels, services, and schedule.
@DataClassName('AppSettingsRecord')
class AppSettings extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get clientLabelPlural => text().withDefault(
    const Constant(AppConstants.defaultClientLabelPlural),
  )();
  TextColumn get clientLabelSingular => text().withDefault(
    const Constant(AppConstants.defaultClientLabelSingular),
  )();
  TextColumn get servicesJson => text().withDefault(const Constant('[]'))();
  TextColumn get scheduleJson => text().withDefault(const Constant('{}'))();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Singleton metadata row storing sync timestamps and last active Firebase UID.
@DataClassName('SyncMetadataRecord')
class SyncMetadata extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get syncToken => text().nullable()();
  DateTimeColumn get lastSyncTimestamp => dateTime().nullable()();
  TextColumn get lastAccountUid => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Editable WhatsApp message templates stored locally.
class ReminderTemplates extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get body => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Application Drift database with offline-first persistence.
@DriftDatabase(
  tables: [
    Clients,
    Appointments,
    SyncMetadata,
    ReminderTemplates,
    ClientAttachments,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await customStatement(
          'ALTER TABLE appointments ADD COLUMN sync_id TEXT',
        );
        await customStatement('''
          UPDATE appointments
          SET sync_id = CASE
            WHEN google_calendar_event_id IS NOT NULL
              AND length(trim(google_calendar_event_id)) > 0
              THEN 'gcal-' || replace(google_calendar_event_id, '/', '_')
            ELSE 'legacy-' || lower(hex(randomblob(8)))
          END
          WHERE sync_id IS NULL
        ''');
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_appointments_sync_id '
          'ON appointments (sync_id)',
        );
      }

      if (from < 3) {
        await customStatement('ALTER TABLE clients ADD COLUMN sync_id TEXT');
        await customStatement(
          'ALTER TABLE clients ADD COLUMN general_notes TEXT',
        );
        await customStatement(
          "ALTER TABLE clients ADD COLUMN sync_status TEXT NOT NULL DEFAULT 'synced'",
        );
        await customStatement(
          'ALTER TABLE clients ADD COLUMN last_modified INTEGER NOT NULL DEFAULT 0',
        );
        await customStatement('''
          UPDATE clients
          SET sync_id = CASE
            WHEN length(trim(phone_e164)) > 0
              AND id = (
                SELECT MIN(c2.id)
                FROM clients c2
                WHERE c2.phone_e164 = clients.phone_e164
              )
              THEN 'phone-' || phone_e164
            ELSE 'client-' || lower(hex(randomblob(8)))
          END
          WHERE sync_id IS NULL
        ''');
        await customStatement(
          'CREATE UNIQUE INDEX IF NOT EXISTS idx_clients_sync_id '
          'ON clients (sync_id)',
        );
        await customStatement(
          'ALTER TABLE sync_metadata ADD COLUMN last_account_uid TEXT',
        );
        await m.createTable(clientAttachments);
        await m.createTable(appSettings);
        await customStatement('''
          UPDATE reminder_templates
          SET name = '${AppConstants.tomorrowTemplateName}'
          WHERE id = '${AppConstants.tomorrowTemplateId}'
        ''');
        await customStatement('''
          DELETE FROM reminder_templates
          WHERE id = '${AppConstants.confirmationTemplateId}'
        ''');
      }
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _seedDefaults();
    },
  );

  Future<void> _seedDefaults() async {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    await into(syncMetadata).insert(
      const SyncMetadataCompanion(id: Value(1)),
      mode: InsertMode.insertOrIgnore,
    );

    await into(appSettings).insert(
      AppSettingsCompanion.insert(updatedAt: epoch),
      mode: InsertMode.insertOrIgnore,
    );

    await into(reminderTemplates).insert(
      ReminderTemplatesCompanion.insert(
        id: AppConstants.tomorrowTemplateId,
        name: AppConstants.tomorrowTemplateName,
        body: AppConstants.defaultTomorrowReminderBody,
        updatedAt: epoch,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'nudge.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Provides a singleton [AppDatabase] scoped to the Riverpod container.
final appDatabaseProvider = Provider<AppDatabase>((Ref ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
