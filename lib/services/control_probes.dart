import 'dart:async';

import 'package:dio/dio.dart';

/// Mode Contrôle — tests web et vidéo SANS écran.
///
/// Dans l'app citoyenne, ces tests ouvrent un vrai navigateur et un vrai
/// lecteur vidéo, ce qui demande un écran allumé. Une campagne de contrôle
/// tourne écran éteint : on chronomètre donc directement les téléchargements
/// qu'un navigateur ou un lecteur feraient.
///
///  - Web : la page de référence, puis ses principales ressources (scripts,
///    feuilles de style, images, au plus [maxResources]) en parallèle. Seuil
///    ARCEP : page chargée en moins de 30 s.
///  - Vidéo : la liste de lecture HLS, la variante 720p (ou la plus proche
///    en dessous), puis son premier segment : c'est ce qu'un lecteur doit
///    recevoir avant d'afficher la première image. Seuil ARCEP : moins de 5 s.
///
/// Ces mesures approchent l'expérience d'un navigateur ou d'un lecteur sans
/// l'égaler (pas d'exécution de JavaScript, pas de décodage vidéo) : la fiche
/// de méthode du contrôle le dit.

/// Seuils ARCEP (annexe 3 des cahiers des charges des licences).
const double webMaxSeconds = 30;
const double videoStartMaxSeconds = 5;

class ProbeResult {
  final double? seconds; // durée mesurée ; null si rien n'a pu être chargé
  final bool ok; // sous le seuil ARCEP
  final String target; // page ou variante testée
  final int bytes;
  final String? error;

  const ProbeResult({
    required this.seconds,
    required this.ok,
    required this.target,
    this.bytes = 0,
    this.error,
  });
}

// ── Analyse (fonctions pures, testées) ──────────────────────────────────────

/// Ressources principales d'une page : scripts, feuilles de style, images,
/// en URL absolues, sans doublon, dans l'ordre d'apparition.
List<String> extractResources(String html, Uri base, {int max = 10}) {
  final found = <String>{};
  final patterns = [
    RegExp(r'''<script[^>]+src\s*=\s*["']([^"']+)["']''', caseSensitive: false),
    RegExp(r'''<link[^>]+rel\s*=\s*["']?stylesheet["']?[^>]*href\s*=\s*["']([^"']+)["']''', caseSensitive: false),
    RegExp(r'''<link[^>]+href\s*=\s*["']([^"']+)["'][^>]*rel\s*=\s*["']?stylesheet''', caseSensitive: false),
    RegExp(r'''<img[^>]+src\s*=\s*["']([^"']+)["']''', caseSensitive: false),
  ];
  final hits = <MapEntry<int, String>>[];
  for (final re in patterns) {
    for (final m in re.allMatches(html)) {
      hits.add(MapEntry(m.start, m.group(1)!));
    }
  }
  hits.sort((a, b) => a.key.compareTo(b.key));
  for (final h in hits) {
    final raw = h.value.trim();
    if (raw.isEmpty || raw.startsWith('data:') || raw.startsWith('javascript:')) continue;
    final Uri u;
    try {
      u = base.resolve(raw.replaceAll('&amp;', '&'));
    } catch (_) {
      continue;
    }
    if (u.scheme != 'http' && u.scheme != 'https') continue;
    found.add(u.toString());
    if (found.length >= max) break;
  }
  return found.toList();
}

class HlsVariant {
  final int bandwidth;
  final int? height;
  final Uri uri;
  const HlsVariant(this.bandwidth, this.height, this.uri);
}

/// Variantes d'une liste de lecture HLS maîtresse.
List<HlsVariant> parseMasterPlaylist(String text, Uri base) {
  final lines = text.split(RegExp(r'\r?\n')).map((l) => l.trim()).toList();
  final out = <HlsVariant>[];
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (!l.startsWith('#EXT-X-STREAM-INF:')) continue;
    final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(l)?.group(1) ?? '') ?? 0;
    final h = int.tryParse(RegExp(r'RESOLUTION=\d+x(\d+)').firstMatch(l)?.group(1) ?? '');
    for (var j = i + 1; j < lines.length; j++) {
      if (lines[j].isEmpty || lines[j].startsWith('#')) continue;
      out.add(HlsVariant(bw, h, base.resolve(lines[j])));
      break;
    }
  }
  return out;
}

