import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:logger/logger.dart';

import '../constants/config.dart';
import '../models/speed_test_result.dart';
import '../models/test_selection.dart';
import 'account_service.dart';
import 'device_identity_service.dart';
import 'network_info_service.dart';
import 'speed_test_api_service.dart';

/// Mode Contrôle — campagne de drive test / walk test de l'autorité.
///
/// Une fois démarrée, la campagne enchaîne seule les cycles de mesure (débit,
/// latence, perte de paquets, radio, position) jusqu'à l'arrêt demandé par
/// l'agent, même écran éteint : le service Android `ControlService` garde le
/// processeur actif et autorise le GPS en arrière-plan.
///
/// Les mesures ne passent JAMAIS par l'envoi citoyen (/results/telemetry) :
/// elles partent vers /api/control/measurements, dans une collection séparée,
/// avec le compte de l'agent. Hors réseau, elles attendent dans une file
/// persistante et partent dès que possible, dans l'ordre.

/// État matériel du téléphone, remonté par `ControlService.health`.
class DeviceHealth {
  final int? batteryPercent;
  final double? batteryTempC;
  final bool charging;
  final bool ignoringBatteryOptimizations;

  const DeviceHealth({
    this.batteryPercent,
    this.batteryTempC,
    this.charging = false,
    this.ignoringBatteryOptimizations = false,
  });

  static const unknown = DeviceHealth();

  factory DeviceHealth.fromMap(Map<dynamic, dynamic> m) => DeviceHealth(
        batteryPercent: (m['batteryPercent'] as num?)?.toInt(),
        batteryTempC: (m['batteryTempC'] as num?)?.toDouble(),
        charging: m['charging'] == true,
        ignoringBatteryOptimizations: m['ignoringBatteryOptimizations'] == true,
      );
}

/// Pause avant le cycle suivant, et sa raison si elle diffère du rythme
/// normal.
class ControlPause {
  final Duration delay;
  final String? reason;
  const ControlPause(this.delay, [this.reason]);
}

/// Seuils de protection du téléphone (véhicule au soleil, batterie).
class ControlLimits {
  static const warmC = 42.0; // au-delà : cycles deux fois plus espacés
  static const hotC = 46.0; // au-delà : mesure suspendue 5 minutes
  static const lowBatteryPercent = 15; // hors charge : cycles espacés
  static const coolDown = Duration(minutes: 5);
}

/// Rythme des cycles : l'intervalle choisi, allongé quand le téléphone
/// chauffe ou que sa batterie faiblit hors charge. Fonction pure, testée.
ControlPause controlPause(Duration interval, DeviceHealth h) {
  final t = h.batteryTempC;
  if (t != null && t >= ControlLimits.hotC) {
    return ControlPause(ControlLimits.coolDown,
        'Téléphone trop chaud (${t.toStringAsFixed(0)} °C) : pause de refroidissement');
  }
  if (t != null && t >= ControlLimits.warmC) {
    return ControlPause(interval * 2,
        'Téléphone chaud (${t.toStringAsFixed(0)} °C) : cycles espacés');
  }
  final b = h.batteryPercent;
  if (!h.charging && b != null && b <= ControlLimits.lowBatteryPercent) {
    return ControlPause(
        interval * 2, 'Batterie faible ($b %) et hors charge : cycles espacés');
  }
  return ControlPause(interval);
}

