import 'package:flutter/services.dart';

/// Compteur d'octets reçus par l'application, lu via `TrafficStats` (Android).
///
/// Sert à mesurer la consommation de données d'un test de streaming : on relève
/// le compteur avant et après la lecture, la différence est le volume réellement
/// téléchargé. Le trafic du WebView est inclus : sur Android, la pile réseau de
/// Chromium tourne dans le processus de l'application, donc sous le même UID.
///
/// iOS n'expose aucun équivalent propre : [rxBytes] y retourne null et la
/// colonne « données consommées » affiche « — ».
class TrafficStatsService {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');

  /// Octets reçus par l'application depuis le démarrage de l'appareil.
  /// null si la plateforme ne sait pas le fournir.
  Future<int?> rxBytes() async {
    try {
      final value = await _channel.invokeMethod<int>('getRxBytes');
      if (value == null || value < 0) return null;
      return value;
    } catch (_) {
      // Canal absent (iOS, tests) ou compteur indisponible.
      return null;
    }
  }

  /// Octets reçus + émis par l'application (IMP-01). null si indisponible.
  Future<int?> totalBytes() async {
    final rx = await rxBytes();
    if (rx == null) return null;
    try {
      final tx = await _channel.invokeMethod<int>('getTxBytes');
      if (tx == null || tx < 0) return rx;
      return rx + tx;
    } catch (_) {
      return rx;
    }
  }

  /// Volume reçu entre deux relevés, en kibioctets. -1 si non mesurable.
  static int kibBetween(int? before, int? after) {
    if (before == null || after == null || after < before) return -1;
    return ((after - before) / 1024).round();
  }
}
