<div align="center">

# Nudge

**Tu agenda de citas estilo Pixel con Google Calendar y recordatorios rápidos por WhatsApp.**

*Pensada para profesionales independientes y negocios locales que quieren organizar su día sin suscripciones ni costos ocultos.*

[![Nudge CI/CD](https://github.com/MidKnight458/Nudge/actions/workflows/ci_cd.yml/badge.svg?branch=main)](https://github.com/MidKnight458/Nudge/actions/workflows/ci_cd.yml)
[![Latest Release](https://img.shields.io/github/v/release/MidKnight458/Nudge?label=Descarga%20APK&color=1A73E8)](https://github.com/MidKnight458/Nudge/releases/latest)
[![Platform](https://img.shields.io/badge/Android-8.0%2B-3DDC84?logo=android&logoColor=white)](https://github.com/MidKnight458/Nudge/releases/latest)

[Descargar última versión](https://github.com/MidKnight458/Nudge/releases/latest) · [Reportar un problema](https://github.com/MidKnight458/Nudge/issues)

</div>

---

## ¿Qué es Nudge?

**Nudge** convierte tu teléfono en una agenda rápida, clara y confiable. Nació para quienes atienden clientes por cita —consultorios, barberías, estudios, terapeutas, asesorías o freelancers— y buscan evitar inasistencias sin pagar plataformas mensuales ni APIs empresariales.

Todo se guarda primero en tu dispositivo para que nunca dependas de tener señal, se mantiene sincronizado en ambos sentidos con tu **Google Calendar** y te permite enviar recordatorios de **WhatsApp** con un solo toque.

---

## Lo que hace por tu día

- **Diseño Pixel limpio y adaptable:** Interfaz moderna con **Material You**, modo claro y oscuro automático, y respuesta háptica sutil en cada acción importante.
- **Funciona incluso sin internet:** Agenda, edita o cancela citas aunque no tengas conexión; Nudge las guarda localmente y las sincroniza automáticamente en cuanto vuelves a estar en línea.
- **Sincronización bidireccional con Google Calendar:** Los cambios que haces en la app aparecen en tu calendario de Google, y las citas que agregues desde la web o tu computadora llegan directo a Nudge.
- **Contactos listos para WhatsApp:** Prioriza tus contactos de Google y formatea automáticamente cualquier número local o internacional para abrir el chat sin errores.
- **Recordatorios de mañana en un toque:** Revisa en una sola lista todas las citas del día siguiente, envía cada recordatorio de WhatsApp con un toque y visualiza cuáles ya confirmaste.
- **Mensajes a tu manera:** Personaliza las plantillas de recordatorio y confirmación usando datos automáticos como `{cliente}`, `{servicio}`, `{fecha}` y `{hora}`.
- **100% gratuita y sin intermediarios:** Sin servidores propios, sin cuentas externas adicionales y sin cuotas por mensaje enviado.

---

## Cómo empezar en 3 pasos

1. **Descarga la app:** Ve a la sección de [**Releases**](https://github.com/MidKnight458/Nudge/releases/latest) e instala el archivo `nudge-v*.apk` en tu Android.
2. **Conecta tu cuenta de Google:** Inicia sesión desde el icono de perfil para mantener tus citas sincronizadas con Google Calendar.
3. **Agenda y envía recordatorios:** Selecciona a tu cliente desde tus contactos, guarda la cita y envía confirmaciones o recordatorios de mañana por WhatsApp en segundos.

---

## Privacidad

Tus citas, clientes y plantillas permanecen en tu teléfono y en tu propia cuenta de Google Calendar. Nudge no envía tu agenda a servidores de terceros ni recopila tus conversaciones de WhatsApp.

---

<details>
<summary>Información para desarrolladores</summary>

- **Stack:** Flutter (`>= 3.47.0`, `material_ui`), Dart (`>= 3.13.0`), Riverpod, Drift (SQLite), `dynamic_color`, `flutter_contacts`, `phone_numbers_parser`, `google_sign_in`, `googleapis` (Calendar v3) y `url_launcher`.
- **Verificación local:**
  ```bash
  flutter pub get
  dart run build_runner build --delete-conflicting-outputs
  dart format --output=none --set-exit-if-changed .
  flutter analyze --fatal-infos
  flutter test
  ```
- **Publicar un release localmente (solo APK):**
  ```bash
  ./scripts/release.sh v1.0.1
  ```
  El script valida formato, análisis estático y tests, compila `app-release.apk` en tu equipo y sube `nudge-v1.0.1.apk` a GitHub Releases. GitHub Actions solo ejecuta el chequeo rápido de formato, análisis y tests en cada `push` a `main`.

</details>
