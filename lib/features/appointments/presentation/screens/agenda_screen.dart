import 'dart:async';

import 'package:animations/animations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/appointments/presentation/controllers/sync_controller.dart';
import 'package:nudge/features/appointments/presentation/screens/appointment_form_sheet.dart';
import 'package:nudge/features/appointments/presentation/widgets/appointment_card.dart';
import 'package:nudge/features/appointments/presentation/widgets/date_selector_strip.dart';
import 'package:nudge/features/appointments/presentation/widgets/tomorrow_reminders_sheet.dart';
import 'package:nudge/features/auth/domain/auth_repository.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/reminders/presentation/template_editor_sheet.dart';

/// Main offline-first Pixel M3 Expressive agenda screen.
class AgendaScreen extends ConsumerStatefulWidget {
  const AgendaScreen({super.key});

  @override
  ConsumerState<AgendaScreen> createState() => _AgendaScreenState();
}

class _AgendaScreenState extends ConsumerState<AgendaScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncInBackgroundIfReady();
    }
  }

  void _syncInBackgroundIfReady() {
    if (!mounted) {
      return;
    }
    final auth = ref.read(authControllerProvider);
    final sync = ref.read(syncControllerProvider);
    if (!auth.isSignedIn ||
        auth.isLoading ||
        !sync.isOnline ||
        sync.isSyncing) {
      return;
    }
    unawaited(ref.read(syncControllerProvider.notifier).syncNow(silent: true));
  }

  @override
  Widget build(BuildContext context) {
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
    final upcomingDay =
        ref.watch(nextUpcomingDayProvider).valueOrNull ??
        (date: null, appointments: const <AppointmentEntity>[]);

    final tomorrowList =
        tomorrowAppointmentsAsync.valueOrNull ?? const <AppointmentEntity>[];
    final tomorrowTotal = tomorrowList.length;
    final tomorrowPending = tomorrowList
        .where((AppointmentEntity a) => !a.reminderSent)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'NUDGE',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Plantilla de Respuesta',
            onPressed: () {
              HapticFeedback.lightImpact();
              TemplateEditorSheet.show(context);
            },
            icon: const Icon(Icons.sms_outlined),
          ),
          IconButton(
            tooltip: 'Sincronizar',
            onPressed: syncState.isSyncing
                ? null
                : () => _triggerManualSync(context),
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
                _showAccountSheet(context);
              },
              icon: _GoogleAccountAvatar(user: authState.user, radius: 16),
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
                  ? () => _triggerManualSync(context)
                  : null,
            ),
          if (authState.isSignedIn && syncState.lastError != null)
            _SyncErrorBanner(
              errorMessage: syncState.lastError!,
              onRetryTap: syncState.isSyncing
                  ? null
                  : () => _triggerManualSync(context),
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
              onRefresh: () => _triggerManualSync(context),
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
                          upcomingDate: upcomingDay.date,
                          upcomingAppointments: upcomingDay.appointments,
                          onCreateTap: () {
                            HapticFeedback.lightImpact();
                            AppointmentFormSheet.show(
                              context,
                              initialDate: selectedDate,
                            );
                          },
                          onJumpToUpcomingDate: upcomingDay.date == null
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  ref
                                          .read(selectedDateProvider.notifier)
                                          .state =
                                      upcomingDay.date!;
                                },
                          onEditUpcomingTap: (AppointmentEntity appt) =>
                              AppointmentFormSheet.show(
                                context,
                                initialDate: DateFormatters.startOfDay(
                                  appt.startTime,
                                ),
                                existing: appt,
                              ),
                          onWhatsAppUpcomingTap: (AppointmentEntity appt) =>
                              _sendCardReminder(context, appt),
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
                                _sendCardReminder(context, appointment),
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

  Future<void> _triggerManualSync(BuildContext screenContext) async {
    HapticFeedback.lightImpact();
    final result = await ref
        .read(syncControllerProvider.notifier)
        .syncNow(silent: false);
    if (!screenContext.mounted) {
      return;
    }

    if (result.hasError) {
      ScaffoldMessenger.of(screenContext)
          .showSnackBar(SnackBar(content: Text(result.errorMessage!)));
    } else if (result.wasSkipped) {
      ScaffoldMessenger.of(screenContext)
          .showSnackBar(SnackBar(content: Text(result.skippedReason!)));
    } else {
      ScaffoldMessenger.of(
        screenContext,
      ).showSnackBar(SnackBar(content: Text(_buildSyncSummaryMessage(result))));
    }
  }

  String _buildSyncSummaryMessage(SyncResult result) {
    final pushed =
        result.pushedCreated + result.pushedUpdated + result.pushedDeleted;
    final pulled = result.pulledUpserted + result.pulledDeleted;
    if (pushed == 0 && pulled == 0) {
      return 'Agenda al día.';
    }
    return 'Sincronizado: $pushed enviadas, $pulled actualizadas.';
  }

  Future<void> _sendCardReminder(
    BuildContext screenContext,
    AppointmentEntity appointment,
  ) async {
    final template = ref.read(responseTemplateBodyProvider);

    final launched = await ref
        .read(appointmentsControllerProvider.notifier)
        .sendWhatsAppReminder(appointment: appointment, templateBody: template);
    if (!launched && screenContext.mounted) {
      ScaffoldMessenger.of(screenContext).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
        ),
      );
    }
  }

  Future<void> _showAccountSheet(BuildContext screenContext) {
    return showModalBottomSheet<void>(
      context: screenContext,
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

            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Cuenta de Google', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: _GoogleAccountAvatar(
                          user: auth.user,
                          radius: 22,
                        ),
                        title: Text(
                          auth.isSignedIn
                              ? (auth.user?.displayName ?? auth.user!.email)
                              : 'Sin cuenta vinculada',
                        ),
                        subtitle: Text(
                          auth.isSignedIn
                              ? '${auth.user!.email}\n'
                                    '${sync.lastSyncAt != null ? 'Última sincronización: ${DateFormatters.formatCompactDateTime(sync.lastSyncAt!)}' : 'Sincronización activa'}'
                                    '${pending > 0 ? ' · $pending pendientes' : ''}'
                              : 'Conecta tu cuenta de Google para respaldar y sincronizar tus datos.',
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
                    if (auth.isSignedIn && sync.lastError != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        sync.lastError!,
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
                                await _triggerManualSync(screenContext);
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
                                final switched = await sheetRef
                                    .read(authControllerProvider.notifier)
                                    .switchAccount();
                                if (switched && context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                        icon: const Icon(Icons.switch_account_outlined),
                        label: const Text('Cambiar cuenta'),
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
                        style: OutlinedButton.styleFrom(
                          foregroundColor: colorScheme.error,
                        ),
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
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.login_rounded),
                        label: const Text('Conectar con Google'),
                      ),
                  ],
                ),
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
                  ? '$pendingCount cambios pendientes por sincronizar'
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

