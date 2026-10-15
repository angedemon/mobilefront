// Captures d'écran de l'application pour la présentation des modifications.
//
// Rend les vrais écrans (polices réelles, données d'exemple) en PNG dans
// build/captures/. Lancé à la main par le workflow « Captures d'écran » :
//   flutter test test/screenshots --dart-define=YELE_GOOGLE_CLIENT_ID=demo
// Ce n'est pas un test de non-régression : il ne vérifie rien.
@Tags(['captures'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:yele/models/speed_test_result.dart';
import 'package:yele/screens/account_screen.dart';
import 'package:yele/screens/consent_screen.dart';
import 'package:yele/screens/full_test_screen.dart';
import 'package:yele/screens/help_screen.dart';
import 'package:yele/screens/history_screen.dart';
import 'package:yele/screens/permissions_screen.dart';
import 'package:yele/screens/privacy_policy_screen.dart';
import 'package:yele/screens/score_screen.dart';
import 'package:yele/screens/settings_screen.dart';
import 'package:yele/services/consent_service.dart';
import 'package:yele/services/local_storage_service.dart';
import 'package:yele/services/streaming_test_service.dart';
import 'package:yele/theme/yele_theme.dart';

final _out = Directory('build/captures');

Future<void> _loadFonts() async {
  final root = Platform.environment['FLUTTER_ROOT']!;
  final dir = '$root/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in Directory(dir).listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.startsWith('Roboto') && name.endsWith('.ttf')) {
      roboto.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await roboto.load();
  // Police par défaut des tests (« FlutterTest ») : les textes sans famille
  // explicite (logo en RichText, symboles) s'afficheraient en carrés.
  final fallback = FontLoader('FlutterTest');
  for (final f in Directory(dir).listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name == 'Roboto-Regular.ttf' || name == 'Roboto-Bold.ttf') {
      fallback.addFont(Future.value(ByteData.sublistView(f.readAsBytesSync())));
    }
  }
  await fallback.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(
        File('$dir/MaterialIcons-Regular.otf').readAsBytesSync())));
  await icons.load();
}

void _mockPlatform(Directory tmp) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path);
  messenger.setMockMethodCallHandler(const MethodChannel('com.yele/telephony'),
      (call) async {
    switch (call.method) {
      case 'getPermissions':
        return {
          'location': true,
          'preciseLocation': true,
          'phone': true,
          'notifications': false,
        };
      case 'getTelephony':
        return {
          'simOperator': 'Orange BF',
          'mccMnc': '61302',
          'cellularTech': '4G',
          'simSlot': 2,
          'simCount': 2,
          'rsrp': -97,
          'rsrq': -11,
          'sinr': 9,
        };
      case 'getCollectStatus':
        return {
          'running': false,
          'enabled': false,
          'intervalMinutes': 15,
          'lastCollectAt': 0,
          'count': 0,
        };
      case 'isMonitorRunning':
        return true;
    }
    return null;
  });
}

