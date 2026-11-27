import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/reminders/presentation/template_editor_sheet.dart';

/// Expressive bottom sheet listing all appointments for tomorrow so the user
/// can dispatch WhatsApp reminders one-by-one with a single tap.
class TomorrowRemindersSheet extends ConsumerWidget {
  const TomorrowRemindersSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TomorrowRemindersSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tomorrowAsync = ref.watch(tomorrowAppointmentsProvider);
    final templateBody = ref.watch(tomorrowTemplateBodyProvider);
    final tomorrowDate = DateFormatters.tomorrowRange().start;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.92,
      builder: (BuildContext context, ScrollController scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recordatorios de mañana',
                          style: theme.textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormatters.formatFullDate(tomorrowDate),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Editar plantilla',
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      TemplateEditorSheet.show(
                        context,
                        initialTemplateId: AppConstants.tomorrowTemplateId,
                      );
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: tomorrowAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(
                  child: Text('No se pudieron cargar las citas de mañana.'),
                ),
                data: (List<AppointmentEntity> appointments) {
                  if (appointments.isEmpty) {
                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(24),
                      children: [
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.event_available_rounded,
                                  size: 48,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Sin citas para mañana',
                                  style: theme.textTheme.titleMedium,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Cuando agendes citas para mañana aparecerán '
                                  'aquí listas para enviar su recordatorio.',
                                  style: theme.textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  final sentCount =
                      appointments.where((a) => a.reminderSent).length;
                  final total = appointments.length;
                  final progress = total == 0 ? 0.0 : sentCount / total;

                  return ListView.separated(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    itemCount: appointments.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      if (index == 0) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer.withValues(
                              alpha: 0.55,
                            ),
                            borderRadius: PixelShapes.cardBorderRadius,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.send_rounded,
                                    size: 18,
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$sentCount de $total recordatorios enviados',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: colorScheme.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: PixelShapes.pillBorderRadius,
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 8,
                                  backgroundColor: colorScheme.surface
                                      .withValues(alpha: 0.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      }

                      final appointment = appointments[index - 1];
                      return _TomorrowReminderItem(
                        appointment: appointment,
                        onSendTap: () async {
                          final launched = await ref
                              .read(appointmentsControllerProvider.notifier)
                              .sendWhatsAppReminder(
                                appointment: appointment,
                                templateBody: templateBody,
                              );
                          if (!launched && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No se pudo abrir WhatsApp en este dispositivo.',
                                ),
                              ),
                            );
                          }
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TomorrowReminderItem extends StatelessWidget {
  const _TomorrowReminderItem({
    required this.appointment,
    required this.onSendTap,
  });

  final AppointmentEntity appointment;
  final VoidCallback onSendTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPhone = appointment.hasValidWhatsAppPhone;
    final sent = appointment.reminderSent;

    return Card(
      color: sent
          ? colorScheme.tertiaryContainer.withValues(alpha: 0.35)
          : colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: sent
                  ? colorScheme.tertiaryContainer
                  : colorScheme.primaryContainer,
              foregroundColor: sent
                  ? colorScheme.onTertiaryContainer
                  : colorScheme.onPrimaryContainer,
              child: Icon(
                sent ? Icons.check_rounded : Icons.schedule_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appointment.clientName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${DateFormatters.formatTime(appointment.startTime)} · '
                    '${appointment.title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasPhone
                        ? PhoneSanitizer.formatForDisplay(
                            appointment.clientPhoneE164,
                          )
                        : 'Sin teléfono válido',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: hasPhone
                          ? colorScheme.onSurfaceVariant
                          : colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (sent)
              FilledButton.tonalIcon(
                onPressed: hasPhone
                    ? () {
                        HapticFeedback.lightImpact();
                        onSendTap();
                      }
                    : null,
                icon: const Icon(Icons.done_all_rounded, size: 18),
                label: const Text('Enviado'),
              )
            else
              FilledButton.icon(
                onPressed: hasPhone
                    ? () {
                        HapticFeedback.lightImpact();
                        onSendTap();
                      }
                    : null,
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('Enviar'),
              ),
          ],
        ),
      ),
    );
  }
}
