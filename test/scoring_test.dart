import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/scoring.dart';

void main() {
  group('Seuils ARCEP navigation (IMP-06, page réussie sous 30 s)', () {
    test('page rapide (≤ 5 s) = 100', () {
      expect(Scoring.browsing([4999], 0), 100);
      expect(Scoring.browsing([5000], 0), 100);
    });
    test('entre 5 et 30 s : de 100 à 50', () {
      expect(Scoring.browsing([17500], 0), closeTo(75, 0.01));
      expect(Scoring.browsing([29999], 0), closeTo(50, 0.1));
    });
    test('au-delà de 30 s ou en échec = 0', () {
      expect(Scoring.browsing([30000], 0), 0);
      expect(Scoring.browsing([], 1), 0);
    });
    test('moyenne sur toutes les pages tentées', () {
      expect(Scoring.browsing([1000, 1000], 2), 50);
    });
  });

  group('Seuils ARCEP streaming (première image sous 5 s)', () {
    test('1080p, démarrage conforme = 90', () {
      expect(
          Scoring.streaming(
              maxHeight: 1080, startupMs: 4999, rebufferRatio: 0, rebufferCount: 0),
          90);
    });
    test('démarrage au-delà de 5 s : -25, plafonné à 50', () {
      expect(
          Scoring.streaming(
              maxHeight: 2160, startupMs: 5001, rebufferRatio: 0, rebufferCount: 0),
          50);
      expect(
          Scoring.streaming(
              maxHeight: 720, startupMs: 6000, rebufferRatio: 0, rebufferCount: 0),
          50);
      expect(
          Scoring.streaming(
              maxHeight: 480, startupMs: 6000, rebufferRatio: 0, rebufferCount: 0),
          30);
    });
  });

  group('Référentiel ARCEP (annexe 3)', () {
    test('catégories de débit D1 à D4', () {
      expect(Arcep.debitCategory(4.5, 2.5), 'D4');
      expect(Arcep.debitCategory(4.5, 1.5), 'D3');
      expect(Arcep.debitCategory(1.5, 0.6), 'D2');
      expect(Arcep.debitCategory(0.06, 0.04), 'D1');
      expect(Arcep.debitCategory(0.04, 0.02), isNull);
    });
    test('couverture 4G : RSRP ≥ -102 dBm', () {
      expect(Arcep.coverageOk('4G', -102, null), isTrue);
      expect(Arcep.coverageOk('4G', -103, null), isFalse);
      expect(Arcep.coverageOk('3G', null, -96), isTrue);
      expect(Arcep.coverageOk('2G', null, -93), isFalse);
      expect(Arcep.coverageOk('WiFi', -80, null), isNull);
    });
    test('débit conforme : 4G > 2 / 1 Mb/s, 3G > 1 Mb/s / 512 kb/s', () {
      expect(Arcep.debitOk('4G', 2.1, 1.1), isTrue);
      expect(Arcep.debitOk('4G', 2.1, 0.9), isFalse);
      expect(Arcep.debitOk('3G', 1.1, 0.6), isTrue);
      expect(Arcep.debitOk('WiFi', 50, 20), isNull);
    });
  });

  group('Score global (IMP-12)', () {
    test('composantes absentes ignorées', () {
      expect(Scoring.global(), 0);
      expect(Scoring.global(downloadMbps: 100), 100);
    });
    test('borné entre 0 et 100, identique pour les mêmes entrées', () {
      final a = Scoring.global(
          downloadMbps: 12, uploadMbps: 3, pingMs: 60, browsingScore: 80);
      final b = Scoring.global(
          downloadMbps: 12, uploadMbps: 3, pingMs: 60, browsingScore: 80);
      expect(a, b);
      expect(a, inInclusiveRange(0, 100));
    });
    test('latence : 100 sous 20 ms, 0 au-delà de 500 ms', () {
      expect(Scoring.latency(15), 100);
      expect(Scoring.latency(600), 0);
    });
  });

  test('échelle de libellés (IMP-05)', () {
    expect(scoreBand(85).label, 'Excellent');
    expect(scoreBand(60).label, 'Bon');
    expect(scoreBand(59.9).label, 'Moyen');
    expect(scoreBand(20).label, 'Faible');
    expect(scoreBand(5).label, 'Très faible');
  });
}
