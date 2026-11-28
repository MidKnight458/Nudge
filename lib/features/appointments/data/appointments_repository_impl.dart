import 'dart:async';

import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/data/google_calendar_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

/// Offline-first repository backed by Drift SQLite, Cloud Firestore
/// (real-time multi-device source of truth), and Google Calendar mirroring.
class AppointmentsRepositoryImpl implements AppointmentsRepository {
  AppointmentsRepositoryImpl({
    required LocalAppointmentsDatasource localDatasource,
    required GoogleCalendarDatasource remoteDatasource,
    required FirestoreSyncDatasource firestoreDatasource,
    required ConnectivityService connectivityService,
    required AuthRepository authRepository,
    DateTime Function()? nowProvider,
  }) : _local = localDatasource,
       _calendar = remoteDatasource,
       _firestore = firestoreDatasource,
       _connectivity = connectivityService,
       _auth = authRepository,
       _now = nowProvider ?? DateTime.now;

  final LocalAppointmentsDatasource _local;
  final GoogleCalendarDatasource _calendar;
  final FirestoreSyncDatasource _firestore;
  final ConnectivityService _connectivity;
  final AuthRepository _auth;
  final DateTime Function() _now;

  Future<SyncResult>? _inFlightSync;
  Future<void> _serialQueue = Future<void>.value();

  @override
  Stream<List<AppointmentEntity>> watchAppointmentsForDay(DateTime day) {
    final localDay = day.toLocal();
    final start = DateTime(localDay.year, localDay.month, localDay.day);
    final end = DateTime(localDay.year, localDay.month, localDay.day + 1);
    return watchAppointmentsForRange(start, end);
  }

