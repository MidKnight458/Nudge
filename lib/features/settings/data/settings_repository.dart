import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/database/app_database.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/settings/domain/app_preferences.dart';

/// Persists customizable client terminology, services, and schedule slots in
/// Drift SQLite and synchronizes them with Cloud Firestore.
class SettingsRepository {
  SettingsRepository(
    this._db, {
    FirestoreSyncDatasource? firestoreDatasource,
    String? Function()? currentUserId,
    Future<bool> Function()? isOnline,
  }) : _cloud = firestoreDatasource,
       _userIdProvider = currentUserId,
       _onlineCheck = isOnline;

  final AppDatabase _db;
  final FirestoreSyncDatasource? _cloud;
  final String? Function()? _userIdProvider;
  final Future<bool> Function()? _onlineCheck;

  Stream<AppPreferencesEntity> watchPreferences() {
    final query = _db.select(_db.appSettings)
      ..where((s) => s.id.equals(1))
      ..limit(1);
    return query.watchSingleOrNull().map(
      (AppSettingsRecord? row) => row == null
          ? AppPreferencesEntity(
              updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            )
          : _mapRecord(row),
    );
  }

  Future<AppPreferencesEntity> getPreferences() async {
    final row =
        await (_db.select(_db.appSettings)
              ..where((s) => s.id.equals(1))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return AppPreferencesEntity(
        updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    return _mapRecord(row);
  }

  Future<void> saveClientLabels({
    required String plural,
    required String singular,
  }) async {
    final cleanPlural = plural.trim().isNotEmpty
        ? plural.trim()
        : AppConstants.defaultClientLabelPlural;
    final cleanSingular = singular.trim().isNotEmpty
        ? singular.trim()
        : AppConstants.defaultClientLabelSingular;

    final current = await getPreferences();
    await _savePreferences(
      current.copyWith(
        clientLabelPlural: cleanPlural,
        clientLabelSingular: cleanSingular,
      ),
    );
  }

  Future<void> saveServices(List<CustomServiceItem> services) async {
    final cleanServices = services
        .where((CustomServiceItem s) => s.name.trim().isNotEmpty)
        .map(
          (CustomServiceItem s) => s.copyWith(
            name: s.name.trim(),
            durationMinutes: s.durationMinutes > 0
                ? s.durationMinutes
                : AppConstants.defaultSlotDurationMinutes,
          ),
        )
        .toList(growable: false);

    final current = await getPreferences();
    await _savePreferences(current.copyWith(services: cleanServices));
  }

  Future<void> saveSchedule(ScheduleConfig schedule) async {
    final current = await getPreferences();
    await _savePreferences(current.copyWith(schedule: schedule));
  }

  Future<void> _savePreferences(AppPreferencesEntity next) async {
    final nowUtc = _truncateUtcSeconds(DateTime.now());
    final saved = next.copyWith(updatedAt: nowUtc);

    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(1),
            clientLabelPlural: Value(saved.clientLabelPlural),
            clientLabelSingular: Value(saved.clientLabelSingular),
            servicesJson: Value(CustomServiceItem.encodeList(saved.services)),
            scheduleJson: Value(saved.schedule.toJson()),
            updatedAt: Value(nowUtc),
          ),
        );

    await _pushToCloud(saved);
  }

  Future<void> applyCloudPreferences(CloudSettingsDocument? remote) async {
    if (remote == null) {
      return;
    }

    final local = await getPreferences();
    final remoteSec = remote.updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    final localSec = local.updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000;

    if (remoteSec <= localSec) {
      return;
    }

    final remoteUtc = _truncateUtcSeconds(remote.updatedAt);
    await _db
        .into(_db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion(
            id: const Value(1),
            clientLabelPlural: Value(remote.clientLabelPlural),
            clientLabelSingular: Value(remote.clientLabelSingular),
            servicesJson: Value(CustomServiceItem.encodeList(remote.services)),
            scheduleJson: Value(remote.schedule.toJson()),
            updatedAt: Value(remoteUtc),
          ),
        );
  }

  Future<void> syncWithCloud() async {
    final firestore = _cloud;
    final uid = _userIdProvider?.call();
    if (firestore == null || uid == null || uid.isEmpty) {
      return;
    }
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(true));
    if (!online) {
      return;
    }

    final remote = await firestore.fetchSettings(uid);
    final local = await getPreferences();
    final localSec = local.updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000;

    if (remote == null) {
      final hasCustomizedLocal =
          localSec > 0 ||
          local.services.isNotEmpty ||
          local.schedule.slotMinutesFromMidnight.isNotEmpty ||
          local.clientLabelPlural != AppConstants.defaultClientLabelPlural ||
          local.clientLabelSingular != AppConstants.defaultClientLabelSingular;
      if (hasCustomizedLocal) {
        await firestore.upsertSettings(
          uid,
          CloudSettingsDocument.fromEntity(local),
        );
      }
      return;
    }

    final remoteSec = remote.updatedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (remoteSec > localSec) {
      await applyCloudPreferences(remote);
    } else if (localSec > remoteSec) {
      await firestore.upsertSettings(
        uid,
        CloudSettingsDocument.fromEntity(local),
      );
    }
  }

  Future<void> _pushToCloud(AppPreferencesEntity entity) async {
    final firestore = _cloud;
    final uid = _userIdProvider?.call();
    if (firestore == null || uid == null || uid.isEmpty) {
      return;
    }
    final online = await (_onlineCheck?.call() ?? Future<bool>.value(true));
    if (!online) {
      return;
    }

    try {
      await firestore.upsertSettings(
        uid,
        CloudSettingsDocument.fromEntity(entity),
      );
    } catch (_) {
      // Next reconnect/sync will reconcile local updatedAt against cloud.
    }
  }

  AppPreferencesEntity _mapRecord(AppSettingsRecord row) {
    return AppPreferencesEntity(
      clientLabelPlural: row.clientLabelPlural,
      clientLabelSingular: row.clientLabelSingular,
      services: CustomServiceItem.decodeList(row.servicesJson),
      schedule: ScheduleConfig.fromJson(row.scheduleJson),
      updatedAt: row.updatedAt.toLocal(),
    );
  }

  DateTime _truncateUtcSeconds(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMillisecondsSinceEpoch(
      (utc.millisecondsSinceEpoch ~/ 1000) * 1000,
      isUtc: true,
    );
  }
}

final settingsRepositoryProvider = Provider<SettingsRepository>((Ref ref) {
  return SettingsRepository(
    ref.watch(appDatabaseProvider),
    firestoreDatasource: ref.watch(firestoreSyncDatasourceProvider),
    currentUserId: () => ref.read(authControllerProvider).user?.id,
    isOnline: () => ref.read(connectivityServiceProvider).isOnline,
  );
});

final appPreferencesProvider = StreamProvider<AppPreferencesEntity>((Ref ref) {
  return ref.watch(settingsRepositoryProvider).watchPreferences();
});
