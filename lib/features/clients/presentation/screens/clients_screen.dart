import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/pixel_shapes.dart';
import 'package:nudge/core/utils/phone_sanitizer.dart';
import 'package:nudge/features/clients/data/clients_repository.dart';
import 'package:nudge/features/clients/domain/entities/client_entity.dart';
import 'package:nudge/features/clients/presentation/screens/client_detail_screen.dart';
import 'package:nudge/features/contacts/presentation/widgets/contact_picker_sheet.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';

/// Directory of clients/patients with general notes, files, and appointment history.
class ClientsScreen extends ConsumerStatefulWidget {
  const ClientsScreen({super.key});

  @override
  ConsumerState<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends ConsumerState<ClientsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _addClientFromPicker() async {
    HapticFeedback.lightImpact();
    final contact = await ContactPickerSheet.show(context);
    if (contact == null || !mounted) {
      return;
    }
    final saved = await ref
        .read(clientsRepositoryProvider)
        .createOrUpdateClient(
          name: contact.displayName,
          rawPhone: contact.rawPhone,
          phoneE164: contact.phoneE164,
          googleContactId: contact.id,
        );
    if (!mounted) {
      return;
    }
    await ClientDetailScreen.push(context, saved.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final prefs = ref.watch(appPreferencesProvider).valueOrNull;
    final pluralLabel =
        prefs?.clientLabelPlural ?? AppConstants.defaultClientLabelPlural;
    final singularLabel =
        prefs?.clientLabelSingular ?? AppConstants.defaultClientLabelSingular;
    final clientsAsync = ref.watch(clientsListProvider);

    return Scaffold(
      appBar: AppBar(title: Text(pluralLabel)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (String value) {
                setState(() => _searchQuery = value.trim().toLowerCase());
              },
              decoration: InputDecoration(
                hintText: 'Buscar ${pluralLabel.toLowerCase()}...',
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
          Expanded(
            child: clientsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Center(
                child: Text(
                  'No se pudo cargar el listado de ${pluralLabel.toLowerCase()}.',
                ),
              ),
              data: (List<ClientEntity> allClients) {
                final filtered = _searchQuery.isEmpty
                    ? allClients
                    : allClients
                          .where((ClientEntity client) {
                            final digitsQuery = _searchQuery.replaceAll(
                              RegExp(r'[^0-9]'),
                              '',
                            );
                            return client.name.toLowerCase().contains(
                                  _searchQuery,
                                ) ||
                                client.rawPhone.toLowerCase().contains(
                                  _searchQuery,
                                ) ||
                                (digitsQuery.isNotEmpty &&
                                    client.phoneE164.contains(digitsQuery));
                          })
                          .toList(growable: false);

                if (filtered.isEmpty) {
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
                            child: const Icon(
                              Icons.people_outline_rounded,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            allClients.isEmpty
                                ? 'Sin ${pluralLabel.toLowerCase()} registrados'
                                : 'Sin resultados para "$_searchQuery"',
                            style: theme.textTheme.titleMedium,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Agrega un ${singularLabel.toLowerCase()} para guardar sus notas generales y archivos adjuntos.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (allClients.isEmpty) ...[
                            const SizedBox(height: 16),
                            FilledButton.tonalIcon(
                              onPressed: _addClientFromPicker,
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: Text(
                                'Nuevo ${singularLabel.toLowerCase()}',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (BuildContext context, int index) {
                    final client = filtered[index];
                    final initial = client.name.isNotEmpty
                        ? client.name[0].toUpperCase()
                        : '?';
                    final hasNotes =
                        client.generalNotes != null &&
                        client.generalNotes!.isNotEmpty;

                    return Card(
                      child: InkWell(
                        borderRadius: PixelShapes.cardBorderRadius,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ClientDetailScreen.push(context, client.id);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: colorScheme.primaryContainer,
                                foregroundColor: colorScheme.onPrimaryContainer,
                                child: Text(
                                  initial,
                                  style: theme.textTheme.titleMedium,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      client.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      client.hasValidWhatsAppPhone
                                          ? PhoneSanitizer.formatForDisplay(
                                              client.phoneE164,
                                            )
                                          : 'Sin teléfono',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    if (hasNotes) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        client.generalNotes!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 4,
                                      children: [
                                        _StatPill(
                                          icon: Icons.event_outlined,
                                          label:
                                              '${client.appointmentCount} citas',
                                        ),
                                        _StatPill(
                                          icon: Icons.attach_file_rounded,
                                          label:
                                              '${client.attachmentCount} archivos',
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addClientFromPicker,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('Nuevo ${singularLabel.toLowerCase()}'),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: PixelShapes.pillBorderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
