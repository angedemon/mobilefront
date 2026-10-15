import 'dart:math' as math;

/// Échelle de score Yélé (IMP-05, IMP-06, IMP-12).
///
/// Toutes les notes de l'application sont sur 0-100 et passent par ce
/// fichier : le score global, ceux de la navigation et du streaming, et les
/// libellés de qualité. Le tableau de bord applique la même formule
/// (`docs/SCORE.md` décrit l'échelle ; toute modification doit y être
/// reportée, ainsi que dans `New_web/js/score.js`).

/// Seuils de référence ARCEP Burkina intégrés au scoring (IMP-06).
///
/// Source : cahiers des charges des licences technologiquement neutres
/// (Orange Burkina Faso, ONATEL, Telecel Faso), annexe n° 3 « Engagements
/// de couverture et de qualité de service du titulaire ». Les trois
/// opérateurs ont les mêmes seuils. C'est le seul endroit à modifier si
/// l'ARCEP les révise.
class ArcepThresholds {
  ArcepThresholds._();

  // ── Qualité de service (annexe 3, § 2) ──────────────────────────────────

  /// « Taux de chargement des pages web en 30 secondes (page Kepler) » :
  /// une page chargée en moins de 30 s est réussie…
  static const double webSuccessMs = 30000;

  /// … et plus de 95 % des pages doivent l'être.
  static const double webSuccessRateMin = 0.95;

  /// « Temps moyen de pré-chargement ou temps au bout duquel la première
  /// image de la vidéo est affichée » : moins de 5 s.
  static const double videoStartMaxMs = 5000;

  /// « Taux de connexion réussi à Internet (dans 20 secondes) » : > 98 %.
  static const double internetConnectMs = 20000;

  // Repère interne Yélé (pas un seuil ARCEP) : une page sous 5 s est jugée
  // rapide et reçoit la note maximale.
  static const double webFastMs = 5000;

  // ── Couverture : niveau de puissance (annexe 3, § 1.1) ──────────────────

  static const int rsrp4gMinDbm = -102; // 4G : RSRP ≥ -102 dBm
  static const int rscp3gMinDbm = -96; // 3G : RSCP ≥ -96 dBm
  static const int rxlev2gMinDbm = -92; // 2G : RxLev ≥ -92 dBm

  // ── Débits (annexe 3, § 1.3/1.4 et § 3.1) ──────────────────────────────

  /// Zone couverte en 4G : 90 % des mesures > 2 Mb/s descendant et
  /// > 1 Mb/s montant ; en 3G : > 1 Mb/s et > 512 kb/s.
  static const double dl4gMinMbps = 2, ul4gMinMbps = 1;
  static const double dl3gMinMbps = 1, ul3gMinMbps = 0.512;

  /// Catégories de débits D1 à D4 (descendant, montant), en Mb/s.
  static const debitCategories = [
    (name: 'D4', dl: 4.0, ul: 2.0),
    (name: 'D3', dl: 2.0, ul: 1.0),
    (name: 'D2', dl: 1.0, ul: 0.512),
    (name: 'D1', dl: 0.05, ul: 0.03),
  ];
}

/// Un critère du référentiel ARCEP évalué sur une mesure.
class ArcepCheck {
  final String label;
  final String value;
  final bool? ok; // null : non mesuré
  const ArcepCheck(this.label, this.value, this.ok);
}

/// Évaluation d'une mesure au regard des seuils ARCEP (IMP-06).
class Arcep {
  Arcep._();

