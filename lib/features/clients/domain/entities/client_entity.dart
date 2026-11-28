import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Client / patient profile persisted locally and synced with Cloud Firestore.
class ClientEntity {
  const ClientEntity({
    required this.id,
    required this.syncId,
    this.googleContactId,
    required this.name,
    required this.rawPhone,
    required this.phoneE164,
    this.generalNotes,
    required this.syncStatus,
    required this.lastModified,
    this.appointmentCount = 0,
    this.attachmentCount = 0,
  });

  final int id;
  final String syncId;
  final String? googleContactId;
  final String name;
  final String rawPhone;
  final String phoneE164;
  final String? generalNotes;
  final AppointmentSyncStatus syncStatus;
  final DateTime lastModified;
  final int appointmentCount;
  final int attachmentCount;

  bool get hasValidWhatsAppPhone => phoneE164.isNotEmpty;

  ClientEntity copyWith({
    int? id,
    String? syncId,
    String? googleContactId,
    String? name,
    String? rawPhone,
    String? phoneE164,
    String? generalNotes,
    bool clearGeneralNotes = false,
    AppointmentSyncStatus? syncStatus,
    DateTime? lastModified,
    int? appointmentCount,
    int? attachmentCount,
  }) {
    return ClientEntity(
      id: id ?? this.id,
      syncId: syncId ?? this.syncId,
      googleContactId: googleContactId ?? this.googleContactId,
      name: name ?? this.name,
      rawPhone: rawPhone ?? this.rawPhone,
      phoneE164: phoneE164 ?? this.phoneE164,
      generalNotes: clearGeneralNotes
          ? null
          : (generalNotes ?? this.generalNotes),
      syncStatus: syncStatus ?? this.syncStatus,
      lastModified: lastModified ?? this.lastModified,
      appointmentCount: appointmentCount ?? this.appointmentCount,
      attachmentCount: attachmentCount ?? this.attachmentCount,
    );
  }
}

/// File attachment (image or PDF) attached to a client profile.
class ClientAttachmentEntity {
  const ClientAttachmentEntity({
    required this.id,
    required this.syncId,
    required this.clientId,
    required this.clientSyncId,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    this.localPath,
    this.driveFileId,
    required this.syncStatus,
    required this.createdAt,
    required this.lastModified,
  });

  final int id;
  final String syncId;
  final int clientId;
  final String clientSyncId;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String? localPath;
  final String? driveFileId;
  final AppointmentSyncStatus syncStatus;
  final DateTime createdAt;
  final DateTime lastModified;

  bool get isImage {
    final lowerMime = mimeType.toLowerCase();
    final lowerName = fileName.toLowerCase();
    return lowerMime.startsWith('image/') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp');
  }

  bool get isPdf {
    return mimeType.toLowerCase() == 'application/pdf' ||
        fileName.toLowerCase().endsWith('.pdf');
  }

  bool get isSyncedToDrive => driveFileId != null && driveFileId!.isNotEmpty;
}
