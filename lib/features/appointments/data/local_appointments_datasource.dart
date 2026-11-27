import 'package:drift/drift.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Result returned when applying a batch of Cloud Firestore appointment documents.
class CloudApplyResult {
  const CloudApplyResult({required this.upserted, required this.deleted});

  final int upserted;
  final int deleted;

  int get totalChanges => upserted + deleted;
}

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

      final now = _truncateUtcSeconds(DateTime.now());
      final cleanNotes = input.notes?.trim();
      final insertedId = await _db
          .into(_db.appointments)
          .insert(
            AppointmentsCompanion.insert(
              syncId: generateAppointmentSyncId(),
              clientId: clientId,
              title: input.title.trim(),
              notes: Value(
                (cleanNotes == null || cleanNotes.isEmpty) ? null : cleanNotes,
              ),
              startTime: _truncateUtcSeconds(input.startTime),
              endTime: _truncateUtcSeconds(input.endTime),
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

      final nextSyncStatus =
          existing.syncStatus == AppointmentSyncStatus.pendingCreate
          ? AppConstants.syncStatusPendingCreate
          : AppConstants.syncStatusPendingUpdate;

      final cleanNotes = input.notes?.trim();
      final now = _truncateUtcSeconds(DateTime.now());

      await (_db.update(
        _db.appointments,
      )..where((a) => a.id.equals(existing.id))).write(
        AppointmentsCompanion(
          clientId: Value(clientId),
          title: Value(input.title.trim()),
          notes: Value(
            (cleanNotes == null || cleanNotes.isEmpty) ? null : cleanNotes,
          ),
          startTime: Value(_truncateUtcSeconds(input.startTime)),
          endTime: Value(_truncateUtcSeconds(input.endTime)),
          syncStatus: Value(nextSyncStatus),
          lastModified: Value(now),
        ),
      );

      return (await getAppointmentById(existing.id))!;
    });
  }

  /// Marks a synced/uploaded appointment as `pending_delete`, or purges a
  /// purely local `pending_create` row that has never reached Firestore.
  Future<bool> markAppointmentDeletedOffline(int appointmentId) async {
    final row =
        await (_db.select(_db.appointments)
              ..where((a) => a.id.equals(appointmentId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return false;
    }

    if (row.syncStatus == AppConstants.syncStatusPendingCreate &&
        (row.googleCalendarEventId == null ||
            row.googleCalendarEventId!.isEmpty)) {
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
        lastModified: Value(_truncateUtcSeconds(DateTime.now())),
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

  /// Updates the `reminderSent` flag on a local appointment and queues sync.
  Future<AppointmentEntity?> markReminderSent(
    int appointmentId, {
    bool sent = true,
  }) async {
    final row =
        await (_db.select(_db.appointments)
              ..where((a) => a.id.equals(appointmentId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null || row.syncStatus == AppConstants.syncStatusPendingDelete) {
      return null;
    }

    final nextSyncStatus =
        row.syncStatus == AppConstants.syncStatusPendingCreate
        ? AppConstants.syncStatusPendingCreate
        : AppConstants.syncStatusPendingUpdate;

    await (_db.update(
      _db.appointments,
    )..where((a) => a.id.equals(appointmentId))).write(
      AppointmentsCompanion(
        reminderSent: Value(sent),
        syncStatus: Value(nextSyncStatus),
        lastModified: Value(_truncateUtcSeconds(DateTime.now())),
      ),
    );
    return getAppointmentById(appointmentId);
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

  /// Returns all non-deleted appointments stored locally.
  Future<List<AppointmentEntity>> getAllActiveAppointments() async {
    final query = _baseJoinedQuery()
      ..where(
        _db.appointments.syncStatus
            .equals(AppConstants.syncStatusPendingDelete)
            .not(),
      )
      ..orderBy([OrderingTerm.asc(_db.appointments.id)]);

    final rows = await query.get();
    return rows.map(_mapJoinedRow).toList(growable: false);
  }

  /// Marks an appointment as synchronized and updates its metadata.
  Future<AppointmentEntity?> markAppointmentSynced({
    required int appointmentId,
    String? googleCalendarEventId,
    bool clearGoogleCalendarEventId = false,
    DateTime? lastModified,
  }) async {
    await (_db.update(
      _db.appointments,
    )..where((a) => a.id.equals(appointmentId))).write(
      AppointmentsCompanion(
        googleCalendarEventId: clearGoogleCalendarEventId
            ? const Value(null)
            : (googleCalendarEventId != null
                  ? Value(googleCalendarEventId)
                  : const Value.absent()),
        syncStatus: const Value(AppConstants.syncStatusSynced),
        lastModified: Value(
          _truncateUtcSeconds(lastModified ?? DateTime.now()),
        ),
      ),
    );
    return getAppointmentById(appointmentId);
  }

  /// Merges a Cloud Firestore snapshot into Drift without duplicating rows.
  Future<CloudApplyResult> applyCloudAppointments(
    List<CloudAppointmentDocument> documents,
  ) async {
    if (documents.isEmpty) {
      return const CloudApplyResult(upserted: 0, deleted: 0);
    }

    return _db.transaction(() async {
      var upserted = 0;
      var deleted = 0;

      for (final doc in documents) {
        if (doc.syncId.isEmpty) {
          continue;
        }

        var existing =
            await (_db.select(_db.appointments)
                  ..where((a) => a.syncId.equals(doc.syncId))
                  ..limit(1))
                .getSingleOrNull();

        if (existing == null &&
            doc.googleCalendarEventId != null &&
            doc.googleCalendarEventId!.isNotEmpty) {
          existing =
              await (_db.select(_db.appointments)
                    ..where(
                      (a) => a.googleCalendarEventId.equals(
                        doc.googleCalendarEventId!,
                      ),
                    )
                    ..limit(1))
                  .getSingleOrNull();
        }

        if (doc.deleted) {
          if (existing != null) {
            final keepLocalPending =
                (existing.syncStatus == AppConstants.syncStatusPendingCreate ||
                    existing.syncStatus ==
                        AppConstants.syncStatusPendingUpdate) &&
                _secondsAfter(existing.lastModified, doc.lastModified);
            if (!keepLocalPending) {
              await (_db.delete(
                _db.appointments,
              )..where((a) => a.id.equals(existing!.id))).go();
              deleted++;
            }
          }
          continue;
        }

        if (doc.title.trim().isEmpty && doc.clientName.trim().isEmpty) {
          continue;
        }

        final startUtc = _truncateUtcSeconds(doc.startTime);
        final endUtc = _truncateUtcSeconds(doc.endTime);
        final modifiedUtc = _truncateUtcSeconds(doc.lastModified);
        final remoteNotes = _nullIfEmpty(doc.notes);

        // Guard against unique `googleCalendarEventId` constraint collisions if
        // another local record with a different `syncId` already holds this ID.
        final current = existing;
        var effectiveCalendarId = doc.googleCalendarEventId;
        if (effectiveCalendarId != null && effectiveCalendarId.isNotEmpty) {
          final targetCalendarId = effectiveCalendarId;
          final holder =
              await (_db.select(_db.appointments)
                    ..where(
                      (a) => a.googleCalendarEventId.equals(targetCalendarId),
                    )
                    ..limit(1))
                  .getSingleOrNull();
          if (holder != null && (current == null || holder.id != current.id)) {
            effectiveCalendarId = null;
          }
        }

        if (current != null) {
          if (current.syncStatus != AppConstants.syncStatusSynced &&
              _secondsAfter(current.lastModified, modifiedUtc)) {
            continue;
          }

          final clientId = await upsertClient(
            name: doc.clientName.isNotEmpty ? doc.clientName : 'Cliente',
            rawPhone: doc.clientRawPhone,
            phoneE164: doc.clientPhoneE164,
            googleContactId: doc.clientGoogleContactId,
          );

          final cleanTitle = doc.title.trim();
          final sameData =
              current.syncId == doc.syncId &&
              current.googleCalendarEventId == effectiveCalendarId &&
              current.clientId == clientId &&
              current.title == cleanTitle &&
              current.notes == remoteNotes &&
              _sameUnixSecond(current.startTime, startUtc) &&
              _sameUnixSecond(current.endTime, endUtc) &&
              current.reminderSent == doc.reminderSent &&
              current.syncStatus == AppConstants.syncStatusSynced;

          if (sameData) {
            continue;
          }

          await (_db.update(
            _db.appointments,
          )..where((a) => a.id.equals(current.id))).write(
            AppointmentsCompanion(
              syncId: Value(doc.syncId),
              googleCalendarEventId: Value(effectiveCalendarId),
              clientId: Value(clientId),
              title: Value(cleanTitle),
              notes: Value(remoteNotes),
              startTime: Value(startUtc),
              endTime: Value(endUtc),
              reminderSent: Value(doc.reminderSent),
              syncStatus: const Value(AppConstants.syncStatusSynced),
              lastModified: Value(modifiedUtc),
            ),
          );
          upserted++;
        } else {
          final clientId = await upsertClient(
            name: doc.clientName.isNotEmpty ? doc.clientName : 'Cliente',
            rawPhone: doc.clientRawPhone,
            phoneE164: doc.clientPhoneE164,
            googleContactId: doc.clientGoogleContactId,
          );

          await _db
              .into(_db.appointments)
              .insert(
                AppointmentsCompanion.insert(
                  syncId: doc.syncId,
                  googleCalendarEventId: Value(effectiveCalendarId),
                  clientId: clientId,
                  title: doc.title.trim(),
                  notes: Value(remoteNotes),
                  startTime: startUtc,
                  endTime: endUtc,
                  reminderSent: Value(doc.reminderSent),
                  syncStatus: const Value(AppConstants.syncStatusSynced),
                  lastModified: modifiedUtc,
                ),
              );
          upserted++;
        }
      }

      return CloudApplyResult(upserted: upserted, deleted: deleted);
    });
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
                syncId: 'gcal-${googleEventId.replaceAll('/', '_')}',
                googleCalendarEventId: Value(googleEventId),
                clientId: clientId,
                title: decoded.title,
                notes: Value(decoded.notes),
                startTime: _truncateUtcSeconds(startTime),
                endTime: _truncateUtcSeconds(endTime),
                reminderSent: const Value(false),
                syncStatus: const Value(AppConstants.syncStatusSynced),
                lastModified: _truncateUtcSeconds(now),
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
      syncId: appointment.syncId,
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

  DateTime _truncateUtcSeconds(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      (utc.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
  }

  bool _sameUnixSecond(DateTime a, DateTime b) {
    return (a.toUtc().millisecondsSinceEpoch ~/ 1000) ==
        (b.toUtc().millisecondsSinceEpoch ~/ 1000);
  }

  bool _secondsAfter(DateTime a, DateTime b) {
    return (a.toUtc().millisecondsSinceEpoch ~/ 1000) >
        (b.toUtc().millisecondsSinceEpoch ~/ 1000);
  }

  String? _nullIfEmpty(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}
