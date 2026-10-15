import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Réglages de l'utilisateur (ISS-12), enregistrés dans la boîte Hive
/// `settings` — ouverte au démarrage par ConsentService.initialize.
///
/// Chaque réglage est lu à la construction des écrans ; [revision] change à
/// chaque modification pour que l'application (langue) se reconstruise.
class AppSettings {
  AppSettings._();

  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Box? get _box =>
      Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  static T _get<T>(String key, T fallback) {
    try {
      final v = _box?.get(key);
      return v is T ? v : fallback;
    } catch (_) {
      return fallback;
    }
  }

  static Future<void> _set(String key, Object value) async {
    await _box?.put(key, value);
    revision.value++;
  }

  // ── Langue ────────────────────────────────────────────────────────────────

  /// 'system' (langue du téléphone), 'fr' ou 'en'. Français par défaut :
  /// l'application est d'abord destinée au Burkina Faso.
  static String get language => _get('language', 'fr');
  static Future<void> setLanguage(String v) => _set('language', v);

  /// Langue effective : celle du téléphone si 'system' (français par défaut
  /// si le téléphone n'est ni en français ni en anglais).
  static bool get isEnglish {
    final lang = language;
    if (lang == 'en') return true;
    if (lang == 'fr') return false;
    return PlatformDispatcher.instance.locale.languageCode == 'en';
  }

  // ── Test lancé au démarrage ───────────────────────────────────────────────

  static const testRoutes = ['/full', '/speed', '/browsing', '/streaming'];

  static String get defaultTest {
    final v = _get('defaultTest', '/full');
    return testRoutes.contains(v) ? v : '/full';
  }

  static Future<void> setDefaultTest(String v) => _set('defaultTest', v);

  // ── Unité de débit ────────────────────────────────────────────────────────

  /// 'mbps' (Mb/s), 'kbps' (kb/s) ou 'MBps' (Mo/s).
  static String get speedUnit => _get('speedUnit', 'mbps');
  static Future<void> setSpeedUnit(String v) => _set('speedUnit', v);

  static String get speedUnitLabel => switch (speedUnit) {
        'kbps' => 'kb/s',
        'MBps' => 'Mo/s',
        _ => 'Mb/s',
      };

  /// Convertit un débit mesuré en Mb/s dans l'unité choisie.
  static double convertSpeed(double mbps) => switch (speedUnit) {
        'kbps' => mbps * 1000,
        'MBps' => mbps / 8,
        _ => mbps,
      };

  /// « 12.34 Mb/s » dans l'unité choisie.
  static String formatSpeed(double mbps, {int decimals = 2}) {
    final v = convertSpeed(mbps);
    final d = speedUnit == 'kbps' ? 0 : decimals;
    return '${v.toStringAsFixed(d)} $speedUnitLabel';
  }

  /// Valeur seule, sans unité, dans l'unité choisie.
  static String speedValue(double mbps, {int decimals = 2}) =>
      convertSpeed(mbps).toStringAsFixed(speedUnit == 'kbps' ? 0 : decimals);

  // ── Style de fond ─────────────────────────────────────────────────────────

  /// 'vert', 'bleu' ou 'sombre'.
  static String get backgroundStyle => _get('backgroundStyle', 'vert');
  static Future<void> setBackgroundStyle(String v) =>
      _set('backgroundStyle', v);

  // ── Paramètres techniques (IMP-02) ────────────────────────────────────────

  /// Durée de chaque phase de débit (download, upload), en secondes.
  static int get testDurationSec {
    final v = _get('testDurationSec', 10);
    return const [5, 10, 15].contains(v) ? v : 10;
  }

  static Future<void> setTestDurationSec(int v) => _set('testDurationSec', v);

  /// Tester la 4K (2160p) en streaming : la qualité la plus gourmande
  /// (~15 Mo pour 10 s). Désactivable pour économiser le forfait.
  static bool get streaming4k => _get('streaming4k', true);
  static Future<void> setStreaming4k(bool v) => _set('streaming4k', v);

  // ── Consommation (IMP-08) ─────────────────────────────────────────────────

  /// Seuil mensuel d'alerte en Mo ; 0 = pas d'alerte.
  static int get monthlyLimitMb => _get('monthlyLimitMb', 0);
  static Future<void> setMonthlyLimitMb(int v) => _set('monthlyLimitMb', v);

  /// Mois (« 2026-10 ») de la dernière alerte, pour n'alerter qu'une fois.
  static String get lastDataAlertMonth => _get('lastDataAlertMonth', '');
  static Future<void> setLastDataAlertMonth(String v) =>
      _set('lastDataAlertMonth', v);
}

/// Texte dans la langue choisie : français par défaut, anglais si demandé.
String tr(String fr, String en) => AppSettings.isEnglish ? en : fr;
