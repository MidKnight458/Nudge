import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/network/connectivity_service.dart';
import 'package:nudge/features/appointments/data/appointments_repository_impl.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';

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

/// Orchestrates manual sync, reconnect sync worker, and account changes.
class SyncController extends Notifier<SyncUiState> {
  StreamSubscription<bool>? _connectivitySubscription;

  @override
  SyncUiState build() {
    final connectivity = ref.watch(connectivityServiceProvider);

    _connectivitySubscription?.cancel();
    _connectivitySubscription = connectivity.onConnectivityChanged.listen((
      bool online,
    ) {
      final wasOffline = !state.isOnline;
      state = state.copyWith(isOnline: online);
      if (online && wasOffline) {
        unawaited(syncNow(silent: true));
      } else if (online) {
        unawaited(syncNow(silent: true));
      }
    });

    ref.listen<AuthState>(authControllerProvider, (
      AuthState? previous,
      AuthState next,
    ) {
      if (next.user != null && previous?.user?.id != next.user?.id) {
        unawaited(syncNow(silent: true));
      } else if (next.user == null && previous?.user != null) {
        final repo = ref.read(appointmentsRepositoryProvider);
        if (repo is AppointmentsRepositoryImpl) {
          unawaited(repo.resetSyncMetadata());
        }
        state = state.copyWith(clearLastSyncAt: true, clearError: true);
      }
    });

    ref.onDispose(() => _connectivitySubscription?.cancel());

    Future<void>.microtask(_initialize);
    return const SyncUiState();
  }

  AppointmentsRepository get _repository =>
      ref.read(appointmentsRepositoryProvider);

  Future<void> _initialize() async {
    final connectivity = ref.read(connectivityServiceProvider);
    final online = await connectivity.isOnline;
    final lastSync = await _repository.getLastSyncTimestamp();
    state = state.copyWith(isOnline: online, lastSyncAt: lastSync);

    if (online && ref.read(authControllerProvider).isSignedIn) {
      await syncNow(silent: true);
    }
  }

  Future<SyncResult> syncNow({bool silent = false}) async {
    if (state.isSyncing) {
      return state.lastResult ?? const SyncResult();
    }

    state = state.copyWith(isSyncing: true, clearError: true);

    final result = await _repository.synchronize();

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