/// Contenu d'une mesure de contrôle, envoyé tel quel au serveur (qui le
/// chaîne à la mesure précédente). Fonction pure, testée.
Map<String, dynamic> controlPayload({
  required String campaign,
  required String deviceId,
  required int seq,
  required DateTime measuredAt,
  required Position? gps,
  required NetworkStatus? network,
  required SpeedTestResult? result,
  required DeviceHealth health,
  required int cycleMs,
  String? error,
}) {
  final mobile = network?.usesMobile ?? false;
  return {
    'campaign': campaign,
    'deviceId': deviceId,
    'seq': seq,
    'measuredAt': measuredAt.toUtc().toIso8601String(),
    'latitude': gps?.latitude ?? 0,
    'longitude': gps?.longitude ?? 0,
    'gpsAccuracyM': gps?.accuracy,
    'speedKmh': gps == null || gps.speed < 0 ? null : gps.speed * 3.6,
    'gpsMocked': gps?.isMocked ?? false,
    'connection': network?.connectionType,
    'simOperator': mobile ? network?.simOperator : null,
    'cellularTech': mobile ? network?.cellularTech : null,
    'simSlot': mobile ? network?.simSlot : null,
    'signalDbm': mobile ? network?.signalDbm : null,
    'rsrp': mobile ? network?.rsrp : null,
    'rsrq': mobile ? network?.rsrq : null,
    'sinr': mobile ? network?.sinr : null,
    'operator': result?.operator,
    'download': result?.downloadSpeed,
    'downloadMin': result?.downloadMin,
    'downloadMax': result?.downloadMax,
    'upload': result?.uploadSpeed,
    'uploadMin': result?.uploadMin,
    'uploadMax': result?.uploadMax,
    'ping': result?.ping,
    'pingMin': result?.pingMin,
    'pingMax': result?.pingMax,
    'jitter': result?.jitter,
    'packetLoss': result?.packetLoss,
    'dataUsedKiB': result?.dataUsedKiB,
    'batteryPercent': health.batteryPercent,
    'batteryTempC': health.batteryTempC,
    'charging': health.charging,
    'cycleMs': cycleMs,
    // Un cycle en échec est une mesure : une connexion data impossible
    // compte dans le taux de réussite exigé par l'ARCEP.
    'error': error,
  };
}

/// Résultat de l'envoi d'une mesure.
enum ControlSendResult { sent, duplicate, retryLater, forbidden }

/// État affiché par l'écran du mode Contrôle.
class ControlState {
  final bool running;
  final String campaign;
  final int cycles; // cycles terminés depuis le démarrage (cette session)
  final int failed; // cycles en échec
  final int pending; // mesures en attente d'envoi
  final String status; // phase en cours
  final String? lastSummary;
  final String? warning;
  final DeviceHealth health;

  const ControlState({
    this.running = false,
    this.campaign = '',
    this.cycles = 0,
    this.failed = 0,
    this.pending = 0,
    this.status = 'À l\'arrêt',
    this.lastSummary,
    this.warning,
    this.health = DeviceHealth.unknown,
  });

  ControlState copyWith({
    bool? running,
    String? campaign,
    int? cycles,
    int? failed,
    int? pending,
    String? status,
    String? lastSummary,
    String? warning,
    bool clearWarning = false,
    DeviceHealth? health,
  }) =>
      ControlState(
        running: running ?? this.running,
        campaign: campaign ?? this.campaign,
        cycles: cycles ?? this.cycles,
        failed: failed ?? this.failed,
        pending: pending ?? this.pending,
        status: status ?? this.status,
        lastSummary: lastSummary ?? this.lastSummary,
        warning: clearWarning ? null : (warning ?? this.warning),
        health: health ?? this.health,
      );
}

/// File persistante des mesures à envoyer, et numéro du dernier cycle.
class ControlStore {
  static const boxName = 'control';
  Box? _box;

  Future<void> open() async {
    if (!(_box?.isOpen ?? false)) _box = await Hive.openBox(boxName);
  }

  bool get active => _box?.get('active') == true;
  String get campaign => (_box?.get('campaign') as String?) ?? '';
  int get intervalSeconds => (_box?.get('intervalSeconds') as int?) ?? 180;

  Future<void> setActive(bool active, {String? campaign, int? intervalSeconds}) async {
    await _box?.put('active', active);
    if (campaign != null) await _box?.put('campaign', campaign);
    if (intervalSeconds != null) {
      await _box?.put('intervalSeconds', intervalSeconds);
    }
  }

  /// Numéro de cycle suivant pour une campagne. Il ne revient jamais en
  /// arrière : le serveur refuse un numéro déjà reçu.
  Future<int> nextSeq(String campaign) async {
    final key = 'seq:$campaign';
    final next = ((_box?.get(key) as int?) ?? 0) + 1;
    await _box?.put(key, next);
    return next;
  }

  List<String> get pending =>
      List<String>.from((_box?.get('pending') as List?) ?? const []);

  Future<void> enqueue(String json) async =>
      _box?.put('pending', [...pending, json]);

  Future<void> dropFirst() async {
    final p = pending;
    if (p.isNotEmpty) await _box?.put('pending', p.sublist(1));
  }

  Future<void> close() async {
    await _box?.close();
    _box = null;
  }
}

