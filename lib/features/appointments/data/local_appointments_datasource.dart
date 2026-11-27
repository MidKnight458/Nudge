import 'package:drift/drift.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Drift/SQLite local data source for clients, appointments, and sync metadata.
class LocalAppointmentsDatasource {
  LocalAppointmentsDatasource(this._db);

  final AppDatabase _db;

  /// Watches non-deleted appointments overlapping `[startInclusive, endExclusive)`.
  Stream<List<AppointmentEntity>> watchAppointmentsInRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    final query = _baseJoinedQuery()
      ..where(
        _db.appointments.syncStatus
                .equals(AppConstants.syncStatusPendingDelete)
                .not() &
            _db.appointments.startTime.isBiggerOrEqualValue(startInclusive) &
            _db.appointments.startTime.isSmallerThanValue(endExclusive),
      )
      ..orderBy([
        OrderingTerm.asc(_db.appointments.startTime),
        OrderingTerm.asc(_db.appointments.id),
      ]);

    return query.watch().map(
      (List<TypedResult> rows) =>
          rows.map(_mapJoinedRow).toList(growable: false),
    );
  }

  /// Watches unique local calendar dates within `[startInclusive, endExclusive)`
  /// that contain at least one active appointment.
  Stream<Set<DateTime>> watchAppointmentDatesInRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    return watchAppointmentsInRange(startInclusive, endExclusive).map((
      List<AppointmentEntity> items,
    ) {
      return items.map((AppointmentEntity item) {
        final local = item.startTime.toLocal();
        return DateTime(local.year, local.month, local.day);
      }).toSet();
    });
  }

  /// Watches the count of appointments awaiting synchronization.
  Stream<int> watchPendingSyncCount() {
    final countExp = _db.appointments.id.count();
    final query = _db.selectOnly(_db.appointments)
      ..addColumns([countExp])
      ..where(
        _db.appointments.syncStatus.equals(AppConstants.syncStatusSynced).not(),
      );

    return query.watchSingle().map(
      (TypedResult row) => row.read(countExp) ?? 0,
    );
  }

  /// Finds or inserts a client record matching Google Contact ID or E.164 phone.
  Future<int> upsertClient({
    required String name,
    required String rawPhone,
    required String phoneE164,
    String? googleContactId,
  }) async {
    final cleanContactId = googleContactId?.trim().isEmpty == true
        ? null
        : googleContactId?.trim();
    final cleanName = name.trim();
    final cleanRawPhone = rawPhone.trim();
    final cleanE164 = phoneE164.trim();

    Client? existing;
    if (cleanContactId != null) {
      existing =
          await (_db.select(_db.clients)
                ..where((c) => c.googleContactId.equals(cleanContactId))
                ..limit(1))
              .getSingleOrNull();
    }

    if (existing == null && cleanE164.isNotEmpty) {
      existing =
          await (_db.select(_db.clients)
                ..where((c) => c.phoneE164.equals(cleanE164))
                ..limit(1))
              .getSingleOrNull();
    }

    if (existing == null && cleanE164.isEmpty) {
      existing =
          await (_db.select(_db.clients)
                ..where(
                  (c) => c.name.equals(cleanName) & c.phoneE164.equals(''),
                )
                ..limit(1))
              .getSingleOrNull();
    }

    if (existing != null) {
      final resolvedRawPhone = cleanRawPhone.isNotEmpty
          ? cleanRawPhone
          : existing.rawPhone;
      final resolvedE164 = cleanE164.isNotEmpty
          ? cleanE164
          : existing.phoneE164;
      final resolvedName = cleanName.isNotEmpty ? cleanName : existing.name;
      final resolvedContactId = cleanContactId ?? existing.googleContactId;

      await (_db.update(
        _db.clients,
      )..where((c) => c.id.equals(existing!.id))).write(
        ClientsCompanion(
          googleContactId: Value(resolvedContactId),
          name: Value(resolvedName),
          rawPhone: Value(resolvedRawPhone),
          phoneE164: Value(resolvedE164),
        ),
      );
      return existing.id;
    }

    return _db
        .into(_db.clients)
        .insert(
          ClientsCompanion.insert(
            googleContactId: Value(cleanContactId),
            name: cleanName,
            rawPhone: cleanRawPhone,
            phoneE164: cleanE164,
          ),
        );
  }

  /// Inserts a new local appointment queued as `pending_create`.
  Future<AppointmentEntity> createAppointmentOffline(
    AppointmentInput input,
  ) async {
    return _db.transaction(() async {
      final clientId = await upsertClient(
        name: input.clientName,
        rawPhone: input.clientRawPhone,
        phoneE164: input.clientPhoneE164,
        googleContactId: input.clientGoogleContactId,
      );

      final now = DateTime.now().toUtc();
      final cleanNotes = input.notes?.trim();
      final insertedId = await _db
          .into(_db.appointments)
          .insert(
            AppointmentsCompanion.insert(
              clientId: clientId,
              title: input.title.trim(),
              notes: Value(
                (cleanNotes == null || cleanNotes.isEmpty) ? null : cleanNotes,
              ),
              startTime: input.startTime.toUtc(),
              endTime: input.endTime.toUtc(),
              reminderSent: const Value(false),
              syncStatus: const Value(AppConstants.syncStatusPendingCreate),
              lastModified: now,
            ),
          );

      return (await getAppointmentById(insertedId))!;
    });
  }

  /// Updates an existing appointment locally and marks its next sync status.
  Future<AppointmentEntity> updateAppointmentOffline(
    AppointmentEntity existing,
    AppointmentInput input,
  ) async {
    return _db.transaction(() async {
      final clientId = await upsertClient(
        name: input.clientName,
        rawPhone: input.clientRawPhone,
        phoneE164: input.clientPhoneE164,
        googleContactId: input.clientGoogleContactId,
      );

      final nextSyncStatus = existing.googleCalendarEventId == null
          ? AppConstants.syncStatusPendingCreate
          : AppConstants.syncStatusPendingUpdate;

      final cleanNotes = input.notes?.trim();
      final now = DateTime.now().toUtc();

      await (_db.update(
        _db.appointments,
      )..where((a) => a.id.equals(existing.id))).write(
        AppointmentsCompanion(
          clientId: Value(clientId),
          title: Value(input.title.trim()),
          notes: Value(
            (cleanNotes == null || cleanNotes.isEmpty) ? null : cleanNotes,
          ),
          startTime: Value(input.startTime.toUtc()),
          endTime: Value(input.endTime.toUtc()),
          syncStatus: Value(nextSyncStatus),
          lastModified: Value(now),
        ),
      );

      return (await getAppointmentById(existing.id))!;
    });
  }

  /// Marks a synced appointment as `pending_delete`, or purges an unsynced row.
  Future<bool> markAppointmentDeletedOffline(int appointmentId) async {
    final row =
        await (_db.select(_db.appointments)
              ..where((a) => a.id.equals(appointmentId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return false;
    }

    if (row.googleCalendarEventId == null ||
        row.googleCalendarEventId!.isEmpty) {
      await (_db.delete(
        _db.appointments,
      )..where((a) => a.id.equals(appointmentId))).go();
      return false;
    }

    await (_db.update(
      _db.appointments,
    )..where((a) => a.id.equals(appointmentId))).write(
      AppointmentsCompanion(
        syncStatus: const Value(AppConstants.syncStatusPendingDelete),
        lastModified: Value(DateTime.now().toUtc()),
      ),
    );
    return true;
  }

  /// Permanently removes a local appointment row after remote deletion.
  Future<void> purgeAppointmentById(int appointmentId) async {
    await (_db.delete(
      _db.appointments,
    )..where((a) => a.id.equals(appointmentId))).go();
  }

  /// Removes a local appointment matching [googleCalendarEventId].
  Future<bool> deleteByGoogleEventId(String googleCalendarEventId) async {
    final deletedCount =
        await (_db.delete(_db.appointments)..where(
              (a) => a.googleCalendarEventId.equals(googleCalendarEventId),
            ))
            .go();
    return deletedCount > 0;
  }

  /// Updates the `reminderSent` flag on a local appointment.
  Future<void> markReminderSent(int appointmentId, {bool sent = true}) async {
    await (_db.update(_db.appointments)
          ..where((a) => a.id.equals(appointmentId)))
        .write(AppointmentsCompanion(reminderSent: Value(sent)));
  }

  /// Returns all appointments whose `syncStatus` is not `'synced'`.
  Future<List<AppointmentEntity>> getPendingSyncAppointments() async {
    final query = _baseJoinedQuery()
      ..where(
        _db.appointments.syncStatus.equals(AppConstants.syncStatusSynced).not(),
      )
      ..orderBy([OrderingTerm.asc(_db.appointments.id)]);

    final rows = await query.get();
    return rows.map(_mapJoinedRow).toList(growable: false);
  }

  /// Marks an appointment as synchronized and attaches its Google Calendar ID.
  Future<AppointmentEntity?> markAppointmentSynced({
    required int appointmentId,
    required String googleCalendarEventId,
  }) async {
    await (_db.update(
      _db.appointments,
    )..where((a) => a.id.equals(appointmentId))).write(
      AppointmentsCompanion(
        googleCalendarEventId: Value(googleCalendarEventId),
        syncStatus: const Value(AppConstants.syncStatusSynced),
        lastModified: Value(DateTime.now().toUtc()),
      ),
    );
    return getAppointmentById(appointmentId);
  }

  /// Inserts or updates a local appointment from a remote Google Calendar event.
  Future<bool> upsertFromRemoteEvent({
    required String googleEventId,
    required String? summary,
    required String? description,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    return _db.transaction(() async {
      final existing =
          await (_db.select(_db.appointments)
                ..where((a) => a.googleCalendarEventId.equals(googleEventId))
                ..limit(1))
              .getSingleOrNull();

      if (existing != null &&
          (existing.syncStatus == AppConstants.syncStatusPendingUpdate ||
              existing.syncStatus == AppConstants.syncStatusPendingDelete)) {
        return false;
      }

      final decoded = CalendarEventMetadataCodec.decodeEvent(
        summary: summary,
        description: description,
      );

      final clientId = await upsertClient(
        name: decoded.clientName,
        rawPhone: decoded.clientPhoneE164,
        phoneE164: decoded.clientPhoneE164,
      );

      final now = DateTime.now().toUtc();
      if (existing != null) {
        await (_db.update(
          _db.appointments,
        )..where((a) => a.id.equals(existing.id))).write(
          AppointmentsCompanion(
            clientId: Value(clientId),
            title: Value(decoded.title),
            notes: Value(decoded.notes),
            startTime: Value(startTime.toUtc()),
            endTime: Value(endTime.toUtc()),
            syncStatus: const Value(AppConstants.syncStatusSynced),
            lastModified: Value(now),
          ),
        );
      } else {
        await _db
            .into(_db.appointments)
            .insert(
              AppointmentsCompanion.insert(
                googleCalendarEventId: Value(googleEventId),
                clientId: clientId,
                title: decoded.title,
                notes: Value(decoded.notes),
                startTime: startTime.toUtc(),
                endTime: endTime.toUtc(),
                reminderSent: const Value(false),
                syncStatus: const Value(AppConstants.syncStatusSynced),
                lastModified: now,
              ),
            );
      }
      return true;
    });
  }

  Future<AppointmentEntity?> getAppointmentById(int id) async {
    final query = _baseJoinedQuery()
      ..where(_db.appointments.id.equals(id))
      ..limit(1);
    final row = await query.getSingleOrNull();
    return row == null ? null : _mapJoinedRow(row);
  }

  Future<SyncMetadataRecord> getSyncMetadata() async {
    final row =
        await (_db.select(_db.syncMetadata)
              ..where((m) => m.id.equals(1))
              ..limit(1))
            .getSingleOrNull();
    if (row != null) {
      return row;
    }
    await _db
        .into(_db.syncMetadata)
        .insert(
          const SyncMetadataCompanion(id: Value(1)),
          mode: InsertMode.insertOrIgnore,
        );
    return (_db.select(
      _db.syncMetadata,
    )..where((m) => m.id.equals(1))).getSingle();
  }

  Future<void> saveSyncMetadata({
    String? syncToken,
    DateTime? lastSyncTimestamp,
  }) async {
    await _db
        .into(_db.syncMetadata)
        .insertOnConflictUpdate(
          SyncMetadataCompanion(
            id: const Value(1),
            syncToken: Value(syncToken),
            lastSyncTimestamp: Value(lastSyncTimestamp?.toUtc()),
          ),
        );
  }

  Future<void> clearSyncToken({bool clearTimestamp = false}) async {
    await (_db.update(_db.syncMetadata)..where((m) => m.id.equals(1))).write(
      SyncMetadataCompanion(
        syncToken: const Value(null),
        lastSyncTimestamp: clearTimestamp
            ? const Value(null)
            : const Value.absent(),
      ),
    );
  }

  JoinedSelectStatement<HasResultSet, dynamic> _baseJoinedQuery() {
    return _db.select(_db.appointments).join([
      innerJoin(
        _db.clients,
        _db.clients.id.equalsExp(_db.appointments.clientId),
      ),
    ]);
  }

  AppointmentEntity _mapJoinedRow(TypedResult row) {
    final appointment = row.readTable(_db.appointments);
    final client = row.readTable(_db.clients);

    return AppointmentEntity(
      id: appointment.id,
      googleCalendarEventId: appointment.googleCalendarEventId,
      clientId: client.id,
      clientName: client.name,
      clientRawPhone: client.rawPhone,
      clientPhoneE164: client.phoneE164,
      clientGoogleContactId: client.googleContactId,
      title: appointment.title,
      notes: appointment.notes,
      startTime: appointment.startTime.toLocal(),
      endTime: appointment.endTime.toLocal(),
      reminderSent: appointment.reminderSent,
      syncStatus: AppointmentSyncStatus.fromDbValue(appointment.syncStatus),
      lastModified: appointment.lastModified.toLocal(),
    );
  }
}
