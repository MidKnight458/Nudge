import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/features/appointments/domain/archive_filter.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/controllers/appointments_controller.dart';
import 'package:nudge/features/appointments/presentation/screens/appointment_form_sheet.dart';
import 'package:nudge/features/appointments/presentation/widgets/appointment_card.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';

/// Archive screen displaying past appointments filtered by current year,
/// week, month, or year.
class ArchiveScreen extends ConsumerStatefulWidget {
  const ArchiveScreen({super.key});

  @override
  ConsumerState<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends ConsumerState<ArchiveScreen> {
  final TextEditingController _searchController = TextEditingController();
  ArchivePeriodMode _mode = ArchivePeriodMode.allCurrentYear;
  DateTime _anchorDate = DateFormatters.startOfDay(DateTime.now());
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _selectMode(ArchivePeriodMode nextMode) {
    HapticFeedback.lightImpact();
    setState(() {
      _mode = nextMode;
      _anchorDate = DateFormatters.startOfDay(DateTime.now());
    });
  }

  void _stepPeriod(int delta) {
    HapticFeedback.lightImpact();
    setState(() {
      _anchorDate = ArchiveFilter.stepPeriod(
        mode: _mode,
        anchorDate: _anchorDate,
        delta: delta,
      );
    });
  }

  String _formatPeriodTitle(ArchivePeriodMode mode, DateTime anchor) {
    return switch (mode) {
      ArchivePeriodMode.allCurrentYear => 'Año ${DateTime.now().year}',
      ArchivePeriodMode.week =>
        '${DateFormatters.formatShortDate(ArchiveFilter.startOfWeek(anchor))} - '
            '${DateFormatters.formatShortDate(ArchiveFilter.endOfWeekInclusive(anchor))}',
      ArchivePeriodMode.month => DateFormatters.formatMonthYear(anchor),
      ArchivePeriodMode.year => '${anchor.year}',
    };
  }

  Future<void> _sendConfirmation(
    BuildContext context,
    AppointmentEntity appointment,
  ) async {
    final template = ref.read(responseTemplateBodyProvider);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final appointmentsAsync = ref.watch(allActiveAppointmentsProvider);

    final allAppointments =
        appointmentsAsync.valueOrNull ?? const <AppointmentEntity>[];
    final filtered = ArchiveFilter.filterPast(
      allAppointments: allAppointments,
      mode: _mode,
      anchorDate: _anchorDate,
      now: now,
      searchQuery: _searchQuery,
    );
    final sections = ArchiveFilter.groupAppointments(filtered, _mode);
    final canGoForward = ArchiveFilter.canStepForward(
      mode: _mode,
      anchorDate: _anchorDate,
      now: now,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Archivo'),
        actions: [
          if (appointmentsAsync.hasValue)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: PixelShapes.pillBorderRadius,
                  ),
                  child: Text(
                    filtered.length == 1
                        ? '1 cita'
                        : '${filtered.length} citas',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) {
                setState(() => _searchQuery = value);
              },
              decoration: InputDecoration(
                hintText: 'Buscar en archivo...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      )
                    : null,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                ChoiceChip(
                  label: Text('Todas (${now.year})'),
                  selected: _mode == ArchivePeriodMode.allCurrentYear,
                  onSelected: (_) =>
                      _selectMode(ArchivePeriodMode.allCurrentYear),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Semana'),
                  selected: _mode == ArchivePeriodMode.week,
                  onSelected: (_) => _selectMode(ArchivePeriodMode.week),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Mes'),
                  selected: _mode == ArchivePeriodMode.month,
                  onSelected: (_) => _selectMode(ArchivePeriodMode.month),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Año'),
                  selected: _mode == ArchivePeriodMode.year,
                  onSelected: (_) => _selectMode(ArchivePeriodMode.year),
                ),
              ],
            ),
          ),
          if (_mode != ArchivePeriodMode.allCurrentYear) ...[
            const SizedBox(height: 10),
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: PixelShapes.cardBorderRadius,
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Periodo anterior',
                    onPressed: () => _stepPeriod(-1),
                    icon: const Icon(Icons.chevron_left_rounded),
                  ),
                  Expanded(
                    child: Text(
                      _formatPeriodTitle(_mode, _anchorDate),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Periodo siguiente',
                    onPressed: canGoForward ? () => _stepPeriod(1) : null,
                    icon: const Icon(Icons.chevron_right_rounded),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Expanded(
            child: appointmentsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Center(
                child: Text('No se pudo cargar el archivo de citas.'),
              ),
              data: (_) {
                if (sections.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 30,
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            child: const Icon(Icons.history_rounded, size: 30),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Sin citas pasadas en este periodo',
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Las citas concluidas aparecerán aquí ordenadas del más reciente al más antiguo.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    4,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  itemCount: sections.length,
                  itemBuilder: (BuildContext context, int sectionIndex) {
                    final section = sections[sectionIndex];
                    return Padding(
                      padding: EdgeInsets.only(top: sectionIndex == 0 ? 4 : 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    section.title,
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                                Text(
                                  section.appointments.length == 1
                                      ? '1 cita'
                                      : '${section.appointments.length} citas',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          for (final appt in section.appointments) ...[
                            AppointmentCard(
                              appointment: appt,
                              onTap: () => AppointmentFormSheet.show(
                                context,
                                initialDate: DateFormatters.startOfDay(
                                  appt.startTime,
                                ),
                                existing: appt,
                              ),
                              onWhatsAppTap: () =>
                                  _sendConfirmation(context, appt),
                            ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
