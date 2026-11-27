import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/firebase/firebase_bootstrap.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/reminders/domain/reminder_template.dart';

/// Appointment payload stored in `users/{uid}/appointments/{syncId}`.
class CloudAppointmentDocument {
  const CloudAppointmentDocument({
    required this.syncId,
    this.googleCalendarEventId,
    required this.clientName,
    required this.clientRawPhone,
    required this.clientPhoneE164,
    this.clientGoogleContactId,
    required this.title,
    this.notes,
    required this.startTime,
    required this.endTime,
    required this.reminderSent,
    required this.deleted,
    required this.lastModified,
  });

  factory CloudAppointmentDocument.fromEntity(
    AppointmentEntity entity, {
    bool deleted = false,
  }) {
    return CloudAppointmentDocument(
      syncId: entity.syncId,
      googleCalendarEventId: entity.googleCalendarEventId,
      clientName: entity.clientName,
      clientRawPhone: entity.clientRawPhone,
      clientPhoneE164: entity.clientPhoneE164,
      clientGoogleContactId: entity.clientGoogleContactId,
      title: entity.title,
      notes: entity.notes,
      startTime: entity.startTime.toUtc(),
      endTime: entity.endTime.toUtc(),
      reminderSent: entity.reminderSent,
      deleted: deleted,
      lastModified: entity.lastModified.toUtc(),
    );
  }

  factory CloudAppointmentDocument.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rawSyncId = (data['syncId'] as String?)?.trim();
    final resolvedSyncId = (rawSyncId != null && rawSyncId.isNotEmpty)
        ? rawSyncId
        : (documentId ?? '');

    final startTime = _parseUtcDateTime(data['startTime']) ?? epoch;
    final endTime =
        _parseUtcDateTime(data['endTime']) ??
        startTime.add(const Duration(hours: 1));
    final lastModified = _parseUtcDateTime(data['lastModified']) ?? epoch;

    return CloudAppointmentDocument(
      syncId: resolvedSyncId,
      googleCalendarEventId: _trimOrNull(
        data['googleCalendarEventId'] as String?,
      ),
      clientName: (data['clientName'] as String?) ?? '',
      clientRawPhone: (data['clientRawPhone'] as String?) ?? '',
      clientPhoneE164: (data['clientPhoneE164'] as String?) ?? '',
      clientGoogleContactId: _trimOrNull(
        data['clientGoogleContactId'] as String?,
      ),
      title: (data['title'] as String?) ?? '',
      notes: _trimOrNull(data['notes'] as String?),
      startTime: startTime,
      endTime: endTime,
      reminderSent: (data['reminderSent'] as bool?) ?? false,
      deleted: (data['deleted'] as bool?) ?? false,
      lastModified: lastModified,
    );
  }

  final String syncId;
  final String? googleCalendarEventId;
  final String clientName;
  final String clientRawPhone;
  final String clientPhoneE164;
  final String? clientGoogleContactId;
  final String title;
  final String? notes;
  final DateTime startTime;
  final DateTime endTime;
  final bool reminderSent;
  final bool deleted;
  final DateTime lastModified;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'syncId': syncId,
      'googleCalendarEventId': googleCalendarEventId,
      'clientName': clientName,
      'clientRawPhone': clientRawPhone,
      'clientPhoneE164': clientPhoneE164,
      'clientGoogleContactId': clientGoogleContactId,
      'title': title,
      'notes': notes,
      'startTime': Timestamp.fromDate(startTime.toUtc()),
      'endTime': Timestamp.fromDate(endTime.toUtc()),
      'reminderSent': reminderSent,
      'deleted': deleted,
      'lastModified': Timestamp.fromDate(lastModified.toUtc()),
    };
  }
}

/// Reminder template payload stored in `users/{uid}/templates/{templateId}`.
class CloudTemplateDocument {
  const CloudTemplateDocument({
    required this.id,
    required this.name,
    required this.body,
    required this.updatedAt,
  });

  factory CloudTemplateDocument.fromEntity(ReminderTemplateEntity entity) {
    return CloudTemplateDocument(
      id: entity.id,
      name: entity.name,
      body: entity.body,
      updatedAt: entity.updatedAt.toUtc(),
    );
  }

  factory CloudTemplateDocument.fromMap(
    Map<String, dynamic> data, {
    String? documentId,
  }) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    final rawId = (data['id'] as String?)?.trim();
    return CloudTemplateDocument(
      id: (rawId != null && rawId.isNotEmpty) ? rawId : (documentId ?? ''),
      name: (data['name'] as String?) ?? '',
      body: (data['body'] as String?) ?? '',
      updatedAt: _parseUtcDateTime(data['updatedAt']) ?? epoch,
    );
  }

  final String id;
  final String name;
  final String body;
  final DateTime updatedAt;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'body': body,
      'updatedAt': Timestamp.fromDate(updatedAt.toUtc()),
    };
  }
}

/// Real-time Cloud Firestore datasource scoped per authenticated user (`uid`).
abstract interface class FirestoreSyncDatasource {
  Stream<List<CloudAppointmentDocument>> watchAppointments(String userId);

