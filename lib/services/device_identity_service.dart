import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

/// Identifiant d'appareil anonyme et stable (IMP-13).
///
/// Android : empreinte SHA-256 d'ANDROID_ID calculée côté natif, stable même
/// après réinstallation. Ailleurs (ou si le natif échoue) : UUID aléatoire
/// conservé dans Hive, stable tant que l'app n'est pas désinstallée.
/// Aucune donnée personnelle (IMEI, numéro, compte) n'est lue ni transmise.
class DeviceIdentityService {
  static const MethodChannel _channel = MethodChannel('com.yele/telephony');
  static String? _cached;

  Future<String> deviceId() async {
    if (_cached != null) return _cached!;
    String? id;
    try {
      id = await _channel.invokeMethod<String>('getDeviceUuid');
    } catch (_) {
      // Canal absent (iOS, tests).
    }
    if (id == null || id.isEmpty) {
      final box = Hive.isBoxOpen('settings') ? Hive.box('settings') : null;
      id = box?.get('deviceId') as String?;
      if (id == null) {
        id = const Uuid().v4();
        await box?.put('deviceId', id);
      }
    }
    return _cached = id;
  }
}
