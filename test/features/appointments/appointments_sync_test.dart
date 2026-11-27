import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/appointments_repository_impl.dart';
import 'package:nudge/features/appointments/data/google_calendar_datasource.dart';
import 'package:nudge/features/appointments/data/local_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

class _FakeConnectivityService implements ConnectivityService {
  _FakeConnectivityService({this.online = true});

  bool online;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  @override
  Future<bool> get isOnline async => online;

  @override
  Stream<bool> get onConnectivityChanged => _controller.stream;

  void dispose() => _controller.close();
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({AuthUser? initialUser}) : _user = initialUser;

  AuthUser? _user;
  final StreamController<AuthUser?> _controller =
      StreamController<AuthUser?>.broadcast();

  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  AuthUser? get currentUser => _user;

  @override
  Future<AuthenticatedCalendarClient?> openCalendarClient() async => null;

  @override
  Future<AuthUser?> signIn() async => _user;

  @override
  Future<AuthUser?> signInSilently() async => _user;

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }

  @override
  Future<void> clearAuthCache() async {}

  void dispose() => _controller.close();
}

class _FakeGoogleCalendarDatasource implements GoogleCalendarDatasource {
  int insertCount = 0;
  int patchCount = 0;
  int deleteCount = 0;
  int listDeltaCalls = 0;
  DateTime? lastTimeMinPassed;
  String? lastSyncTokenPassed;

  final List<String> deletedRemoteIds = <String>[];
  final List<AppointmentEntity> insertedEvents = <AppointmentEntity>[];
  final List<AppointmentEntity> patchedEvents = <AppointmentEntity>[];

  Future<CalendarDeltaPage> Function({String? syncToken, DateTime? timeMin})?
  onListEventsDelta;

  @override
  Future<String> insertEvent(AppointmentEntity appointment) async {
    insertCount++;
    insertedEvents.add(appointment);
    return 'remote-evt-$insertCount';
  }

  @override
  Future<void> patchEvent(AppointmentEntity appointment) async {
    patchCount++;
    patchedEvents.add(appointment);
  }

  @override
  Future<void> deleteEvent(String googleCalendarEventId) async {
    deleteCount++;
    deletedRemoteIds.add(googleCalendarEventId);
  }

  @override
  Future<CalendarDeltaPage> listEventsDelta({
    String? syncToken,
    DateTime? timeMin,
  }) async {
    listDeltaCalls++;
    lastSyncTokenPassed = syncToken;
    lastTimeMinPassed = timeMin;
    if (onListEventsDelta != null) {
      return onListEventsDelta!(syncToken: syncToken, timeMin: timeMin);
    }
    return const CalendarDeltaPage(
      events: <CalendarRemoteEvent>[],
      nextSyncToken: 'sync-token-1',
    );
  }
}

