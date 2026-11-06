import 'package:flutter_test/flutter_test.dart';
import 'package:yele/screens/control_screen.dart';
import 'package:yele/services/control_probes.dart';
import 'package:yele/services/control_session.dart';
import 'package:yele/services/network_info_service.dart';

/// Mode Contrôle : refus du Wi-Fi, vérifications avant départ, analyse des
/// pages et des listes de lecture vidéo des tests sans écran.
void main() {
  const mobile = NetworkStatus(connectionType: 'Mobile', cellularTech: '4G', simOperator: 'Orange BF');
  const wifi = NetworkStatus(connectionType: 'WiFi');
  const none = NetworkStatus(connectionType: 'Aucune');

  group('exclusionFor (le contrôle ne vaut que sur le réseau mobile)', () {
    test('réseau mobile : retenu', () => expect(exclusionFor(mobile), isNull));
    test('Wi-Fi : non retenu', () => expect(exclusionFor(wifi), 'wifi'));
    test('aucun réseau : non retenu', () => expect(exclusionFor(none), 'hors réseau mobile'));
  });

  test('un cycle non retenu le dit, sans être compté en échec', () {
    final p = controlPayload(
      campaign: 'C1',
      deviceId: 'd',
      seq: 1,
      measuredAt: DateTime.utc(2026, 11, 6),
      gps: null,
      network: wifi,
      result: null,
      health: DeviceHealth.unknown,
      cycleMs: 10,
      excluded: 'wifi',
    );
    expect(p['excluded'], 'wifi');
    expect(p['error'], isNull);
    expect(p['connection'], 'WiFi');
  });

  test('résultats web et vidéo dans la mesure', () {
    final p = controlPayload(
      campaign: 'C1',
      deviceId: 'd',
      seq: 2,
      measuredAt: DateTime.utc(2026, 11, 6),
      gps: null,
      network: mobile,
      result: null,
      health: DeviceHealth.unknown,
      cycleMs: 10,
      web: const ProbeResult(seconds: 4.2, ok: true, target: 'https://lefaso.net'),
      video: const ProbeResult(seconds: 6.1, ok: false, target: '720p'),
    );
    expect(p['webLoadS'], 4.2);
    expect(p['webOk'], isTrue);
    expect(p['webUrl'], 'https://lefaso.net');
    expect(p['videoStartS'], 6.1);
    expect(p['videoOk'], isFalse);
    expect(p['videoVariant'], '720p');
  });

  group('startProblem (vérifications avant le départ)', () {
    test('tout est prêt', () {
      expect(startProblem(network: mobile, phoneGranted: true, locationGranted: true), isNull);
    });
    test('Wi-Fi actif : départ refusé', () {
      expect(startProblem(network: wifi, phoneGranted: true, locationGranted: true), contains('Wi-Fi'));
    });
    test('pas de réseau mobile', () {
      expect(startProblem(network: none, phoneGranted: true, locationGranted: true), contains('données mobiles'));
    });
    test('autorisations manquantes', () {
      expect(startProblem(network: mobile, phoneGranted: true, locationGranted: false), contains('localisation'));
      expect(startProblem(network: mobile, phoneGranted: false, locationGranted: true), contains('Téléphone'));
    });
  });

  test('extractResources : scripts, styles et images en URL absolues', () {
    const html = '''
      <html><head>
        <link rel="stylesheet" href="/css/site.css">
        <link href="theme.css" rel="stylesheet">
        <script src="https://cdn.exemple.bf/app.js"></script>
        <link rel="icon" href="/favicon.ico">
      </head><body>
        <img src="images/logo.png"><img src="data:image/png;base64,AAAA">
        <img src="images/logo.png">
      </body></html>''';
    final r = extractResources(html, Uri.parse('https://lefaso.net/actu/'));
    expect(r, [
      'https://lefaso.net/css/site.css',
      'https://lefaso.net/actu/theme.css',
      'https://cdn.exemple.bf/app.js',
      'https://lefaso.net/actu/images/logo.png',
    ]);
    expect(extractResources(html, Uri.parse('https://lefaso.net/'), max: 2), hasLength(2));
  });

  group('HLS', () {
    const master = '''#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2817071,RESOLUTION=1280x720
720p/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=1920x1080
1080p/index.m3u8
''';
    final base = Uri.parse('https://yele-test-assets.netlify.app/bbb/master.m3u8');

    test('variantes et choix du 720p pour démarrer', () {
      final v = parseMasterPlaylist(master, base);
      expect(v, hasLength(3));
      expect(v[1].height, 720);
      expect(v[1].uri.toString(), 'https://yele-test-assets.netlify.app/bbb/720p/index.m3u8');
      expect(pickStartVariant(v)!.height, 720);
    });

    test('sans 720p : la plus haute en dessous, sinon la plus légère', () {
      final v = parseMasterPlaylist(master, base);
      expect(pickStartVariant([v[0], v[2]])!.height, 360);
      expect(pickStartVariant([v[2]])!.height, 1080);
      expect(pickStartVariant(const []), isNull);
    });

    test('premier segment, avec ou sans segment d\'initialisation', () {
      final b = Uri.parse('https://x.bf/720p/index.m3u8');
      final fmp4 = firstSegments('#EXTM3U\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:4.0,\nseg0.m4s\nseg1.m4s\n', b);
      expect(fmp4.init.toString(), 'https://x.bf/720p/init.mp4');
      expect(fmp4.first.toString(), 'https://x.bf/720p/seg0.m4s');
      final ts = firstSegments('#EXTM3U\n#EXTINF:4.0,\nseg0.ts\n', b);
      expect(ts.init, isNull);
      expect(ts.first.toString(), 'https://x.bf/720p/seg0.ts');
    });
  });
}
