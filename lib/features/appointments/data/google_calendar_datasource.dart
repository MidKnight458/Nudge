import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

/// Thrown when Google Calendar API rejects an incremental `syncToken` (`410`).
class SyncTokenExpiredException implements Exception {
  const SyncTokenExpiredException();

  @override
  String toString() => 'Google Calendar syncToken expired (HTTP 410 Gone).';
}

/// Thrown when no authenticated Calendar API client is available.
class CalendarAuthUnavailableException implements Exception {
  const CalendarAuthUnavailableException();

  @override
  String toString() => 'Authenticated Google Calendar client unavailable.';
}

/// Normalized representation of a Google Calendar event returned by delta sync.
class CalendarRemoteEvent {
  const CalendarRemoteEvent({
    required this.id,
    required this.status,
    this.summary,
    this.description,
    this.startTime,
    this.endTime,
  });

  final String id;
  final String status;
  final String? summary;
  final String? description;
  final DateTime? startTime;
  final DateTime? endTime;

  bool get isCancelled => status == 'cancelled';
}

/// Aggregated result of listing all pages of a Google Calendar delta query.
class CalendarDeltaPage {
  const CalendarDeltaPage({required this.events, this.nextSyncToken});

  final List<CalendarRemoteEvent> events;
  final String? nextSyncToken;
}

/// Remote data source contract for Google Calendar v3 operations targeting the
/// dedicated secondary "Nudge" calendar.
abstract interface class GoogleCalendarDatasource {
  Future<String> ensureNudgeCalendar({bool requestScopeIfNeeded = false});

  Future<void> shareNudgeCalendarWithEmail(
    String email, {
    String role = 'reader',
  });

  Future<String> insertEvent(AppointmentEntity appointment);

  Future<void> patchEvent(AppointmentEntity appointment);

  Future<void> deleteEvent(String googleCalendarEventId);

  Future<CalendarDeltaPage> listEventsDelta({
    String? syncToken,
    DateTime? timeMin,
  });
}

/// Google Calendar API v3 implementation using an authenticated OAuth client
/// targeting a dedicated secondary "Nudge" calendar so events stay isolated
/// from personal events and can be shared read-only across accounts.
class GoogleCalendarDatasourceImpl implements GoogleCalendarDatasource {
  GoogleCalendarDatasourceImpl(this._authRepository);

  final AuthRepository _authRepository;

  String? _cachedCalendarId;
  String? _cachedOwnerUid;
  Future<String>? _pendingCalendarResolution;

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  /// Returns whether [raw] looks like a valid email address.
  static bool isValidEmail(String raw) {
    final trimmed = raw.trim();
    return trimmed.isNotEmpty && _emailPattern.hasMatch(trimmed);
  }

  /// Selects the owned, non-primary, non-deleted "Nudge" calendar ID from
  /// [entries], or `null` if none exists yet.
  static String? findOwnedNudgeCalendarId(
    Iterable<calendar.CalendarListEntry> entries,
  ) {
    final targetName = AppConstants.nudgeCalendarName.trim().toLowerCase();
    for (final entry in entries) {
      if (entry.deleted == true || entry.primary == true) {
        continue;
      }
      if (entry.accessRole != 'owner') {
        continue;
      }
      final summary = entry.summary?.trim().toLowerCase();
      final id = entry.id?.trim();
      if (summary == targetName && id != null && id.isNotEmpty) {
        return id;
      }
    }
    return null;
  }

  void _invalidateCache() {
    _cachedCalendarId = null;
    _cachedOwnerUid = null;
  }

  Future<String> _resolveNudgeCalendarId(calendar.CalendarApi api) async {
    final currentUid = _authRepository.currentUser?.id;
    if (_cachedCalendarId != null && _cachedOwnerUid == currentUid) {
      return _cachedCalendarId!;
    }
    if (_cachedOwnerUid != currentUid) {
      _invalidateCache();
    }

    final existingFuture = _pendingCalendarResolution;
    if (existingFuture != null) {
      return existingFuture;
    }

    final future = _findOrCreateNudgeCalendarId(api, currentUid);
    _pendingCalendarResolution = future;
    future.whenComplete(() {
      if (identical(_pendingCalendarResolution, future)) {
        _pendingCalendarResolution = null;
      }
    });
    return future;
  }