void main() {
  group('CalendarEventMetadataCodec', () {
    test('round-trips summary, description metadata, and clean notes', () {
      final summary = CalendarEventMetadataCodec.buildEventSummary(
        title: 'Terapia física',
        clientName: 'Sofía Ramírez',
      );
      final encoded = CalendarEventMetadataCodec.encodeDescription(
        clientName: 'Sofía Ramírez',
        clientPhoneE164: '524611234567',
        title: 'Terapia física',
        notes: 'Traer estudios previos',
      );

      // Re-encoding an already-encoded description must not duplicate [Nudge].
      final reEncoded = CalendarEventMetadataCodec.encodeDescription(
        clientName: 'Sofía Ramírez',
        clientPhoneE164: '524611234567',
        title: 'Terapia física',
        notes: encoded,
      );

      final decoded = CalendarEventMetadataCodec.decodeEvent(
        summary: summary,
        description: reEncoded,
      );

      expect(decoded.title, 'Terapia física');
      expect(decoded.clientName, 'Sofía Ramírez');
      expect(decoded.clientPhoneE164, '524611234567');
      expect(decoded.notes, 'Traer estudios previos');
    });

    test(
      'gracefully decodes events created directly on Google Calendar web',
      () {
        final decoded = CalendarEventMetadataCodec.decodeEvent(
          summary: 'Reunión externa',
          description: 'Sala 3, edificio central',
        );

        expect(decoded.title, 'Reunión externa');
        expect(decoded.clientName, 'Google Calendar');
        expect(decoded.clientPhoneE164, '');
        expect(decoded.notes, 'Sala 3, edificio central');
      },
    );
  });

  group('AppointmentsRepositoryImpl offline-first & delta sync', () {
    late AppDatabase db;
    late LocalAppointmentsDatasource local;
    late _FakeGoogleCalendarDatasource remote;
    late _FakeConnectivityService connectivity;
    late _FakeAuthRepository auth;
    late AppointmentsRepositoryImpl repository;
    late DateTime fixedNow;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      local = LocalAppointmentsDatasource(db);
      remote = _FakeGoogleCalendarDatasource();
      connectivity = _FakeConnectivityService(online: false);
      auth = _FakeAuthRepository(
        initialUser: const AuthUser(
          id: 'user-1',
          email: 'pro@gmail.com',
          displayName: 'Pro User',
        ),
      );
      fixedNow = DateTime(2026, 11, 27, 12, 0);
      repository = AppointmentsRepositoryImpl(
        localDatasource: local,
        remoteDatasource: remote,
        connectivityService: connectivity,
        authRepository: auth,
        nowProvider: () => fixedNow,
      );
    });

    tearDown(() async {
      connectivity.dispose();
      auth.dispose();
      await db.close();
    });

    test(
      'queues offline create, update, and delete then syncs when online',
      () async {
        final day = DateTime(2026, 11, 28);
        final input = AppointmentInput(
          clientName: 'Ana López',
          clientRawPhone: '461 123 4567',
          clientPhoneE164: '524611234567',
          clientGoogleContactId: 'g-1',
          title: 'Diseño de cejas',
          notes: 'Primera visita',
          startTime: DateTime(2026, 11, 28, 10, 0),
          endTime: DateTime(2026, 11, 28, 11, 0),
        );

        // 1. Create offline -> pending_create
        final created = await repository.createAppointment(input);
        expect(created.syncStatus, AppointmentSyncStatus.pendingCreate);
        expect(created.googleCalendarEventId, isNull);
        expect(remote.insertCount, 0);

        // 2. Reconnect and sync -> pushed to remote and marked synced
        connectivity.online = true;
        final firstSync = await repository.synchronize();
        expect(firstSync.pushedCreated, 1);
        expect(remote.insertCount, 1);

        var dayItems = await repository.watchAppointmentsForDay(day).first;
        expect(dayItems, hasLength(1));
        expect(dayItems.first.syncStatus, AppointmentSyncStatus.synced);
        expect(dayItems.first.googleCalendarEventId, 'remote-evt-1');

        // 3. Go offline and update -> pending_update, then sync -> patchEvent
        connectivity.online = false;
        final updated = await repository.updateAppointment(
          dayItems.first,
          AppointmentInput(
            clientName: 'Ana López',
            clientRawPhone: '461 123 4567',
            clientPhoneE164: '524611234567',
            clientGoogleContactId: 'g-1',
            title: 'Diseño de cejas VIP',
            notes: 'Confirmado',
            startTime: DateTime(2026, 11, 28, 10, 30),
            endTime: DateTime(2026, 11, 28, 11, 30),
          ),
        );
        expect(updated.syncStatus, AppointmentSyncStatus.pendingUpdate);

        connectivity.online = true;
        final secondSync = await repository.synchronize();
        expect(secondSync.pushedUpdated, 1);
        expect(remote.patchCount, 1);

        // 4. Go offline and delete -> hidden locally, pending_delete -> purged on sync
        connectivity.online = false;
        final syncedItem =
            (await repository.watchAppointmentsForDay(day).first).single;
        await repository.deleteAppointment(syncedItem);

        dayItems = await repository.watchAppointmentsForDay(day).first;
        expect(dayItems, isEmpty);
        expect(await repository.watchPendingSyncCount().first, 1);

        connectivity.online = true;
        final thirdSync = await repository.synchronize();
        expect(thirdSync.pushedDeleted, 1);
        expect(remote.deletedRemoteIds, <String>['remote-evt-1']);
        expect(await repository.watchPendingSyncCount().first, 0);
      },
    );

    test(
      'applies remote delta events and recovers from HTTP 410 Gone',
      () async {
        connectivity.online = true;
        await local.saveSyncMetadata(
          syncToken: 'expired-token',
          lastSyncTimestamp: fixedNow.subtract(const Duration(days: 1)),
        );

        var callIndex = 0;
        remote.onListEventsDelta =
            ({String? syncToken, DateTime? timeMin}) async {
              callIndex++;
              if (callIndex == 1) {
                expect(syncToken, 'expired-token');
                expect(timeMin, isNull);
                throw const SyncTokenExpiredException();
              }
              expect(syncToken, isNull);
              expect(timeMin, isNotNull);
              return CalendarDeltaPage(
                nextSyncToken: 'fresh-sync-token',
                events: <CalendarRemoteEvent>[
                  CalendarRemoteEvent(
                    id: 'cal-100',
                    status: 'confirmed',
                    summary: CalendarEventMetadataCodec.buildEventSummary(
                      title: 'Consulta médica',
                      clientName: 'Diego Soto',
                    ),
                    description: CalendarEventMetadataCodec.encodeDescription(
                      clientName: 'Diego Soto',
                      clientPhoneE164: '524615551234',
                      title: 'Consulta médica',
                      notes: 'Ayuno de 8h',
                    ),
                    startTime: DateTime(2026, 11, 29, 9, 0),
                    endTime: DateTime(2026, 11, 29, 10, 0),
                  ),
                ],
              );
            };

        final result = await repository.synchronize();
        expect(result.usedFullResync, isTrue);
        expect(result.pulledUpserted, 1);
        expect(remote.listDeltaCalls, 2);

        final metadata = await local.getSyncMetadata();
        expect(metadata.syncToken, 'fresh-sync-token');

        final imported = await repository
            .watchAppointmentsForDay(DateTime(2026, 11, 29))
            .first;
        expect(imported, hasLength(1));
        expect(imported.first.clientName, 'Diego Soto');
        expect(imported.first.clientPhoneE164, '524615551234');
        expect(imported.first.title, 'Consulta médica');
        expect(imported.first.notes, 'Ayuno de 8h');

        // Subsequent delta sync uses fresh token and deletes cancelled events.
        remote.onListEventsDelta =
            ({String? syncToken, DateTime? timeMin}) async {
              expect(syncToken, 'fresh-sync-token');
              return const CalendarDeltaPage(
                nextSyncToken: 'fresh-sync-token-2',
                events: <CalendarRemoteEvent>[
                  CalendarRemoteEvent(id: 'cal-100', status: 'cancelled'),
                ],
              );
            };

        final deltaResult = await repository.synchronize();
        expect(deltaResult.usedFullResync, isFalse);
        expect(deltaResult.pulledDeleted, 1);
        expect(
          await repository
              .watchAppointmentsForDay(DateTime(2026, 11, 29))
              .first,
          isEmpty,
        );
      },
    );

    test('marks reminderSent flag cleanly in SQLite', () async {
      final created = await repository.createAppointment(
        AppointmentInput(
          clientName: 'Elena Ruiz',
          clientRawPhone: '4617778899',
          clientPhoneE164: '524617778899',
          title: 'Masaje terapéutico',
          startTime: DateTime(2026, 11, 28, 17, 0),
          endTime: DateTime(2026, 11, 28, 18, 0),
        ),
      );
      expect(created.reminderSent, isFalse);

      await repository.markReminderSent(created.id);
      final items = await repository
          .watchAppointmentsForDay(DateTime(2026, 11, 28))
          .first;
      expect(items.single.reminderSent, isTrue);
    });

    test(
      'surfaces clear error messages for HTTP 403 and HTTP 401 API errors',
      () async {
        connectivity.online = true;
        remote.onListEventsDelta =
            ({String? syncToken, DateTime? timeMin}) async {
              throw calendar.DetailedApiRequestError(403, 'Forbidden');
            };

        final forbiddenResult = await repository.synchronize();
        expect(forbiddenResult.hasError, isTrue);
        expect(forbiddenResult.errorMessage, contains('HTTP 403'));

        remote.onListEventsDelta =
            ({String? syncToken, DateTime? timeMin}) async {
              throw calendar.DetailedApiRequestError(401, 'Unauthorized');
            };

        final unauthorizedResult = await repository.synchronize();
        expect(unauthorizedResult.hasError, isTrue);
        expect(unauthorizedResult.errorMessage, contains('HTTP 401'));
      },
    );

    test(
      'synchronizes appointments bi-directionally across two separate devices',
      () async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        // Shared fake Google Calendar backend between Device A and Device B.
        final serverEvents = <String, CalendarRemoteEvent>{};
        var revision = 0;

        GoogleCalendarDatasource createSharedRemote() {
          return _SharedFakeGoogleCalendarDatasource(
            serverEvents: serverEvents,
            nextId: () => 'shared-evt-${++revision}',
          );
        }

        final dbB = AppDatabase(NativeDatabase.memory());
        addTearDown(dbB.close);

        final repoA = AppointmentsRepositoryImpl(
          localDatasource: local,
          remoteDatasource: createSharedRemote(),
          connectivityService: connectivity,
          authRepository: auth,
          nowProvider: () => fixedNow,
        );
        final repoB = AppointmentsRepositoryImpl(
          localDatasource: LocalAppointmentsDatasource(dbB),
          remoteDatasource: createSharedRemote(),
          connectivityService: connectivity,
          authRepository: auth,
          nowProvider: () => fixedNow,
        );

        connectivity.online = true;
        final day = DateTime(2026, 11, 30);

        // Device A creates an appointment while online -> synced to Calendar.
        await repoA.createAppointment(
          AppointmentInput(
            clientName: 'Lucía Vega',
            clientRawPhone: '461 888 9900',
            clientPhoneE164: '524618889900',
            title: 'Limpieza facial',
            notes: 'Piel sensible',
            startTime: DateTime(2026, 11, 30, 11, 0),
            endTime: DateTime(2026, 11, 30, 12, 0),
          ),
        );

        // Device B syncs and receives Device A's appointment.
        final syncB1 = await repoB.synchronize();
        expect(syncB1.hasError, isFalse);
        expect(syncB1.pulledUpserted, 1);

        final itemsB = await repoB.watchAppointmentsForDay(day).first;
        expect(itemsB, hasLength(1));
        expect(itemsB.single.clientName, 'Lucía Vega');
        expect(itemsB.single.clientPhoneE164, '524618889900');
        expect(itemsB.single.title, 'Limpieza facial');

        // Device B edits the appointment -> Device A picks it up incrementally.
        await repoB.updateAppointment(
          itemsB.single,
          AppointmentInput(
            clientName: 'Lucía Vega',
            clientRawPhone: '461 888 9900',
            clientPhoneE164: '524618889900',
            title: 'Limpieza facial + Mascarilla',
            notes: 'Confirmada',
            startTime: DateTime(2026, 11, 30, 11, 30),
            endTime: DateTime(2026, 11, 30, 12, 30),
          ),
        );

        final syncA2 = await repoA.synchronize();
        expect(syncA2.hasError, isFalse);
        expect(syncA2.pulledUpserted, 1);

        final itemsA = await repoA.watchAppointmentsForDay(day).first;
        expect(itemsA.single.title, 'Limpieza facial + Mascarilla');
        expect(itemsA.single.notes, 'Confirmada');
      },
    );
  });
}

