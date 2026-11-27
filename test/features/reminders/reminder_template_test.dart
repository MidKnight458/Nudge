import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/reminders/domain/reminder_template.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es');
  });

  group('ReminderTemplateEngine', () {
    test('renders all template placeholders in tomorrow reminder', () {
      final start = DateTime(2026, 11, 28, 9, 30);
      final rendered = ReminderTemplateEngine.render(
        templateBody: AppConstants.defaultTomorrowReminderBody,
        clientName: 'Ana López',
        appointmentStart: start,
        serviceTitle: 'Corte de cabello',
      );

      expect(rendered, contains('Hola Ana López'));
      expect(rendered, contains('Corte de cabello'));
      expect(rendered, contains('09:30'));
      expect(rendered, isNot(contains('{cliente}')));
      expect(rendered, isNot(contains('{servicio}')));
      expect(rendered, isNot(contains('{hora}')));
    });

    test('renders confirmation template including formatted date and time', () {
      final start = DateTime(2026, 12, 5, 16, 45);
      final rendered = ReminderTemplateEngine.render(
        templateBody:
            'Cita de {servicio} para {cliente} el {fecha} a las {hora}.',
        clientName: 'Luis Pérez',
        appointmentStart: start,
        serviceTitle: 'Consulta dental',
      );

      expect(
        rendered,
        'Cita de Consulta dental para Luis Pérez el 5 dic 2026 a las 16:45.',
      );
    });
  });

  group('WhatsAppLauncherService.buildWhatsAppUri', () {
    test('generates properly encoded wa.me URI without leading plus', () {
      final uri = WhatsAppLauncherService.buildWhatsAppUri(
        phoneE164Digits: '+52 461 123 4567',
        message: 'Hola Ana! Tu cita es mañana a las 09:30.',
      );

      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/524611234567');
      expect(
        uri.queryParameters['text'],
        'Hola Ana! Tu cita es mañana a las 09:30.',
      );
      expect(uri.toString(), startsWith('https://wa.me/524611234567?text='));
      expect(uri.toString(), isNot(contains(' ')));
    });

    test('throws ArgumentError when phone digits are empty or invalid', () {
      expect(
        () => WhatsAppLauncherService.buildWhatsAppUri(
          phoneE164Digits: '',
          message: 'Hola',
        ),
        throwsArgumentError,
      );
      expect(
        () => WhatsAppLauncherService.buildWhatsAppUri(
          phoneE164Digits: '123',
          message: 'Hola',
        ),
        throwsArgumentError,
      );
    });
  });
}
