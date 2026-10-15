import 'dart:math' as math;

/// Échelle de score Yélé (IMP-05, IMP-06, IMP-12).
///
/// Toutes les notes de l'application sont sur 0-100 et passent par ce
/// fichier : le score global, ceux de la navigation et du streaming, et les
/// libellés de qualité. Le tableau de bord applique la même formule
/// (`docs/SCORE.md` décrit l'échelle ; toute modification doit y être
/// reportée, ainsi que dans `New_web/js/score.js`).

/// Seuils de référence ARCEP intégrés au scoring (IMP-06).
///
/// Valeurs du protocole de mesure de la qualité des services mobiles
/// (navigation web et streaming vidéo). À ajuster ici si le référentiel
/// validé par l'ARCEP Burkina en fixe d'autres : c'est le seul endroit.
class ArcepThresholds {
  ArcepThresholds._();

  /// Navigation : une page chargée en moins de 10 s est réussie.
  static const double webSuccessMs = 10000;

  /// Navigation : en dessous de 5 s, le chargement est jugé rapide.
  static const double webFastMs = 5000;

  /// Streaming : démarrage de la vidéo en moins de 10 s, sinon échec.
  static const double videoStartMaxMs = 10000;

  /// Streaming : démarrage jugé rapide en dessous de 5 s.
  static const double videoStartFastMs = 5000;
}

/// Libellé et niveau (0 = très faible … 4 = excellent) d'un score 0-100.
/// Même découpage partout : bilan, historique, tableau de bord.
({String label, int level}) scoreBand(double score) {
  if (score >= 80) return (label: 'Excellent', level: 4);
  if (score >= 60) return (label: 'Bon', level: 3);
  if (score >= 40) return (label: 'Moyen', level: 2);
  if (score >= 20) return (label: 'Faible', level: 1);
  return (label: 'Très faible', level: 0);
}

class Scoring {
  Scoring._();

  /// Note d'une valeur sur une échelle logarithmique : 0 à [zeroAt] (ou
  /// moins), 100 à [fullAt] (ou plus). Le logarithme reflète l'usage : passer
  /// de 1 à 10 Mb/s change bien plus l'expérience que de 50 à 60 Mb/s.
  static double _logScale(double v, double zeroAt, double fullAt) {
    if (v <= zeroAt) return 0;
    if (v >= fullAt) return 100;
    return 100 *
        (math.log(v / zeroAt) / math.log(fullAt / zeroAt)).clamp(0.0, 1.0);
  }

  /// Débit descendant : 0 à 0,25 Mb/s, 100 à partir de 100 Mb/s.
  static double download(double mbps) => _logScale(mbps, 0.25, 100);

  /// Débit montant : 0 à 0,1 Mb/s, 100 à partir de 50 Mb/s.
  static double upload(double mbps) => _logScale(mbps, 0.1, 50);

  /// Latence : 100 jusqu'à 20 ms, 0 à partir de 500 ms (échelle log inverse).
  static double latency(double ms) {
    if (ms <= 0) return 0; // non mesurée
    if (ms <= 20) return 100;
    if (ms >= 500) return 0;
    return 100 * (1 - math.log(ms / 20) / math.log(500 / 20));
  }

  /// Navigation web (IMP-06) : chaque page vaut 100 si elle se charge en
  /// moins de [ArcepThresholds.webFastMs], de 100 à 50 jusqu'à
  /// [ArcepThresholds.webSuccessMs], 0 au-delà ou en cas d'échec. Le score
  /// est la moyenne sur toutes les pages tentées.
  static double browsing(List<double> loadTimesMs, int failures) {
    final total = loadTimesMs.length + failures;
    if (total == 0) return 0;
    double sum = 0;
    for (final ms in loadTimesMs) {
      if (ms <= ArcepThresholds.webFastMs) {
        sum += 100;
      } else if (ms < ArcepThresholds.webSuccessMs) {
        final t = (ms - ArcepThresholds.webFastMs) /
            (ArcepThresholds.webSuccessMs - ArcepThresholds.webFastMs);
        sum += 100 - 50 * t;
      }
    }
    return sum / total;
  }

  /// Streaming (IMP-06) : base selon la meilleure résolution tenue, puis
  /// pénalités de démarrage et d'interruptions. Un démarrage au-delà de
  /// [ArcepThresholds.videoStartMaxMs] est un échec au sens ARCEP : la note
  /// est plafonnée à 20.
  static double streaming({
    required int maxHeight,
    required int startupMs,
    required double rebufferRatio,
    required int rebufferCount,
  }) {
    if (maxHeight <= 0) return 0;
    double s = maxHeight >= 2160
        ? 100
        : maxHeight >= 1080
            ? 90
            : maxHeight >= 720
                ? 75
                : maxHeight >= 480
                    ? 55
                    : 35;
    if (startupMs > ArcepThresholds.videoStartFastMs) {
      s -= 10;
    }
    s -= 40 * rebufferRatio + 5 * rebufferCount;
    if (startupMs > ArcepThresholds.videoStartMaxMs) s = math.min(s, 20);
    return s.clamp(0, 100).toDouble();
  }

  /// Score global 0-100 (IMP-12) : moyenne pondérée des composantes
  /// mesurées — débit descendant 30 %, montant 15 %, latence 15 %,
  /// navigation 20 %, streaming 20 %. Une composante non mesurée (test
  /// partiel) est retirée et les poids restants sont renormalisés.
  static double global({
    double? downloadMbps,
    double? uploadMbps,
    double? pingMs,
    double? browsingScore,
    double? streamingScore,
  }) {
    final parts = <(double, double)>[
      if (downloadMbps != null && downloadMbps > 0) (download(downloadMbps), 30),
      if (uploadMbps != null && uploadMbps > 0) (upload(uploadMbps), 15),
      if (pingMs != null && pingMs > 0) (latency(pingMs), 15),
      if (browsingScore != null && browsingScore > 0) (browsingScore, 20),
      if (streamingScore != null && streamingScore > 0) (streamingScore, 20),
    ];
    if (parts.isEmpty) return 0;
    final weight = parts.fold<double>(0, (s, p) => s + p.$2);
    final total = parts.fold<double>(0, (s, p) => s + p.$1 * p.$2);
    return double.parse((total / weight).toStringAsFixed(1));
  }
}
