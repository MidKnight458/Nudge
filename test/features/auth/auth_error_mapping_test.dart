import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';

void main() {
  group('mapSignInErrorMessage', () {
    test('maps Android ApiException 10 / developer_error clearly', () {
      final platformError = PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 10: ',
      );
      expect(mapSignInErrorMessage(platformError), contains('código 10'));
      expect(
        mapSignInErrorMessage(PlatformException(code: 'developer_error')),
        contains('com.midknight.nudge'),
      );
    });

    test('maps consent / test user error 12500 and 12502', () {
      final error12500 = PlatformException(
        code: 'sign_in_failed',
        message: 'com.google.android.gms.common.api.ApiException: 12500: ',
      );
      final error12502 = PlatformException(code: '12502');

      expect(mapSignInErrorMessage(error12500), contains('código 12500'));
      expect(mapSignInErrorMessage(error12502), contains('código 12500'));
    });

    test('maps cancellation and network errors', () {
      expect(
        mapSignInErrorMessage(PlatformException(code: 'sign_in_canceled')),
        'Inicio de sesión cancelado.',
      );
      expect(
        mapSignInErrorMessage(PlatformException(code: '12501')),
        'Inicio de sesión cancelado.',
      );
      expect(
        mapSignInErrorMessage(PlatformException(code: 'network_error')),
        'Sin conexión con los servicios de Google. Verifica tu internet.',
      );
      expect(
        mapSignInErrorMessage(
          PlatformException(
            code: 'sign_in_failed',
            message: 'ApiException: 7: ',
          ),
        ),
        'Sin conexión con los servicios de Google. Verifica tu internet.',
      );
    });

    test('includes error code for other PlatformExceptions and fallback', () {
      expect(
        mapSignInErrorMessage(PlatformException(code: 'sign_in_failed')),
        'No fue posible iniciar sesión con Google (sign_in_failed).',
      );
      expect(
        mapSignInErrorMessage(StateError('unexpected')),
        'No fue posible iniciar sesión con Google.',
      );
    });

    test(
      'maps FirebaseAuthException and Firebase configuration StateError',
      () {
        expect(
          mapSignInErrorMessage(
            FirebaseAuthException(code: 'invalid-credential'),
          ),
          contains('Firebase Auth'),
        );
        expect(
          mapSignInErrorMessage(
            FirebaseAuthException(code: 'network-request-failed'),
          ),
          'Sin conexión con Firebase Auth. Verifica tu internet.',
        );
        expect(
          mapSignInErrorMessage(
            FirebaseAuthException(code: 'operation-not-allowed'),
          ),
          contains('Firebase Authentication'),
        );
        expect(
          mapSignInErrorMessage(FirebaseAuthException(code: 'custom-code')),
          'No fue posible autenticar con Firebase (custom-code).',
        );
        expect(
          mapSignInErrorMessage(
            StateError(
              'Firebase no está configurado en esta compilación '
              '(falta google-services.json).',
            ),
          ),
          contains('google-services.json'),
        );
      },
    );
  });
}
