import 'package:flutter_test/flutter_test.dart';
import 'package:yele/services/scoring.dart';

void main() {
  group('Seuils ARCEP navigation (IMP-06)', () {
    test('page rapide (< 5 s) = 100', () {
      expect(Scoring.browsing([4999], 0), 100);
    });
    test('page entre 5 et 10 s : de 100 à 50', () {
      expect(Scoring.browsing([5000], 0), 100);
      expect(Scoring.browsing([7500], 0), closeTo(75, 0.01));
      expect(Scoring.browsing([9999], 0), closeTo(50, 0.1));
    });
    test('page au-delà de 10 s ou en échec = 0', () {
      expect(Scoring.browsing([10000], 0), 0);
      expect(Scoring.browsing([], 1), 0);
    });
    test('moyenne sur toutes les pages tentées', () {
      expect(Scoring.browsing([1000, 1000], 2), 50);
    });
  });

  group('Seuils ARCEP streaming (IMP-06)', () {
    test('1080p sans incident = 90', () {
      expect(
          Scoring.streaming(
              maxHeight: 1080, startupMs: 2000, rebufferRatio: 0, rebufferCount: 0),
          90);
    });
    test('démarrage au-delà de 10 s : plafonné à 20', () {
      expect(
          Scoring.streaming(
              maxHeight: 2160, startupMs: 10001, rebufferRatio: 0, rebufferCount: 0),
          20);
    });
    test('démarrage entre 5 et 10 s : -10', () {
      expect(
          Scoring.streaming(
              maxHeight: 720, startupMs: 6000, rebufferRatio: 0, rebufferCount: 0),
          65);
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
