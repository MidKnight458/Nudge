import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/firebase/firebase_bootstrap.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

/// Google Sign-In backed by Firebase Auth and Calendar/Drive authorization.
class GoogleAuthRepositoryImpl implements AuthRepository {
  GoogleAuthRepositoryImpl({
    GoogleSignIn? googleSignIn,
    FirebaseAuth? firebaseAuth,
    bool Function()? isFirebaseReady,
  }) : _googleSignIn =
           googleSignIn ??
           GoogleSignIn(
             scopes: const <String>[
               AppConstants.calendarScope,
               AppConstants.driveFileScope,
             ],
           ),
       _firebaseAuthOverride = firebaseAuth,
       _isFirebaseReady =
           isFirebaseReady ?? (() => FirebaseBootstrap.isInitialized);

  final GoogleSignIn _googleSignIn;
  final FirebaseAuth? _firebaseAuthOverride;
  final bool Function() _isFirebaseReady;

  FirebaseAuth? get _firebaseAuth {
    if (_firebaseAuthOverride != null) {
      return _firebaseAuthOverride;
    }
    if (!_isFirebaseReady()) {
      return null;
    }
    return FirebaseAuth.instance;
  }

  @override
  Stream<AuthUser?> get authStateChanges {
    final auth = _firebaseAuth;
    if (auth == null) {
      return const Stream<AuthUser?>.empty();
    }
    return auth.authStateChanges().map(
      (User? user) =>
          user == null ? null : _mapUsers(user, _googleSignIn.currentUser),
    );
  }

  @override
  AuthUser? get currentUser {
    final firebaseUser = _firebaseAuth?.currentUser;
    if (firebaseUser == null) {
      return null;
    }
    return _mapUsers(firebaseUser, _googleSignIn.currentUser);
  }

  @override
  Future<AuthUser?> signIn() async {
    final auth = _firebaseAuth;
    if (auth == null) {
      throw StateError(
        'Firebase no está configurado en esta compilación (falta google-services.json).',
      );
    }

    final account = await _googleSignIn.signIn();
    if (account == null) {
      return null;
    }

    final granted = await _googleSignIn.requestScopes(const <String>[
      AppConstants.calendarScope,
    ]);
    if (!granted) {
      await _googleSignIn.signOut();
      return null;
    }

    final googleAuth = await account.authentication;
    if (googleAuth.idToken == null && googleAuth.accessToken == null) {
      await _googleSignIn.signOut();
      throw StateError(
        'No se pudieron obtener tokens de Google para Firebase Auth. '
        'Verifica el SHA-1 y google-services.json en Firebase Console.',
      );
    }

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    final userCredential = await auth.signInWithCredential(credential);
    final firebaseUser = userCredential.user;
    if (firebaseUser == null) {
      return null;
    }

    return _mapUsers(firebaseUser, account);
  }

  @override
  Future<AuthUser?> signInSilently() async {
    final auth = _firebaseAuth;
    if (auth == null) {
      return null;
    }

    GoogleSignInAccount? account;
    try {
      account = await _googleSignIn.signInSilently();
    } catch (_) {
      account = _googleSignIn.currentUser;
    }

    var firebaseUser = auth.currentUser;
    if (firebaseUser == null && account != null) {
      try {
        final googleAuth = await account.authentication;
        if (googleAuth.idToken != null || googleAuth.accessToken != null) {
          final credential = GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
          final result = await auth.signInWithCredential(credential);
          firebaseUser = result.user;
        }
      } catch (_) {
        // Ignore silent Firebase exchange errors so startup stays resilient offline.
      }
    }

    if (firebaseUser == null) {
      return null;
    }
    return _mapUsers(firebaseUser, account ?? _googleSignIn.currentUser);
  }

  @override
  Future<void> signOut() async {
    try {
      await _firebaseAuth?.signOut();
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  @override
  Future<void> clearAuthCache() async {
    try {
      await _firebaseAuth?.signOut();
    } catch (_) {}
    try {
      await _googleSignIn.disconnect();
    } catch (_) {}
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
  }

  @override
  Future<AuthenticatedCalendarClient?> openCalendarClient() async {
    if (_googleSignIn.currentUser == null) {
      try {
        await _googleSignIn.signInSilently();
      } catch (_) {
        return null;
      }
    }
    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) {
      return null;
    }

    return AuthenticatedCalendarClient(
      api: calendar.CalendarApi(authClient),
      close: authClient.close,
    );
  }

  @override
  Future<AuthenticatedDriveClient?> openDriveClient({
    bool requestScopeIfNeeded = false,
  }) async {
    var account = _googleSignIn.currentUser;
    if (account == null) {
      try {
        account = await _googleSignIn.signInSilently();
      } catch (_) {
        return null;
      }
    }
    if (account == null) {
      return null;
    }

    if (requestScopeIfNeeded) {
      try {
        final granted = await _googleSignIn.requestScopes(const <String>[
          AppConstants.driveFileScope,
        ]);
        if (!granted) {
          return null;
        }
      } catch (_) {
        return null;
      }
    }

    final authClient = await _googleSignIn.authenticatedClient();
    if (authClient == null) {
      return null;
    }

    return AuthenticatedDriveClient(
      api: drive.DriveApi(authClient),
      close: authClient.close,
    );
  }

  AuthUser _mapUsers(User firebaseUser, GoogleSignInAccount? googleAccount) {
    return AuthUser(
      id: firebaseUser.uid,
      email: firebaseUser.email ?? googleAccount?.email ?? '',
      displayName: firebaseUser.displayName ?? googleAccount?.displayName,
      photoUrl: firebaseUser.photoURL ?? googleAccount?.photoUrl,
    );
  }
}