class _SyncErrorBanner extends StatelessWidget {
  const _SyncErrorBanner({required this.errorMessage, this.onRetryTap});

  final String errorMessage;
  final VoidCallback? onRetryTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: PixelShapes.inputBorderRadius,
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_problem_rounded,
            size: 18,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              errorMessage,
              style: theme.textTheme.labelMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
          if (onRetryTap != null)
            TextButton(
              onPressed: onRetryTap,
              child: Text(
                'Reintentar',
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
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
                        'Confirmaciones de mañana ($totalCount)',
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
                                  ? '$pendingCount por confirmar por WhatsApp con un toque'
                                  : 'Todas las confirmaciones de mañana fueron enviadas')
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

class _GoogleAccountAvatar extends StatelessWidget {
  const _GoogleAccountAvatar({required this.user, required this.radius});

  final AuthUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final photoUrl = user?.photoUrl?.trim();

    if (user == null) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.surfaceContainerHighest,
        foregroundColor: colorScheme.onSurfaceVariant,
        child: Icon(Icons.account_circle_outlined, size: radius * 1.25),
      );
    }

    final initial = (user!.displayName ?? user!.email).trim().isNotEmpty
        ? (user!.displayName ?? user!.email).trim()[0].toUpperCase()
        : 'G';

    final fallback = Text(initial, style: theme.textTheme.labelLarge);

    return CircleAvatar(
      radius: radius,
      backgroundColor: colorScheme.primaryContainer,
      foregroundColor: colorScheme.onPrimaryContainer,
      child: (photoUrl != null && photoUrl.isNotEmpty)
          ? ClipOval(
              child: Image.network(
                photoUrl,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              ),
            )
          : fallback,
    );
  }
}

class _EmptyDayView extends StatelessWidget {
  const _EmptyDayView({
    required this.selectedDate,
    required this.onCreateTap,
    this.upcomingDate,
    this.upcomingAppointments = const <AppointmentEntity>[],
    this.onJumpToUpcomingDate,
    this.onEditUpcomingTap,
    this.onWhatsAppUpcomingTap,
  });

  final DateTime selectedDate;
  final DateTime? upcomingDate;
  final List<AppointmentEntity> upcomingAppointments;
  final VoidCallback onCreateTap;
  final VoidCallback? onJumpToUpcomingDate;
  final ValueChanged<AppointmentEntity>? onEditUpcomingTap;
  final ValueChanged<AppointmentEntity>? onWhatsAppUpcomingTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 104),
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
        if (upcomingDate != null && upcomingAppointments.isNotEmpty) ...[
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Próximas Citas',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ActionChip(
                  avatar: const Icon(Icons.calendar_today_rounded, size: 15),
                  label: Text(DateFormatters.formatShortDate(upcomingDate!)),
                  onPressed: onJumpToUpcomingDate,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          for (final appointment in upcomingAppointments) ...[
            AppointmentCard(
              appointment: appointment,
              onTap: () => onEditUpcomingTap?.call(appointment),
              onWhatsAppTap: () => onWhatsAppUpcomingTap?.call(appointment),
            ),
            const SizedBox(height: 10),
          ],
        ],
      ],
    );
  }
}
