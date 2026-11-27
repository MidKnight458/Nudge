import 'package:googleapis/calendar/v3.dart' as calendar;

/// Lightweight representation of the signed-in Google account.
class AuthUser {
  const AuthUser({
    required this.id,
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String id;
  final String email;
  final String? displayName;
  final String? photoUrl;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AuthUser &&
        other.id == id &&
        other.email == email &&
        other.displayName == displayName &&
        other.photoUrl == photoUrl;
  }

  @override
  int get hashCode => Object.hash(id, email, displayName, photoUrl);
}

/// Scoped handle to an authenticated Google Calendar API client.
class AuthenticatedCalendarClient {
  const AuthenticatedCalendarClient({required this.api, required this.close});

  final calendar.CalendarApi api;
  final void Function() close;
}

/// Domain contract for Google authentication and Calendar API authorization.
abstract interface class AuthRepository {
  Stream<AuthUser?> get authStateChanges;

  AuthUser? get currentUser;

  Future<AuthUser?> signIn();

  Future<AuthUser?> signInSilently();

  Future<void> signOut();

  Future<AuthenticatedCalendarClient?> openCalendarClient();
}
