import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';

/// Synchronization state for an appointment stored in SQLite.
enum AppointmentSyncStatus {
  synced(AppConstants.syncStatusSynced),
  pendingCreate(AppConstants.syncStatusPendingCreate),
  pendingUpdate(AppConstants.syncStatusPendingUpdate),
  pendingDelete(AppConstants.syncStatusPendingDelete);

  const AppointmentSyncStatus(this.dbValue);

  final String dbValue;

  bool get isPending => this != AppointmentSyncStatus.synced;

  static AppointmentSyncStatus fromDbValue(String value) {
    for (final status in AppointmentSyncStatus.values) {
      if (status.dbValue == value) {
        return status;
      }
    }
    return AppointmentSyncStatus.synced;
  }
}

/// Complete domain view of an appointment joined with its client.
class AppointmentEntity {
  const AppointmentEntity({
    required this.id,
    this.googleCalendarEventId,
    required this.clientId,
    required this.clientName,
    required this.clientRawPhone,
    required this.clientPhoneE164,
    this.clientGoogleContactId,
    required this.title,
    this.notes,
    required this.startTime,
    required this.endTime,
    required this.reminderSent,
    required this.syncStatus,
    required this.lastModified,
  });

  final int id;
  final String? googleCalendarEventId;
  final int clientId;
  final String clientName;
  final String clientRawPhone;
  final String clientPhoneE164;
  final String? clientGoogleContactId;
  final String title;
  final String? notes;
  final DateTime startTime;
  final DateTime endTime;
  final bool reminderSent;
  final AppointmentSyncStatus syncStatus;
  final DateTime lastModified;

  bool get hasValidWhatsAppPhone => clientPhoneE164.isNotEmpty;

  AppointmentEntity copyWith({
    int? id,
    String? googleCalendarEventId,
    bool clearGoogleCalendarEventId = false,
    int? clientId,
    String? clientName,
    String? clientRawPhone,
    String? clientPhoneE164,
    String? clientGoogleContactId,
    String? title,
    String? notes,
    bool clearNotes = false,
    DateTime? startTime,
    DateTime? endTime,
    bool? reminderSent,
    AppointmentSyncStatus? syncStatus,
    DateTime? lastModified,
  }) {
    return AppointmentEntity(
      id: id ?? this.id,
      googleCalendarEventId: clearGoogleCalendarEventId
          ? null
          : (googleCalendarEventId ?? this.googleCalendarEventId),
      clientId: clientId ?? this.clientId,
      clientName: clientName ?? this.clientName,
      clientRawPhone: clientRawPhone ?? this.clientRawPhone,
      clientPhoneE164: clientPhoneE164 ?? this.clientPhoneE164,
      clientGoogleContactId:
          clientGoogleContactId ?? this.clientGoogleContactId,
      title: title ?? this.title,
      notes: clearNotes ? null : (notes ?? this.notes),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      reminderSent: reminderSent ?? this.reminderSent,
      syncStatus: syncStatus ?? this.syncStatus,
      lastModified: lastModified ?? this.lastModified,
    );
  }
}

/// Decoded structured metadata extracted from a Google Calendar event.
class DecodedCalendarMetadata {
  const DecodedCalendarMetadata({
    required this.title,
    required this.clientName,
    required this.clientPhoneE164,
    this.notes,
  });

  final String title;
  final String clientName;
  final String clientPhoneE164;
  final String? notes;
}

/// Encodes and decodes discrete `[Nudge]` client metadata inside Google Calendar
/// event descriptions so appointments can be reconstructed losslessly.
abstract final class CalendarEventMetadataCodec {
  static const String _summarySeparator = ' — ';
  static const String _serviceKey = 'servicio:';

  /// Builds the event summary shown in Google Calendar.
  static String buildEventSummary({
    required String title,
    required String clientName,
  }) {
    final cleanTitle = title.trim();
    final cleanClient = clientName.trim();
    if (cleanClient.isEmpty) {
      return cleanTitle;
    }
    return '$cleanTitle$_summarySeparator$cleanClient';
  }

  /// Serializes user notes and discrete `[Nudge]` client metadata.
  static String encodeDescription({
    required String clientName,
    required String clientPhoneE164,
    required String title,
    String? notes,
  }) {
    final cleanNotes = stripMetadata(notes);
    final metadataLines = <String>[
      AppConstants.metadataHeader,
      '${AppConstants.metadataClientKey} ${clientName.trim()}',
      '${AppConstants.metadataPhoneKey} ${clientPhoneE164.trim()}',
      '$_serviceKey ${title.trim()}',
    ].join('\n');

    if (cleanNotes == null || cleanNotes.isEmpty) {
      return metadataLines;
    }
    return '$cleanNotes\n\n$metadataLines';
  }

  /// Strips any embedded `[Nudge]` block from [description].
  static String? stripMetadata(String? description) {
    if (description == null) {
      return null;
    }
    final markerIndex = description.indexOf(AppConstants.metadataHeader);
    if (markerIndex == -1) {
      final trimmed = description.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final beforeMarker = description.substring(0, markerIndex).trim();
    return beforeMarker.isEmpty ? null : beforeMarker;
  }

  /// Reconstructs appointment title, client info, and clean notes from a
  /// Google Calendar event `summary` and `description`.
  static DecodedCalendarMetadata decodeEvent({
    required String? summary,
    required String? description,
  }) {
    final rawSummary = (summary ?? '').trim();
    final cleanNotes = stripMetadata(description);

    String? parsedClient;
    String? parsedPhone;
    String? parsedService;

    if (description != null) {
      final markerIndex = description.indexOf(AppConstants.metadataHeader);
      if (markerIndex != -1) {
        final block = description.substring(markerIndex);
        for (final rawLine in block.split('\n')) {
          final line = rawLine.trim();
          if (line.startsWith(AppConstants.metadataClientKey)) {
            parsedClient = line
                .substring(AppConstants.metadataClientKey.length)
                .trim();
          } else if (line.startsWith(AppConstants.metadataPhoneKey)) {
            final candidate = line
                .substring(AppConstants.metadataPhoneKey.length)
                .trim();
            parsedPhone =
                PhoneSanitizer.sanitizeToE164Digits(candidate) ??
                candidate.replaceAll(RegExp(r'[^0-9]'), '');
          } else if (line.startsWith(_serviceKey)) {
            parsedService = line.substring(_serviceKey.length).trim();
          }
        }
      }
    }

    final resolvedClient = (parsedClient != null && parsedClient.isNotEmpty)
        ? parsedClient
        : 'Google Calendar';

    String resolvedTitle;
    if (parsedService != null && parsedService.isNotEmpty) {
      resolvedTitle = parsedService;
    } else if (rawSummary.isNotEmpty) {
      final suffix = '$_summarySeparator$resolvedClient';
      if (parsedClient != null && rawSummary.endsWith(suffix)) {
        resolvedTitle = rawSummary
            .substring(0, rawSummary.length - suffix.length)
            .trim();
      } else {
        resolvedTitle = rawSummary;
      }
    } else {
      resolvedTitle = 'Cita';
    }

    return DecodedCalendarMetadata(
      title: resolvedTitle,
      clientName: resolvedClient,
      clientPhoneE164: parsedPhone ?? '',
      notes: cleanNotes,
    );
  }
}
