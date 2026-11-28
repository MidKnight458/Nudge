import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/appointments/domain/appointments_repository.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';
import 'package:nudge/features/contacts/presentation/widgets/contact_picker_sheet.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';
import 'package:nudge/features/settings/domain/app_preferences.dart';
import 'package:nudge/features/settings/presentation/screens/settings_screen.dart';

/// Expressive modal bottom sheet for creating, editing, and deleting appointments.
class AppointmentFormSheet extends ConsumerStatefulWidget {
  const AppointmentFormSheet({
    super.key,
    required this.initialDate,
    this.existing,
    this.initialContact,
  });

  final DateTime initialDate;
  final AppointmentEntity? existing;
  final ContactEntity? initialContact;

  static Future<void> show(
    BuildContext context, {
    required DateTime initialDate,
    AppointmentEntity? existing,
    ContactEntity? initialContact,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AppointmentFormSheet(
        initialDate: initialDate,
        existing: existing,
        initialContact: initialContact,
      ),
    );
  }

  @override
  ConsumerState<AppointmentFormSheet> createState() =>
      _AppointmentFormSheetState();
}

class _AppointmentFormSheetState extends ConsumerState<AppointmentFormSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  ContactEntity? _selectedContact;
  int _activeDurationMinutes = AppConstants.defaultSlotDurationMinutes;
  bool _timeTouched = false;
  bool _customTimeMode = false;
  bool _isSubmitting = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _notesController = TextEditingController(text: existing?.notes ?? '');

    if (existing != null) {
      final startLocal = existing.startTime.toLocal();
      final endLocal = existing.endTime.toLocal();
      _selectedDate = DateFormatters.startOfDay(startLocal);
      _startTime = TimeOfDay(hour: startLocal.hour, minute: startLocal.minute);
      _endTime = TimeOfDay(hour: endLocal.hour, minute: endLocal.minute);
      final diffMins = endLocal.difference(startLocal).inMinutes;
      _activeDurationMinutes = diffMins > 0
          ? diffMins
          : AppConstants.defaultSlotDurationMinutes;
      _selectedContact = ContactEntity(
        id: existing.clientGoogleContactId,
        displayName: existing.clientName,
        rawPhone: existing.clientRawPhone,
        phoneE164: existing.clientPhoneE164,
        isGoogleAccount: existing.clientGoogleContactId != null,
      );
      _timeTouched = true;
    } else {
      final now = DateTime.now();
      final base = DateFormatters.startOfDay(widget.initialDate);
      final defaultHour = DateFormatters.isSameDay(base, now)
          ? (now.hour + 1).clamp(8, 20)
          : 10;
      _selectedDate = base;
      _startTime = TimeOfDay(hour: defaultHour, minute: 0);
      _endTime = TimeOfDay(hour: (defaultHour + 1).clamp(1, 23), minute: 0);
      _selectedContact = widget.initialContact;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime day, TimeOfDay time) {
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  int _toMinutesOfDay(TimeOfDay time) => time.hour * 60 + time.minute;

  TimeOfDay _fromMinutesOfDay(int minutes) {
    final clamped = minutes.clamp(0, 23 * 60 + 59);
    return TimeOfDay(hour: clamped ~/ 60, minute: clamped % 60);
  }

  void _applyStartAndDuration(int startMinutes, int durationMinutes) {
    final start = _fromMinutesOfDay(startMinutes);
    final endMinutes = (startMinutes + durationMinutes).clamp(
      startMinutes + 5,
      23 * 60 + 59,
    );
    setState(() {
      _startTime = start;
      _endTime = _fromMinutesOfDay(endMinutes);
      _activeDurationMinutes = durationMinutes;
      _timeTouched = true;
      _customTimeMode = false;
    });
  }

  Future<void> _pickContact() async {
    HapticFeedback.lightImpact();
    final picked = await ContactPickerSheet.show(context);
    if (picked != null && mounted) {
      setState(() => _selectedContact = picked);
    }
  }

  Future<void> _pickDate() async {
    HapticFeedback.lightImpact();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(_selectedDate.year - 1),
      lastDate: DateTime(_selectedDate.year + 3),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = DateFormatters.startOfDay(picked);
        _timeTouched = false;
      });
    }
  }

  Future<void> _pickStartTime() async {
    HapticFeedback.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null && mounted) {
      setState(() {
        final previousStart = _combine(_selectedDate, _startTime);
        final previousEnd = _combine(_selectedDate, _endTime);
        final duration = previousEnd.isAfter(previousStart)
            ? previousEnd.difference(previousStart)
            : Duration(minutes: _activeDurationMinutes);

        _startTime = picked;
        final newStart = _combine(_selectedDate, picked);
        final adjustedEnd = newStart.add(duration);
        _endTime = TimeOfDay(
          hour: adjustedEnd.hour,
          minute: adjustedEnd.minute,
        );
        _timeTouched = true;
      });
    }
  }

  Future<void> _pickEndTime() async {
    HapticFeedback.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null && mounted) {
      setState(() {
        _endTime = picked;
        _timeTouched = true;
      });
    }
  }

  Future<void> _save(String singularLower) async {
    if (_selectedContact == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Selecciona un $singularLower antes de guardar la cita.',
          ),
        ),
      );
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final start = _combine(_selectedDate, _startTime);
    final end = _combine(_selectedDate, _endTime);
    if (!end.isAfter(start)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La hora de fin debe ser posterior a la de inicio.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final contact = _selectedContact!;
      final input = AppointmentInput(
        clientName: contact.displayName,
        clientRawPhone: contact.rawPhone,
        clientPhoneE164: contact.phoneE164,
        clientGoogleContactId: contact.id,
        title: _titleController.text.trim(),
        notes: _notesController.text.trim(),
        startTime: start,
        endTime: end,
      );

      final controller = ref.read(appointmentsControllerProvider.notifier);
      if (_isEditing) {
        await controller.updateAppointment(widget.existing!, input);
      } else {
        await controller.createAppointment(input);
      }

      ref.read(selectedDateProvider.notifier).state = _selectedDate;
      await HapticFeedback.lightImpact();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) {
      return;
    }

    HapticFeedback.lightImpact();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar cita'),
          content: Text(
            '¿Deseas eliminar "${existing.title}" con ${existing.clientName}? '
            'También se eliminará de Google Calendar al sincronizar.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
                foregroundColor: Theme.of(dialogContext).colorScheme.onError,
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await ref
          .read(appointmentsControllerProvider.notifier)
          .deleteAppointment(existing);
      await HapticFeedback.lightImpact();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _sendConfirmationWhatsApp() async {
    final existing = widget.existing;
    if (existing == null || !existing.hasValidWhatsAppPhone) {
      return;
    }

    HapticFeedback.lightImpact();
    final template = ref.read(responseTemplateBodyProvider);
    final launched = await ref
        .read(appointmentsControllerProvider.notifier)
        .sendWhatsAppReminder(appointment: existing, templateBody: template);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir WhatsApp en este dispositivo.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    final prefs =
        ref.watch(appPreferencesProvider).valueOrNull ??
        AppPreferencesEntity(
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
    final singularLower = prefs.clientLabelSingular.toLowerCase();

    final dayAppointments =
        ref.watch(appointmentsForDateProvider(_selectedDate)).valueOrNull ??
        const <AppointmentEntity>[];

    final matchedService = prefs.services
        .where(
          (CustomServiceItem s) =>
              s.name.trim().toLowerCase() ==
              _titleController.text.trim().toLowerCase(),
        )
        .firstOrNull;

    final effectiveDuration = _isEditing
        ? _activeDurationMinutes
        : (matchedService?.durationMinutes ??
              prefs.schedule.defaultSlotDurationMinutes);

    final availableSlots = prefs.schedule.availableSlotsForDay(
      day: _selectedDate,
      dayAppointments: dayAppointments,
      durationMinutes: effectiveDuration,
      excludeAppointmentId: widget.existing?.id,
    );

    if (!_isEditing &&
        !_timeTouched &&
        !_customTimeMode &&
        availableSlots.isNotEmpty) {
      final firstSlot = availableSlots.first;
      if (_toMinutesOfDay(_startTime) != firstSlot) {
        _startTime = _fromMinutesOfDay(firstSlot);
        _endTime = _fromMinutesOfDay(firstSlot + effectiveDuration);
      }
    }

    final startDateTime = _combine(_selectedDate, _startTime);
    final endDateTime = _combine(_selectedDate, _endTime);
    final selectedStartMinutes = _toMinutesOfDay(_startTime);
    final occupiedSlotsCount =
        prefs.schedule.slotMinutesFromMidnight.length - availableSlots.length;

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _isEditing ? 'Editar cita' : 'Nueva cita',
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    if (_isEditing)
                      IconButton(
                        tooltip: 'Eliminar cita',
                        onPressed: _isSubmitting ? null : _confirmDelete,
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: colorScheme.error,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                Card(
                  color: _selectedContact != null
                      ? colorScheme.primaryContainer.withValues(alpha: 0.45)
                      : colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                  child: ListTile(
                    shape: PixelShapes.cardShape,
                    leading: CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: Icon(
                        _selectedContact == null
                            ? Icons.person_add_alt_1_rounded
                            : Icons.person_rounded,
                      ),
                    ),
                    title: Text(
                      _selectedContact?.displayName ??
                          'Seleccionar $singularLower',
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: Text(
                      _selectedContact == null
                          ? 'Elige un contacto de Google o crea uno manual'
                          : (_selectedContact!.phoneE164.isEmpty
                                ? 'Sin teléfono WhatsApp (toca para agregar)'
                                : PhoneSanitizer.formatForDisplay(
                                    _selectedContact!.phoneE164,
                                  )),
                      style: theme.textTheme.bodyMedium,
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: _isSubmitting ? null : _pickContact,
                  ),
                ),
                const SizedBox(height: 14),
                if (prefs.services.isNotEmpty) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Servicios o motivos',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          SettingsScreen.push(
                            context,
                            initialSection: SettingsSection.services,
                          );
                        },
                        icon: const Icon(Icons.tune_rounded, size: 16),
                        label: const Text('Editar'),
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: prefs.services
                        .map((CustomServiceItem service) {
                          final selected =
                              _titleController.text.trim().toLowerCase() ==
                              service.name.trim().toLowerCase();
                          return ChoiceChip(
                            label: Text(
                              '${service.name} (${service.durationMinutes}m)',
                            ),
                            selected: selected,
                            onSelected: (_) {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _titleController.text = service.name;
                                _activeDurationMinutes =
                                    service.durationMinutes;
                                final currentStartMin = _toMinutesOfDay(
                                  _startTime,
                                );
                                _endTime = _fromMinutesOfDay(
                                  currentStartMin + service.durationMinutes,
                                );
                              });
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                  const SizedBox(height: 10),
                ] else ...[
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        SettingsScreen.push(
                          context,
                          initialSection: SettingsSection.services,
                        );
                      },
                      icon: const Icon(Icons.tune_rounded, size: 18),
                      label: const Text('Personalizar servicios o motivos'),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _titleController,
                  textCapitalization: TextCapitalization.sentences,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Servicio o motivo de la cita',
                    hintText: 'Ej. Corte, consulta, sesión...',
                    prefixIcon: Icon(Icons.work_outline_rounded),
                  ),
                  validator: (String? value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Ingresa el servicio o motivo de la cita.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    ActionChip(
                      avatar: const Icon(
                        Icons.calendar_today_rounded,
                        size: 17,
                      ),
                      label: Text(
                        DateFormatters.formatShortDate(_selectedDate),
                      ),
                      onPressed: _isSubmitting ? null : _pickDate,
                    ),
                    const Spacer(),
                    if (prefs.schedule.hasConfiguredSlots)
                      FilterChip(
                        avatar: const Icon(
                          Icons.edit_calendar_outlined,
                          size: 16,
                        ),
                        label: const Text('Horario personalizado'),
                        selected: _customTimeMode,
                        onSelected: (bool selected) {
                          HapticFeedback.lightImpact();
                          setState(() => _customTimeMode = selected);
                        },
                      )
                    else
                      TextButton.icon(
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          SettingsScreen.push(
                            context,
                            initialSection: SettingsSection.schedule,
                          );
                        },
                        icon: const Icon(Icons.schedule_rounded, size: 16),
                        label: const Text('Configurar horarios'),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                if (prefs.schedule.hasConfiguredSlots && !_customTimeMode) ...[
                  Row(
                    children: [
                      Text(
                        'Horarios disponibles',
                        style: theme.textTheme.labelLarge,
                      ),
                      if (occupiedSlotsCount > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '($occupiedSlotsCount ocupados)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (availableSlots.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        borderRadius: PixelShapes.inputBorderRadius,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Todos los horarios configurados ya están ocupados este día.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () =>
                                setState(() => _customTimeMode = true),
                            icon: const Icon(
                              Icons.access_time_rounded,
                              size: 16,
                            ),
                            label: const Text('Elegir horario personalizado'),
                          ),
                        ],
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableSlots
                          .map((int slotMinutes) {
                            final selected =
                                selectedStartMinutes == slotMinutes;
                            return ChoiceChip(
                              label: Text(
                                ScheduleConfig.formatMinutesOfDay(slotMinutes),
                              ),
                              selected: selected,
                              onSelected: (_) {
                                HapticFeedback.lightImpact();
                                _applyStartAndDuration(
                                  slotMinutes,
                                  effectiveDuration,
                                );
                              },
                            );
                          })
                          .toList(growable: false),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Horario seleccionado: '
                    '${DateFormatters.formatTimeRange(startDateTime, endDateTime)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.schedule_rounded, size: 17),
                        label: Text(
                          'Inicio: ${DateFormatters.formatTime(startDateTime)}',
                        ),
                        onPressed: _isSubmitting ? null : _pickStartTime,
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.timelapse_rounded, size: 17),
                        label: Text(
                          'Fin: ${DateFormatters.formatTime(endDateTime)}',
                        ),
                        onPressed: _isSubmitting ? null : _pickEndTime,
                      ),
                    ],
                  ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  minLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notas de la cita (opcional)',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                if (_isEditing && widget.existing!.hasValidWhatsAppPhone) ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _isSubmitting ? null : _sendConfirmationWhatsApp,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Enviar confirmación por WhatsApp'),
                  ),
                ],
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : () => _save(singularLower),
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_isEditing ? 'Guardar cambios' : 'Agendar cita'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