class _SharedFakeGoogleCalendarDatasource implements GoogleCalendarDatasource {
  _SharedFakeGoogleCalendarDatasource({
    required this.serverEvents,
    required this.nextId,
  });

  final Map<String, CalendarRemoteEvent> serverEvents;
  final String Function() nextId;

  @override
  Future<String> insertEvent(AppointmentEntity appointment) async {
    final id = nextId();
    serverEvents[id] = CalendarRemoteEvent(
      id: id,
      status: 'confirmed',
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
      startTime: appointment.startTime,
      endTime: appointment.endTime,
    );
    return id;
  }

  @override
  Future<void> patchEvent(AppointmentEntity appointment) async {
    final id = appointment.googleCalendarEventId!;
    serverEvents[id] = CalendarRemoteEvent(
      id: id,
      status: 'confirmed',
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
      startTime: appointment.startTime,
      endTime: appointment.endTime,
    );
  }

  @override
  Future<void> deleteEvent(String googleCalendarEventId) async {
    serverEvents[googleCalendarEventId] = CalendarRemoteEvent(
      id: googleCalendarEventId,
      status: 'cancelled',
    );
  }

  @override
  Future<CalendarDeltaPage> listEventsDelta({
    String? syncToken,
    DateTime? timeMin,
  }) async {
    return CalendarDeltaPage(
      events: serverEvents.values.toList(growable: false),
      nextSyncToken: 'tok-${serverEvents.length}',
    );
  }
}
