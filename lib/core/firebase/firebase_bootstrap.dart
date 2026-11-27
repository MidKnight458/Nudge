import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Safe bootstrapper for Firebase Core and Cloud Firestore offline cache.
abstract final class FirebaseBootstrap {
  static bool _initialized = false;

  /// Returns `true` when Firebase Core was initialized from native config
  /// (`google-services.json` / `GoogleService-Info.plist`).
  static bool get isInitialized {
    if (_initialized) {
      return true;
    }
    try {
      _initialized = Firebase.apps.isNotEmpty;
      return _initialized;
    } catch (_) {
      return false;
    }
  }

  /// Initializes the default Firebase app if native configuration exists.
  ///
  /// Missing configuration in tests or CI returns `false` cleanly so offline
  /// local SQLite features remain operational.
  static Future<bool> initialize() async {
    if (isInitialized) {
      return true;
    }

    try {
      await Firebase.initializeApp();
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
      _initialized = true;
      return true;
    } catch (error) {
      debugPrint('Firebase no inicializado: $error');
      _initialized = false;
      return false;
    }
  }
}
