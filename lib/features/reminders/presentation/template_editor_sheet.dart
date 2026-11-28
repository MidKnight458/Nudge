import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/reminders/domain/reminder_template.dart';

/// Expressive bottom sheet to customize the single WhatsApp confirmation
/// response template.
class TemplateEditorSheet extends ConsumerStatefulWidget {
  const TemplateEditorSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const TemplateEditorSheet(),
    );
  }

  @override
  ConsumerState<TemplateEditorSheet> createState() =>
      _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends ConsumerState<TemplateEditorSheet> {
  late final TextEditingController _controller;
  bool _initializedFromTemplates = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: AppConstants.defaultTomorrowReminderBody,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncEditorWithTemplates(List<ReminderTemplateEntity> templates) {
    if (_initializedFromTemplates) {
      return;
    }
    final match = templates
        .where((t) => t.id == AppConstants.tomorrowTemplateId)
        .firstOrNull;
    if (match != null) {
      _controller.text = match.body;
      _initializedFromTemplates = true;
    }
  }

  void _insertPlaceholder(String variable) {
    HapticFeedback.lightImpact();
    final text = _controller.text;
    final selection = _controller.selection;
    if (!selection.isValid) {
      _controller.text = '$text$variable';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      setState(() {});
      return;
    }

    final updated = text.replaceRange(selection.start, selection.end, variable);
    _controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(
        offset: selection.start + variable.length,
      ),
    );
    setState(() {});
  }

  Future<void> _restoreDefault() async {
    HapticFeedback.lightImpact();
    setState(() {
      _controller.text = AppConstants.defaultTomorrowReminderBody;
    });
  }

  Future<void> _save() async {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escribe un mensaje para la plantilla.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(reminderTemplatesRepositoryProvider)
          .saveTemplate(
            templateId: AppConstants.tomorrowTemplateId,
            body: text,
          );
      await HapticFeedback.lightImpact();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plantilla de Respuesta guardada.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final templatesAsync = ref.watch(reminderTemplatesProvider);
    final templates =
        templatesAsync.valueOrNull ?? const <ReminderTemplateEntity>[];
    _syncEditorWithTemplates(templates);

    final previewText = ReminderTemplateEngine.render(
      templateBody: _controller.text,
      clientName: 'Ana López',
      appointmentStart: DateTime(2026, 11, 28, 10, 30),
      serviceTitle: 'Corte y diseño',
    );

    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Plantilla de Respuesta',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const Chip(
                  avatar: Icon(Icons.check_circle_outline_rounded, size: 16),
                  label: Text('Confirmación'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Personaliza el mensaje de confirmación que se enviará por WhatsApp.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ReminderTemplateVariables.all
                  .map((String variable) {
                    return ActionChip(
                      avatar: const Icon(Icons.add_rounded, size: 16),
                      label: Text(variable),
                      onPressed: () => _insertPlaceholder(variable),
                    );
                  })
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              maxLines: 4,
              minLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Mensaje de confirmación',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer.withValues(alpha: 0.45),
                borderRadius: PixelShapes.cardBorderRadius,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 16,
                        color: colorScheme.onSecondaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Vista previa',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    previewText,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _isSaving ? null : _restoreDefault,
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Restaurar'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Guardar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
