import 'dart:async';

import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/google_calendar_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

/// Offline-first repository coordinating Drift SQLite and Google Calendar v3.
class AppointmentsRepositoryImpl implements AppointmentsRepository {
  AppointmentsRepositoryImpl({
    required LocalAppointmentsDatasource localDatasource,
    required GoogleCalendarDatasource remoteDatasource,
    required ConnectivityService connectivityService,
    required AuthRepository authRepository,
    DateTime Function()? nowProvider,
  })  : _local = localDatasource,
        _remote = remoteDatasource,
        _connectivity = connectivityService,
        _auth = authRepository,
        _now = nowProvider ?? DateTime.now;

  final LocalAppointmentsDatasource _local;
  final GoogleCalendarDatasource _remote;
  final ConnectivityService _connectivity;
  final AuthRepository _auth;
  final DateTime Function() _now;

  Future<SyncResult>? _inFlightSync;

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
  Stream<int> watchPendingSyncCount() => _local.watchPendingSyncCount();

  @override
  Future<DateTime?> getLastSyncTimestamp() async {
    final metadata = await _local.getSyncMetadata();
    return metadata.lastSyncTimestamp?.toLocal();
  }

  @override
  Future<AppointmentEntity> createAppointment(AppointmentInput input) async {
    final created = await _local.createAppointmentOffline(input);
    if (await _canAttemptRemoteSync()) {
      try {
        final remoteId = await _remote.insertEvent(created);
        final synced = await _local.markAppointmentSynced(
          appointmentId: created.id,
          googleCalendarEventId: remoteId,
        );
        if (synced != null) {
          return synced;
        }
      } catch (_) {
        // Remains queued as `pending_create` in SQLite until next sync pass.
      }
    }
    return created;
  }

  @override
  Future<AppointmentEntity> updateAppointment(
    AppointmentEntity existing,
    AppointmentInput input,
  ) async {
    final updated = await _local.updateAppointmentOffline(existing, input);
    if (await _canAttemptRemoteSync()) {
      try {
        if (updated.googleCalendarEventId == null ||
            updated.googleCalendarEventId!.isEmpty) {
          final remoteId = await _remote.insertEvent(updated);
          final synced = await _local.markAppointmentSynced(
            appointmentId: updated.id,
            googleCalendarEventId: remoteId,
          );
          if (synced != null) {
            return synced;
          }
        } else {
          await _remote.patchEvent(updated);
          final synced = await _local.markAppointmentSynced(
            appointmentId: updated.id,
            googleCalendarEventId: updated.googleCalendarEventId!,
          );
          if (synced != null) {
            return synced;
          }
        }
      } catch (_) {
        // Remains queued as pending in SQLite until next sync pass.
      }
    }
    return updated;
  }

  @override
  Future<void> deleteAppointment(AppointmentEntity appointment) async {
    final needsRemoteDelete =
        await _local.markAppointmentDeletedOffline(appointment.id);
    if (!needsRemoteDelete) {
      return;
    }

    final eventId = appointment.googleCalendarEventId;
    if (eventId != null &&
        eventId.isNotEmpty &&
        await _canAttemptRemoteSync()) {
      try {
        await _remote.deleteEvent(eventId);
        await _local.purgeAppointmentById(appointment.id);
      } catch (_) {
        // Remains queued as `pending_delete` until connectivity returns.
      }
    }
  }

  @override
  Future<void> markReminderSent(int appointmentId, {bool sent = true}) {
    return _local.markReminderSent(appointmentId, sent: sent);
  }

  /// Clears stored incremental `syncToken` when changing Google accounts.
  Future<void> resetSyncMetadata() {
    return _local.clearSyncToken(clearTimestamp: true);
  }

  @override
  Future<SyncResult> synchronize() {
    final existing = _inFlightSync;
    if (existing != null) {
      return existing;
    }

    final future = _runSynchronize();
    _inFlightSync = future;
    future.whenComplete(() {
      if (identical(_inFlightSync, future)) {
        _inFlightSync = null;
      }
    });
    return future;
  }