SpeedTestResult _sample({
  required DateTime at,
  required double dl,
  required double ul,
  required double ping,
  String tech = '4G',
  String network = '4G',
  bool full = true,
}) {
  final streaming = StreamingTestResult(
    qualities: const [
      StreamingQualityResult(
          label: '720p',
          reached: true,
          performanceRate: 96.4,
          initialLoadingSec: 1.2,
          bufferingSec: 0.3,
          dataUsedKiB: 3100),
      StreamingQualityResult(
          label: '1080p',
          reached: true,
          performanceRate: 88.1,
          initialLoadingSec: 1.9,
          bufferingSec: 1.1,
          rebufferCount: 1,
          dataUsedKiB: 5400),
      StreamingQualityResult.unavailable('2160p'),
    ],
    startupMs: 1200,
    rebufferCount: 1,
    rebufferRatio: 0.06,
    maxResolution: '1080p',
    score: 78,
  );
  return SpeedTestResult(
    timestamp: at,
    downloadSpeed: dl,
    uploadSpeed: ul,
    ping: ping,
    jitter: 6.8,
    server: 'yele_serveur — Render (hors Afrique)',
    networkType: network,
    operator: 'Orange Burkina Faso',
    simOperator: network == 'WiFi' ? null : 'Orange BF',
    cellularTech: network == 'WiFi' ? null : tech,
    simSlot: network == 'WiFi' ? null : 2,
    rsrp: network == 'WiFi' ? null : -97,
    rsrq: network == 'WiFi' ? null : -11,
    sinr: network == 'WiFi' ? null : 9,
    latitude: 12.3714,
    longitude: -1.5197,
    locationSource: 'gps',
    location: 'Ouagadougou, Burkina Faso',
    address: 'Avenue Kwame Nkrumah, Koulouba, Ouagadougou',
    deviceModel: 'TECNO Spark 20',
    downloadMin: dl * 0.55,
    downloadMax: dl * 1.32,
    uploadMin: ul * 0.6,
    uploadMax: ul * 1.25,
    pingMin: ping * 0.8,
    pingMax: ping * 1.6,
    packetLoss: 0.5,
    dataUsedKiB: 46 * 1024,
    streamingStartupMs: full ? streaming.startupMs : null,
    streamingRebufferCount: full ? 1 : null,
    streamingRebufferRatio: full ? 0.06 : null,
    streamingMaxResolution: full ? '1080p' : null,
    streamingScore: full ? 78 : null,
    streamingQualitiesJson: full ? streaming.encodeQualities() : null,
    browsingAvgLoadMs: full ? 2350 : null,
    browsingSuccessRate: full ? 1 : null,
    browsingPagesTested: full ? 6 : null,
    browsingScore: full ? 92 : null,
    qoeRating: 4,
    isUploaded: true,
  );
}

Future<void> _shot(WidgetTester tester, String name, Widget screen,
    {Future<void> Function()? before, Size size = const Size(360, 780)}) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildYeleTheme(),
      home: screen,
      routes: {'/privacy': (_) => const PrivacyPolicyScreen()},
    ),
  ));
  // Plusieurs images : écrans animés (jauge) et chargements asynchrones.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
  if (before != null) {
    await before();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File('${_out.path}/$name.png').writeAsBytesSync(bytes!);
  // Démonte l'écran : arrête jauges et minuteurs avant la capture suivante.
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  late SpeedTestResult full;

  setUpAll(() async {
    _out.createSync(recursive: true);
    final tmp = Directory.systemTemp.createTempSync('yele_captures');
    _mockPlatform(tmp);
    await _loadFonts();
    await ConsentService().initialize();
    await LocalStorageService().initialize();
    await ConsentService().accept();
    await Hive.box('settings').put('monthlyLimitMb', 1024);

    final now = DateTime(2026, 10, 15, 10, 5);
    full = _sample(at: now, dl: 31.4, ul: 9.2, ping: 48);
    final storage = LocalStorageService();
    await storage.clearAll();
    await storage.saveResult(full);
    await storage.saveResult(_sample(
        at: now.subtract(const Duration(hours: 3)),
        dl: 12.7,
        ul: 4.1,
        ping: 71,
        tech: '5G'));
    await storage.saveResult(_sample(
        at: now.subtract(const Duration(days: 1)),
        dl: 64.0,
        ul: 21.5,
        ping: 33,
        network: 'WiFi'));
  });

  testWidgets('captures', (tester) async {
    await _shot(tester, '01_consentement', const ConsentScreen());
    await _shot(tester, '02_politique', const PrivacyPolicyScreen());
    await _shot(tester, '03_test_complet', const FullTestScreen());
    await _shot(tester, '04_bilan', ScoreScreen(result: full),
        size: const Size(360, 1360));
    await _shot(tester, '05_historique', const HistoryScreen(),
        size: const Size(360, 1000), before: () async {
      await tester.tap(find.textContaining('Mb/s').first);
    });
    await _shot(tester, '06_reglages', const SettingsScreen(),
        size: const Size(360, 1300));
    await _shot(tester, '07_compte', const AccountScreen());
    await _shot(tester, '08_autorisations', const PermissionsScreen());
    await _shot(tester, '09_aide', const HelpScreen(),
        size: const Size(360, 1150), before: () async {
      await tester.tap(find.text('Que sont RSRP, RSRQ et SINR ?'));
    });
    await _shot(tester, '10_menu', const FullTestScreen(), before: () async {
      final state = tester.state<ScaffoldState>(find.byType(Scaffold).first);
      state.openDrawer();
    });
  });
}
