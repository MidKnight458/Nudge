import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/features/appointments/presentation/screens/agenda_screen.dart';
import 'package:nudge/features/clients/presentation/screens/clients_screen.dart';
import 'package:nudge/features/settings/data/settings_repository.dart';
import 'package:nudge/features/settings/presentation/screens/settings_screen.dart';

/// Top-level Pixel Material 3 navigation shell connecting Agenda, Clients,
/// and Settings.
class HomeShellScreen extends ConsumerStatefulWidget {
  const HomeShellScreen({super.key});

  @override
  ConsumerState<HomeShellScreen> createState() => _HomeShellScreenState();
}

class _HomeShellScreenState extends ConsumerState<HomeShellScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(appPreferencesProvider).valueOrNull;
    final clientsLabel =
        prefs?.clientLabelPlural ?? AppConstants.defaultClientLabelPlural;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          AgendaScreen(),
          ClientsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          if (index == _selectedIndex) {
            return;
          }
          HapticFeedback.lightImpact();
          setState(() => _selectedIndex = index);
        },
        destinations: <NavigationDestination>[
          const NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline_rounded),
            selectedIcon: const Icon(Icons.people_rounded),
            label: clientsLabel,
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune_rounded),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }
}