  Future<SyncResult> _runSynchronize() async {
    if (!await _connectivity.isOnline) {
      return const SyncResult(skippedReason: 'Sin conexión a internet.');
    }

    final hasAuth = await _ensureSignedIn();
    if (!hasAuth) {
      return const SyncResult(
        skippedReason: 'Inicia sesión con Google para sincronizar.',
      );
    }

    var pushedCreated = 0;
    var pushedUpdated = 0;
    var pushedDeleted = 0;
    var pulledUpserted = 0;
    var pulledDeleted = 0;
    var usedFullResync = false;

    try {
      // 1. Drain local offline mutation queue first.
      final pending = await _local.getPendingSyncAppointments();
      for (final item in pending) {
        switch (item.syncStatus) {
          case AppointmentSyncStatus.pendingCreate:
            final remoteId = await _remote.insertEvent(item);
            await _local.markAppointmentSynced(
              appointmentId: item.id,
              googleCalendarEventId: remoteId,
            );
            pushedCreated++;
          case AppointmentSyncStatus.pendingUpdate:
            if (item.googleCalendarEventId == null ||
                item.googleCalendarEventId!.isEmpty) {
              final remoteId = await _remote.insertEvent(item);
              await _local.markAppointmentSynced(
                appointmentId: item.id,
                googleCalendarEventId: remoteId,
              );
            } else {
              await _remote.patchEvent(item);
              await _local.markAppointmentSynced(
                appointmentId: item.id,
                googleCalendarEventId: item.googleCalendarEventId!,
              );
            }
            pushedUpdated++;
          case AppointmentSyncStatus.pendingDelete:
            final eventId = item.googleCalendarEventId;
            if (eventId != null && eventId.isNotEmpty) {
              await _remote.deleteEvent(eventId);
            }
            await _local.purgeAppointmentById(item.id);
            pushedDeleted++;
          case AppointmentSyncStatus.synced:
            break;
        }
      }

      // 2. Pull incremental changes from Google Calendar (with 410 recovery).
      final metadata = await _local.getSyncMetadata();
      var syncToken = metadata.syncToken;
      CalendarDeltaPage deltaPage;

      try {
        deltaPage = await _remote.listEventsDelta(
          syncToken: syncToken,
          timeMin: syncToken == null
              ? _now().subtract(AppConstants.initialSyncLookback)
              : null,
        );
      } on SyncTokenExpiredException {
        await _local.clearSyncToken();
        syncToken = null;
        usedFullResync = true;
        deltaPage = await _remote.listEventsDelta(
          syncToken: null,
          timeMin: _now().subtract(AppConstants.initialSyncLookback),
        );
      }

      for (final remoteEvent in deltaPage.events) {
        if (remoteEvent.isCancelled) {
          final removed = await _local.deleteByGoogleEventId(remoteEvent.id);
          if (removed) {
            pulledDeleted++;
          }
          continue;
        }

        final start = remoteEvent.startTime;
        final end = remoteEvent.endTime;
        if (start == null || end == null) {
          continue;
        }

        final changed = await _local.upsertFromRemoteEvent(
          googleEventId: remoteEvent.id,
          summary: remoteEvent.summary,
          description: remoteEvent.description,
          startTime: start,
          endTime: end,
        );
        if (changed) {
          pulledUpserted++;
        }
      }

      final syncedAt = _now().toUtc();
      await _local.saveSyncMetadata(
        syncToken: deltaPage.nextSyncToken ?? syncToken,
        lastSyncTimestamp: syncedAt,
      );

      return SyncResult(
        pushedCreated: pushedCreated,
        pushedUpdated: pushedUpdated,
        pushedDeleted: pushedDeleted,
        pulledUpserted: pulledUpserted,
        pulledDeleted: pulledDeleted,
        usedFullResync: usedFullResync,
        syncedAt: syncedAt.toLocal(),
      );
    } on CalendarAuthUnavailableException {
      return const SyncResult(
        skippedReason: 'Sesión de Google Calendar expirada o sin permisos.',
      );
    } catch (_) {
      return const SyncResult(
        errorMessage: 'No se pudo completar la sincronización con Calendar.',
      );
    }
  }

  Future<bool> _canAttemptRemoteSync() async {
    if (!await _connectivity.isOnline) {
      return false;
    }
    return _ensureSignedIn();
  }

  Future<bool> _ensureSignedIn() async {
    if (_auth.currentUser != null) {
      return true;
    }
    try {
      final restored = await _auth.signInSilently();
      return restored != null;
    } catch (_) {
      return false;
    }
  }
}