  Future<List<CloudAppointmentDocument>> fetchAppointments(String userId);

  Future<void> upsertAppointment(
    String userId,
    CloudAppointmentDocument document,
  );

  Future<void> markAppointmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
    String? googleCalendarEventId,
  });

  Stream<List<CloudTemplateDocument>> watchTemplates(String userId);

  Future<List<CloudTemplateDocument>> fetchTemplates(String userId);

  Future<void> upsertTemplate(String userId, CloudTemplateDocument document);
}

/// Cloud Firestore implementation of [FirestoreSyncDatasource].
class FirestoreSyncDatasourceImpl implements FirestoreSyncDatasource {
  FirestoreSyncDatasourceImpl({
    FirebaseFirestore? firestore,
    bool Function()? isFirebaseReady,
  }) : _firestoreOverride = firestore,
       _isFirebaseReady =
           isFirebaseReady ?? (() => FirebaseBootstrap.isInitialized);

  final FirebaseFirestore? _firestoreOverride;
  final bool Function() _isFirebaseReady;

  FirebaseFirestore? get _firestore {
    if (_firestoreOverride != null) {
      return _firestoreOverride;
    }
    if (!_isFirebaseReady()) {
      return null;
    }
    return FirebaseFirestore.instance;
  }

  CollectionReference<Map<String, dynamic>> _appointmentsCollection(
    FirebaseFirestore firestore,
    String userId,
  ) {
    return firestore.collection('users').doc(userId).collection('appointments');
  }

  CollectionReference<Map<String, dynamic>> _templatesCollection(
    FirebaseFirestore firestore,
    String userId,
  ) {
    return firestore.collection('users').doc(userId).collection('templates');
  }

  @override
  Stream<List<CloudAppointmentDocument>> watchAppointments(String userId) {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return const Stream<List<CloudAppointmentDocument>>.empty();
    }

    return _appointmentsCollection(firestore, userId).snapshots().map(
      (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                CloudAppointmentDocument.fromMap(
                  doc.data(),
                  documentId: doc.id,
                ),
          )
          .where((CloudAppointmentDocument doc) => doc.syncId.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<List<CloudAppointmentDocument>> fetchAppointments(
    String userId,
  ) async {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return const <CloudAppointmentDocument>[];
    }

    final snapshot = await _appointmentsCollection(firestore, userId).get();
    return snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              CloudAppointmentDocument.fromMap(doc.data(), documentId: doc.id),
        )
        .where((CloudAppointmentDocument doc) => doc.syncId.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> upsertAppointment(
    String userId,
    CloudAppointmentDocument document,
  ) async {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return;
    }

    await _appointmentsCollection(
      firestore,
      userId,
    ).doc(document.syncId).set(document.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> markAppointmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
    String? googleCalendarEventId,
  }) async {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return;
    }

    await _appointmentsCollection(firestore, userId).doc(syncId).set(
      <String, dynamic>{
        'syncId': syncId,
        'deleted': true,
        'lastModified': Timestamp.fromDate(deletedAt.toUtc()),
        if (googleCalendarEventId != null)
          'googleCalendarEventId': googleCalendarEventId,
      },
      SetOptions(merge: true),
    );
  }

  @override
  Stream<List<CloudTemplateDocument>> watchTemplates(String userId) {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return const Stream<List<CloudTemplateDocument>>.empty();
    }

    return _templatesCollection(firestore, userId).snapshots().map(
      (QuerySnapshot<Map<String, dynamic>> snapshot) => snapshot.docs
          .map(
            (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
                CloudTemplateDocument.fromMap(doc.data(), documentId: doc.id),
          )
          .where((CloudTemplateDocument doc) => doc.id.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<List<CloudTemplateDocument>> fetchTemplates(String userId) async {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return const <CloudTemplateDocument>[];
    }

    final snapshot = await _templatesCollection(firestore, userId).get();
    return snapshot.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              CloudTemplateDocument.fromMap(doc.data(), documentId: doc.id),
        )
        .where((CloudTemplateDocument doc) => doc.id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<void> upsertTemplate(
    String userId,
    CloudTemplateDocument document,
  ) async {
    final firestore = _firestore;
    if (firestore == null || userId.isEmpty) {
      return;
    }

    await _templatesCollection(
      firestore,
      userId,
    ).doc(document.id).set(document.toMap(), SetOptions(merge: true));
  }
}

DateTime? _parseUtcDateTime(dynamic raw) {
  if (raw is Timestamp) {
    return raw.toDate().toUtc();
  }
  if (raw is DateTime) {
    return raw.toUtc();
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw, isUtc: true);
  }
  if (raw is String) {
    return DateTime.tryParse(raw)?.toUtc();
  }
  return null;
}

String? _trimOrNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

final firestoreSyncDatasourceProvider = Provider<FirestoreSyncDatasource>((
  Ref ref,
) {
  return FirestoreSyncDatasourceImpl();
});
