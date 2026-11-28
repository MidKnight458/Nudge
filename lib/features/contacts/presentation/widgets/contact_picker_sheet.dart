import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/auth/presentation/auth_controller.dart';
import 'package:nudge/features/contacts/domain/contacts_repository.dart';
import 'package:nudge/features/contacts/domain/entities/contact_entity.dart';
import 'package:nudge/features/contacts/presentation/contacts_controller.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';
import 'package:permission_handler/permission_handler.dart';

/// Expressive modal bottom sheet for picking a Google-prioritized contact
/// or entering a client manually with optional Google Contacts saving.
class ContactPickerSheet extends ConsumerStatefulWidget {
  const ContactPickerSheet({super.key});

  static Future<ContactEntity?> show(BuildContext context) {
    return showModalBottomSheet<ContactEntity>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ContactPickerSheet(),
    );
  }

  @override
  ConsumerState<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends ConsumerState<ContactPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _manualNameController = TextEditingController();
  final TextEditingController _manualPhoneController = TextEditingController();
  final GlobalKey<FormState> _manualFormKey = GlobalKey<FormState>();

  bool _manualMode = false;
  bool _saveToGoogleContacts = true;
  bool _isSavingManual = false;
  String? _selectedGoogleAccount;
  String? _manualPhonePreview;

  @override
  void dispose() {
    _searchController.dispose();
    _manualNameController.dispose();
    _manualPhoneController.dispose();
    super.dispose();
  }

  void _updateManualPreview(String value) {
    setState(() {
      _manualPhonePreview = PhoneSanitizer.sanitizeToE164Digits(value);
    });
  }

  List<String> _resolveAvailableGoogleAccounts(ContactsState contactsState) {
    final signedInEmail = ref.read(authControllerProvider).user?.email.trim();
    final merged = <String>{
      if (signedInEmail != null && signedInEmail.isNotEmpty) signedInEmail,
      ...contactsState.deviceGoogleAccounts,
    };
    return merged.toList(growable: false);
  }

  Future<void> _submitManualContact(ContactsState contactsState) async {
    if (!(_manualFormKey.currentState?.validate() ?? false)) {
      return;
    }
    final displayName = _manualNameController.text.trim();
    final rawPhone = _manualPhoneController.text.trim();
    final e164 = PhoneSanitizer.sanitizeToE164Digits(rawPhone);
    if (e164 == null) {
      return;
    }

    final availableAccounts = _resolveAvailableGoogleAccounts(contactsState);
    final targetAccount =
        _selectedGoogleAccount ??
        (availableAccounts.isNotEmpty ? availableAccounts.first : null);

    setState(() => _isSavingManual = true);
    try {
      late final ContactEntity result;
      if (_saveToGoogleContacts) {
        try {
          result = await ref
              .read(contactsControllerProvider.notifier)
              .saveManualContactToGoogle(
                displayName: displayName,
                rawPhone: rawPhone,
                phoneE164: e164,
                googleAccountName: targetAccount,
              );
        } on StateError catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.message)));
          }
          result = ContactEntity(
            displayName: displayName,
            rawPhone: rawPhone,
            phoneE164: e164,
            isGoogleAccount: false,
          );
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Se usará en Nudge; no se pudo guardar en Contactos de Google.',
                ),
              ),
            );
          }
          result = ContactEntity(
            displayName: displayName,
            rawPhone: rawPhone,
            phoneE164: e164,
            isGoogleAccount: false,
          );
        }
      } else {
        result = ContactEntity(
          displayName: displayName,
          rawPhone: rawPhone,
          phoneE164: e164,
          isGoogleAccount: false,
        );
      }

      await HapticFeedback.lightImpact();
      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } finally {
      if (mounted) {
        setState(() => _isSavingManual = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final state = ref.watch(contactsControllerProvider);
    final prefs = ref.watch(appPreferencesProvider).valueOrNull;
    final singularLabel =
        prefs?.clientLabelSingular ?? AppConstants.defaultClientLabelSingular;
    final singularLower = singularLabel.toLowerCase();
    final filtered = state.filteredContacts;
    final viewInsets = MediaQuery.viewInsetsOf(context);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: _manualMode ? 0.68 : 0.84,
        minChildSize: 0.45,
        maxChildSize: 0.94,
        builder: (BuildContext context, ScrollController scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _manualMode
                                ? 'Nuevo $singularLower'
                                : 'Seleccionar $singularLower',
                            style: theme.textTheme.titleLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _manualMode
                                ? 'Guárdalo directo en Google o úsalo solo aquí'
                                : 'Contactos de Google priorizados',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _isSavingManual
                          ? null
                          : () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                _manualMode = !_manualMode;
                                if (_manualMode &&
                                    _manualNameController.text.isEmpty &&
                                    _searchController.text.trim().isNotEmpty) {
                                  _manualNameController.text = _searchController
                                      .text
                                      .trim();
                                }
                              });
                            },
                      icon: Icon(
                        _manualMode
                            ? Icons.contacts_outlined
                            : Icons.person_add_alt_1_rounded,
                      ),
                      label: Text(_manualMode ? 'Contactos' : 'Manual'),
                    ),
                  ],
                ),
              ),
              if (_manualMode)
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: _buildManualForm(
                      theme,
                      colorScheme,
                      state,
                      singularLower,
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: TextField(
                    controller: _searchController,
                    textInputAction: TextInputAction.search,
                    onChanged: (String value) {
                      ref
                          .read(contactsControllerProvider.notifier)
                          .setSearchQuery(value);
                    },
                    decoration: InputDecoration(
                      hintText: 'Buscar por nombre o teléfono...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: state.searchQuery.isNotEmpty
                          ? IconButton(
                              tooltip: 'Limpiar búsqueda',
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(contactsControllerProvider.notifier)
                                    .setSearchQuery('');
                              },
                              icon: const Icon(Icons.close_rounded),
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildContactsBody(
                    context: context,
                    theme: theme,
                    colorScheme: colorScheme,
                    state: state,
                    filtered: filtered,
                    scrollController: scrollController,
                    singularLower: singularLower,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildManualForm(
    ThemeData theme,
    ColorScheme colorScheme,
    ContactsState state,
    String singularLower,
  ) {
    final googleAccounts = _resolveAvailableGoogleAccounts(state);
    final activeAccount =
        _selectedGoogleAccount != null &&
            googleAccounts.contains(_selectedGoogleAccount)
        ? _selectedGoogleAccount
        : (googleAccounts.isNotEmpty ? googleAccounts.first : null);

    return Form(
      key: _manualFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _manualNameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nombre del $singularLower',
              prefixIcon: const Icon(Icons.person_outline_rounded),
            ),
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa el nombre del $singularLower.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _manualPhoneController,
            keyboardType: TextInputType.phone,
            onChanged: _updateManualPreview,
            decoration: const InputDecoration(
              labelText: 'Teléfono WhatsApp',
              hintText: 'Ej. 461 123 4567 o +52 461 123 4567',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
            validator: (String? value) {
              if (value == null || value.trim().isEmpty) {
                return 'Ingresa un número telefónico.';
              }
              if (PhoneSanitizer.sanitizeToE164Digits(value) == null) {
                return 'Ingresa un número telefónico válido con lada o código de país.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _manualPhonePreview == null
                ? const SizedBox.shrink()
                : Container(
                    key: ValueKey<String>(_manualPhonePreview!),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.6,
                      ),
                      borderRadius: PixelShapes.inputBorderRadius,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 18,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Listo para WhatsApp · ${PhoneSanitizer.formatForDisplay(_manualPhonePreview!)}',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  value: _saveToGoogleContacts,
                  onChanged: _isSavingManual
                      ? null
                      : (bool value) {
                          HapticFeedback.lightImpact();
                          setState(() => _saveToGoogleContacts = value);
                        },
                  title: const Text('Guardar en Contactos de Google'),
                  subtitle: Text(
                    _saveToGoogleContacts
                        ? (activeAccount != null
                              ? 'Se guardará en $activeAccount'
                              : 'Se guardará en tu agenda de contactos')
                        : 'Solo se guardará dentro de Nudge',
                  ),
                ),
                if (_saveToGoogleContacts && googleAccounts.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: DropdownButtonFormField<String>(
                      initialValue: activeAccount,
                      decoration: const InputDecoration(
                        labelText: 'Cuenta de Google',
                        prefixIcon: Icon(Icons.account_circle_outlined),
                      ),
                      items: googleAccounts
                          .map(
                            (String email) => DropdownMenuItem<String>(
                              value: email,
                              child: Text(
                                email,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _isSavingManual
                          ? null
                          : (String? value) {
                              setState(() => _selectedGoogleAccount = value);
                            },
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _isSavingManual
                ? null
                : () => _submitManualContact(state),
            icon: _isSavingManual
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(
              _saveToGoogleContacts
                  ? 'Guardar y usar $singularLower'
                  : 'Usar este $singularLower',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsBody({
    required BuildContext context,
    required ThemeData theme,
    required ColorScheme colorScheme,
    required ContactsState state,
    required List<ContactEntity> filtered,
    required ScrollController scrollController,
    required String singularLower,
  }) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.permissionState != ContactsPermissionState.granted) {
      final isPermanent =
          state.permissionState == ContactsPermissionState.permanentlyDenied;
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    Icons.contacts_outlined,
                    size: 44,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Permiso de contactos requerido',
                    style: theme.textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Autoriza el acceso para priorizar tus contactos de Google '
                    'y preparar sus números automáticamente para WhatsApp.',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      if (isPermanent) {
                        openAppSettings();
                      } else {
                        ref
                            .read(contactsControllerProvider.notifier)
                            .requestPermissionAndLoad();
                      }
                    },
                    icon: Icon(
                      isPermanent
                          ? Icons.settings_outlined
                          : Icons.verified_user_outlined,
                    ),
                    label: Text(
                      isPermanent ? 'Abrir ajustes' : 'Conceder permiso',
                    ),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _manualMode = true),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: Text('Ingresar $singularLower manualmente'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (state.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(state.errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => ref
                    .read(contactsControllerProvider.notifier)
                    .loadContacts(),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_search_rounded,
                size: 44,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(
                'No se encontraron contactos con teléfono válido.',
                style: theme.textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _manualMode = true),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text('Crear $singularLower manual'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (BuildContext context, int index) {
        final contact = filtered[index];
        final initial = contact.displayName.isNotEmpty
            ? contact.displayName[0].toUpperCase()
            : '?';

        return Card(
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 6,
            ),
            leading: CircleAvatar(
              backgroundColor: contact.isGoogleAccount
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: contact.isGoogleAccount
                  ? colorScheme.onPrimaryContainer
                  : colorScheme.onSurfaceVariant,
              child: Text(initial, style: theme.textTheme.titleMedium),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    contact.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (contact.isGoogleAccount) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: PixelShapes.pillBorderRadius,
                    ),
                    child: Text(
                      'Google',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              PhoneSanitizer.formatForDisplay(contact.phoneE164),
              style: theme.textTheme.bodyMedium,
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop(contact);
            },
          ),
        );
      },
    );
  }
}
