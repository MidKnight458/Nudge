import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/reminders/presentation/template_editor_sheet.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';
import 'package:nudge/features/settings/domain/app_preferences.dart';

/// Sections inside [SettingsScreen] that deep-links can scroll directly into.
enum SettingsSection { clientLabel, services, schedule }

/// Pixel Material 3 Expressive settings screen for terminology, services,
/// available appointment time slots, and WhatsApp response template.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  final SettingsSection? initialSection;

  static Future<void> push(
    BuildContext context, {
    SettingsSection? initialSection,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(initialSection: initialSection),
      ),
    );
  }

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final GlobalKey _servicesKey = GlobalKey();
  final GlobalKey _scheduleKey = GlobalKey();

  late final TextEditingController _pluralController;
  late final TextEditingController _singularController;
  bool _labelsInitialized = false;
  bool _isSavingLabels = false;

  TimeOfDay _rangeStart = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _rangeEnd = const TimeOfDay(hour: 18, minute: 0);
  int _intervalMinutes = 30;

  @override
  void initState() {
    super.initState();
    _pluralController = TextEditingController();
    _singularController = TextEditingController();

    if (widget.initialSection != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToInitialSection();
      });
    }
  }

  @override
  void dispose() {
    _pluralController.dispose();
    _singularController.dispose();
    super.dispose();
  }

  void _scrollToInitialSection() {
    final targetContext = switch (widget.initialSection) {
      SettingsSection.services => _servicesKey.currentContext,
      SettingsSection.schedule => _scheduleKey.currentContext,
      _ => null,
    };
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _syncLabels(AppPreferencesEntity prefs) {
    if (_labelsInitialized) {
      return;
    }
    _pluralController.text = prefs.clientLabelPlural;
    _singularController.text = prefs.clientLabelSingular;
    _intervalMinutes = prefs.schedule.defaultSlotDurationMinutes;
    _labelsInitialized = true;
  }

  Future<void> _saveLabels() async {
    final plural = _pluralController.text.trim();
    final singular = _singularController.text.trim();
    if (plural.isEmpty || singular.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ingresa el nombre en singular y en plural.'),
        ),
      );
      return;
    }
    setState(() => _isSavingLabels = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveClientLabels(plural: plural, singular: singular);
      await HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apartado actualizado a "$plural".')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingLabels = false);
      }
    }
  }

  Future<void> _applyLabelPreset(String plural, String singular) async {
    HapticFeedback.lightImpact();
    _pluralController.text = plural;
    _singularController.text = singular;
    await _saveLabels();
  }

  Future<void> _openServiceDialog(
    AppPreferencesEntity prefs, {
    CustomServiceItem? existing,
  }) async {
    final nameController = TextEditingController(text: existing?.name ?? '');
    var duration =
        existing?.durationMinutes ?? prefs.schedule.defaultSlotDurationMinutes;

    final saved = await showDialog<CustomServiceItem>(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null
                    ? 'Nuevo servicio o motivo'
                    : 'Editar servicio',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Nombre del servicio o motivo',
                      hintText: 'Ej. Consulta, Corte, Terapia...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Duración estimada',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <int>[15, 20, 30, 45, 60, 90, 120]
                        .map((int mins) {
                          return ChoiceChip(
                            label: Text('$mins min'),
                            selected: duration == mins,
                            onSelected: (_) {
                              setDialogState(() => duration = mins);
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final trimmed = nameController.text.trim();
                    if (trimmed.isEmpty) {
                      return;
                    }
                    Navigator.of(dialogContext).pop(
                      CustomServiceItem(
                        id: existing?.id ?? generateAppointmentSyncId(),
                        name: trimmed,
                        durationMinutes: duration,
                      ),
                    );
                  },
                  child: const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    if (saved == null) {
      return;
    }

    final updated = <CustomServiceItem>[
      for (final item in prefs.services)
        if (item.id == saved.id) saved else item,
      if (existing == null) saved,
    ];
    await HapticFeedback.lightImpact();
    await ref.read(settingsRepositoryProvider).saveServices(updated);
  }

  Future<void> _deleteService(
    AppPreferencesEntity prefs,
    CustomServiceItem item,
  ) async {
    HapticFeedback.lightImpact();
    final updated = prefs.services
        .where((CustomServiceItem s) => s.id != item.id)
        .toList(growable: false);
    await ref.read(settingsRepositoryProvider).saveServices(updated);
  }

  Future<void> _generateScheduleSlots(
    AppPreferencesEntity prefs, {
    required bool mergeWithExisting,
  }) async {
    final startMin = _rangeStart.hour * 60 + _rangeStart.minute;
    final endMin = _rangeEnd.hour * 60 + _rangeEnd.minute;
    if (endMin < startMin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La hora de fin debe ser igual o posterior al inicio.'),
        ),
      );
      return;
    }

    final generated = ScheduleConfig.generateSlots(
      startMinutes: startMin,
      endMinutes: endMin,
      intervalMinutes: _intervalMinutes,
    );
    final combined = mergeWithExisting
        ? <int>{
            ...prefs.schedule.slotMinutesFromMidnight,
            ...generated,
          }.toList()
        : generated;

    await HapticFeedback.lightImpact();
    await ref
        .read(settingsRepositoryProvider)
        .saveSchedule(
          prefs.schedule.copyWith(
            defaultSlotDurationMinutes: _intervalMinutes,
            slotMinutesFromMidnight: combined,
          ),
        );
  }

  Future<void> _addSingleSlot(AppPreferencesEntity prefs) async {
    HapticFeedback.lightImpact();
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 16, minute: 30),
    );
    if (picked == null) {
      return;
    }
    final mins = picked.hour * 60 + picked.minute;
    await ref
        .read(settingsRepositoryProvider)
        .saveSchedule(
          prefs.schedule.copyWith(
            slotMinutesFromMidnight: <int>{
              ...prefs.schedule.slotMinutesFromMidnight,
              mins,
            }.toList(),
          ),
        );
  }

  Future<void> _removeSlot(AppPreferencesEntity prefs, int slotMinutes) async {
    HapticFeedback.lightImpact();
    final updated = prefs.schedule.slotMinutesFromMidnight
        .where((int m) => m != slotMinutes)
        .toList(growable: false);
    await ref
        .read(settingsRepositoryProvider)
        .saveSchedule(
          prefs.schedule.copyWith(slotMinutesFromMidnight: updated),
        );
  }

  Future<void> _clearAllSlots(AppPreferencesEntity prefs) async {
    HapticFeedback.lightImpact();
    await ref
        .read(settingsRepositoryProvider)
        .saveSchedule(
          prefs.schedule.copyWith(slotMinutesFromMidnight: const <int>[]),
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prefsAsync = ref.watch(appPreferencesProvider);
    final prefs =
        prefsAsync.valueOrNull ??
        AppPreferencesEntity(
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
    _syncLabels(prefs);

    final previewCount = ScheduleConfig.generateSlots(
      startMinutes: _rangeStart.hour * 60 + _rangeStart.minute,
      endMinutes: _rangeEnd.hour * 60 + _rangeEnd.minute,
      intervalMinutes: _intervalMinutes,
    ).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
        children: [
          _SectionCard(
            icon: Icons.badge_outlined,
            title: 'Tipo de contactos',
            subtitle: 'Adapta el nombre del apartado según tu negocio (ej. Pacientes, Clientes, Alumnos).',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children:
                      const <(String, String)>[
                            ('Clientes', 'Cliente'),
                            ('Pacientes', 'Paciente'),
                            ('Alumnos', 'Alumno'),
                            ('Estudiantes', 'Estudiante'),
                            ('Socios', 'Socio'),
                          ]
                          .map(((String, String) preset) {
                            final selected =
                                prefs.clientLabelPlural.toLowerCase() ==
                                preset.$1.toLowerCase();
                            return ChoiceChip(
                              label: Text(preset.$1),
                              selected: selected,
                              onSelected: (_) =>
                                  _applyLabelPreset(preset.$1, preset.$2),
                            );
                          })
                          .toList(growable: false),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _pluralController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Plural',
                          hintText: 'Clientes / Pacientes',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _singularController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Singular',
                          hintText: 'Cliente / Paciente',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonalIcon(
                    onPressed: _isSavingLabels ? null : _saveLabels,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Guardar nombre'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            key: _servicesKey,
            icon: Icons.medical_services_outlined,
            title: 'Servicios o motivos',
            subtitle: 'Crea accesos rápidos con duración predefinida para llenar tus citas con un toque.',
            trailing: FilledButton.tonalIcon(
              onPressed: () => _openServiceDialog(prefs),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Agregar'),
            ),
            child: prefs.services.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.45,
                      ),
                      borderRadius: PixelShapes.inputBorderRadius,
                    ),
                    child: Text(
                      'Aún no has agregado servicios o motivos personalizados.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : Column(
                    children: prefs.services
                        .map((CustomServiceItem item) {
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.name),
                            subtitle: Text('${item.durationMinutes} min'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Editar',
                                  onPressed: () =>
                                      _openServiceDialog(prefs, existing: item),
                                  icon: const Icon(Icons.edit_outlined),
                                ),
                                IconButton(
                                  tooltip: 'Eliminar',
                                  onPressed: () => _deleteService(prefs, item),
                                  icon: Icon(
                                    Icons.delete_outline_rounded,
                                    color: colorScheme.error,
                                  ),
                                ),
                              ],
                            ),
                          );
                        })
                        .toList(growable: false),
                  ),
          ),
          const SizedBox(height: 14),
          _SectionCard(
            key: _scheduleKey,
            icon: Icons.schedule_rounded,
            title: 'Horarios personalizados',
            subtitle: 'Configura los bloques disponibles (ej. 16:30, 17:00, 17:30). Al ocupar uno, desaparece de los disponibles.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Generador rápido', style: theme.textTheme.titleSmall),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ActionChip(
                      avatar: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text('Desde ${_rangeStart.format(context)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _rangeStart,
                        );
                        if (picked != null && mounted) {
                          setState(() => _rangeStart = picked);
                        }
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.stop_rounded, size: 18),
                      label: Text('Hasta ${_rangeEnd.format(context)}'),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _rangeEnd,
                        );
                        if (picked != null && mounted) {
                          setState(() => _rangeEnd = picked);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Lapso / duración por cita',
                  style: theme.textTheme.labelMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <int>[15, 20, 30, 45, 60, 90]
                      .map((int mins) {
                        return ChoiceChip(
                          label: Text('$mins min'),
                          selected: _intervalMinutes == mins,
                          onSelected: (_) {
                            setState(() => _intervalMinutes = mins);
                          },
                        );
                      })
                      .toList(growable: false),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: previewCount > 0
                          ? () => _generateScheduleSlots(
                              prefs,
                              mergeWithExisting: false,
                            )
                          : null,
                      icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                      label: Text('Aplicar rango ($previewCount)'),
                    ),
                    OutlinedButton.icon(
                      onPressed: previewCount > 0
                          ? () => _generateScheduleSlots(
                              prefs,
                              mergeWithExisting: true,
                            )
                          : null,
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: const Text('Sumar al actual'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Horas configuradas (${prefs.schedule.slotMinutesFromMidnight.length})',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _addSingleSlot(prefs),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Hora puntual'),
                    ),
                    if (prefs.schedule.slotMinutesFromMidnight.isNotEmpty)
                      TextButton(
                        onPressed: () => _clearAllSlots(prefs),
                        child: const Text('Limpiar'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                if (prefs.schedule.slotMinutesFromMidnight.isEmpty)
                  Text(
                    'Sin horarios fijos. Puedes agendar cualquier hora libremente o generar un rango arriba.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: prefs.schedule.slotMinutesFromMidnight
                        .map((int mins) {
                          return InputChip(
                            label: Text(
                              ScheduleConfig.formatMinutesOfDay(mins),
                            ),
                            onDeleted: () => _removeSlot(prefs, mins),
                          );
                        })
                        .toList(growable: false),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Card(
            child: ListTile(
              shape: PixelShapes.cardShape,
              leading: CircleAvatar(
                backgroundColor: colorScheme.tertiaryContainer,
                foregroundColor: colorScheme.onTertiaryContainer,
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              title: const Text('Plantilla de Respuesta'),
              subtitle: const Text(
                'Edita el mensaje de confirmación que se enviará por WhatsApp.',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                HapticFeedback.lightImpact();
                TemplateEditorSheet.show(context);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Icon(icon, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
