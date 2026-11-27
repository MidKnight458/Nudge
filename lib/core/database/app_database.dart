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
  TextColumn get googleContactId => text().nullable().unique()();
  TextColumn get name => text()();
  TextColumn get rawPhone => text()();
  TextColumn get phoneE164 => text()();
}

/// Offline-first appointment record synchronized with Google Calendar v3.
class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
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

/// Singleton metadata row storing Google Calendar incremental `syncToken`.
@DataClassName('SyncMetadataRecord')
class SyncMetadata extends Table {
  IntColumn get id => integer().withDefault(const Constant(1))();
  TextColumn get syncToken => text().nullable()();
  DateTimeColumn get lastSyncTimestamp => dateTime().nullable()();

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
@DriftDatabase(tables: [Clients, Appointments, SyncMetadata, ReminderTemplates])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
    },
    beforeOpen: (OpeningDetails details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await _seedDefaults();
    },
  );

  Future<void> _seedDefaults() async {
    await into(syncMetadata).insert(
      const SyncMetadataCompanion(id: Value(1)),
      mode: InsertMode.insertOrIgnore,
    );

    final now = DateTime.now().toUtc();
    await batch((Batch batch) {
      batch.insertAll(reminderTemplates, [
        ReminderTemplatesCompanion.insert(
          id: AppConstants.tomorrowTemplateId,
          name: AppConstants.tomorrowTemplateName,
          body: AppConstants.defaultTomorrowReminderBody,
          updatedAt: now,
        ),
        ReminderTemplatesCompanion.insert(
          id: AppConstants.confirmationTemplateId,
          name: AppConstants.confirmationTemplateName,
          body: AppConstants.defaultConfirmationBody,
          updatedAt: now,
        ),
      ], mode: InsertMode.insertOrIgnore);
    });
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
