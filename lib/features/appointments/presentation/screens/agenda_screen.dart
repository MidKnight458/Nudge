import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/appointments/presentation/controllers/sync_controller.dart';
import 'package:nudge/features/appointments/presentation/screens/appointment_form_sheet.dart';
import 'package:nudge/features/appointments/presentation/widgets/appointment_card.dart';
import 'package:nudge/features/appointments/presentation/widgets/date_selector_strip.dart';
import 'package:nudge/features/appointments/presentation/widgets/tomorrow_reminders_sheet.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/reminders/presentation/template_editor_sheet.dart';

/// Main offline-first Pixel M3 Expressive agenda screen.
class AgendaScreen extends ConsumerWidget {
  const AgendaScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final selectedDate = ref.watch(selectedDateProvider);
    final dayAppointmentsAsync = ref.watch(selectedDayAppointmentsProvider);
    final tomorrowAppointmentsAsync = ref.watch(tomorrowAppointmentsProvider);
    final markedDates =
        ref.watch(agendaMarkedDatesProvider).valueOrNull ?? const <DateTime>{};
    final pendingSyncCount =
        ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    final authState = ref.watch(authControllerProvider);
    final syncState = ref.watch(syncControllerProvider);

    final tomorrowList =
        tomorrowAppointmentsAsync.valueOrNull ?? const <AppointmentEntity>[];
    final tomorrowTotal = tomorrowList.length;
    final tomorrowPending = tomorrowList
        .where((AppointmentEntity a) => !a.reminderSent)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppConstants.appName),
            Text(
              _buildSyncSubtitle(authState, syncState, pendingSyncCount),
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Plantillas de WhatsApp',
            onPressed: () {
              HapticFeedback.lightImpact();
              TemplateEditorSheet.show(context);
            },
            icon: const Icon(Icons.sms_outlined),
          ),
          IconButton(
            tooltip: 'Sincronizar con Google Calendar',
            onPressed: syncState.isSyncing
                ? null
                : () => _triggerManualSync(context, ref),
            icon: syncState.isSyncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : Badge(
                    isLabelVisible: pendingSyncCount > 0,
                    label: Text('$pendingSyncCount'),
                    child: const Icon(Icons.sync_rounded),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              tooltip: 'Cuenta de Google',
              onPressed: () {
                HapticFeedback.lightImpact();
                _showAccountSheet(context, ref);
              },
              icon: CircleAvatar(
                radius: 16,
                backgroundColor: authState.isSignedIn
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                foregroundColor: authState.isSignedIn
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant,
                child: authState.isSignedIn
                    ? Text(
                        (authState.user?.displayName ??
                                authState.user?.email ??
                                'G')[0]
                            .toUpperCase(),
                        style: theme.textTheme.labelLarge,
                      )
                    : const Icon(Icons.account_circle_outlined, size: 20),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!syncState.isOnline || pendingSyncCount > 0)
            _OfflineOrPendingBanner(
              isOnline: syncState.isOnline,
              pendingCount: pendingSyncCount,
              onSyncTap: syncState.isOnline && !syncState.isSyncing
                  ? () => _triggerManualSync(context, ref)
                  : null,
            ),
          _TomorrowRemindersBanner(
            totalCount: tomorrowTotal,
            pendingCount: tomorrowPending,
            onTap: () {
              HapticFeedback.lightImpact();
              TomorrowRemindersSheet.show(context);
            },
          ),
          DateSelectorStrip(
            selectedDate: selectedDate,
            markedDates: markedDates,
            onDateSelected: (DateTime day) {
              ref.read(selectedDateProvider.notifier).state = day;
            },
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    DateFormatters.formatFullDate(selectedDate),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                dayAppointmentsAsync.maybeWhen(
                  data: (List<AppointmentEntity> list) => Text(
                    list.length == 1 ? '1 cita' : '${list.length} citas',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.primary,
                    ),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _triggerManualSync(context, ref),
              child: PageTransitionSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder:
                    (
                      Widget child,
                      Animation<double> primaryAnimation,
                      Animation<double> secondaryAnimation,
                    ) {
                      return FadeThroughTransition(
                        animation: primaryAnimation,
                        secondaryAnimation: secondaryAnimation,
                        child: child,
                      );
                    },
                child: KeyedSubtree(
                  key: ValueKey<DateTime>(selectedDate),
                  child: dayAppointmentsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (_, __) => ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: const [
                        Center(
                          child: Text(
                            'Ocurrió un error al cargar las citas locales.',
                          ),
                        ),
                      ],
                    ),
                    data: (List<AppointmentEntity> appointments) {
                      if (appointments.isEmpty) {
                        return _EmptyDayView(
                          selectedDate: selectedDate,
                          onCreateTap: () {
                            HapticFeedback.lightImpact();
                            AppointmentFormSheet.show(
                              context,
                              initialDate: selectedDate,
                            );
                          },
                        );
                      }

                      return ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
                        itemCount: appointments.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (BuildContext context, int index) {
                          final appointment = appointments[index];
                          return AppointmentCard(
                            appointment: appointment,
                            onTap: () => AppointmentFormSheet.show(
                              context,
                              initialDate: selectedDate,
                              existing: appointment,
                            ),
                            onWhatsAppTap: () =>
                                _sendCardReminder(context, ref, appointment),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticFeedback.lightImpact();
          AppointmentFormSheet.show(context, initialDate: selectedDate);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nueva cita'),
      ),
    );
  }

  String _buildSyncSubtitle(
    AuthState authState,
    SyncUiState syncState,
    int pendingCount,
  ) {
    if (!syncState.isOnline) {
      return pendingCount > 0
          ? 'Modo offline · $pendingCount en cola'
          : 'Modo offline';
    }
    if (!authState.isSignedIn) {
      return 'Solo local · Conecta Google Calendar';
    }
    if (syncState.isSyncing) {
      return 'Sincronizando con Google Calendar...';
    }
    if (syncState.lastSyncAt != null) {
      return 'Sincronizado ${DateFormatters.formatTime(syncState.lastSyncAt!)}';
    }
    return authState.user?.email ?? 'Google Calendar conectado';
  }

  Future<void> _triggerManualSync(BuildContext context, WidgetRef ref) async {
    HapticFeedback.lightImpact();
    final result = await ref
        .read(syncControllerProvider.notifier)
        .syncNow(silent: false);
    if (!context.mounted) {
      return;
    }

    if (result.hasError) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    } else if (result.wasSkipped) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.skippedReason!)));
    }
  }

  Future<void> _sendCardReminder(
    BuildContext context,
    WidgetRef ref,
    AppointmentEntity appointment,
  ) async {
    final tomorrow = DateFormatters.tomorrowRange().start;
    final isTomorrow = DateFormatters.isSameDay(
      appointment.startTime,
      tomorrow,
    );
    final template = isTomorrow
        ? ref.read(tomorrowTemplateBodyProvider)
        : ref.read(confirmationTemplateBodyProvider);

    final launched = await ref
        .read(appointmentsControllerProvider.notifier)
        .sendWhatsAppReminder(appointment: appointment, templateBody: template);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
        ),
      );
    }
  }

  Future<void> _showAccountSheet(BuildContext context, WidgetRef ref) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (BuildContext sheetContext) {
        return Consumer(
          builder: (BuildContext context, WidgetRef sheetRef, _) {
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final auth = sheetRef.watch(authControllerProvider);
            final sync = sheetRef.watch(syncControllerProvider);
            final pending =
                sheetRef.watch(pendingSyncCountProvider).valueOrNull ?? 0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Google Calendar Sync',
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                        child: Icon(
                          auth.isSignedIn
                              ? Icons.cloud_done_outlined
                              : Icons.cloud_off_outlined,
                        ),
                      ),
                      title: Text(
                        auth.isSignedIn
                            ? (auth.user?.displayName ?? auth.user!.email)
                            : 'Sin cuenta vinculada',
                      ),
                      subtitle: Text(
                        auth.isSignedIn
                            ? '${auth.user!.email}\n'
                                  '${sync.lastSyncAt != null ? 'Última sync: ${DateFormatters.formatCompactDateTime(sync.lastSyncAt!)}' : 'Aún no sincronizado'}'
                                  '${pending > 0 ? ' · $pending pendientes' : ''}'
                            : 'Conecta tu cuenta de Google para sincronizar citas en dos vías.',
                      ),
                    ),
                  ),
                  if (auth.errorMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      auth.errorMessage!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (auth.isSignedIn) ...[
                    FilledButton.icon(
                      onPressed: sync.isSyncing
                          ? null
                          : () async {
                              Navigator.of(context).pop();
                              await _triggerManualSync(context, sheetRef);
                            },
                      icon: const Icon(Icons.sync_rounded),
                      label: const Text('Sincronizar ahora'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: auth.isLoading
                          ? null
                          : () async {
                              HapticFeedback.lightImpact();
                              await sheetRef
                                  .read(authControllerProvider.notifier)
                                  .signOut();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Desconectar cuenta'),
                    ),
                  ] else
                    FilledButton.icon(
                      onPressed: auth.isLoading
                          ? null
                          : () async {
                              HapticFeedback.lightImpact();
                              final signedIn = await sheetRef
                                  .read(authControllerProvider.notifier)
                                  .signIn();
                              if (signedIn && context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      icon: auth.isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_rounded),
                      label: const Text('Conectar con Google'),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _OfflineOrPendingBanner extends StatelessWidget {
  const _OfflineOrPendingBanner({
    required this.isOnline,
    required this.pendingCount,
    this.onSyncTap,
  });

  final bool isOnline;
  final int pendingCount;
  final VoidCallback? onSyncTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isOnline
            ? colorScheme.secondaryContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: PixelShapes.inputBorderRadius,
      ),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.cloud_upload_outlined : Icons.wifi_off_rounded,
            size: 18,
            color: isOnline
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isOnline
                  ? '$pendingCount cambios locales por subir a Calendar'
                  : 'Sin conexión · Los cambios se guardan localmente'
                        '${pendingCount > 0 ? ' ($pendingCount)' : ''}',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isOnline
                    ? colorScheme.onSecondaryContainer
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onSyncTap != null)
            TextButton(onPressed: onSyncTap, child: const Text('Subir')),
        ],
      ),
    );
  }
}

