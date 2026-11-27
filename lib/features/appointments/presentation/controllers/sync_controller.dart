import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/appointments_repository_impl.dart';
import 'package:nudge/features/appointments/data/firestore_appointments_datasource.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';

/// UI state reflecting connectivity and Google Calendar synchronization status.
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
/// Google Calendar mirroring, and account changes.
class SyncController extends Notifier<SyncUiState> {
  StreamSubscription<bool>? _connectivitySubscription;
  StreamSubscription<List<CloudAppointmentDocument>>?
  _appointmentsCloudSubscription;
  StreamSubscription<List<CloudTemplateDocument>>? _templatesCloudSubscription;
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
        _startRealtimeListeners(nextUid);
        unawaited(syncNow(silent: true));
      } else if (next.user != null &&
          !next.isLoading &&
          nextUid != null &&
          _activeCloudUid != nextUid) {
        _startRealtimeListeners(nextUid);
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

  Future<void> _initialize() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final online = await connectivity.isOnline;
    final lastSync = await _repository.getLastSyncTimestamp();
    state = state.copyWith(isOnline: online, lastSyncAt: lastSync);

    final authState = ref.read(authControllerProvider);
    final uid = authState.user?.id;
    if (!authState.isLoading && authState.isSignedIn && uid != null) {
      _startRealtimeListeners(uid);
      if (online) {
        await syncNow(silent: true);
      }
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
        .listen(
          (List<CloudAppointmentDocument> documents) {
            unawaited(_applyCloudAppointments(documents));
          },
          onError: (_) {
            // Firestore SDK automatically recovers temporary stream errors.
          },
        );

    _templatesCloudSubscription = _firestoreDatasource
        .watchTemplates(uid)
        .listen((List<CloudTemplateDocument> documents) {
          unawaited(_templatesRepository.applyCloudTemplates(documents));
        }, onError: (_) {});
  }

  void _stopRealtimeListeners() {
    _appointmentsCloudSubscription?.cancel();
    _appointmentsCloudSubscription = null;
    _templatesCloudSubscription?.cancel();
    _templatesCloudSubscription = null;
    _activeCloudUid = null;
  }

  Future<void> _applyCloudAppointments(
    List<CloudAppointmentDocument> documents,
  ) async {
    try {
      await _repository.applyCloudSnapshot(documents);
      state = state.copyWith(lastSyncAt: DateTime.now(), clearError: true);
    } catch (_) {
      // Transient merge issues will be retried on the next snapshot/sync.
    }
  }

  Future<SyncResult> syncNow({bool silent = false}) async {
    if (state.isSyncing) {
      return state.lastResult ?? const SyncResult();
    }

    state = state.copyWith(isSyncing: true, clearError: true);

    final result = await _repository.synchronize();
    if (!result.wasSkipped) {
      try {
        await _templatesRepository.syncWithCloud();
      } catch (_) {
        // Template sync failures do not block appointment sync.
      }
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