/// Accès serveur du mode Contrôle.
class ControlApi {
  final Dio _dio;

  ControlApi([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: API_BASE_URL,
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(seconds: 60),
            ));

  /// Le compte connecté est-il un agent habilité ? null si le serveur est
  /// injoignable.
  Future<bool?> isAgent() async {
    if (AccountService.token == null) return false;
    try {
      final res = await _dio.get('/api/control/me',
          options: Options(headers: AccountService.authHeaders));
      return (res.data as Map)['agent'] == true;
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      return code == 401 || code == 403 ? false : null;
    }
  }

  Future<ControlSendResult> send(String json) async {
    try {
      await _dio.post('/api/control/measurements',
          data: json,
          options: Options(
            headers: AccountService.authHeaders,
            contentType: Headers.jsonContentType,
          ));
      return ControlSendResult.sent;
    } on DioException catch (e) {
      return sendResultFor(e.response?.statusCode);
    }
  }

  /// Traduit un code HTTP d'échec. 409 : déjà reçue, à retirer de la file.
  /// 400 : mesure refusée, gardée nulle part (elle bloquerait la file).
  static ControlSendResult sendResultFor(int? status) {
    switch (status) {
      case 409:
      case 400:
        return ControlSendResult.duplicate;
      case 401:
      case 403:
        return ControlSendResult.forbidden;
    }
    return ControlSendResult.retryLater;
  }
}

class ControlSession {
  ControlSession._();
  static final ControlSession instance = ControlSession._();

  static const MethodChannel _channel = MethodChannel('com.yele/telephony');
  final logger = Logger();

  final ValueNotifier<ControlState> state = ValueNotifier(const ControlState());
  final ControlStore store = ControlStore();
  final ControlApi api = ControlApi();

  bool _stopRequested = false;
  Completer<void>? _wake;

  bool get running => state.value.running;

  /// À l'ouverture de l'app : reprend une campagne restée active (arrêt du
  /// téléphone, app tuée par le système).
  Future<bool> resumeIfActive() async {
    await store.open();
    if (!store.active || running) return false;
    await start(store.campaign,
        interval: Duration(seconds: store.intervalSeconds), resumed: true);
    return true;
  }

  Future<void> start(String campaign,
      {Duration interval = const Duration(minutes: 3),
      bool resumed = false}) async {
    if (running) return;
    await store.open();
    await store.setActive(true,
        campaign: campaign, intervalSeconds: interval.inSeconds);
    _stopRequested = false;
    state.value = ControlState(
      running: true,
      campaign: campaign,
      pending: store.pending.length,
      status: resumed ? 'Reprise de la campagne' : 'Démarrage',
    );
    await _native('startControl', {'campaign': campaign});
    unawaited(_loop(campaign, interval));
  }

  Future<void> stop() async {
    _stopRequested = true;
    _wake?.complete();
    await store.setActive(false);
    await _native('stopControl');
    state.value = state.value.copyWith(running: false, status: 'Arrêtée');
  }

  Future<DeviceHealth> health() async {
    try {
      final m = await _channel.invokeMethod<Map>('getDeviceHealth');
      return m == null ? DeviceHealth.unknown : DeviceHealth.fromMap(m);
    } catch (_) {
      return DeviceHealth.unknown;
    }
  }

  Future<void> requestBatteryExemption() =>
      _native('requestIgnoreBatteryOptimizations');

  Future<void> setKeepScreenOn(bool on) => _native('setKeepScreenOn', {'on': on});

  Future<void> _native(String method, [Map<String, dynamic>? args]) async {
    try {
      await _channel.invokeMethod(method, args);
    } catch (e) {
      logger.w('Mode Contrôle : $method indisponible ($e)');
    }
  }

  void _set(ControlState s) {
    if (_stopRequested) return;
    state.value = s;
  }

