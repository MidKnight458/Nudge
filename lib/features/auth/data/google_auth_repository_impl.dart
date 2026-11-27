import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';

/// Google Sign-In implementation requesting the Calendar Events scope.
class GoogleAuthRepositoryImpl implements AuthRepository {
  GoogleAuthRepositoryImpl({GoogleSignIn? googleSignIn})
    : _googleSignIn =
          googleSignIn ??
          GoogleSignIn(scopes: const <String>[AppConstants.calendarScope]);

  final GoogleSignIn _googleSignIn;

  @override
  Stream<AuthUser?> get authStateChanges =>
      _googleSignIn.onCurrentUserChanged.map(_mapAccount);

  @override
  AuthUser? get currentUser => _mapAccount(_googleSignIn.currentUser);

  @override
  Future<AuthUser?> signIn() async {
    final account = await _googleSignIn.signIn();
    if (account == null) {
      return null;
    }

    final hasScope = await _googleSignIn.canAccessScopes(const <String>[
      AppConstants.calendarScope,
    ]);
    if (!hasScope) {
      final granted = await _googleSignIn.requestScopes(const <String>[
        AppConstants.calendarScope,
      ]);
      if (!granted) {
        return null;
      }
    }
    return _mapAccount(account);
  }

  @override
  Future<AuthUser?> signInSilently() async {
    final account = await _googleSignIn.signInSilently();
    return _mapAccount(account);
  }

  @override
  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  @override
  Future<AuthenticatedCalendarClient?> openCalendarClient() async {
    if (_googleSignIn.currentUser == null) {
      await _googleSignIn.signInSilently(suppressErrors: true);
    }
    if (_googleSignIn.currentUser == null) {
      return null;
    }

    final client = await _googleSignIn.authenticatedClient();
    if (client == null) {
      return null;
    }

    return AuthenticatedCalendarClient(
      api: calendar.CalendarApi(client),
      close: client.close,
    );
  }

  AuthUser? _mapAccount(GoogleSignInAccount? account) {
    if (account == null) {
      return null;
    }
    return AuthUser(
      id: account.id,
      email: account.email,
      displayName: account.displayName,
      photoUrl: account.photoUrl,
    );
  }
}
