import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/appointments_repository_impl.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/clients/data/clients_repository.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';

/// UI state reflecting connectivity and cloud synchronization status.
class SyncUiState {
  const SyncUiState({
    this.isSyncing = false,
    this.isOnline = true,
    this.lastSyncAt,
    this.lastResult,
    this.lastError,
  });

  final bool isSyncing;
  final bool isOnline;
  final DateTime? lastSyncAt;
  final SyncResult? lastResult;
  final String? lastError;

  SyncUiState copyWith({
    bool? isSyncing,
    bool? isOnline,
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    SyncResult? lastResult,
    String? lastError,
    bool clearError = false,
  }) {
    return SyncUiState(
      isSyncing: isSyncing ?? this.isSyncing,
      isOnline: isOnline ?? this.isOnline,
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      lastResult: lastResult ?? this.lastResult,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

/// Orchestrates real-time Cloud Firestore listeners, offline queue drain,
/// Google Calendar/Drive mirroring, and safe account switching.
class SyncController extends Notifier<SyncUiState> {
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<List<CloudAppointmentDocument>>?
  _appointmentsCloudSubscription;
  StreamSubscription<List<CloudTemplateDocument>>? _templatesCloudSubscription;
  StreamSubscription<List<CloudClientDocument>>? _clientsCloudSubscription;
  StreamSubscription<List<CloudAttachmentDocument>>?
  _attachmentsCloudSubscription;
  StreamSubscription<CloudSettingsDocument?>? _settingsCloudSubscription;
  String? _activeCloudUid;

  @override
  SyncUiState build() {
    final connectivity = ref.watch(connectivityServiceProvider);

    _connectivitySubscription?.cancel();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      bool online,
    ) {
      state = state.copyWith(isOnline: online);
      if (online && ref.read(authControllerProvider).isSignedIn) {
        unawaited(syncNow(silent: true));
      }
    });

    ref.listen<AuthState>(authControllerProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      final previousUid = previous?.user?.id;
      final nextUid = next.user?.id;
      final userChanged = previousUid != nextUid;
      final finishedSignIn =
          next.user != null &&
          !next.isLoading &&
          (userChanged || previous?.isLoading == true);

      if (finishedSignIn && nextUid != null) {
        unawaited(_handleAuthenticatedSession(nextUid));
      } else if (next.user != null &&
          !next.isLoading &&
          nextUid != null &&
          _activeCloudUid != nextUid) {
        unawaited(_handleAuthenticatedSession(nextUid));
      } else if (next.user == null && previous?.user != null) {
        _stopRealtimeListeners();
        final repo = ref.read(appointmentsRepositoryProvider);
        if (repo is AppointmentsRepositoryImpl) {
          unawaited(repo.resetSyncMetadata());
        }
        state = state.copyWith(clearLastSyncAt: true, clearError: true);
      }
    });

    ref.onDispose(() {
      _connectivitySubscription?.cancel();
      _stopRealtimeListeners();
    });

    Future<void>.microtask(_initialize);
    return const SyncUiState();
  }

  AppointmentsRepository get _repository =>
      ref.read(appointmentsRepositoryProvider);

  FirestoreSyncDatasource get _firestoreDatasource =>
      ref.read(firestoreSyncDatasourceProvider);

  ReminderTemplatesRepository get _templatesRepository =>
      ref.read(reminderTemplatesRepositoryProvider);

  ClientsRepository get _clientsRepository =>
      ref.read(clientsRepositoryProvider);

  SettingsRepository get _settingsRepository =>
      ref.read(settingsRepositoryProvider);

  Future<void> _initialize() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final online = await connectivity.isOnline;
    final lastSync = await _repository.getLastSyncTimestamp();
    state = state.copyWith(isOnline: online, lastSyncAt: lastSync);