/// Variante qu'un lecteur prendrait pour démarrer : 720p, sinon la plus haute
/// en dessous, sinon la plus basse disponible.
HlsVariant? pickStartVariant(List<HlsVariant> variants, {int targetHeight = 720}) {
  if (variants.isEmpty) return null;
  final below = variants.where((v) => (v.height ?? 0) <= targetHeight && v.height != null).toList()
    ..sort((a, b) => b.height!.compareTo(a.height!));
  if (below.isNotEmpty) return below.first;
  final sorted = [...variants]..sort((a, b) => a.bandwidth.compareTo(b.bandwidth));
  return sorted.first;
}

/// Segment d'initialisation (fMP4, facultatif) et premier segment média.
({Uri? init, Uri? first}) firstSegments(String text, Uri base) {
  Uri? init;
  Uri? first;
  for (final raw in text.split(RegExp(r'\r?\n'))) {
    final l = raw.trim();
    if (l.startsWith('#EXT-X-MAP:')) {
      final m = RegExp(r'URI="([^"]+)"').firstMatch(l);
      if (m != null) init = base.resolve(m.group(1)!);
    } else if (l.isNotEmpty && !l.startsWith('#')) {
      first = base.resolve(l);
      break;
    }
  }
  return (init: init, first: first);
}

// ── Mesures ─────────────────────────────────────────────────────────────────

class ControlProbes {
  ControlProbes([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 20),
              receiveTimeout: const Duration(seconds: 30),
              followRedirects: true,
              headers: {
                // Un navigateur mobile : certaines pages servent sinon une
                // version réduite ou refusent la requête.
                'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
                    '(KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36',
              },
            ));

  final Dio _dio;
  static const int maxResources = 10;

  Future<int> _bytes(String url, Duration budget) async {
    final res = await _dio.get<List<int>>(url,
        options: Options(responseType: ResponseType.bytes, receiveTimeout: budget));
    return res.data?.length ?? 0;
  }

  /// Chargement d'une page de référence et de ses ressources principales.
  Future<ProbeResult> web(String url) async {
    final sw = Stopwatch()..start();
    try {
      final res = await _dio.get<String>(url,
          options: Options(responseType: ResponseType.plain))
          .timeout(const Duration(seconds: 30));
      final html = res.data ?? '';
      var bytes = html.length;
      final base = res.realUri;
      final left = const Duration(seconds: 30) - sw.elapsed;
      final resources = extractResources(html, base, max: maxResources);
      if (resources.isNotEmpty && left > Duration.zero) {
        final sizes = await Future.wait(resources.map((r) =>
            _bytes(r, left).catchError((_) => 0))).timeout(left, onTimeout: () => const <int>[]);
        bytes += sizes.fold<int>(0, (a, b) => a + b);
      }
      final s = sw.elapsedMilliseconds / 1000;
      return ProbeResult(seconds: s, ok: s < webMaxSeconds, target: url, bytes: bytes);
    } catch (e) {
      final s = sw.elapsedMilliseconds / 1000;
      return ProbeResult(
          seconds: s, ok: false, target: url, error: 'page non chargée (${e.runtimeType})');
    }
  }

  /// Délai avant la première image d'une vidéo HLS.
  Future<ProbeResult> video(String masterUrl) async {
    final sw = Stopwatch()..start();
    try {
      final master = await _dio.get<String>(masterUrl,
          options: Options(responseType: ResponseType.plain));
      final variant = pickStartVariant(parseMasterPlaylist(master.data ?? '', master.realUri));
      if (variant == null) throw StateError('aucune variante');
      final playlist = await _dio.get<String>(variant.uri.toString(),
          options: Options(responseType: ResponseType.plain));
      final seg = firstSegments(playlist.data ?? '', playlist.realUri);
      if (seg.first == null) throw StateError('aucun segment');
      var bytes = 0;
      if (seg.init != null) bytes += await _bytes(seg.init.toString(), const Duration(seconds: 20));
      bytes += await _bytes(seg.first.toString(), const Duration(seconds: 20));
      final s = sw.elapsedMilliseconds / 1000;
      return ProbeResult(
          seconds: s,
          ok: s < videoStartMaxSeconds,
          target: '${variant.height ?? '?'}p',
          bytes: bytes);
    } catch (e) {
      final s = sw.elapsedMilliseconds / 1000;
      return ProbeResult(
          seconds: s, ok: false, target: masterUrl, error: 'vidéo non démarrée (${e.runtimeType})');
    }
  }
}
