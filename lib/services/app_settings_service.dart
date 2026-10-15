import 'package:hive_flutter/hive_flutter.dart';

/// Réglages de l'utilisateur, dans la même boîte Hive `settings` que le
/// consentement (ouverte par ConsentService.initialize au démarrage).
class AppSettingsService {
  static const String _useGpsKey = 'useGps';

  Box? get _box => Hive.isBoxOpen('settings') ? Hive.box('settings') : null;

  /// Géolocaliser les tests par GPS. Si faux, seule la position approximative
  /// de l'adresse IP (niveau ville) accompagne les mesures. Activé par défaut.
  bool get useGps => _box?.get(_useGpsKey, defaultValue: true) as bool? ?? true;

  Future<void> setUseGps(bool value) async => _box?.put(_useGpsKey, value);
}
