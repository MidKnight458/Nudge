import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/appointments_repository_impl.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/data/google_calendar_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/reminders/domain/reminder_template.dart';

class _FakeConnectivityService implements ConnectivityService {
  _FakeConnectivityService({bool initialOnline = true})
    : _online = initialOnline;

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _online;

  void setOnline(bool online) {
    _online = online;
    _controller.add(online);
  }

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({AuthUser? initialUser}) : _currentUser = initialUser;

  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();
  AuthUser? _currentUser;

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  Future<AuthUser?> signIn() async => _currentUser;

  @override
  Future<AuthUser?> signInSilently() async => _currentUser;

  @override
  Future<void> signOut() async {
    _currentUser = null;
    _controller.add(null);
  }

  @override
  Future<void> clearAuthCache() async {
    await signOut();
  }

  @override
  Future<AuthenticatedCalendarClient?> openCalendarClient({
    bool requestScopeIfNeeded = false,
  }) async => null;

  @override
  Future<AuthenticatedDriveClient?> openDriveClient({
    bool requestScopeIfNeeded = false,
  }) async => null;

  void setUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }
}

class _SharedFakeGoogleCalendarDatasource implements GoogleCalendarDatasource {
  final Map<String, calendar.Event> eventsById = <String, calendar.Event>{};
  final List<String> sharedEmails = <String>[];
  final List<String> deletedLegacyPrimaryIds = <String>[];
  int ensureCalendarCount = 0;
  int insertCount = 0;
  int patchCount = 0;
  int deleteCount = 0;
  int listActiveEventsCount = 0;
  int _nextId = 1;
  Object? errorToThrowOnWrite;
  Object? errorToThrowOnList;

  @override
  Future<String> ensureNudgeCalendar({
    bool requestScopeIfNeeded = false,
  }) async {
    ensureCalendarCount++;
    return 'nudge_calendar_id';
  }

  @override
  Future<void> shareNudgeCalendarWithEmail(
    String email, {
    String role = 'reader',
  }) async {
    sharedEmails.add(email);
  }

  @override
  Future<String> insertEvent(
    AppointmentEntity appointment, {
    bool requestScopeIfNeeded = false,
  }) async {
    final error = errorToThrowOnWrite;
    if (error != null) {
      throw error;
    }
    insertCount++;
    final id = 'gcal_evt_${_nextId++}';
    eventsById[id] = calendar.Event(
      id: id,
      summary: CalendarEventMetadataCodec.buildEventSummary(
        title: appointment.title,
        clientName: appointment.clientName,
      ),
      description: CalendarEventMetadataCodec.encodeDescription(
        clientName: appointment.clientName,
        clientPhoneE164: appointment.clientPhoneE164,
        title: appointment.title,
        notes: appointment.notes,
      ),
      start: calendar.EventDateTime(dateTime: appointment.startTime.toUtc()),
      end: calendar.EventDateTime(dateTime: appointment.endTime.toUtc()),
      extendedProperties: calendar.EventExtendedProperties(
        private: <String, String>{'nudgeSyncId': appointment.syncId},
      ),
    );
    return id;
  }

  @override
  Future<void> patchEvent(
    AppointmentEntity appointment, {
    bool requestScopeIfNeeded = false,
  }) async {
    final error = errorToThrowOnWrite;
    if (error != null) {
      throw error;
    }
    final eventId = appointment.googleCalendarEventId;
    if (eventId == null || !eventsById.containsKey(eventId)) {
      throw calendar.DetailedApiRequestError(404, 'Not Found');
    }
    patchCount++;
    eventsById[eventId] = calendar.Event(
      id: eventId,
      summary: CalendarEventMetadataCodec.buildEventSummary(
        title: appointment.title,
        clientName: appointment.clientName,
      ),
      description: CalendarEventMetadataCodec.encodeDescription(
        clientName: appointment.clientName,
        clientPhoneE164: appointment.clientPhoneE164,
        title: appointment.title,
        notes: appointment.notes,
      ),
      start: calendar.EventDateTime(dateTime: appointment.startTime.toUtc()),
      end: calendar.EventDateTime(dateTime: appointment.endTime.toUtc()),
      extendedProperties: calendar.EventExtendedProperties(
        private: <String, String>{'nudgeSyncId': appointment.syncId},
      ),
    );
  }

  @override
  Future<void> deleteEvent(String googleCalendarEventId) async {
    final error = errorToThrowOnWrite;
    if (error != null) {
      throw error;
    }
    deleteCount++;
    eventsById.remove(googleCalendarEventId);
  }

  @override
  Future<void> deleteLegacyPrimaryEvent(String googleCalendarEventId) async {
    deletedLegacyPrimaryIds.add(googleCalendarEventId);
  }

  @override
  Future<List<CalendarRemoteEvent>> listActiveEvents({
    DateTime? timeMin,
    bool requestScopeIfNeeded = false,
  }) async {
    final error = errorToThrowOnList;
    if (error != null) {
      throw error;
    }
    listActiveEventsCount++;
    final results = <CalendarRemoteEvent>[];
    for (final event in eventsById.values) {
      final id = event.id;
      final start = event.start?.dateTime ?? event.start?.date;
      final end = event.end?.dateTime ?? event.end?.date;
      if (id == null || start == null || end == null) {
        continue;
      }
      if (timeMin != null && !end.toUtc().isAfter(timeMin.toUtc())) {
        continue;
      }
      final rawSyncId = event.extendedProperties?.private?['nudgeSyncId']
          ?.trim();
      results.add(
        CalendarRemoteEvent(
          id: id,
          status: event.status ?? 'confirmed',
          summary: event.summary,
          description: event.description,
          startTime: start.toLocal(),
          endTime: end.toLocal(),
          nudgeSyncId: (rawSyncId == null || rawSyncId.isEmpty)
              ? null
              : rawSyncId,
        ),
      );
    }
    return results;
  }

