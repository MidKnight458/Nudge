import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/auth/data/google_auth_repository_impl.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

/// Maps Google Sign-In exceptions into actionable, non-sensitive messages.
String mapSignInErrorMessage(Object error) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'network-request-failed':
        return 'Sin conexión con Firebase Auth. Verifica tu internet.';
      case 'invalid-credential':
        return 'Las credenciales de Google no fueron aceptadas por Firebase Auth. '
            'Verifica la configuración OAuth y el SHA-1 en Firebase Console.';
      case 'account-exists-with-different-credential':
        return 'Esta cuenta ya existe con otro método de acceso.';
      case 'user-disabled':
        return 'Esta cuenta está deshabilitada en Firebase Auth.';
      case 'operation-not-allowed':
        return 'El acceso con Google no está habilitado en Firebase Authentication.';
      case 'app-not-authorized':
      case 'invalid-api-key':
        return 'Esta compilación no está autorizada en Firebase Console. '
            'Verifica el SHA-1 y google-services.json.';
      default:
        final code = error.code.trim();
        return code.isEmpty
            ? 'No fue posible autenticar con Firebase.'
            : 'No fue posible autenticar con Firebase ($code).';
    }
  }
  if (error is StateError &&
      (error.message.contains('google-services.json') ||
          error.message.contains('Firebase'))) {
    return error.message;
  }
  if (error is PlatformException) {
    final code = error.code.toLowerCase();
    final message = error.message ?? '';

    if (code == '10' ||
        code == 'developer_error' ||
        RegExp(r'ApiException:\s*10\b').hasMatch(message)) {
      return 'Falta configurar el cliente OAuth Android (${AppConstants.packageId} y huella SHA-1) '
          'en Google Cloud Console (código 10).';
    }
    if (code == '12500' ||
        code == '12502' ||
        RegExp(r'ApiException:\s*1250[02]\b').hasMatch(message)) {
      return 'Configura la pantalla de consentimiento OAuth y agrega tu cuenta '
          'como usuario de prueba en Google Cloud (código 12500).';
    }
    if (code == '12501' ||
        code == 'sign_in_canceled' ||
        RegExp(r'ApiException:\s*12501\b').hasMatch(message)) {
      return 'Inicio de sesión cancelado.';
    }
    if (code == '7' ||
        code == 'network_error' ||
        RegExp(r'ApiException:\s*7\b').hasMatch(message)) {
      return 'Sin conexión con los servicios de Google. Verifica tu internet.';
    }
    return 'No fue posible iniciar sesión con Google (${error.code}).';
  }
  return 'No fue posible iniciar sesión con Google.';
}

final authRepositoryProvider = Provider<AuthRepository>((Ref ref) {
  return GoogleAuthRepositoryImpl();
});

/// UI state for Google authentication.
class AuthState {
  const AuthState({this.user, this.isLoading = false, this.errorMessage});

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
    } catch (error) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: mapSignInErrorMessage(error),
      );
      return false;
    }
  }

  Future<bool> switchAccount() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      await _repository.clearAuthCache();
    } catch (_) {
      // Proceed to account picker even if disconnect reported no active grant.
    }
    return signIn();
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
