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

/// Remote data source contract for Google Calendar v3 operations.
abstract interface class GoogleCalendarDatasource {
  Future<String> insertEvent(AppointmentEntity appointment);

  Future<void> patchEvent(AppointmentEntity appointment);

  Future<void> deleteEvent(String googleCalendarEventId);

  Future<CalendarDeltaPage> listEventsDelta({
    String? syncToken,
    DateTime? timeMin,
  });
}

/// Google Calendar API v3 implementation using an authenticated OAuth client.
class GoogleCalendarDatasourceImpl implements GoogleCalendarDatasource {
  GoogleCalendarDatasourceImpl(this._authRepository);

  final AuthRepository _authRepository;

  @override
  Future<String> insertEvent(AppointmentEntity appointment) async {
    return _withClient((calendar.CalendarApi api) async {
      final created = await api.events.insert(
        _toCalendarEvent(appointment),
        AppConstants.primaryCalendarId,
      );
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
      await api.events.patch(
        _toCalendarEvent(appointment),
        AppConstants.primaryCalendarId,
        eventId,
      );
    });
  }

  @override
  Future<void> deleteEvent(String googleCalendarEventId) async {
    await _withClient((calendar.CalendarApi api) async {
      try {
        await api.events.delete(
          AppConstants.primaryCalendarId,
          googleCalendarEventId,
        );
      } on calendar.DetailedApiRequestError catch (error) {
        // Treat already-deleted events as successfully removed remotely.
        if (error.status != 404 && error.status != 410) {
          rethrow;
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
      final collected = <CalendarRemoteEvent>[];
      String? pageToken;
      String? nextSyncToken;

      try {
        do {
          final response = await api.events.list(
            AppConstants.primaryCalendarId,
            syncToken: syncToken,
            timeMin: syncToken == null ? timeMin?.toUtc() : null,
            showDeleted: true,
            singleEvents: syncToken == null && timeMin != null ? true : null,
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
        if (error.status == 410) {
          throw const SyncTokenExpiredException();
        }
        rethrow;
      }

      return CalendarDeltaPage(events: collected, nextSyncToken: nextSyncToken);
    });
  }

  Future<T> _withClient<T>(
    Future<T> Function(calendar.CalendarApi api) action,
  ) async {
    final handle = await _authRepository.openCalendarClient();
    if (handle == null) {
      throw const CalendarAuthUnavailableException();
    }
    try {
      return await action(handle.api);
    } finally {
      handle.close();
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