  @override
  Future<CalendarDeltaPage> listEventsDelta({
    String? syncToken,
    DateTime? timeMin,
  }) async {
    return const CalendarDeltaPage(
      events: <CalendarRemoteEvent>[],
      nextSyncToken: 'unused',
    );
  }
}

class _InMemoryFirestoreSyncDatasource implements FirestoreSyncDatasource {
  final Map<String, Map<String, CloudAppointmentDocument>> _appointmentsByUid =
      <String, Map<String, CloudAppointmentDocument>>{};
  final Map<String, Map<String, CloudTemplateDocument>> _templatesByUid =
      <String, Map<String, CloudTemplateDocument>>{};
  final Map<String, Map<String, CloudClientDocument>> _clientsByUid =
      <String, Map<String, CloudClientDocument>>{};
  final Map<String, Map<String, CloudAttachmentDocument>> _attachmentsByUid =
      <String, Map<String, CloudAttachmentDocument>>{};
  final Map<String, CloudSettingsDocument> _settingsByUid =
      <String, CloudSettingsDocument>{};

  final Map<String, StreamController<List<CloudAppointmentDocument>>>
  _appointmentControllers =
      <String, StreamController<List<CloudAppointmentDocument>>>{};
  final Map<String, StreamController<List<CloudTemplateDocument>>>
  _templateControllers =
      <String, StreamController<List<CloudTemplateDocument>>>{};
  final Map<String, StreamController<List<CloudClientDocument>>>
  _clientControllers = <String, StreamController<List<CloudClientDocument>>>{};
  final Map<String, StreamController<List<CloudAttachmentDocument>>>
  _attachmentControllers =
      <String, StreamController<List<CloudAttachmentDocument>>>{};
  final Map<String, StreamController<CloudSettingsDocument?>>
  _settingsControllers = <String, StreamController<CloudSettingsDocument?>>{};

  int upsertAppointmentCount = 0;
  int markDeletedCount = 0;

  Map<String, CloudAppointmentDocument> _userAppointments(String uid) =>
      _appointmentsByUid.putIfAbsent(
        uid,
        () => <String, CloudAppointmentDocument>{},
      );

  Map<String, CloudTemplateDocument> _userTemplates(String uid) =>
      _templatesByUid.putIfAbsent(uid, () => <String, CloudTemplateDocument>{});

  Map<String, CloudClientDocument> _userClients(String uid) =>
      _clientsByUid.putIfAbsent(uid, () => <String, CloudClientDocument>{});

  Map<String, CloudAttachmentDocument> _userAttachments(String uid) =>
      _attachmentsByUid.putIfAbsent(
        uid,
        () => <String, CloudAttachmentDocument>{},
      );

  StreamController<List<CloudAppointmentDocument>> _appointmentController(
    String uid,
  ) {
    return _appointmentControllers.putIfAbsent(
      uid,
      () => StreamController<List<CloudAppointmentDocument>>.broadcast(),
    );
  }

  StreamController<List<CloudTemplateDocument>> _templateController(
    String uid,
  ) {
    return _templateControllers.putIfAbsent(
      uid,
      () => StreamController<List<CloudTemplateDocument>>.broadcast(),
    );
  }

  StreamController<List<CloudClientDocument>> _clientController(String uid) {
    return _clientControllers.putIfAbsent(
      uid,
      () => StreamController<List<CloudClientDocument>>.broadcast(),
    );
  }

  StreamController<List<CloudAttachmentDocument>> _attachmentController(
    String uid,
  ) {
    return _attachmentControllers.putIfAbsent(
      uid,
      () => StreamController<List<CloudAttachmentDocument>>.broadcast(),
    );
  }

  StreamController<CloudSettingsDocument?> _settingsController(String uid) {
    return _settingsControllers.putIfAbsent(
      uid,
      () => StreamController<CloudSettingsDocument?>.broadcast(),
    );
  }

  @override
  Stream<List<CloudAppointmentDocument>> watchAppointments(String userId) {
    return _appointmentController(userId).stream;
  }

  @override
  Future<List<CloudAppointmentDocument>> fetchAppointments(
    String userId,
  ) async {
    return _userAppointments(userId).values.toList(growable: false);
  }

  @override
  Future<void> upsertAppointment(
    String userId,
    CloudAppointmentDocument document,
  ) async {
    upsertAppointmentCount++;
    _userAppointments(userId)[document.syncId] = document;
    _appointmentController(userId)
        .add(_userAppointments(userId).values.toList(growable: false));
  }

