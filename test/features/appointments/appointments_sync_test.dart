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
  Future<AuthenticatedCalendarClient?> openCalendarClient() async => null;

  void setUser(AuthUser? user) {
    _currentUser = user;
    _controller.add(user);
  }
}

class _SharedFakeGoogleCalendarDatasource implements GoogleCalendarDatasource {
  final Map<String, calendar.Event> eventsById = <String, calendar.Event>{};
  int insertCount = 0;
  int patchCount = 0;
  int deleteCount = 0;
  int _nextId = 1;
  Object? errorToThrowOnWrite;

  @override
  Future<String> insertEvent(AppointmentEntity appointment) async {
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
    );
    return id;
  }

  @override
  Future<void> patchEvent(AppointmentEntity appointment) async {
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
  final Map<String, StreamController<List<CloudAppointmentDocument>>>
  _appointmentControllers =
      <String, StreamController<List<CloudAppointmentDocument>>>{};
  final Map<String, StreamController<List<CloudTemplateDocument>>>
  _templateControllers =
      <String, StreamController<List<CloudTemplateDocument>>>{};

  int upsertAppointmentCount = 0;
  int markDeletedCount = 0;

  Map<String, CloudAppointmentDocument> _userAppointments(String uid) =>
      _appointmentsByUid.putIfAbsent(
        uid,
        () => <String, CloudAppointmentDocument>{},
      );

  Map<String, CloudTemplateDocument> _userTemplates(String uid) =>
      _templatesByUid.putIfAbsent(uid, () => <String, CloudTemplateDocument>{});

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

  Future<void> dispose() async {
    for (final controller in _appointmentControllers.values) {
      await controller.close();
    }
    for (final controller in _templateControllers.values) {
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
  });
}
