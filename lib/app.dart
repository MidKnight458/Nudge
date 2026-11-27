import 'package:dynamic_color/dynamic_color.dart';
import 'package:material_ui/material_ui.dart';
import 'package:nudge/core/constants/app_constants.dart';
import 'package:nudge/core/theme/app_theme.dart';
import 'package:nudge/features/appointments/presentation/screens/agenda_screen.dart';

/// Root application widget with Monet dynamic color theming.
class NudgeApp extends StatelessWidget {
  const NudgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.system,
          theme: AppTheme.buildTheme(
            brightness: Brightness.light,
            dynamicScheme: lightDynamic,
          ),
          darkTheme: AppTheme.buildTheme(
            brightness: Brightness.dark,
            dynamicScheme: darkDynamic,
          ),
          home: const AgendaScreen(),
        );
      },
    );
  }
}