  @override
  Future<void> markAppointmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
    String? googleCalendarEventId,
  }) async {
    markDeletedCount++;
    final store = _userAppointments(userId);
    final previous = store[syncId];
    store[syncId] = CloudAppointmentDocument(
      syncId: syncId,
      googleCalendarEventId:
          googleCalendarEventId ?? previous?.googleCalendarEventId,
      clientName: previous?.clientName ?? '',
      clientRawPhone: previous?.clientRawPhone ?? '',
      clientPhoneE164: previous?.clientPhoneE164 ?? '',
      clientGoogleContactId: previous?.clientGoogleContactId,
      title: previous?.title ?? '',
      notes: previous?.notes,
      startTime:
          previous?.startTime ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      endTime:
          previous?.endTime ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      reminderSent: previous?.reminderSent ?? false,
      deleted: true,
      lastModified: deletedAt.toUtc(),
    );
    _appointmentController(userId).add(store.values.toList(growable: false));
  }

  @override
  Stream<List<CloudTemplateDocument>> watchTemplates(String userId) {
    return _templateController(userId).stream;
  }

  @override
  Future<List<CloudTemplateDocument>> fetchTemplates(String userId) async {
    return _userTemplates(userId).values.toList(growable: false);
  }

  @override
  Future<void> upsertTemplate(
    String userId,
    CloudTemplateDocument document,
  ) async {
    final store = _userTemplates(userId);
    store[document.id] = document;
    _templateController(userId).add(store.values.toList(growable: false));
  }

  @override
  Stream<List<CloudClientDocument>> watchClients(String userId) =>
      _clientController(userId).stream;

  @override
  Future<List<CloudClientDocument>> fetchClients(String userId) async =>
      _userClients(userId).values.toList(growable: false);

  @override
  Future<void> upsertClient(String userId, CloudClientDocument document) async {
    final store = _userClients(userId);
    store[document.syncId] = document;
    _clientController(userId).add(store.values.toList(growable: false));
  }

  @override
  Future<void> markClientDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
  }) async {
    final store = _userClients(userId);
    final prev = store[syncId];
    store[syncId] = CloudClientDocument(
      syncId: syncId,
      googleContactId: prev?.googleContactId,
      name: prev?.name ?? '',
      rawPhone: prev?.rawPhone ?? '',
      phoneE164: prev?.phoneE164 ?? '',
      generalNotes: prev?.generalNotes,
      deleted: true,
      lastModified: deletedAt.toUtc(),
    );
    _clientController(userId).add(store.values.toList(growable: false));
  }

  @override
  Stream<List<CloudAttachmentDocument>> watchClientAttachments(String userId) =>
      _attachmentController(userId).stream;

  @override
  Future<List<CloudAttachmentDocument>> fetchClientAttachments(
    String userId,
  ) async => _userAttachments(userId).values.toList(growable: false);

  @override
  Future<void> upsertClientAttachment(
    String userId,
    CloudAttachmentDocument document,
  ) async {
    final store = _userAttachments(userId);
    store[document.syncId] = document;
    _attachmentController(userId).add(store.values.toList(growable: false));
  }

  @override
  Future<void> markClientAttachmentDeleted(
    String userId, {
    required String syncId,
    required DateTime deletedAt,
  }) async {
    final store = _userAttachments(userId);
    final prev = store[syncId];
    store[syncId] = CloudAttachmentDocument(
      syncId: syncId,
      clientSyncId: prev?.clientSyncId ?? '',
      fileName: prev?.fileName ?? '',
      mimeType: prev?.mimeType ?? 'application/octet-stream',
      sizeBytes: prev?.sizeBytes ?? 0,
      driveFileId: prev?.driveFileId,
      deleted: true,
      createdAt:
          prev?.createdAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      lastModified: deletedAt.toUtc(),
    );
    _attachmentController(userId).add(store.values.toList(growable: false));
  }

  @override
  Stream<CloudSettingsDocument?> watchSettings(String userId) =>
      _settingsController(userId).stream;

  @override
  Future<CloudSettingsDocument?> fetchSettings(String userId) async =>
      _settingsByUid[userId];

  @override
  Future<void> upsertSettings(
    String userId,
    CloudSettingsDocument document,
  ) async {
    _settingsByUid[userId] = document;
    _settingsController(userId).add(document);
  }

  Future<void> dispose() async {
    for (final controller in _appointmentControllers.values) {
      await controller.close();
    }
    for (final controller in _templateControllers.values) {
      await controller.close();
    }
    for (final controller in _clientControllers.values) {
      await controller.close();
    }
    for (final controller in _attachmentControllers.values) {
      await controller.close();
    }
    for (final controller in _settingsControllers.values) {
      await controller.close();
    }
  }
}