    final authState = ref.read(authControllerProvider);
    final uid = authState.user?.id;
    if (!authState.isLoading && authState.isSignedIn && uid != null) {
      await _handleAuthenticatedSession(uid, triggerSync: online);
    }
  }

  Future<void> _handleAuthenticatedSession(
    String uid, {
    bool triggerSync = true,
  }) async {
    final local = ref.read(localAppointmentsDatasourceProvider);
    final previousAccountUid = await local.getLastAccountUid();
    if (previousAccountUid != null &&
        previousAccountUid.isNotEmpty &&
        previousAccountUid != uid) {
      _stopRealtimeListeners();
      await _clientsRepository.clearLocalAttachmentFiles();
      await local.clearAllLocalUserData();
      state = state.copyWith(clearLastSyncAt: true, clearError: true);
    }
    await local.setLastAccountUid(uid);

    _startRealtimeListeners(uid);
    if (triggerSync) {
      unawaited(syncNow(silent: true));
    }
  }

  void _startRealtimeListeners(String uid) {
    if (_activeCloudUid == uid && _appointmentsCloudSubscription != null) {
      return;
    }

    _stopRealtimeListeners();
    _activeCloudUid = uid;

    _appointmentsCloudSubscription = _firestoreDatasource
        .watchAppointments(uid)
        .listen((List<CloudAppointmentDocument> documents) {
          unawaited(_applyCloudAppointments(documents));
        }, onError: (_) {});

    _templatesCloudSubscription = _firestoreDatasource
        .watchTemplates(uid)
        .listen((List<CloudTemplateDocument> documents) {
          unawaited(_templatesRepository.applyCloudTemplates(documents));
        }, onError: (_) {});

    _clientsCloudSubscription = _firestoreDatasource.watchClients(uid).listen((
      List<CloudClientDocument> documents,
    ) {
      unawaited(_clientsRepository.applyCloudClients(documents));
    }, onError: (_) {});

    _attachmentsCloudSubscription = _firestoreDatasource
        .watchClientAttachments(uid)
        .listen((List<CloudAttachmentDocument> documents) {
          unawaited(_clientsRepository.applyCloudAttachments(documents));
        }, onError: (_) {});

    _settingsCloudSubscription = _firestoreDatasource.watchSettings(uid).listen(
      (CloudSettingsDocument? document) {
        unawaited(_settingsRepository.applyCloudPreferences(document));
      },
      onError: (_) {},
    );
  }

  void _stopRealtimeListeners() {
    _appointmentsCloudSubscription?.cancel();
    _appointmentsCloudSubscription = null;
    _templatesCloudSubscription?.cancel();
    _templatesCloudSubscription = null;
    _clientsCloudSubscription?.cancel();
    _clientsCloudSubscription = null;
    _attachmentsCloudSubscription?.cancel();
    _attachmentsCloudSubscription = null;
    _settingsCloudSubscription?.cancel();
    _settingsCloudSubscription = null;
    _activeCloudUid = null;
  }

  Future<void> _applyCloudAppointments(
    List<CloudAppointmentDocument> documents,
  ) async {
    try {
      await _repository.applyCloudSnapshot(documents);
      state = state.copyWith(lastSyncAt: DateTime.now(), clearError: true);
    } catch (_) {}
  }

  Future<SyncResult> syncNow({bool silent = false}) async {
    if (state.isSyncing) {
      return state.lastResult ?? const SyncResult();
    }

    state = state.copyWith(isSyncing: true, clearError: true);

    try {
      await _settingsRepository.syncWithCloud();
    } catch (_) {}

    final result = await _repository.synchronize(interactive: !silent);
    if (!result.wasSkipped) {
      try {
        await _clientsRepository.syncWithCloud();
      } catch (_) {}
      try {
        await _templatesRepository.syncWithCloud();
      } catch (_) {}
    }

    state = state.copyWith(
      isSyncing: false,
      lastResult: result,
      lastSyncAt: result.syncedAt ?? state.lastSyncAt,
      lastError: result.hasError
          ? result.errorMessage
          : (silent ? null : result.skippedReason),
      clearError: !result.hasError && (silent || !result.wasSkipped),
    );

    return result;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncUiState>(
  SyncController.new,
);