  /// Critères évalués pour une mesure, dans l'ordre d'affichage.
  /// [tech] vaut null pour un test Wi-Fi : débit et couverture radio ne
  /// relèvent alors pas des obligations des opérateurs mobiles.
  static List<ArcepCheck> checks({
    String? tech,
    double? dlMbps,
    double? ulMbps,
    int? rsrp,
    int? signalDbm,
    double? browsingSuccessRate,
    int? streamingStartupMs,
  }) {
    final list = <ArcepCheck>[];
    if (tech != null && dlMbps != null && dlMbps > 0 && ulMbps != null) {
      final is4g = tech == '4G' || tech == '5G';
      final cat = debitCategory(dlMbps, ulMbps);
      list.add(ArcepCheck(
        'Débit $tech (seuil ${is4g ? '> 2 / 1 Mb/s' : '> 1 Mb/s / 512 kb/s'})',
        cat == null ? 'sous D1' : 'catégorie $cat',
        debitOk(tech, dlMbps, ulMbps),
      ));
    }
    final cov = coverageOk(tech, rsrp, signalDbm);
    if (cov != null) {
      final is4g = tech == '4G' || tech == '5G';
      final v = is4g ? (rsrp ?? signalDbm) : signalDbm;
      list.add(ArcepCheck(
        is4g ? 'Couverture (RSRP ≥ -102 dBm)' : 'Couverture ($tech)',
        '$v dBm',
        cov,
      ));
    }
    if (browsingSuccessRate != null) {
      list.add(ArcepCheck(
        'Pages web en moins de 30 s (> 95 %)',
        '${(browsingSuccessRate * 100).toStringAsFixed(0)} %',
        browsingSuccessRate > ArcepThresholds.webSuccessRateMin,
      ));
    }
    if (streamingStartupMs != null && streamingStartupMs > 0) {
      list.add(ArcepCheck(
        'Première image vidéo (< 5 s)',
        '${(streamingStartupMs / 1000).toStringAsFixed(1)} s',
        streamingStartupMs < ArcepThresholds.videoStartMaxMs,
      ));
    }
    return list;
  }

  /// Catégorie de débit atteinte (« D4 » … « D1 »), ou null en dessous de D1.
  static String? debitCategory(double dlMbps, double ulMbps) {
    for (final c in ArcepThresholds.debitCategories) {
      if (dlMbps > c.dl && ulMbps > c.ul) return c.name;
    }
    return null;
  }

  /// Seuil de puissance de la technologie : couvert ou non. null si la
  /// technologie ou la mesure manque.
  static bool? coverageOk(String? tech, int? rsrp, int? signalDbm) {
    switch (tech) {
      case '4G':
      case '5G':
        final v = rsrp ?? signalDbm;
        return v == null ? null : v >= ArcepThresholds.rsrp4gMinDbm;
      case '3G':
        return signalDbm == null ? null : signalDbm >= ArcepThresholds.rscp3gMinDbm;
      case '2G':
        return signalDbm == null ? null : signalDbm >= ArcepThresholds.rxlev2gMinDbm;
    }
    return null;
  }

  /// Débit conforme au seuil de couverture de la technologie (4G : 2 et
  /// 1 Mb/s ; 3G : 1 Mb/s et 512 kb/s). null hors 3G/4G/5G.
  static bool? debitOk(String? tech, double dl, double ul) {
    if (tech == '4G' || tech == '5G') {
      return dl > ArcepThresholds.dl4gMinMbps && ul > ArcepThresholds.ul4gMinMbps;
    }
    if (tech == '3G') {
      return dl > ArcepThresholds.dl3gMinMbps && ul > ArcepThresholds.ul3gMinMbps;
    }
    return null;
  }
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
  /// moins de [ArcepThresholds.webFastMs], de 100 à 50 jusqu'au seuil ARCEP
  /// de réussite [ArcepThresholds.webSuccessMs] (30 s), 0 au-delà ou en cas
  /// d'échec. Le score est la moyenne sur toutes les pages tentées.
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
  /// pénalité d'interruptions. Une première image affichée au-delà du
  /// seuil ARCEP [ArcepThresholds.videoStartMaxMs] (5 s) rend la session
  /// non conforme : -25 points et note plafonnée à 50.
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
    s -= 40 * rebufferRatio + 5 * rebufferCount;
    if (startupMs > ArcepThresholds.videoStartMaxMs) {
      s = math.min(s - 25, 50);
    }
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