  Future<void> _loop(String campaign, Duration interval) async {
    final deviceId = await DeviceIdentityService().deviceId();
    while (!_stopRequested) {
      final started = DateTime.now();
      final health = await this.health();
      _set(state.value.copyWith(status: 'Mesure en cours', health: health));
      await _native('updateControl', {
        'text': 'Cycle ${state.value.cycles + 1} en cours · '
            '${state.value.pending} en attente d\'envoi',
      });

      final payload = await _measureOnce(campaign, deviceId, health, started);
      if (_stopRequested) break;
      await store.enqueue(jsonEncode(payload));
      final ok = payload['error'] == null;
      final summary = ok
          ? '▼ ${(payload['download'] as double).toStringAsFixed(1)} Mb/s · '
              '▲ ${(payload['upload'] as double).toStringAsFixed(1)} Mb/s · '
              '${(payload['ping'] as double).toStringAsFixed(0)} ms'
          : 'Échec : ${payload['error']}';
      await _flush();

      final pause = controlPause(interval, health);
      _set(state.value.copyWith(
        cycles: state.value.cycles + 1,
        failed: state.value.failed + (ok ? 0 : 1),
        pending: store.pending.length,
        lastSummary: summary,
        warning: pause.reason,
        clearWarning: pause.reason == null,
        status: 'Prochain cycle dans ${pause.delay.inSeconds} s',
      ));
      await _native('updateControl', {
        'text': '${state.value.cycles} cycles · dernier : $summary'
            '${pause.reason != null ? '\n${pause.reason}' : ''}',
      });

      // Attente interruptible : « Arrêter » ne patiente pas la fin du délai.
      final remaining = pause.delay - DateTime.now().difference(started);
      if (remaining > Duration.zero && !_stopRequested) {
        _wake = Completer<void>();
        await Future.any([Future.delayed(remaining), _wake!.future]);
        _wake = null;
      }
    }
  }

  /// Un cycle complet. Une erreur ne casse jamais la boucle : elle devient
  /// une mesure en échec.
  Future<Map<String, dynamic>> _measureOnce(String campaign, String deviceId,
      DeviceHealth health, DateTime started) async {
    Position? gps;
    NetworkStatus? network;
    SpeedTestResult? result;
    String? error;
    try {
      _set(state.value.copyWith(status: 'Position GPS'));
      gps = await _position();
      network = await NetworkInfoService().getStatus();
      _set(state.value.copyWith(status: 'Débit, latence, perte de paquets'));
      result = await SpeedTestApiService().runSpeedTest(
        latitude: gps?.latitude,
        longitude: gps?.longitude,
        locationSource: gps == null ? null : (gps.isMocked ? 'gps_mocked' : 'gps'),
        networkType: network.networkBadge,
        simOperator: network.usesMobile ? network.simOperator : null,
        cellularTech: network.usesMobile ? network.cellularTech : null,
        simSlot: network.usesMobile ? network.simSlot : null,
        signalDbm: network.usesMobile ? network.signalDbm : null,
        rsrp: network.usesMobile ? network.rsrp : null,
        rsrq: network.usesMobile ? network.rsrq : null,
        sinr: network.usesMobile ? network.sinr : null,
        selection: const TestSelection(speed: true),
        // Jamais d'envoi citoyen : la mesure part vers l'espace Contrôle.
        autoUpload: false,
      );
      if (result.downloadSpeed <= 0 && result.uploadSpeed <= 0) {
        error = 'aucun débit mesuré';
      }
      if (gps == null) error ??= 'position GPS indisponible';
    } catch (e) {
      error = 'test impossible (${e.runtimeType})';
      logger.w('Mode Contrôle : cycle en échec ($e)');
    }
    return controlPayload(
      campaign: campaign,
      deviceId: deviceId,
      seq: await store.nextSeq(campaign),
      measuredAt: started,
      gps: gps,
      network: network,
      result: result,
      health: health,
      cycleMs: DateTime.now().difference(started).inMilliseconds,
      error: error,
    );
  }

  Future<Position?> _position() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // Pas de correctif à temps (tunnel, parking) : dernière position connue.
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  /// Envoie les mesures en attente, dans l'ordre, jusqu'au premier échec.
  Future<void> _flush() async {
    for (var json = _first(); json != null; json = _first()) {
      _set(state.value.copyWith(status: 'Envoi des mesures'));
      final r = await api.send(json);
      if (r == ControlSendResult.retryLater) return;
      if (r == ControlSendResult.forbidden) {
        _set(state.value.copyWith(
            warning: 'Compte non habilité : mesures gardées sur le téléphone'));
        return;
      }
      await store.dropFirst();
    }
  }

  String? _first() {
    final p = store.pending;
    return p.isEmpty ? null : p.first;
  }
}