class _TomorrowRemindersBanner extends StatelessWidget {
  const _TomorrowRemindersBanner({
    required this.totalCount,
    required this.pendingCount,
    required this.onTap,
  });

  final int totalCount;
  final int pendingCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasAppointments = totalCount > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Material(
        color: hasAppointments
            ? colorScheme.tertiaryContainer
            : colorScheme.surfaceContainerHigh,
        borderRadius: PixelShapes.cardBorderRadius,
        child: InkWell(
          borderRadius: PixelShapes.cardBorderRadius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: hasAppointments
                      ? colorScheme.tertiary
                      : colorScheme.surfaceContainerHighest,
                  foregroundColor: hasAppointments
                      ? colorScheme.onTertiary
                      : colorScheme.onSurfaceVariant,
                  child: const Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Recordatorios de mañana ($totalCount)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: hasAppointments
                              ? colorScheme.onTertiaryContainer
                              : colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        hasAppointments
                            ? (pendingCount > 0
                                  ? '$pendingCount por enviar por WhatsApp con un toque'
                                  : 'Todos los recordatorios de mañana fueron enviados')
                            : 'No hay citas programadas para mañana',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasAppointments
                              ? colorScheme.onTertiaryContainer.withValues(
                                  alpha: 0.85,
                                )
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
                  color: hasAppointments
                      ? colorScheme.onTertiaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyDayView extends StatelessWidget {
  const _EmptyDayView({required this.selectedDate, required this.onCreateTap});

  final DateTime selectedDate;
  final VoidCallback onCreateTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 100),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.event_note_rounded, size: 28),
                ),
                const SizedBox(height: 14),
                Text('Día libre', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  'No tienes citas agendadas para el '
                  '${DateFormatters.formatShortDate(selectedDate)}.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.tonalIcon(
                  onPressed: onCreateTap,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agendar primera cita'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
