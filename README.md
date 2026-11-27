# Nudge

Aplicación móvil **offline-first** desarrollada en **Flutter 3.x / Dart 3.x** (`com.patoh.nudge`) con estética **Pixel Material 3 Expressive & Material You (`dynamic_color`)**, diseñada para profesionales independientes que necesitan gestionar citas, sincronizarlas bidireccionalmente con **Google Calendar v3** y enviar recordatorios de **WhatsApp sin costos de API** mediante enlaces `wa.me`.

## Características principales

- **Material 3 Expressive (Pixel UI):** Soporte completo claro/oscuro con paleta dinámica del sistema (`dynamic_color`) y semilla fallback `#1A73E8`, tarjetas `20dp`, `ModalBottomSheet` `28dp`, FAB tonal y respuesta háptica (`HapticFeedback.lightImpact()`).
- **Offline-first con Drift / SQLite:** Todas las citas, clientes y plantillas de mensajes se almacenan localmente primero y las mutaciones offline (`pending_create`, `pending_update`, `pending_delete`) se encolan para sincronizarse automáticamente al recuperar conexión.
- **Sincronización bidireccional con Google Calendar v3:** Autenticación OAuth (`https://www.googleapis.com/auth/calendar.events`), envío de cambios locales (`insert`, `patch`, `delete`), delta sync incremental con `syncToken` y recuperación automática ante `HTTP 410 Gone`.
- **Contactos priorizando Google & E.164:** Lectura local con prioridad para cuentas `com.google` y normalización internacional E.164 sin `+` ni espacios (`phone_numbers_parser`).
- **Automatización WhatsApp sin API (`wa.me`):** Plantillas editables con variables `{cliente}`, `{fecha}`, `{hora}` y `{servicio}`, además del flujo rápido **Recordatorios de mañana** para despachar mensajes con un toque y marcar los ya enviados.

## Arquitectura (Clean Architecture + Riverpod)

```text
lib/
├── main.dart
├── app.dart
├── core/
│   ├── constants/        # Constantes globales y defaults de plantillas
│   ├── database/         # Esquema Drift (Clients, Appointments, SyncMetadata, ReminderTemplates)
│   ├── network/          # ConnectivityService (connectivity_plus)
│   ├── theme/            # AppTheme (DynamicColorBuilder) y PixelShapes
│   └── utils/            # PhoneSanitizer E.164 y DateFormatters
└── features/
    ├── auth/             # Google Sign-In y cliente autenticado de Calendar
    ├── contacts/         # Repositorio de contactos (prioridad Google) y ContactPickerSheet
    ├── appointments/     # AgendaScreen, AppointmentFormSheet, TomorrowRemindersSheet y motor Sync
    └── reminders/        # Motor de plantillas, TemplateEditorSheet y WhatsAppLauncherService
```

## Requisitos y configuración

1. **Flutter SDK** `>= 3.47.0` (compatible con última `stable` y `material_ui`, Dart `>= 3.13.0 <4.0.0`).
2. **Android:** `minSdk = 26`, permiso `READ_CONTACTS` y bloque `<queries>` en `android/app/src/main/AndroidManifest.xml` para `com.whatsapp`, `com.whatsapp.w4b` e intents `https`.
3. **iOS:** `NSContactsUsageDescription` y `LSApplicationQueriesSchemes` (`whatsapp`, `https`) configurados en `ios/Runner/Info.plist`.
4. **Google OAuth / Calendar API:** Habilitar **Google Calendar API** en Google Cloud Console y registrar el `applicationId` (`com.patoh.nudge`) con su huella SHA-1 para Android / Client ID de iOS antes de probar Sign-In en dispositivo físico.

## Comandos de desarrollo

```bash
# Instalar dependencias
flutter pub get

# Generar código de Drift
dart run build_runner build --delete-conflicting-outputs

# Formateo, análisis estático estricto y pruebas unitarias
dart format --output=none --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test

# Compilar binarios de release
flutter build apk --release
flutter build appbundle --release
```

## Releases automáticos (CI/CD)

El flujo `.github/workflows/ci_cd.yml` ejecuta `lint_and_test` en cada `push` y `pull_request` hacia `main` y `develop`. Para generar automáticamente el APK (`nudge-vX.Y.Z.apk`), el AAB (`nudge-vX.Y.Z.aab`) y publicar el Release en GitHub:

```bash
git tag v1.0.0
git push origin v1.0.0
```