  @override
  Stream<List<AppointmentEntity>> watchAppointmentsForRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    return _local.watchAppointmentsInRange(startInclusive, endExclusive);
  }

  @override
  Stream<Set<DateTime>> watchAppointmentDatesInRange(
    DateTime startInclusive,
    DateTime endExclusive,
  ) {
    return _local.watchAppointmentDatesInRange(startInclusive, endExclusive);
  }

  @override
  Stream<({DateTime? date, List<AppointmentEntity> appointments})>
  watchNextUpcomingDayAppointments(DateTime afterDay) {
    return _local.watchNextUpcomingDayAppointments(afterDay);
  }

  @override
  Stream<List<AppointmentEntity>> watchAllActiveAppointments() {
    return _local.watchAllActiveAppointments();
  }

  @override
  Stream<int> watchPendingSyncCount() => _local.watchPendingSyncCount();

  @override
  Future<DateTime?> getLastSyncTimestamp() async {
    final metadata = await _local.getSyncMetadata();
    return metadata.lastSyncTimestamp?.toLocal();
  }

  @override
  Future<AppointmentEntity> createAppointment(AppointmentInput input) async {
    final created = await _local.createAppointmentOffline(input);
    final user = await _canAttemptRemoteSync();
    if (user == null) {
      return created;
    }

    return _enqueue(() async {
      try {
        final mirrored = await _mirrorUpsertToCalendar(created);
        final effective = mirrored.entity;
        await _firestore.upsertAppointment(
          user.id,
          CloudAppointmentDocument.fromEntity(effective),
        );
        final synced = await _local.markAppointmentSynced(
          appointmentId: created.id,
          googleCalendarEventId: effective.googleCalendarEventId,
          clearGoogleCalendarEventId: effective.googleCalendarEventId == null,
          lastModified: effective.lastModified,
        );
        return synced ?? effective;
      } catch (_) {
        // Remains queued as `pending_create` in SQLite until next sync pass.
        return created;
      }
    });
  }

  @override
  Future<AppointmentEntity> updateAppointment(
    AppointmentEntity existing,
    AppointmentInput input,
  ) async {
    final updated = await _local.updateAppointmentOffline(existing, input);
    final user = await _canAttemptRemoteSync();
    if (user == null) {
      return updated;
    }

    return _enqueue(() async {
      try {
        final mirrored = await _mirrorUpsertToCalendar(updated);
        final effective = mirrored.entity;
        await _firestore.upsertAppointment(
          user.id,
          CloudAppointmentDocument.fromEntity(effective),
        );
        final synced = await _local.markAppointmentSynced(
          appointmentId: updated.id,
          googleCalendarEventId: effective.googleCalendarEventId,
          clearGoogleCalendarEventId: effective.googleCalendarEventId == null,
          lastModified: effective.lastModified,
        );
        return synced ?? effective;
      } catch (_) {
        // Remains queued as pending in SQLite until next sync pass.
        return updated;
      }
    });
  }

  @override
  Future<void> deleteAppointment(AppointmentEntity appointment) async {
    final needsRemoteDelete = await _local.markAppointmentDeletedOffline(
      appointment.id,
    );
    if (!needsRemoteDelete) {
      return;
    }

    final user = await _canAttemptRemoteSync();
    if (user == null) {
      return;
    }

    await _enqueue(() async {
      try {
        await _mirrorDeleteFromCalendar(appointment.googleCalendarEventId);
        await _firestore.markAppointmentDeleted(
          user.id,
          syncId: appointment.syncId,
          deletedAt: _truncateToSecondsUtc(_now()),
          googleCalendarEventId: appointment.googleCalendarEventId,
        );
        await _local.purgeAppointmentById(appointment.id);
      } catch (_) {
        // Remains queued as `pending_delete` until connectivity returns.
      }
    });
  }

  @override
  Future<void> markReminderSent(int appointmentId, {bool sent = true}) async {
    final updated = await _local.markReminderSent(appointmentId, sent: sent);
    if (updated == null) {
      return;
    }

    final user = await _canAttemptRemoteSync();
    if (user == null) {
      return;
    }

    await _enqueue(() async {
      try {
        await _firestore.upsertAppointment(
          user.id,
          CloudAppointmentDocument.fromEntity(updated),
        );
        await _local.markAppointmentSynced(
          appointmentId: updated.id,
          googleCalendarEventId: updated.googleCalendarEventId,
          lastModified: updated.lastModified,
        );
      } catch (_) {
        // Remains queued as `pending_update` until next sync pass.
      }
    });
  }

  /// Clears stored sync metadata when changing Google/Firebase accounts.
  Future<void> resetSyncMetadata() {
    return _local.clearSyncToken(clearTimestamp: true);
  }

  @override
  Future<int> applyCloudSnapshot(List<CloudAppointmentDocument> documents) {
    return _enqueue(() async {
      final stats = await _local.applyCloudAppointments(documents);
      await _local.saveSyncMetadata(lastSyncTimestamp: _now().toUtc());
      return stats.totalChanges;
    });
  }

  @override
  Future<SyncResult> synchronize({bool interactive = false}) {
    final existing = _inFlightSync;
    if (existing != null) {
      return existing;
    }

    final future = _enqueue(() => _runSynchronize(interactive: interactive));
    _inFlightSync = future;
    future.whenComplete(() {
      if (identical(_inFlightSync, future)) {
        _inFlightSync = null;
      }
    });
    return future;
  }

  Future<SyncResult> _runSynchronize({required bool interactive}) async {
    if (!await _connectivity.isOnline) {
      return const SyncResult(skippedReason: 'Sin conexión a internet.');
    }

    final user = await _ensureSignedInUser();
    if (user == null) {
      return const SyncResult(
        skippedReason: 'Inicia sesión con Google para sincronizar.',
      );
    }

    var pushedCreated = 0;
    var pushedUpdated = 0;
    var pushedDeleted = 0;
    var pulledUpserted = 0;
    var pulledDeleted = 0;
    var calendarBackfilled = 0;
    String? calendarWarning;

    try {
      // 0. Proactively ensure dedicated secondary "Nudge" Google Calendar exists.
      try {
        await _calendar.ensureNudgeCalendar(requestScopeIfNeeded: interactive);
      } catch (_) {
        // Non-fatal: individual operations surface actionable Calendar warnings.
      }

      // 1. Fetch Cloud Firestore state so tombstone conflicts and migrations can be resolved.
      final cloudDocs = await _firestore.fetchAppointments(user.id);
      final cloudBySyncId = <String, CloudAppointmentDocument>{
        for (final doc in cloudDocs) doc.syncId: doc,
      };

      // 2. Drain local offline mutation queue (mirror Calendar best-effort + Firestore).
      final pending = await _local.getPendingSyncAppointments();
      final handledInQueue = <String>{};
      for (final item in pending) {
        handledInQueue.add(item.syncId);
        final remote = cloudBySyncId[item.syncId];
        switch (item.syncStatus) {
          case AppointmentSyncStatus.pendingCreate:
            if (remote != null &&
                remote.deleted &&
                _secondsAfter(remote.lastModified, item.lastModified)) {
              await _mirrorDeleteFromCalendar(remote.googleCalendarEventId);
              await _local.purgeAppointmentById(item.id);
              pulledDeleted++;
              break;
            }
            final mirrored = await _mirrorUpsertToCalendar(
              item,
              requestScopeIfNeeded: interactive,
            );
            calendarWarning ??= mirrored.warning;
            await _firestore.upsertAppointment(
              user.id,
              CloudAppointmentDocument.fromEntity(mirrored.entity),
            );
            await _local.markAppointmentSynced(
              appointmentId: item.id,
              googleCalendarEventId: mirrored.entity.googleCalendarEventId,
              clearGoogleCalendarEventId:
                  mirrored.entity.googleCalendarEventId == null,
              lastModified: item.lastModified,
            );
            pushedCreated++;
          case AppointmentSyncStatus.pendingUpdate:
            if (remote != null &&
                remote.deleted &&
                _secondsAfter(remote.lastModified, item.lastModified)) {
              await _mirrorDeleteFromCalendar(
                item.googleCalendarEventId ?? remote.googleCalendarEventId,
              );
              await _local.purgeAppointmentById(item.id);
              pulledDeleted++;
              break;
            }
            final mirrored = await _mirrorUpsertToCalendar(
              item,
              requestScopeIfNeeded: interactive,
            );
            calendarWarning ??= mirrored.warning;
            await _firestore.upsertAppointment(
              user.id,
              CloudAppointmentDocument.fromEntity(mirrored.entity),
            );
            await _local.markAppointmentSynced(
              appointmentId: item.id,
              googleCalendarEventId: mirrored.entity.googleCalendarEventId,
              clearGoogleCalendarEventId:
                  mirrored.entity.googleCalendarEventId == null,
              lastModified: item.lastModified,
            );
            pushedUpdated++;
          case AppointmentSyncStatus.pendingDelete:
            final calendarWarningForDelete = await _mirrorDeleteFromCalendar(
              item.googleCalendarEventId ?? remote?.googleCalendarEventId,
            );
            calendarWarning ??= calendarWarningForDelete;
            await _firestore.markAppointmentDeleted(
              user.id,
              syncId: item.syncId,
              deletedAt: item.lastModified,
              googleCalendarEventId: item.googleCalendarEventId,
            );
            await _local.purgeAppointmentById(item.id);
            pushedDeleted++;
          case AppointmentSyncStatus.synced:
            break;
        }
      }

      // 3. Migrate pre-existing synced local appointments not yet present in Firestore.
      final activeLocal = await _local.getAllActiveAppointments();
      for (final item in activeLocal) {
        if (item.syncStatus != AppointmentSyncStatus.synced ||
            handledInQueue.contains(item.syncId) ||
            cloudBySyncId.containsKey(item.syncId)) {
          continue;
        }

        var effective = item;
        if (effective.googleCalendarEventId == null ||
            effective.googleCalendarEventId!.isEmpty) {
          final mirrored = await _mirrorUpsertToCalendar(
            effective,
            requestScopeIfNeeded: interactive,
          );
          calendarWarning ??= mirrored.warning;
          effective = mirrored.entity;
          if (effective.googleCalendarEventId != null) {
            await _local.markAppointmentSynced(
              appointmentId: effective.id,
              googleCalendarEventId: effective.googleCalendarEventId,
              lastModified: effective.lastModified,
            );
          }
        }

        await _firestore.upsertAppointment(
          user.id,
          CloudAppointmentDocument.fromEntity(effective),
        );
        pushedCreated++;
      }

      // 4. Re-apply latest Cloud Firestore state (including any remote deletions).
      final latestCloudDocs = pushedCreated + pushedUpdated + pushedDeleted > 0
          ? await _firestore.fetchAppointments(user.id)
          : cloudDocs;
      final pullStats = await _local.applyCloudAppointments(latestCloudDocs);
      pulledUpserted += pullStats.upserted;
      pulledDeleted += pullStats.deleted;

      // 5. Verify today & upcoming synced appointments exist in the dedicated "Nudge" calendar.
      final verification = await _reconcileScheduledCalendarEvents(
        userId: user.id,
        interactive: interactive,
      );
      calendarBackfilled = verification.backfilled;
      calendarWarning ??= verification.warning;

      final syncedAt = _now().toUtc();
      await _local.saveSyncMetadata(lastSyncTimestamp: syncedAt);

      return SyncResult(
        pushedCreated: pushedCreated,
        pushedUpdated: pushedUpdated,
        pushedDeleted: pushedDeleted,
        pulledUpserted: pulledUpserted,
        pulledDeleted: pulledDeleted,
        calendarBackfilled: calendarBackfilled,
        syncedAt: syncedAt.toLocal(),
        errorMessage: calendarWarning,
      );
    } catch (_) {
      return const SyncResult(
        errorMessage: 'No se pudo completar la sincronización con la nube.',
      );
    }
  }

  Future<({int backfilled, String? warning})>
  _reconcileScheduledCalendarEvents({
    required String userId,
    required bool interactive,
  }) async {
    final nowLocal = _now().toLocal();
    final verificationStart = DateTime(
      nowLocal.year,
      nowLocal.month,
      nowLocal.day,
    );
    final calendarQueryMin = verificationStart.subtract(
      const Duration(days: 1),
    );
    final currentActive = await _local.getAllActiveAppointments();

    final candidatesToVerify = currentActive
        .where(
          (AppointmentEntity appt) =>
              appt.syncStatus == AppointmentSyncStatus.synced &&
              (!appt.startTime.toLocal().isBefore(verificationStart) ||
                  appt.endTime.toLocal().isAfter(verificationStart)),
        )
        .toList(growable: false);

    if (candidatesToVerify.isEmpty) {
      return (backfilled: 0, warning: null);
    }

    final List<CalendarRemoteEvent> remoteEvents;
    try {
      remoteEvents = await _calendar.listActiveEvents(
        timeMin: calendarQueryMin,
        requestScopeIfNeeded: interactive,
      );
    } catch (error) {
      return (backfilled: 0, warning: _describeCalendarError(error));
    }

    final remoteById = <String, CalendarRemoteEvent>{};
    final remoteBySyncId = <String, CalendarRemoteEvent>{};
    for (final event in remoteEvents) {
      if (event.isCancelled) {
        continue;
      }
      remoteById[event.id] = event;
      final syncId = event.nudgeSyncId;
      if (syncId != null && syncId.isNotEmpty) {
        remoteBySyncId.putIfAbsent(syncId, () => event);
      }
    }

    final claimedEventIds = <String>{
      for (final appt in currentActive)
        if (appt.googleCalendarEventId != null &&
            appt.googleCalendarEventId!.trim().isNotEmpty &&
            remoteById.containsKey(appt.googleCalendarEventId!.trim()))
          appt.googleCalendarEventId!.trim(),
    };

    var backfilled = 0;
    String? warning;

    for (final appt in candidatesToVerify) {
      try {
        final updated = await _reconcileSingleCalendarAppointment(
          userId: userId,
          appt: appt,
          interactive: interactive,
          remoteEvents: remoteEvents,
          remoteById: remoteById,
          remoteBySyncId: remoteBySyncId,
          claimedEventIds: claimedEventIds,
        );
        if (updated) {
          backfilled++;
        }
      } on CalendarAuthUnavailableException catch (error) {
        warning ??= _describeCalendarError(error);
        break;
      } on calendar.DetailedApiRequestError catch (error) {
        warning ??= _describeCalendarError(error);
        if (error.status == 401 || error.status == 403) {
          break;
        }
      } catch (error) {
        warning ??= _describeCalendarError(error);
      }
    }

    return (backfilled: backfilled, warning: warning);
  }

  Future<bool> _reconcileSingleCalendarAppointment({
    required String userId,
    required AppointmentEntity appt,
    required bool interactive,
    required List<CalendarRemoteEvent> remoteEvents,
    required Map<String, CalendarRemoteEvent> remoteById,
    required Map<String, CalendarRemoteEvent> remoteBySyncId,
    required Set<String> claimedEventIds,
  }) async {
    final expectedSummary = CalendarEventMetadataCodec.buildEventSummary(
      title: appt.title,
      clientName: appt.clientName,
    );
    final existingId = appt.googleCalendarEventId?.trim();

    if (existingId != null &&
        existingId.isNotEmpty &&
        remoteById.containsKey(existingId)) {
      final remoteEvent = remoteById[existingId]!;
      if (_calendarEventNeedsPatch(remoteEvent, appt, expectedSummary)) {
        await _calendar.patchEvent(appt, requestScopeIfNeeded: interactive);
        return true;
      }
      return false;
    }

    final matchedRemote = _findUnclaimedCalendarMatch(
      appt: appt,
      expectedSummary: expectedSummary,
      remoteEvents: remoteEvents,
      remoteBySyncId: remoteBySyncId,
      claimedEventIds: claimedEventIds,
    );

    if (matchedRemote != null) {
      claimedEventIds.add(matchedRemote.id);
      await _persistReconciledEventId(
        userId: userId,
        appt: appt,
        eventId: matchedRemote.id,
      );
      if (_calendarEventNeedsPatch(matchedRemote, appt, expectedSummary)) {
        await _calendar.patchEvent(
          appt.copyWith(googleCalendarEventId: matchedRemote.id),
          requestScopeIfNeeded: interactive,
        );
        return true;
      }
      return false;
    }

    if (existingId != null && existingId.isNotEmpty) {
      try {
        await _calendar.deleteLegacyPrimaryEvent(existingId);
      } catch (_) {}
    }

    final newEventId = await _calendar.insertEvent(
      appt,
      requestScopeIfNeeded: interactive,
    );
    claimedEventIds.add(newEventId);
    final syntheticRemote = CalendarRemoteEvent(
      id: newEventId,
      status: 'confirmed',
      summary: expectedSummary,
      startTime: appt.startTime,
      endTime: appt.endTime,
      nudgeSyncId: appt.syncId,
    );
    remoteById[newEventId] = syntheticRemote;
    remoteBySyncId[appt.syncId] = syntheticRemote;

    await _persistReconciledEventId(
      userId: userId,
      appt: appt,
      eventId: newEventId,
    );
    return true;
  }

  CalendarRemoteEvent? _findUnclaimedCalendarMatch({
    required AppointmentEntity appt,
    required String expectedSummary,
    required List<CalendarRemoteEvent> remoteEvents,
    required Map<String, CalendarRemoteEvent> remoteBySyncId,
    required Set<String> claimedEventIds,
  }) {
    final bySyncId = remoteBySyncId[appt.syncId];
    if (bySyncId != null && !claimedEventIds.contains(bySyncId.id)) {
      return bySyncId;
    }

    for (final event in remoteEvents) {
      if (event.isCancelled || claimedEventIds.contains(event.id)) {
        continue;
      }
      if (event.nudgeSyncId != null && event.nudgeSyncId!.isNotEmpty) {
        continue;
      }
      if (event.summary == expectedSummary &&
          event.startTime != null &&
          event.endTime != null &&
          _sameUnixSecond(event.startTime!, appt.startTime) &&
          _sameUnixSecond(event.endTime!, appt.endTime)) {
        return event;
      }
    }
    return null;
  }

  bool _calendarEventNeedsPatch(
    CalendarRemoteEvent remoteEvent,
    AppointmentEntity appt,
    String expectedSummary,
  ) {
    return remoteEvent.summary != expectedSummary ||
        remoteEvent.startTime == null ||
        remoteEvent.endTime == null ||
        !_sameUnixSecond(remoteEvent.startTime!, appt.startTime) ||
        !_sameUnixSecond(remoteEvent.endTime!, appt.endTime);
  }

  Future<void> _persistReconciledEventId({
    required String userId,
    required AppointmentEntity appt,
    required String eventId,
  }) async {
    final updated = await _local.markAppointmentSynced(
      appointmentId: appt.id,
      googleCalendarEventId: eventId,
      lastModified: appt.lastModified,
    );
    await _firestore.upsertAppointment(
      userId,
      CloudAppointmentDocument.fromEntity(
        updated ?? appt.copyWith(googleCalendarEventId: eventId),
      ),
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serialQueue = _serialQueue.then((_) async {
      try {
        final result = await action();
        if (!completer.isCompleted) {
          completer.complete(result);
        }
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }
    });
    return completer.future;
  }

  Future<({AppointmentEntity entity, String? warning})> _mirrorUpsertToCalendar(
    AppointmentEntity entity, {
    bool requestScopeIfNeeded = false,
  }) async {
    try {
      final eventId = entity.googleCalendarEventId;
      if (eventId == null || eventId.isEmpty) {
        final remoteId = await _calendar.insertEvent(
          entity,
          requestScopeIfNeeded: requestScopeIfNeeded,
        );
        return (
          entity: entity.copyWith(googleCalendarEventId: remoteId),
          warning: null,
        );
      }

      try {
        await _calendar.patchEvent(
          entity,
          requestScopeIfNeeded: requestScopeIfNeeded,
        );
        return (entity: entity, warning: null);
      } on calendar.DetailedApiRequestError catch (error) {
        if (error.status == 404 || error.status == 410) {
          final remoteId = await _calendar.insertEvent(
            entity,
            requestScopeIfNeeded: requestScopeIfNeeded,
          );
          return (
            entity: entity.copyWith(googleCalendarEventId: remoteId),
            warning: null,
          );
        }
        rethrow;
      }
    } on CalendarAuthUnavailableException catch (error) {
      return (entity: entity, warning: _describeCalendarError(error));
    } on calendar.DetailedApiRequestError catch (error) {
      if (error.status == 403 || error.status == 401) {
        return (entity: entity, warning: _describeCalendarError(error));
      }
      return (entity: entity, warning: null);
    } catch (_) {
      return (entity: entity, warning: null);
    }
  }

  String _describeCalendarError(Object error) {
    if (error is CalendarAuthUnavailableException) {
      return 'Firestore sincronizado, pero falta permiso de Google Calendar.';
    }
    if (error is calendar.DetailedApiRequestError) {
      if (error.status == 403) {
        return 'Firestore sincronizado; Google Calendar API sin permisos (HTTP 403).';
      }
      if (error.status == 401) {
        return 'Firestore sincronizado; sesión de Google Calendar expirada (HTTP 401).';
      }
      return 'Firestore sincronizado, pero no se pudo verificar Google Calendar (HTTP ${error.status}).';
    }
    return 'Firestore sincronizado, pero no se pudo verificar Google Calendar.';
  }

  Future<String?> _mirrorDeleteFromCalendar(String? eventId) async {
    if (eventId == null || eventId.isEmpty) {
      return null;
    }
    try {
      await _calendar.deleteEvent(eventId);
      return null;
    } on CalendarAuthUnavailableException {
      return 'Firestore sincronizado, pero falta permiso de Google Calendar.';
    } on calendar.DetailedApiRequestError catch (error) {
      if (error.status == 404 || error.status == 410) {
        return null;
      }
      if (error.status == 403 || error.status == 401) {
        return 'Firestore sincronizado; error de permisos en Google Calendar (HTTP ${error.status}).';
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<AuthUser?> _canAttemptRemoteSync() async {
    if (!await _connectivity.isOnline) {
      return null;
    }
    return _ensureSignedInUser();
  }

  Future<AuthUser?> _ensureSignedInUser() async {
    final current = _auth.currentUser;
    if (current != null && current.id.isNotEmpty) {
      return current;
    }
    try {
      final restored = await _auth.signInSilently();
      if (restored != null && restored.id.isNotEmpty) {
        return restored;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  bool _secondsAfter(DateTime a, DateTime b) {
    return (a.toUtc().millisecondsSinceEpoch ~/ 1000) >
        (b.toUtc().millisecondsSinceEpoch ~/ 1000);
  }

  bool _sameUnixSecond(DateTime a, DateTime b) {
    return (a.toUtc().millisecondsSinceEpoch ~/ 1000) ==
        (b.toUtc().millisecondsSinceEpoch ~/ 1000);
  }

  DateTime _truncateToSecondsUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      (utc.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
  }
}
