import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:yele/models/speed_test_result.dart';
import 'package:yele/screens/control_screen.dart';
import 'package:yele/services/control_session.dart';
import 'package:yele/services/network_info_service.dart';

/// Mode Contrôle : rythme des cycles, contenu des mesures, file d'envoi.
void main() {
  const interval = Duration(minutes: 3);

  group('controlPause (protection du téléphone)', () {
    test('conditions normales : intervalle choisi', () {
      final p = controlPause(interval,
          const DeviceHealth(batteryPercent: 80, batteryTempC: 35, charging: true));
      expect(p.delay, interval);
      expect(p.reason, isNull);
    });

    test('téléphone chaud : cycles deux fois plus espacés', () {
      final p = controlPause(interval, const DeviceHealth(batteryTempC: 43));
      expect(p.delay, interval * 2);
      expect(p.reason, contains('chaud'));
    });

    test('téléphone trop chaud : pause de refroidissement', () {
      final p = controlPause(interval, const DeviceHealth(batteryTempC: 47.5));
      expect(p.delay, ControlLimits.coolDown);
      expect(p.reason, contains('trop chaud'));
    });

    test('batterie faible hors charge : cycles espacés ; en charge : normal', () {
      expect(
          controlPause(interval,
                  const DeviceHealth(batteryPercent: 12, charging: false))
              .delay,
          interval * 2);
      expect(
          controlPause(interval,
                  const DeviceHealth(batteryPercent: 12, charging: true))
              .delay,
          interval);
    });

    test('état inconnu : intervalle choisi', () {
      expect(controlPause(interval, DeviceHealth.unknown).delay, interval);
    });
  });

  group('controlPayload (contenu d\'une mesure)', () {
    final gps = Position(
      latitude: 12.3714,
      longitude: -1.5197,
      timestamp: DateTime.utc(2026, 11, 3, 9, 15),
      accuracy: 6,
      altitude: 300,
      altitudeAccuracy: 3,
      heading: 90,
      headingAccuracy: 5,
      speed: 10, // m/s
      speedAccuracy: 1,
    );
    final result = SpeedTestResult(
      downloadSpeed: 18.4,
      uploadSpeed: 6.1,
      ping: 52,
      jitter: 7,
      server: 's',
      operator: 'Orange Burkina Faso',
    );
    const health = DeviceHealth(batteryPercent: 76, batteryTempC: 39, charging: true);

    test('données mobiles : radio et SIM incluses', () {
      final p = controlPayload(
        campaign: 'OUAGA-2026-11',
        deviceId: 'dev-1',
        seq: 4,
        measuredAt: DateTime.utc(2026, 11, 3, 9, 15),
        gps: gps,
        network: const NetworkStatus(
            connectionType: 'Mobile',
            cellularTech: '4G',
            simOperator: 'Orange BF',
            rsrp: -95),
        result: result,
        health: health,
        cycleMs: 61000,
      );
      expect(p['campaign'], 'OUAGA-2026-11');
      expect(p['seq'], 4);
      expect(p['measuredAt'], startsWith('2026-11-03T09:15:00'));
      expect(p['measuredAt'], endsWith('Z'));
      expect(p['speedKmh'], 36);
      expect(p['simOperator'], 'Orange BF');
      expect(p['rsrp'], -95);
      expect(p['download'], 18.4);
      expect(p['batteryTempC'], 39);
      expect(p['error'], isNull);
    });

    test('Wi-Fi : aucune information de SIM ni de radio', () {
      final p = controlPayload(
        campaign: 'C1',
        deviceId: 'dev-1',
        seq: 1,
        measuredAt: DateTime.utc(2026, 11, 3),
        gps: gps,
        network: const NetworkStatus(
            connectionType: 'WiFi', simOperator: 'Orange BF', rsrp: -95),
        result: result,
        health: health,
        cycleMs: 1,
      );
      expect(p['simOperator'], isNull);
      expect(p['rsrp'], isNull);
    });

    test('cycle en échec : une mesure avec son erreur', () {
      final p = controlPayload(
        campaign: 'C1',
        deviceId: 'dev-1',
        seq: 2,
        measuredAt: DateTime.utc(2026, 11, 3),
        gps: null,
        network: null,
        result: null,
        health: DeviceHealth.unknown,
        cycleMs: 20000,
        error: 'test impossible',
      );
      expect(p['error'], 'test impossible');
      expect(p['download'], isNull);
      expect(p['latitude'], 0);
    });
  });

  test('codes HTTP de l\'envoi', () {
    expect(ControlApi.sendResultFor(409), ControlSendResult.duplicate);
    expect(ControlApi.sendResultFor(400), ControlSendResult.duplicate);
    expect(ControlApi.sendResultFor(401), ControlSendResult.forbidden);
    expect(ControlApi.sendResultFor(403), ControlSendResult.forbidden);
    expect(ControlApi.sendResultFor(500), ControlSendResult.retryLater);
    expect(ControlApi.sendResultFor(null), ControlSendResult.retryLater);
  });

  test('code de campagne', () {
    expect(campaignPattern.hasMatch('OUAGA-2026-11'), isTrue);
    expect(campaignPattern.hasMatch('bobo_axe_1'), isTrue);
    expect(campaignPattern.hasMatch('ouaga 2026'), isFalse);
    expect(campaignPattern.hasMatch(''), isFalse);
  });

  group('ControlStore (file hors réseau et numéro de cycle)', () {
    late Directory tmp;
    final store = ControlStore();

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('yele_control');
      Hive.init(tmp.path);
      await store.open();
    });

    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

    test('le numéro de cycle augmente et survit à la réouverture', () async {
      expect(await store.nextSeq('C1'), 1);
      expect(await store.nextSeq('C1'), 2);
      expect(await store.nextSeq('C2'), 1);
      await store.close();
      await store.open();
      expect(await store.nextSeq('C1'), 3);
    });

    test('file d\'attente dans l\'ordre, conservée à la réouverture', () async {
      await store.enqueue('{"seq":1}');
      await store.enqueue('{"seq":2}');
      await store.close();
      await store.open();
      expect(store.pending, ['{"seq":1}', '{"seq":2}']);
      await store.dropFirst();
      expect(store.pending, ['{"seq":2}']);
    });

    test('campagne active mémorisée (reprise après redémarrage)', () async {
      expect(store.active, isFalse);
      await store.setActive(true, campaign: 'C1', intervalSeconds: 120);
      await store.close();
      await store.open();
      expect(store.active, isTrue);
      expect(store.campaign, 'C1');
      expect(store.intervalSeconds, 120);
    });
  });
}
