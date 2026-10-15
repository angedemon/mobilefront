import 'package:flutter/material.dart';

import 'models/test_selection.dart';
import 'screens/consent_screen.dart';
import 'screens/coverage_screen.dart';
import 'screens/full_test_screen.dart';
import 'screens/history_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/settings_screen.dart';
import 'services/background_collection_service.dart';
import 'services/consent_service.dart';
import 'services/local_storage_service.dart';
import 'theme/yele_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await LocalStorageService().initialize();
  } catch (_) {
    // Le stockage local n'est pas bloquant pour lancer un test.
  }
  try {
    await ConsentService().initialize();
  } catch (_) {
    // Illisible : hasConsented vaudra faux et l'accord sera redemandé.
  }
  final hasConsented = ConsentService().hasConsented;
  if (!hasConsented) {
    // Une collecte activée sous une ancienne version de la politique ne doit
    // pas continuer tant que la nouvelle n'est pas acceptée.
    await BackgroundCollectionService().stop();
  }
  runApp(YeleApp(hasConsented: hasConsented));
}

class YeleApp extends StatelessWidget {
  final bool hasConsented;
  const YeleApp({super.key, this.hasConsented = true});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yélé',
      debugShowCheckedModeBanner: false,
      theme: buildYeleTheme(),
      initialRoute: hasConsented ? '/full' : '/consent',
      routes: {
        '/consent': (_) => const ConsentScreen(),
        '/privacy': (_) => const PrivacyPolicyScreen(),
        '/full': (_) => const FullTestScreen(
              selection: TestSelection.all(),
              title: 'Test complet',
              route: '/full',
              launchLabel: 'LANCER LE\nTEST COMPLET',
            ),
        '/speed': (_) => const FullTestScreen(
              selection: TestSelection(speed: true),
              title: 'Speed test',
              route: '/speed',
              launchLabel: 'LANCER LE\nSPEEDTEST',
            ),
        '/browsing': (_) => const FullTestScreen(
              selection: TestSelection(speed: false, browsing: true),
              title: 'Test de navigation',
              route: '/browsing',
              launchLabel: 'LANCER LE\nTEST NAVIGATION',
            ),
        '/streaming': (_) => const FullTestScreen(
              selection: TestSelection(speed: false, streaming: true),
              title: 'Test de streaming',
              route: '/streaming',
              launchLabel: 'LANCER LE\nTEST STREAMING',
            ),
        '/history': (_) => const HistoryScreen(),
        '/coverage': (_) => const CoverageScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