void main() {
  setUpAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  group('CalendarEventMetadataCodec', () {
    test('round-trips summary, description metadata, and clean notes', () {
      final description = CalendarEventMetadataCodec.encodeDescription(
        clientName: 'Ana López',
        clientPhoneE164: '5215512345678',
        title: 'Corte y tinte',
        notes: 'Trae referencia de color',
      );
      final summary = CalendarEventMetadataCodec.buildEventSummary(
        title: 'Corte y tinte',
        clientName: 'Ana López',
      );

      final decoded = CalendarEventMetadataCodec.decodeEvent(
        summary: summary,
        description: description,
      );

      expect(summary, 'Corte y tinte — Ana López');
      expect(decoded.title, 'Corte y tinte');
      expect(decoded.clientName, 'Ana López');
      expect(decoded.clientPhoneE164, '5215512345678');
      expect(decoded.notes, 'Trae referencia de color');
    });
  });

  group('Firestore real-time + Google Calendar mirror sync', () {
    const testUser = AuthUser(
      id: 'firebase_uid_1',
      email: 'negocio@gmail.com',
      displayName: 'Negocio Nudge',
    );

    late AppDatabase dbA;
    late LocalAppointmentsDatasource localA;
    late _FakeConnectivityService connectivityA;
    late _FakeAuthRepository authA;
    late _SharedFakeGoogleCalendarDatasource calendarMirror;
    late _InMemoryFirestoreSyncDatasource firestore;
    late AppointmentsRepositoryImpl repoA;

    setUp(() {
      dbA = AppDatabase(NativeDatabase.memory());
      localA = LocalAppointmentsDatasource(dbA);
      connectivityA = _FakeConnectivityService(initialOnline: true);
      authA = _FakeAuthRepository(initialUser: testUser);
      calendarMirror = _SharedFakeGoogleCalendarDatasource();
      firestore = _InMemoryFirestoreSyncDatasource();
      repoA = AppointmentsRepositoryImpl(
        localDatasource: localA,
        remoteDatasource: calendarMirror,
        firestoreDatasource: firestore,
        connectivityService: connectivityA,
        authRepository: authA,
        nowProvider: () => DateTime(2026, 11, 28, 8, 0),
      );
    });

    tearDown(() async {
      await dbA.close();
      await firestore.dispose();
    });

    test('syncs create, reminderSent, update, and delete across two devices in real time without duplicating Calendar events', () async {
      final dbB = AppDatabase(NativeDatabase.memory());
      final localB = LocalAppointmentsDatasource(dbB);
      final connectivityB = _FakeConnectivityService(initialOnline: true);
      final authB = _FakeAuthRepository(initialUser: testUser);
      final repoB = AppointmentsRepositoryImpl(
        localDatasource: localB,
        remoteDatasource: calendarMirror,
        firestoreDatasource: firestore,
        connectivityService: connectivityB,
        authRepository: authB,
        nowProvider: () => DateTime(2026, 11, 28, 8, 5),
      );

      final subB = firestore
          .watchAppointments(testUser.id)
          .listen((docs) => unawaited(repoB.applyCloudSnapshot(docs)));

      try {
        // 1. Device A creates appointment -> Firestore + Google Calendar mirror -> real-time stream updates Device B.
        final createdA = await repoA.createAppointment(
          AppointmentInput(
            clientName: 'Sofía Ramírez',
            clientRawPhone: '5512345678',
            clientPhoneE164: '5215512345678',
            title: 'Consulta inicial',
            notes: 'Primera visita',
            startTime: DateTime(2026, 11, 29, 10, 0),
            endTime: DateTime(2026, 11, 29, 11, 0),
          ),
        );

        await pumpEventQueue();

        expect(createdA.syncStatus, AppointmentSyncStatus.synced);
        expect(createdA.googleCalendarEventId, isNotNull);
        expect(calendarMirror.insertCount, 1);

        final dayRangeStart = DateTime(2026, 11, 29, 0, 0);
        final dayRangeEnd = DateTime(2026, 11, 30, 0, 0);
        var itemsB = await localB
            .watchAppointmentsInRange(dayRangeStart, dayRangeEnd)
            .first;
        expect(itemsB, hasLength(1));
        expect(itemsB.first.syncId, createdA.syncId);
        expect(
          itemsB.first.googleCalendarEventId,
          createdA.googleCalendarEventId,
        );
        expect(itemsB.first.clientPhoneE164, '5215512345678');
        expect(itemsB.first.reminderSent, isFalse);
        expect(calendarMirror.insertCount, 1);

        // 2. Device A sends WhatsApp reminder -> Device B immediately reflects reminderSent == true.
        await repoA.markReminderSent(createdA.id, sent: true);
        await pumpEventQueue();

        itemsB = await localB
            .watchAppointmentsInRange(dayRangeStart, dayRangeEnd)
            .first;
        expect(itemsB, hasLength(1));
        expect(itemsB.first.reminderSent, isTrue);

        // 3. Device A edits appointment -> Device B updates existing record with zero duplicates.
        final reloadedA = await localA.getAppointmentById(createdA.id);
        await repoA.updateAppointment(
          reloadedA!,
          AppointmentInput(
            clientName: 'Sofía Ramírez',
            clientRawPhone: '5512345678',
            clientPhoneE164: '5215512345678',
            title: 'Valoración extendida',
            notes: 'Confirmada por WhatsApp',
            startTime: DateTime(2026, 11, 29, 12, 0),
            endTime: DateTime(2026, 11, 29, 13, 30),
          ),
        );
        await pumpEventQueue();

        itemsB = await localB
            .watchAppointmentsInRange(dayRangeStart, dayRangeEnd)
            .first;
        expect(itemsB, hasLength(1));
        expect(itemsB.first.title, 'Valoración extendida');
        expect(itemsB.first.notes, 'Confirmada por WhatsApp');
        expect(calendarMirror.insertCount, 1);
        expect(calendarMirror.patchCount, 1);

        // 4. Device A deletes appointment -> tombstone propagates -> Device B removes and doesn't resurrect.
        final toDeleteA = await localA.getAppointmentById(createdA.id);
        await repoA.deleteAppointment(toDeleteA!);
        await pumpEventQueue();

        itemsB = await localB
            .watchAppointmentsInRange(dayRangeStart, dayRangeEnd)
            .first;
        expect(itemsB, isEmpty);
        expect(calendarMirror.eventsById, isEmpty);

        final syncB = await repoB.synchronize();
        expect(syncB.hasError, isFalse);
        itemsB = await localB
            .watchAppointmentsInRange(dayRangeStart, dayRangeEnd)
            .first;
        expect(itemsB, isEmpty);
      } finally {
        await subB.cancel();
        await dbB.close();
      }
    });

    test('queues offline mutations including deletes without Calendar ID and drains on reconnect', () async {
      connectivityA.setOnline(false);

      final offlineCreated = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Carlos Méndez',
          clientRawPhone: '3310009999',
          clientPhoneE164: '5213310009999',
          title: 'Limpieza dental',
          startTime: DateTime(2026, 11, 30, 9, 0),
          endTime: DateTime(2026, 11, 30, 10, 0),
        ),
      );
      expect(offlineCreated.syncStatus, AppointmentSyncStatus.pendingCreate);

      final offlineEdited = await repoA.updateAppointment(
        offlineCreated,
        AppointmentInput(
          clientName: 'Carlos Méndez',
          clientRawPhone: '3310009999',
          clientPhoneE164: '5213310009999',
          title: 'Limpieza profunda',
          startTime: DateTime(2026, 11, 30, 11, 0),
          endTime: DateTime(2026, 11, 30, 12, 0),
        ),
      );
      expect(offlineEdited.syncStatus, AppointmentSyncStatus.pendingCreate);
      expect(await repoA.watchPendingSyncCount().first, 1);

      connectivityA.setOnline(true);
      final firstSync = await repoA.synchronize();
      expect(firstSync.hasError, isFalse);
      expect(firstSync.pushedCreated, 1);
      expect(await repoA.watchPendingSyncCount().first, 0);

      // Simulate a Firestore-synced row whose Google Calendar ID is null, then delete offline.
      final syncedDoc = (await localA.getAllActiveAppointments()).single;
      final cleared = await localA.markAppointmentSynced(
        appointmentId: syncedDoc.id,
        clearGoogleCalendarEventId: true,
      );
      expect(cleared!.googleCalendarEventId, isNull);

      connectivityA.setOnline(false);
      await repoA.deleteAppointment(cleared);

      // Should stay queued as pending_delete rather than silently disappearing without a tombstone.
      expect(await repoA.watchPendingSyncCount().first, 1);

      connectivityA.setOnline(true);
      final deleteSync = await repoA.synchronize();
      expect(deleteSync.pushedDeleted, 1);
      expect(await repoA.watchPendingSyncCount().first, 0);
      expect(await localA.getAllActiveAppointments(), isEmpty);

      final cloudDocs = await firestore.fetchAppointments(testUser.id);
      expect(cloudDocs.single.deleted, isTrue);
    });

    test('keeps Firestore multi-device sync working even when Google Calendar API returns 403', () async {
      calendarMirror.errorToThrowOnWrite = calendar.DetailedApiRequestError(
        403,
        'Calendar API disabled',
      );

      final created = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Lucía Vega',
          clientRawPhone: '5599887766',
          clientPhoneE164: '5215599887766',
          title: 'Masaje terapéutico',
          startTime: DateTime(2026, 12, 1, 15, 0),
          endTime: DateTime(2026, 12, 1, 16, 0),
        ),
      );

      expect(created.syncStatus, AppointmentSyncStatus.synced);
      expect(created.googleCalendarEventId, isNull);

      final cloudDocs = await firestore.fetchAppointments(testUser.id);
      expect(cloudDocs, hasLength(1));
      expect(cloudDocs.first.title, 'Masaje terapéutico');
    });

    test('migrates Drift v1 SQLite appointments to v2 syncId and uploads pre-existing rows once', () async {
      final v1MigratedDb = AppDatabase(
        NativeDatabase.memory(
          setup: (rawDb) {
            rawDb.execute('''
                CREATE TABLE clients (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  google_contact_id TEXT UNIQUE,
                  name TEXT NOT NULL,
                  raw_phone TEXT NOT NULL,
                  phone_e164 TEXT NOT NULL
                );
                CREATE TABLE appointments (
                  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                  google_calendar_event_id TEXT UNIQUE,
                  client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
                  title TEXT NOT NULL,
                  notes TEXT,
                  start_time INTEGER NOT NULL,
                  end_time INTEGER NOT NULL,
                  reminder_sent INTEGER NOT NULL DEFAULT 0,
                  sync_status TEXT NOT NULL DEFAULT 'synced',
                  last_modified INTEGER NOT NULL
                );
                CREATE TABLE sync_metadata (
                  id INTEGER NOT NULL PRIMARY KEY,
                  sync_token TEXT,
                  last_sync_timestamp INTEGER
                );
                CREATE TABLE reminder_templates (
                  id TEXT NOT NULL PRIMARY KEY,
                  name TEXT NOT NULL,
                  body TEXT NOT NULL,
                  updated_at INTEGER NOT NULL
                );
                INSERT INTO clients (id, name, raw_phone, phone_e164)
                VALUES (1, 'Cliente Histórico', '5511223344', '5215511223344');
                INSERT INTO appointments (
                  id, google_calendar_event_id, client_id, title,
                  start_time, end_time, reminder_sent, sync_status, last_modified
                ) VALUES
                  (1, 'old_cal_123', 1, 'Cita previa', 1795867200, 1795870800, 0, 'synced', 1795860000),
                  (2, NULL, 1, 'Cita solo local', 1795953600, 1795957200, 1, 'synced', 1795860000);
                PRAGMA user_version = 1;
              ''');
          },
        ),
      );

      try {
        final migratedLocal = LocalAppointmentsDatasource(v1MigratedDb);
        final migratedRepo = AppointmentsRepositoryImpl(
          localDatasource: migratedLocal,
          remoteDatasource: calendarMirror,
          firestoreDatasource: firestore,
          connectivityService: connectivityA,
          authRepository: authA,
          nowProvider: () => DateTime(2026, 11, 28, 9, 0),
        );

        final activeBefore = await migratedLocal.getAllActiveAppointments();
        expect(activeBefore, hasLength(2));
        expect(activeBefore[0].syncId, 'gcal-old_cal_123');
        expect(activeBefore[1].syncId, startsWith('legacy-'));
        expect(activeBefore[1].reminderSent, isTrue);

        final firstMigrationSync = await migratedRepo.synchronize();
        expect(firstMigrationSync.pushedCreated, 2);

        final secondSync = await migratedRepo.synchronize();
        expect(secondSync.pushedCreated, 0);
        expect(await migratedLocal.getAllActiveAppointments(), hasLength(2));
      } finally {
        await v1MigratedDb.close();
      }
    });

    test('syncs customized WhatsApp templates without fresh device defaults overwriting cloud edits', () async {
      final dbB = AppDatabase(NativeDatabase.memory());
      try {
        final templatesRepoA = ReminderTemplatesRepository(
          dbA,
          firestoreDatasource: firestore,
          currentUserId: () => testUser.id,
          isOnline: () async => true,
        );
        final templatesRepoB = ReminderTemplatesRepository(
          dbB,
          firestoreDatasource: firestore,
          currentUserId: () => testUser.id,
          isOnline: () async => true,
        );

        await templatesRepoA.saveTemplate(
          templateId: AppConstants.tomorrowTemplateId,
          body:
              'Hola {cliente}, nos vemos mañana a las {hora} para {servicio}.',
        );

        // Device B has freshly seeded default templates (epoch updatedAt).
        // Calling syncWithCloud() must pull Device A's template rather than overwriting it.
        await templatesRepoB.syncWithCloud();

        final templatesB = await templatesRepoB.watchTemplates().first;
        final tomorrowB = templatesB.firstWhere(
          (ReminderTemplateEntity t) => t.id == AppConstants.tomorrowTemplateId,
        );
        expect(
          tomorrowB.body,
          'Hola {cliente}, nos vemos mañana a las {hora} para {servicio}.',
        );

        final cloudTemplates = await firestore.fetchTemplates(testUser.id);
        expect(cloudTemplates.single.body, tomorrowB.body);
      } finally {
        await dbB.close();
      }
    });

    test(
      'watches nearest future day appointments for free-day Próximas Citas',
      () async {
        await repoA.createAppointment(
          AppointmentInput(
            clientName: 'Marcos Díaz',
            clientRawPhone: '5511112222',
            clientPhoneE164: '5215511112222',
            title: 'Revisión posterior',
            startTime: DateTime(2026, 12, 6, 11, 0),
            endTime: DateTime(2026, 12, 6, 12, 0),
          ),
        );
        await repoA.createAppointment(
          AppointmentInput(
            clientName: 'Elena Ruiz',
            clientRawPhone: '5533334444',
            clientPhoneE164: '5215533334444',
            title: 'Sesión próxima',
            startTime: DateTime(2026, 12, 3, 16, 30),
            endTime: DateTime(2026, 12, 3, 17, 0),
          ),
        );

        final upcoming = await localA
            .watchNextUpcomingDayAppointments(DateTime(2026, 12, 1))
            .first;
        expect(upcoming.date, DateTime(2026, 12, 3));
        expect(upcoming.appointments, hasLength(1));
        expect(upcoming.appointments.single.clientName, 'Elena Ruiz');
      },
    );

    test(
      'migrates Drift v2 database to v3 backfilling clients.syncId cleanly',
      () async {
        final v2MigratedDb = AppDatabase(
          NativeDatabase.memory(
            setup: (rawDb) {
              rawDb.execute('''
              CREATE TABLE clients (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                google_contact_id TEXT UNIQUE,
                name TEXT NOT NULL,
                raw_phone TEXT NOT NULL,
                phone_e164 TEXT NOT NULL
              );
              CREATE TABLE appointments (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                sync_id TEXT NOT NULL UNIQUE,
                google_calendar_event_id TEXT UNIQUE,
                client_id INTEGER NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                notes TEXT,
                start_time INTEGER NOT NULL,
                end_time INTEGER NOT NULL,
                reminder_sent INTEGER NOT NULL DEFAULT 0,
                sync_status TEXT NOT NULL DEFAULT 'synced',
                last_modified INTEGER NOT NULL
              );
              CREATE TABLE sync_metadata (
                id INTEGER NOT NULL PRIMARY KEY,
                sync_token TEXT,
                last_sync_timestamp INTEGER
              );
              CREATE TABLE reminder_templates (
                id TEXT NOT NULL PRIMARY KEY,
                name TEXT NOT NULL,
                body TEXT NOT NULL,
                updated_at INTEGER NOT NULL
              );
              INSERT INTO clients (id, name, raw_phone, phone_e164)
              VALUES (1, 'Cliente v2', '5511223344', '5215511223344');
              INSERT INTO reminder_templates (id, name, body, updated_at)
              VALUES ('tomorrow_reminder', 'Recordatorio de mañana', 'Hola', 100),
                     ('confirmation', 'Confirmación de cita', 'Confirmado', 100);
              PRAGMA user_version = 2;
            ''');
            },
          ),
        );

        try {
          final clients = await v2MigratedDb.select(v2MigratedDb.clients).get();
          expect(clients, hasLength(1));
          expect(clients.single.syncId, 'phone-5215511223344');

          final templates = await v2MigratedDb
              .select(v2MigratedDb.reminderTemplates)
              .get();
          expect(templates, hasLength(1));
          expect(templates.single.id, AppConstants.tomorrowTemplateId);
          expect(templates.single.name, AppConstants.tomorrowTemplateName);

          final settingsRows = await v2MigratedDb
              .select(v2MigratedDb.appSettings)
              .get();
          expect(settingsRows, hasLength(1));
        } finally {
          await v2MigratedDb.close();
        }
      },
    );

    test(
      'clearAllLocalUserData resets user-scoped SQLite tables cleanly',
      () async {
        await repoA.createAppointment(
          AppointmentInput(
            clientName: 'Cuenta Uno',
            clientRawPhone: '5511223344',
            clientPhoneE164: '5215511223344',
            title: 'Cita privada',
            startTime: DateTime(2026, 12, 2, 10, 0),
            endTime: DateTime(2026, 12, 2, 11, 0),
          ),
        );
        await localA.setLastAccountUid(testUser.id);
        expect(await localA.getAllActiveAppointments(), hasLength(1));

        await localA.clearAllLocalUserData();
        expect(await localA.getAllActiveAppointments(), isEmpty);
        expect(await dbA.select(dbA.clients).get(), isEmpty);
        expect(await localA.getLastAccountUid(), isNull);
      },
    );

    test('selects owned secondary Nudge calendar cleanly and validates share emails', () {
      final entries = <calendar.CalendarListEntry>[
        calendar.CalendarListEntry(
          id: 'primary@work.com',
          summary: 'Nudge',
          primary: true,
          accessRole: 'owner',
        ),
        calendar.CalendarListEntry(
          id: 'shared_ro_cal',
          summary: 'Nudge',
          accessRole: 'reader',
        ),
        calendar.CalendarListEntry(
          id: 'deleted_nudge_cal',
          summary: 'Nudge',
          deleted: true,
          accessRole: 'owner',
        ),
        calendar.CalendarListEntry(
          id: 'owned_nudge_cal_123',
          summary: '  nudge  ',
          primary: false,
          accessRole: 'owner',
        ),
      ];

      expect(
        GoogleCalendarDatasourceImpl.findOwnedNudgeCalendarId(entries),
        'owned_nudge_cal_123',
      );
      expect(
        GoogleCalendarDatasourceImpl.isValidEmail('personal@gmail.com'),
        isTrue,
      );
      expect(
        GoogleCalendarDatasourceImpl.isValidEmail('correo-invalido'),
        isFalse,
      );
    });

    test('synchronize ensures dedicated Nudge calendar and re-inserts legacy 404 patch events cleanly', () async {
      final created = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Héctor León',
          clientRawPhone: '5588990011',
          clientPhoneE164: '5215588990011',
          title: 'Consulta heredada',
          startTime: DateTime(2026, 12, 4, 10, 0),
          endTime: DateTime(2026, 12, 4, 11, 0),
        ),
      );

      // Simulate legacy event ID from pre-v1.4 primary calendar (not present in Nudge calendar).
      calendarMirror.eventsById.clear();

      final updated = await repoA.updateAppointment(
        created,
        AppointmentInput(
          clientName: 'Héctor León',
          clientRawPhone: '5588990011',
          clientPhoneE164: '5215588990011',
          title: 'Consulta migrada',
          startTime: DateTime(2026, 12, 4, 10, 30),
          endTime: DateTime(2026, 12, 4, 11, 30),
        ),
      );
      expect(
        updated.googleCalendarEventId,
        isNot(created.googleCalendarEventId),
      );

      await repoA.synchronize();
      expect(calendarMirror.ensureCalendarCount, greaterThanOrEqualTo(1));
    });

    test('synchronize backfills synced upcoming appointment with null Calendar ID into Nudge calendar without duplicating', () async {
      calendarMirror.errorToThrowOnWrite = calendar.DetailedApiRequestError(
        403,
        'Calendar API temporarily unavailable',
      );

      final created = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Valeria Paredes',
          clientRawPhone: '5511223344',
          clientPhoneE164: '5215511223344',
          title: 'Cita de sábado',
          startTime: DateTime(2026, 11, 28, 14, 0),
          endTime: DateTime(2026, 11, 28, 15, 0),
        ),
      );
      expect(created.syncStatus, AppointmentSyncStatus.synced);
      expect(created.googleCalendarEventId, isNull);
      expect(calendarMirror.eventsById, isEmpty);

      calendarMirror.errorToThrowOnWrite = null;

      final firstSync = await repoA.synchronize(interactive: true);
      expect(firstSync.hasError, isFalse);
      expect(firstSync.calendarBackfilled, 1);
      expect(calendarMirror.insertCount, 1);
      expect(calendarMirror.eventsById, hasLength(1));

      final localUpdated = await localA.getAppointmentById(created.id);
      expect(localUpdated?.googleCalendarEventId, isNotNull);
      final cloudDocs = await firestore.fetchAppointments(testUser.id);
      expect(
        cloudDocs.single.googleCalendarEventId,
        localUpdated?.googleCalendarEventId,
      );

      final secondSync = await repoA.synchronize();
      expect(secondSync.hasError, isFalse);
      expect(secondSync.calendarBackfilled, 0);
      expect(calendarMirror.insertCount, 1);
    });

    test('synchronize recreates upcoming appointment missing from Nudge calendar and cleans legacy primary ID', () async {
      final created = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Diego Morales',
          clientRawPhone: '5544332211',
          clientPhoneE164: '5215544332211',
          title: 'Control semanal',
          startTime: DateTime(2026, 11, 30, 11, 0),
          endTime: DateTime(2026, 11, 30, 12, 0),
        ),
      );
      final oldEventId = created.googleCalendarEventId!;
      expect(calendarMirror.insertCount, 1);

      // Simulate event missing in "Nudge" (deleted remotely or stored on pre-v1.4 primary).
      calendarMirror.eventsById.clear();

      final syncResult = await repoA.synchronize();
      expect(syncResult.hasError, isFalse);
      expect(syncResult.calendarBackfilled, 1);
      expect(calendarMirror.deletedLegacyPrimaryIds, <String>[oldEventId]);
      expect(calendarMirror.insertCount, 2);
      expect(calendarMirror.eventsById, hasLength(1));

      final localUpdated = await localA.getAppointmentById(created.id);
      final newEventId = localUpdated?.googleCalendarEventId;
      expect(newEventId, isNotNull);
      expect(newEventId, isNot(oldEventId));

      final cloudDocs = await firestore.fetchAppointments(testUser.id);
      expect(cloudDocs.single.googleCalendarEventId, newEventId);

      final secondSync = await repoA.synchronize();
      expect(secondSync.calendarBackfilled, 0);
      expect(calendarMirror.insertCount, 2);
    });

    test('synchronize re-links upcoming appointment when event with matching nudgeSyncId already exists in Nudge', () async {
      calendarMirror.errorToThrowOnWrite = calendar.DetailedApiRequestError(
        403,
        'Transient error',
      );
      final created = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Camila Soto',
          clientRawPhone: '5577889900',
          clientPhoneE164: '5215577889900',
          title: 'Sesión previa',
          startTime: DateTime(2026, 12, 2, 16, 0),
          endTime: DateTime(2026, 12, 2, 17, 0),
        ),
      );
      expect(created.googleCalendarEventId, isNull);
      calendarMirror.errorToThrowOnWrite = null;

      // Simulate another device having already pushed this event to the shared Calendar.
      calendarMirror.eventsById['existing_nudge_evt'] = calendar.Event(
        id: 'existing_nudge_evt',
        status: 'confirmed',
        summary: CalendarEventMetadataCodec.buildEventSummary(
          title: created.title,
          clientName: created.clientName,
        ),
        start: calendar.EventDateTime(dateTime: created.startTime.toUtc()),
        end: calendar.EventDateTime(dateTime: created.endTime.toUtc()),
        extendedProperties: calendar.EventExtendedProperties(
          private: <String, String>{'nudgeSyncId': created.syncId},
        ),
      );

      final syncResult = await repoA.synchronize();
      expect(syncResult.hasError, isFalse);
      expect(syncResult.calendarBackfilled, 0);
      expect(calendarMirror.insertCount, 0);

      final localUpdated = await localA.getAppointmentById(created.id);
      expect(localUpdated?.googleCalendarEventId, 'existing_nudge_evt');
      final cloudDocs = await firestore.fetchAppointments(testUser.id);
      expect(cloudDocs.single.googleCalendarEventId, 'existing_nudge_evt');
    });

    test('synchronize patches stale event details when Nudge calendar event drifted', () async {
      final created = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Fernando Cruz',
          clientRawPhone: '5500112233',
          clientPhoneE164: '5215500112233',
          title: 'Consulta actualizada',
          startTime: DateTime(2026, 12, 3, 9, 0),
          endTime: DateTime(2026, 12, 3, 10, 0),
        ),
      );
      final eventId = created.googleCalendarEventId!;

      // Simulate remote Calendar event holding an outdated summary.
      calendarMirror.eventsById[eventId] = calendar.Event(
        id: eventId,
        status: 'confirmed',
        summary: 'Título antiguo — Fernando Cruz',
        start: calendar.EventDateTime(dateTime: created.startTime.toUtc()),
        end: calendar.EventDateTime(dateTime: created.endTime.toUtc()),
        extendedProperties: calendar.EventExtendedProperties(
          private: <String, String>{'nudgeSyncId': created.syncId},
        ),
      );

      final syncResult = await repoA.synchronize();
      expect(syncResult.hasError, isFalse);
      expect(syncResult.calendarBackfilled, 1);
      expect(calendarMirror.patchCount, 1);
      expect(
        calendarMirror.eventsById[eventId]?.summary,
        CalendarEventMetadataCodec.buildEventSummary(
          title: 'Consulta actualizada',
          clientName: 'Fernando Cruz',
        ),
      );
    });

    test('synchronize skips past concluded appointments before today when verifying Calendar', () async {
      // nowProvider is 2026-11-28 08:00; appointment ended yesterday (2026-11-27 18:00).
      final past = await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Paola Rivas',
          clientRawPhone: '5522446688',
          clientPhoneE164: '5215522446688',
          title: 'Cita pasada',
          startTime: DateTime(2026, 11, 27, 17, 0),
          endTime: DateTime(2026, 11, 27, 18, 0),
        ),
      );
      expect(calendarMirror.insertCount, 1);
      expect(past.syncStatus, AppointmentSyncStatus.synced);

      calendarMirror.eventsById.clear();

      final syncResult = await repoA.synchronize();
      expect(syncResult.hasError, isFalse);
      expect(syncResult.calendarBackfilled, 0);
      expect(calendarMirror.insertCount, 1);
      expect(calendarMirror.listActiveEventsCount, 0);
    });

    test('synchronize surfaces Calendar error while keeping Firestore sync intact on 403', () async {
      await repoA.createAppointment(
        AppointmentInput(
          clientName: 'Renata Luna',
          clientRawPhone: '5566778899',
          clientPhoneE164: '5215566778899',
          title: 'Sesión protegida',
          startTime: DateTime(2026, 12, 5, 13, 0),
          endTime: DateTime(2026, 12, 5, 14, 0),
        ),
      );

      calendarMirror.errorToThrowOnList = calendar.DetailedApiRequestError(
        403,
        'Insufficient scopes',
      );

      final syncResult = await repoA.synchronize();
      expect(syncResult.syncedAt, isNotNull);
      expect(syncResult.hasError, isTrue);
      expect(syncResult.errorMessage, contains('HTTP 403'));
      expect(syncResult.calendarBackfilled, 0);
    });
  });
}
