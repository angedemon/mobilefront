import 'package:flutter/services.dart';

import '../models/speed_test_result.dart';
import 'app_settings.dart';
import 'local_storage_service.dart';

/// Autorisations Android et leur état (IMP-04).
class PermissionInfo {
  final String key;
  final String label;
  final String purpose;
  final bool granted;
  final bool required;

  const PermissionInfo(this.key, this.label, this.purpose, this.granted,
      {this.required = false});
}

/// Outils système : autorisations (IMP-04), moniteur de débit et alerte de
/// consommation (IMP-08). Passe par le canal natif de MainActivity.
class DeviceToolsService {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  Future<List<PermissionInfo>> permissions() async {
    Map<String, dynamic> s = {};
    try {
      s = await _channel.invokeMapMethod<String, dynamic>('getPermissions') ?? {};
    } catch (_) {
      // Canal absent (iOS, tests) : tout est présenté comme non accordé.
    }
    bool g(String k) => s[k] == true;
    return [
      PermissionInfo('location', 'Localisation',
          'Placer chaque mesure sur la carte. Obligatoire pour lancer un test.',
          g('location'),
          required: true),
      PermissionInfo('preciseLocation', 'Localisation précise',
          'Position GPS au mètre près plutôt qu\'approximative.',
          g('preciseLocation')),
      PermissionInfo('phone', 'Téléphone (état du réseau)',
          'Lire l\'opérateur, la SIM de données, la 4G/5G et la qualité du signal.',
          g('phone')),
      PermissionInfo('notifications', 'Notifications',
          'Collecte en arrière-plan, débit en temps réel, alertes de consommation.',
          g('notifications')),
    ];
  }

  Future<void> request(String key) async {
    try {
      await _channel.invokeMethod('requestPermission', {'name': key});
    } catch (_) {}
  }

  Future<void> openAppSettings() async {
    try {
      await _channel.invokeMethod('openAppSettings');
    } catch (_) {}
  }

  // ── Moniteur de débit (IMP-08) ─────────────────────────────────────────

  /// false si l'autorisation de notification vient d'être demandée.
  Future<bool> startMonitor() async {
    try {
      return await _channel.invokeMethod<bool>('startMonitor') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopMonitor() async {
    try {
      await _channel.invokeMethod('stopMonitor');
    } catch (_) {}
  }

  Future<bool> isMonitorRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isMonitorRunning') ?? false;
    } catch (_) {
      return false;
    }
  }

  // ── Consommation cumulée et seuil mensuel (IMP-08) ─────────────────────

  /// Données consommées par les tests Yélé du mois en cours, en Kio.
  static int monthUsageKiB([List<SpeedTestResult>? results]) {
    final now = DateTime.now();
    final all = results ?? LocalStorageService().getAllResults();
    return all
        .where((r) =>
            r.timestamp.year == now.year && r.timestamp.month == now.month)
        .fold<int>(0, (s, r) => s + ((r.dataUsedKiB ?? 0) > 0 ? r.dataUsedKiB! : 0));
  }

  /// « 1,25 Go » / « 340 Mo ».
  static String formatKiB(int kib) {
    if (kib >= 1024 * 1024) return '${(kib / 1048576).toStringAsFixed(2)} Go';
    if (kib >= 1024) return '${(kib / 1024).toStringAsFixed(0)} Mo';
    return '$kib Ko';
  }

  /// Après un test : si la consommation du mois vient de franchir le seuil
  /// configuré, renvoie le message d'alerte (et envoie une notification),
  /// sinon null. Une seule alerte par mois.
  Future<String?> checkMonthlyLimit() async {
    final limitMb = AppSettings.monthlyLimitMb;
    if (limitMb <= 0) return null;
    final usedKiB = monthUsageKiB();
    if (usedKiB < limitMb * 1024) return null;

    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month}';
    if (AppSettings.lastDataAlertMonth == monthKey) return null;
    await AppSettings.setLastDataAlertMonth(monthKey);

    final msg = 'Les tests Yélé ont consommé ${formatKiB(usedKiB)} ce mois-ci, '
        'au-delà de votre seuil de ${formatKiB(limitMb * 1024)}.';
    try {
      await _channel.invokeMethod('notifyDataAlert', {
        'title': 'Seuil de consommation dépassé',
        'text': msg,
      });
    } catch (_) {}
    return msg;
  }
}
