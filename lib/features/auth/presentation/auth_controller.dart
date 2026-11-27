import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/features/auth/data/google_auth_repository_impl.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return GoogleAuthRepositoryImpl();
});

/// UI state for Google authentication.
class AuthState {
  const AuthState({
    this.user,
    this.isLoading = false,
    this.errorMessage,
  });

  final AuthUser? user;
  final bool isLoading;
  final String? errorMessage;

  bool get isSignedIn => user != null;

  AuthState copyWith({
    AuthUser? user,
    bool clearUser = false,
    bool? isLoading,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Manages Google sign-in lifecycle and exposes current account state.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<AuthUser?>? _authSubscription;

  @override
  AuthState build() {
    final repository = ref.watch(authRepositoryProvider);
    _authSubscription?.cancel();
    _authSubscription = repository.authStateChanges.listen((AuthUser? user) {
      state = state.copyWith(
        user: user,
        clearUser: user == null,
        isLoading: false,
      );
    });
    ref.onDispose(() => _authSubscription?.cancel());

    Future<void>.microtask(_restoreSession);
    return AuthState(user: repository.currentUser);
  }

  AuthRepository get _repository => ref.read(authRepositoryProvider);

  Future<void> _restoreSession() async {
    try {
      final user = await _repository.signInSilently();
      if (user != null) {
        state = state.copyWith(user: user, clearError: true);
      }
    } catch (_) {
      // Silent sign-in can fail offline or when no account is cached.
    }
  }

  Future<bool> signIn() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final user = await _repository.signIn();
      if (user == null) {
        state = state.copyWith(
          isLoading: false,
          errorMessage:
              'Inicio de sesión cancelado o sin permisos de Calendar.',
        );
        return false;
      }
      state = state.copyWith(user: user, isLoading: false, clearError: true);
      return true;
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No fue posible iniciar sesión con Google.',
      );
      return false;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.signOut();
      state = const AuthState();
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'No se pudo cerrar la sesión.',
      );
    }
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);
