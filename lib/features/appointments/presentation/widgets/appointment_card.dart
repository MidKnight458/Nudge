import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';

/// Expressive 20dp card displaying a scheduled appointment and quick WhatsApp CTA.
class AppointmentCard extends StatelessWidget {
  const AppointmentCard({
    super.key,
    required this.appointment,
    required this.onTap,
    required this.onWhatsAppTap,
  });

  final AppointmentEntity appointment;
  final VoidCallback onTap;
  final VoidCallback onWhatsAppTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final hasPhone = appointment.hasValidWhatsAppPhone;

    return Card(
      child: InkWell(
        borderRadius: PixelShapes.cardBorderRadius,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 64,
                decoration: BoxDecoration(
                  color: appointment.reminderSent
                      ? colorScheme.tertiary
                      : colorScheme.primary,
                  borderRadius: PixelShapes.pillBorderRadius,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: PixelShapes.pillBorderRadius,
                          ),
                          child: Text(
                            DateFormatters.formatTimeRange(
                              appointment.startTime,
                              appointment.endTime,
                            ),
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (appointment.syncStatus.isPending)
                          Tooltip(
                            message: 'Pendiente de sincronizar',
                            child: Icon(
                              Icons.cloud_upload_outlined,
                              size: 16,
                              color: colorScheme.secondary,
                            ),
                          ),
                        if (appointment.reminderSent) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.tertiaryContainer,
                              borderRadius: PixelShapes.pillBorderRadius,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.done_all_rounded,
                                  size: 13,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Confirmado',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onTertiaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      appointment.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            hasPhone
                                ? '${appointment.clientName} · '
                                      '${PhoneSanitizer.formatForDisplay(appointment.clientPhoneE164)}'
                                : '${appointment.clientName} · Sin teléfono',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (appointment.notes != null &&
                        appointment.notes!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        appointment.notes!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: hasPhone
                    ? 'Enviar confirmación por WhatsApp'
                    : 'Agrega un teléfono para enviar WhatsApp',
                onPressed: hasPhone
                    ? () {
                        HapticFeedback.lightImpact();
                        onWhatsAppTap();
                      }
                    : null,
                icon: Icon(
                  appointment.reminderSent
                      ? Icons.mark_chat_read_outlined
                      : Icons.chat_bubble_outline_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
