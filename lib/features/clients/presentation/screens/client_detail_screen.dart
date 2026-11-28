import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/date_formatters.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/appointments/domain/entities/appointment_entity.dart';
import 'package:nudge/features/appointments/presentation/screens/appointment_form_sheet.dart';
import 'package:nudge/features/clients/data/clients_repository.dart';
import 'package:nudge/features/clients/data/google_drive_files_datasource.dart';
import 'package:nudge/features/clients/domain/entities/client_entity.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';
import 'package:nudge/features/reminders/data/whatsapp_launcher_service.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

/// Client/patient detail screen with general notes, Drive-synced files (photos
/// and PDFs), and full appointment history.
class ClientDetailScreen extends ConsumerStatefulWidget {
  const ClientDetailScreen({super.key, required this.clientId});

  final int clientId;

  static Future<void> push(BuildContext context, int clientId) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => ClientDetailScreen(clientId: clientId),
      ),
    );
  }

  @override
  ConsumerState<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends ConsumerState<ClientDetailScreen> {
  final TextEditingController _notesController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  bool _notesInitialized = false;
  bool _isSavingNotes = false;
  bool _isUploadingAttachment = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  void _syncNotesController(ClientEntity client) {
    if (_notesInitialized) {
      return;
    }
    _notesController.text = client.generalNotes ?? '';
    _notesInitialized = true;
  }

  Future<void> _saveNotes(ClientEntity client) async {
    setState(() => _isSavingNotes = true);
    try {
      await ref
          .read(clientsRepositoryProvider)
          .updateGeneralNotes(client.id, _notesController.text);
      await HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notas generales guardadas.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingNotes = false);
      }
    }
  }

  Future<void> _editClientDialog(
    ClientEntity client,
    String singularLabel,
  ) async {
    final nameController = TextEditingController(text: client.name);
    final phoneController = TextEditingController(
      text: client.rawPhone.isNotEmpty
          ? client.rawPhone
          : (client.phoneE164.isNotEmpty ? '+${client.phoneE164}' : ''),
    );
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Editar $singularLabel'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre'),
                  validator: (String? v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Ingresa el nombre.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Teléfono WhatsApp',
                  ),
                  validator: (String? v) {
                    if (v == null || v.trim().isEmpty) {
                      return null;
                    }
                    if (PhoneSanitizer.sanitizeToE164Digits(v) == null) {
                      return 'Número telefónico no válido.';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.of(dialogContext).pop(true);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    final newName = nameController.text.trim();
    final newRawPhone = phoneController.text.trim();
    nameController.dispose();
    phoneController.dispose();

    if (confirmed != true || !mounted) {
      return;
    }

    final e164 = newRawPhone.isEmpty
        ? ''
        : (PhoneSanitizer.sanitizeToE164Digits(newRawPhone) ?? '');
    await HapticFeedback.lightImpact();
    await ref
        .read(clientsRepositoryProvider)
        .createOrUpdateClient(
          existingClientId: client.id,
          name: newName,
          rawPhone: newRawPhone,
          phoneE164: e164,
          googleContactId: client.googleContactId,
        );
  }

  Future<void> _confirmDeleteClient(
    ClientEntity client,
    String singularLabel,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: Text('Eliminar $singularLabel'),
          content: Text(
            '¿Deseas eliminar a ${client.name}, sus notas, archivos adjuntos y citas asociadas?',
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
    await HapticFeedback.lightImpact();
    await ref.read(clientsRepositoryProvider).deleteClient(client);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _attachImage(ClientEntity client, ImageSource source) async {
    HapticFeedback.lightImpact();
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
    );
    if (picked == null || !mounted) {
      return;
    }
    final name = p.basename(picked.path);
    final mime = name.toLowerCase().endsWith('.png')
        ? 'image/png'
        : 'image/jpeg';
    await _saveAttachmentFile(
      client: client,
      file: File(picked.path),
      fileName: name,
      mimeType: mime,
    );
  }

  Future<void> _attachDocument(ClientEntity client) async {
    HapticFeedback.lightImpact();
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    final selected = files.firstOrNull;
    final path = selected?.path;
    if (selected == null || path == null || !mounted) {
      return;
    }

    final fileName = selected.name;
    final lower = fileName.toLowerCase();
    final mime = switch (p.extension(lower)) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      _ => 'image/jpeg',
    };
    await _saveAttachmentFile(
      client: client,
      file: File(path),
      fileName: fileName,
      mimeType: mime,
    );
  }

  Future<void> _saveAttachmentFile({
    required ClientEntity client,
    required File file,
    required String fileName,
    required String mimeType,
  }) async {
    setState(() => _isUploadingAttachment = true);
    try {
      final result = await ref
          .read(clientsRepositoryProvider)
          .addAttachment(
            client: client,
            sourceFile: file,
            originalFileName: fileName,
            mimeType: mimeType,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.warning ??
                'Archivo "${result.attachment.fileName}" guardado y respaldado en Drive.',
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo adjuntar el archivo seleccionado.'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingAttachment = false);
      }
    }
  }

  Future<void> _openAttachment(ClientAttachmentEntity attachment) async {
    HapticFeedback.lightImpact();
    try {
      final file = await ref
          .read(clientsRepositoryProvider)
          .ensureLocalAttachmentFile(attachment);
      if (!mounted) {
        return;
      }
      if (attachment.isImage) {
        await showDialog<void>(
          context: context,
          builder: (BuildContext dialogContext) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(title: Text(attachment.fileName)),
                body: SafeArea(
                  child: Center(
                    child: InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4,
                      child: Image.file(file),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      } else {
        final result = await OpenFilex.open(
          file.path,
          type: attachment.mimeType,
        );
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('No se pudo abrir: ${result.message}')),
          );
        }
      }
    } on DriveSyncUnavailableException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo abrir el archivo adjunto.')),
        );
      }
    }
  }

  Future<void> _deleteAttachment(ClientAttachmentEntity attachment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Eliminar archivo'),
          content: Text('¿Deseas eliminar "${attachment.fileName}"?'),
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
    await HapticFeedback.lightImpact();
    await ref.read(clientsRepositoryProvider).deleteAttachment(attachment);
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) {
      return '';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prefs = ref.watch(appPreferencesProvider).valueOrNull;
    final singularLabel =
        prefs?.clientLabelSingular ?? AppConstants.defaultClientLabelSingular;
    final clientAsync = ref.watch(clientDetailProvider(widget.clientId));
    final appointmentsAsync = ref.watch(
      clientAppointmentsProvider(widget.clientId),
    );
    final attachmentsAsync = ref.watch(
      clientAttachmentsProvider(widget.clientId),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('Perfil del ${singularLabel.toLowerCase()}'),
        actions: [
          if (clientAsync.valueOrNull != null) ...[
            IconButton(
              tooltip: 'Editar',
              onPressed: () =>
                  _editClientDialog(clientAsync.valueOrNull!, singularLabel),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Eliminar',
              onPressed: () =>
                  _confirmDeleteClient(clientAsync.valueOrNull!, singularLabel),
              icon: Icon(
                Icons.delete_outline_rounded,
                color: colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      body: clientAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Error al cargar el perfil.')),
        data: (ClientEntity? client) {
          if (client == null) {
            return const Center(child: Text('Contacto no encontrado.'));
          }
          _syncNotesController(client);

          final appointments =
              appointmentsAsync.valueOrNull ?? const <AppointmentEntity>[];
          final attachments =
              attachmentsAsync.valueOrNull ?? const <ClientAttachmentEntity>[];

          return ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              32 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 26,
                            backgroundColor: colorScheme.primaryContainer,
                            foregroundColor: colorScheme.onPrimaryContainer,
                            child: Text(
                              client.name.isNotEmpty
                                  ? client.name[0].toUpperCase()
                                  : '?',
                              style: theme.textTheme.titleLarge,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  client.name,
                                  style: theme.textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  client.hasValidWhatsAppPhone
                                      ? PhoneSanitizer.formatForDisplay(
                                          client.phoneE164,
                                        )
                                      : 'Sin teléfono registrado',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              AppointmentFormSheet.show(
                                context,
                                initialDate: DateFormatters.startOfDay(
                                  DateTime.now(),
                                ),
                                initialContact: ContactEntity(
                                  id: client.googleContactId,
                                  displayName: client.name,
                                  rawPhone: client.rawPhone,
                                  phoneE164: client.phoneE164,
                                  isGoogleAccount:
                                      client.googleContactId != null,
                                ),
                              );
                            },
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('Agendar cita'),
                          ),
                          if (client.hasValidWhatsAppPhone)
                            OutlinedButton.icon(
                              onPressed: () async {
                                HapticFeedback.lightImpact();
                                await ref
                                    .read(whatsappLauncherServiceProvider)
                                    .launchMessage(
                                      phoneE164Digits: client.phoneE164,
                                      message: 'Hola ${client.name},',
                                    );
                              },
                              icon: const Icon(Icons.chat_outlined, size: 18),
                              label: const Text('WhatsApp'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Notas generales',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _notesController,
                        maxLines: 4,
                        minLines: 3,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText:
                              'Antecedentes, preferencias o detalles del ${singularLabel.toLowerCase()}...',
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: _isSavingNotes
                              ? null
                              : () => _saveNotes(client),
                          icon: const Icon(Icons.save_outlined, size: 18),
                          label: const Text('Guardar notas'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Archivos adjuntos (${attachments.length})',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (_isUploadingAttachment)
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Fotos o PDFs guardados en el dispositivo y respaldados en tu Google Drive.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: _isUploadingAttachment
                                ? null
                                : () =>
                                      _attachImage(client, ImageSource.camera),
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            label: const Text('Cámara'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isUploadingAttachment
                                ? null
                                : () =>
                                      _attachImage(client, ImageSource.gallery),
                            icon: const Icon(
                              Icons.photo_library_outlined,
                              size: 18,
                            ),
                            label: const Text('Galería'),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _isUploadingAttachment
                                ? null
                                : () => _attachDocument(client),
                            icon: const Icon(
                              Icons.picture_as_pdf_outlined,
                              size: 18,
                            ),
                            label: const Text('PDF / Archivo'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (attachments.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.45),
                            borderRadius: PixelShapes.inputBorderRadius,
                          ),
                          child: Text(
                            'Sin archivos adjuntos todavía.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      else
                        Column(
                          children: attachments
                              .map((ClientAttachmentEntity att) {
                                final sizeText = _formatSize(att.sizeBytes);
                                final subtitleParts = <String>[
                                  if (sizeText.isNotEmpty) sizeText,
                                  DateFormatters.formatCompactDateTime(
                                    att.createdAt,
                                  ),
                                  if (att.isSyncedToDrive)
                                    'En Drive'
                                  else
                                    'Pendiente Drive',
                                ];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: CircleAvatar(
                                    backgroundColor: att.isPdf
                                        ? colorScheme.errorContainer
                                        : colorScheme.secondaryContainer,
                                    foregroundColor: att.isPdf
                                        ? colorScheme.onErrorContainer
                                        : colorScheme.onSecondaryContainer,
                                    child: Icon(
                                      att.isPdf
                                          ? Icons.picture_as_pdf_rounded
                                          : (att.isImage
                                                ? Icons.image_outlined
                                                : Icons
                                                      .insert_drive_file_outlined),
                                    ),
                                  ),
                                  title: Text(
                                    att.fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Text(subtitleParts.join(' · ')),
                                  onTap: () => _openAttachment(att),
                                  trailing: IconButton(
                                    tooltip: 'Eliminar archivo',
                                    onPressed: () => _deleteAttachment(att),
                                    icon: Icon(
                                      Icons.delete_outline_rounded,
                                      color: colorScheme.error,
                                    ),
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Historial de citas (${appointments.length})',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (appointments.isEmpty)
                        Text(
                          'Aún no hay citas registradas.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      else
                        Column(
                          children: appointments
                              .map((AppointmentEntity appt) {
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    appt.reminderSent
                                        ? Icons.done_all_rounded
                                        : Icons.event_note_outlined,
                                    color: appt.reminderSent
                                        ? colorScheme.tertiary
                                        : colorScheme.primary,
                                  ),
                                  title: Text(appt.title),
                                  subtitle: Text(
                                    '${DateFormatters.formatShortDate(appt.startTime)} · '
                                    '${DateFormatters.formatTimeRange(appt.startTime, appt.endTime)}',
                                  ),
                                  trailing: const Icon(
                                    Icons.chevron_right_rounded,
                                  ),
                                  onTap: () => AppointmentFormSheet.show(
                                    context,
                                    initialDate: DateFormatters.startOfDay(
                                      appt.startTime,
                                    ),
                                    existing: appt,
                                  ),
                                );
                              })
                              .toList(growable: false),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