  Future<String> _findOrCreateNudgeCalendarId(
    calendar.CalendarApi api,
    String? ownerUid,
  ) async {
    String? pageToken;
    do {
      final response = await api.calendarList.list(
        minAccessRole: 'owner',
        pageToken: pageToken,
      );
      final foundId = findOwnedNudgeCalendarId(
        response.items ?? const <calendar.CalendarListEntry>[],
      );
      if (foundId != null) {
        _cachedCalendarId = foundId;
        _cachedOwnerUid = ownerUid;
        return foundId;
      }
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    final created = await api.calendars.insert(
      calendar.Calendar(
        summary: AppConstants.nudgeCalendarName,
        description: AppConstants.nudgeCalendarDescription,
      ),
    );
    final createdId = created.id?.trim();
    if (createdId == null || createdId.isEmpty) {
      throw StateError('Google Calendar did not return a valid calendar ID.');
    }

    _cachedCalendarId = createdId;
    _cachedOwnerUid = ownerUid;
    return createdId;
  }

  @override
  Future<String> ensureNudgeCalendar({bool requestScopeIfNeeded = false}) {
    return _withClient((calendar.CalendarApi api) {
      return _resolveNudgeCalendarId(api);
    }, requestScopeIfNeeded: requestScopeIfNeeded);
  }

  @override
  Future<void> shareNudgeCalendarWithEmail(
    String email, {
    String role = 'reader',
  }) async {
    final cleanEmail = email.trim();
    if (!isValidEmail(cleanEmail)) {
      throw ArgumentError.value(email, 'email', 'Correo electrónico inválido.');
    }

    await _withClient((calendar.CalendarApi api) async {
      final calendarId = await _resolveNudgeCalendarId(api);
      await api.acl.insert(
        calendar.AclRule(
          role: role,
          scope: calendar.AclRuleScope(type: 'user', value: cleanEmail),
        ),
        calendarId,
        sendNotifications: true,
      );
    }, requestScopeIfNeeded: true);
  }

  @override
  Future<String> insertEvent(AppointmentEntity appointment) async {
    return _withClient((calendar.CalendarApi api) async {
      final event = _toCalendarEvent(appointment);
      var calendarId = await _resolveNudgeCalendarId(api);
      calendar.Event created;
      try {
        created = await api.events.insert(event, calendarId);
      } on calendar.DetailedApiRequestError catch (error) {
        if (error.status != 404) {
          rethrow;
        }
        _invalidateCache();
        calendarId = await _resolveNudgeCalendarId(api);
        created = await api.events.insert(event, calendarId);
      }

      final eventId = created.id;
      if (eventId == null || eventId.isEmpty) {
        throw StateError('Google Calendar insert returned an empty event ID.');
      }
      return eventId;
    });
  }

  @override
  Future<void> patchEvent(AppointmentEntity appointment) async {
    final eventId = appointment.googleCalendarEventId;
    if (eventId == null || eventId.isEmpty) {
      throw ArgumentError('Cannot patch event without googleCalendarEventId.');
    }

    await _withClient((calendar.CalendarApi api) async {
      final calendarId = await _resolveNudgeCalendarId(api);
      try {
        await api.events.patch(
          _toCalendarEvent(appointment),
          calendarId,
          eventId,
        );
      } on calendar.DetailedApiRequestError catch (error) {
        if (error.status == 404) {
          // Clean up any legacy pre-v1.4 event stored on primary before caller
          // re-inserts into the dedicated Nudge calendar.
          try {
            await api.events.delete(AppConstants.primaryCalendarId, eventId);
          } catch (_) {}
        }
        rethrow;
      }
    });
  }

  @override
  Future<void> deleteEvent(String googleCalendarEventId) async {
    await _withClient((calendar.CalendarApi api) async {
      final calendarId = await _resolveNudgeCalendarId(api);
      try {
        await api.events.delete(calendarId, googleCalendarEventId);
      } on calendar.DetailedApiRequestError catch (error) {
        if (error.status != 404 && error.status != 410) {
          rethrow;
        }
        // Fallback cleanup for legacy pre-v1.4 events on primary calendar.
        try {
          await api.events.delete(
            AppConstants.primaryCalendarId,
            googleCalendarEventId,
          );
        } on calendar.DetailedApiRequestError catch (primaryError) {
          if (primaryError.status != 404 && primaryError.status != 410) {
            rethrow;
          }
        }
      }
    });
  }

  @override
  Future<CalendarDeltaPage> listEventsDelta({
    String? syncToken,
    DateTime? timeMin,
  }) async {
    return _withClient((calendar.CalendarApi api) async {
      final calendarId = await _resolveNudgeCalendarId(api);
      final collected = <CalendarRemoteEvent>[];
      String? pageToken;
      String? nextSyncToken;

      try {
        do {
          final response = await api.events.list(
            calendarId,
            syncToken: syncToken,
            timeMin: syncToken == null ? timeMin?.toUtc() : null,
            showDeleted: true,
            pageToken: pageToken,
          );

          for (final item in response.items ?? const <calendar.Event>[]) {
            final mapped = _fromCalendarEvent(item);
            if (mapped != null) {
              collected.add(mapped);
            }
          }

          pageToken = response.nextPageToken;
          if (response.nextSyncToken != null &&
              response.nextSyncToken!.isNotEmpty) {
            nextSyncToken = response.nextSyncToken;
          }
        } while (pageToken != null && pageToken.isNotEmpty);
      } on calendar.DetailedApiRequestError catch (error) {
        if (error.status == 410 || (syncToken != null && error.status == 400)) {
          throw const SyncTokenExpiredException();
        }
        rethrow;
      }

      return CalendarDeltaPage(events: collected, nextSyncToken: nextSyncToken);
    });
  }

  Future<T> _withClient<T>(
    Future<T> Function(calendar.CalendarApi api) action, {
    bool requestScopeIfNeeded = false,
  }) async {
    Future<T> runAttempt({required bool requestScope}) async {
      final handle = await _authRepository.openCalendarClient(
        requestScopeIfNeeded: requestScope,
      );
      if (handle == null) {
        throw const CalendarAuthUnavailableException();
      }
      try {
        return await action(handle.api);
      } finally {
        handle.close();
      }
    }

    try {
      return await runAttempt(requestScope: requestScopeIfNeeded);
    } on calendar.DetailedApiRequestError catch (error) {
      if ((error.status == 401 || error.status == 403) &&
          !requestScopeIfNeeded) {
        return runAttempt(requestScope: true);
      }
      rethrow;
    }
  }

  calendar.Event _toCalendarEvent(AppointmentEntity appointment) {
    final summary = CalendarEventMetadataCodec.buildEventSummary(
      title: appointment.title,
      clientName: appointment.clientName,
    );
    final description = CalendarEventMetadataCodec.encodeDescription(
      clientName: appointment.clientName,
      clientPhoneE164: appointment.clientPhoneE164,
      title: appointment.title,
      notes: appointment.notes,
    );

    return calendar.Event(
      summary: summary,
      description: description,
      start: calendar.EventDateTime(dateTime: appointment.startTime.toUtc()),
      end: calendar.EventDateTime(dateTime: appointment.endTime.toUtc()),
    );
  }

  CalendarRemoteEvent? _fromCalendarEvent(calendar.Event event) {
    final id = event.id;
    if (id == null || id.isEmpty) {
      return null;
    }

    final status = event.status ?? 'confirmed';
    if (status == 'cancelled') {
      return CalendarRemoteEvent(id: id, status: status);
    }

    final start = event.start?.dateTime ?? event.start?.date;
    if (start == null) {
      return null;
    }

    var end = event.end?.dateTime ?? event.end?.date;
    if (end == null || !end.isAfter(start)) {
      end = start.add(AppConstants.defaultAppointmentDuration);
    }

    return CalendarRemoteEvent(
      id: id,
      status: status,
      summary: event.summary,
      description: event.description,
      startTime: start.toLocal(),
      endTime: end.toLocal(),
    );
  }
}
