import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/app_settings.dart';
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
    // Se reconstruit à chaque changement de réglage (langue notamment).
    return ValueListenableBuilder<int>(
      valueListenable: AppSettings.revision,
      builder: (context, _, __) => _app(),
    );
  }

  Widget _app() {
    return MaterialApp(
      title: 'Yélé',
      debugShowCheckedModeBanner: false,
      theme: buildYeleTheme(),
      // ISS-12 : langue choisie dans les réglages.
      locale: AppSettings.language == 'system'
          ? null
          : Locale(AppSettings.language),
      supportedLocales: const [Locale('fr'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // ISS-12 : test ouvert au démarrage, choisi dans les réglages.
      initialRoute: hasConsented ? AppSettings.defaultTest : '/consent',
      routes: {
        '/consent': (_) => const ConsentScreen(),
        '/privacy': (_) => const PrivacyPolicyScreen(),
        '/full': (_) => FullTestScreen(
              selection: const TestSelection.all(),
              title: tr('Test complet', 'Full test'),
              route: '/full',
              launchLabel: tr('LANCER LE\nTEST COMPLET', 'START\nFULL TEST'),
            ),
        '/speed': (_) => FullTestScreen(
              selection: const TestSelection(speed: true),
              title: 'Speed test',
              route: '/speed',
              launchLabel: tr('LANCER LE\nSPEEDTEST', 'START\nSPEED TEST'),
            ),
        '/browsing': (_) => FullTestScreen(
              selection: const TestSelection(speed: false, browsing: true),
              title: tr('Test de navigation', 'Browsing test'),
              route: '/browsing',
              launchLabel: tr('LANCER LE\nTEST NAVIGATION', 'START\nBROWSING TEST'),
            ),
        '/streaming': (_) => FullTestScreen(
              selection: const TestSelection(speed: false, streaming: true),
              title: tr('Test de streaming', 'Streaming test'),
              route: '/streaming',
              launchLabel: tr('LANCER LE\nTEST STREAMING', 'START\nSTREAMING TEST'),
            ),
        '/history': (_) => const HistoryScreen(),
        '/coverage': (_) => const CoverageScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
