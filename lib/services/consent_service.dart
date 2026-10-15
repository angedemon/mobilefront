import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

/// Consentement à la collecte des données, recueilli au premier lancement.
///
/// Chaque test envoie au serveur la position GPS, l'adresse IP et le modèle
/// de l'appareil : Google Play exige une divulgation explicite et un accord
/// avant toute collecte de ce type. Tant que [hasConsented] est faux, l'app
/// n'affiche que l'écran de consentement.
class ConsentService {
  final logger = Logger();

  /// Version de la politique de confidentialité. L'incrémenter quand les
  /// données collectées changent : l'accord est alors redemandé à tous.
  static const int policyVersion = 1;

  static const String _boxName = 'settings';
  static const String _versionKey = 'consentPolicyVersion';
  static const String _dateKey = 'consentAcceptedAt';

  static Box? _box;

  Future<void> initialize() async {
    if (_box?.isOpen ?? false) return;
    await Hive.initFlutter();
    _box = await Hive.openBox(_boxName);
  }

  /// Vrai si l'utilisateur a accepté la version actuelle de la politique.
  /// Faux si le stockage est illisible : mieux vaut redemander l'accord que
  /// collecter sans.
  bool get hasConsented {
    try {
      return (_box?.get(_versionKey) as int? ?? 0) >= policyVersion;
    } catch (e) {
      logger.e('Lecture du consentement impossible: $e');
      return false;
    }
  }

  DateTime? get acceptedAt {
    final ms = _box?.get(_dateKey) as int?;
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> accept() async {
    await _box?.put(_versionKey, policyVersion);
    await _box?.put(_dateKey, DateTime.now().millisecondsSinceEpoch);
    logger.i('Consentement accepté (politique v$policyVersion)');
  }

  Future<void> withdraw() async {
    await _box?.delete(_versionKey);
    await _box?.delete(_dateKey);
    logger.i('Consentement retiré');
  }
}
