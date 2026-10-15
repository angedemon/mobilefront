import 'dart:async';

import 'package:logger/logger.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../constants/config.dart';

/// Résultat du test de navigation web.
class BrowsingTestResult {
  final double avgLoadMs; // temps de chargement moyen des pages réussies
  final double successRate; // part des pages chargées en < 10 s (0-1)
  final int pagesTested;
  final double score; // score synthétique 0-100

  const BrowsingTestResult({
    required this.avgLoadMs,
    required this.successRate,
    required this.pagesTested,
    required this.score,
  });

  @override
  String toString() =>
      'Browsing: ${avgLoadMs.toStringAsFixed(0)} ms en moyenne, '
      '${(successRate * 100).toStringAsFixed(0)}% de réussite sur $pagesTested pages, '
      'score ${score.toStringAsFixed(1)}';
}

typedef BrowsingProgressCallback = void Function(double progress, String message);

/// Callback fournissant le contrôleur WebView à l'interface pour affichage,
/// puis null quand le test est terminé.
typedef BrowsingControllerCallback = void Function(WebViewController? controller);

/// Test de navigation web **réel et visible**.
///
/// Charge chaque page de référence dans un vrai navigateur intégré
/// ([WebViewController]) affiché à l'écran, et mesure le temps écoulé entre
/// le début du chargement et la fin du rendu ([NavigationDelegate.onPageFinished]).
/// Contrairement à une simple requête HTTP, cela inclut le téléchargement des
/// sous-ressources (CSS, JS, images) et le rendu — la mesure reflète
/// l'expérience réelle de navigation.
///
/// Critère ARCEP : une page est "réussie" si elle se charge en moins de 10 s.
class BrowsingTestService {
  final logger = Logger();

  // Au-delà : la page compte comme un échec (critère ARCEP)
  static const int _successThresholdMs = 10000;
  // Sécurité absolue par page (réseaux très lents) avant de passer à la suivante
  static const int _hardTimeoutMs = 20000;

  Future<BrowsingTestResult> runTest({
    List<String> pages = BROWSING_REFERENCE_PAGES,
    BrowsingControllerCallback? onController,
    BrowsingProgressCallback? onProgress,
  }) async {
    final loadTimes = <double>[];
    int successes = 0;

    // Complète à chaque fin de chargement (ou erreur) de la page courante.
    Completer<void>? pageCompleter;
    bool currentPageFailed = false;

    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            final c = pageCompleter;
            if (c != null && !c.isCompleted) c.complete();
          },
          onWebResourceError: (error) {
            // On n'échoue que sur l'erreur du document principal, pas sur une
            // sous-ressource secondaire (pub, tracker bloqué, etc.).
            final c = pageCompleter;
            if (error.isForMainFrame == true && c != null && !c.isCompleted) {
              currentPageFailed = true;
              c.complete();
            }
          },
        ),
      );

    onController?.call(controller); // le navigateur apparaît à l'écran

    try {
      for (int i = 0; i < pages.length; i++) {
        final url = pages[i];
        onProgress?.call(i / pages.length, 'Chargement de ${_hostOf(url)}');

        final completer = Completer<void>();
        pageCompleter = completer;
        currentPageFailed = false;
        final stopwatch = Stopwatch()..start();

        await controller.loadRequest(Uri.parse(url));

        try {
          await completer.future
              .timeout(const Duration(milliseconds: _hardTimeoutMs));
        } on TimeoutException {
          currentPageFailed = true;
        }
        stopwatch.stop();

        final ms = stopwatch.elapsedMilliseconds.toDouble();
        if (!currentPageFailed) {
          loadTimes.add(ms);
          if (ms < _successThresholdMs) successes++;
          logger.i('Browsing ${_hostOf(url)}: ${ms.toStringAsFixed(0)} ms');
        } else {
          logger.w('Browsing ${_hostOf(url)}: échec/timeout');
        }

        // Laisse la page visible un court instant avant la suivante
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } finally {
      onController?.call(null); // retire le navigateur de l'écran
    }

    onProgress?.call(1.0, 'Test de navigation terminé');

    final successRate = pages.isEmpty ? 0.0 : successes / pages.length;
    final avgLoadMs = loadTimes.isEmpty
        ? 0.0
        : loadTimes.reduce((a, b) => a + b) / loadTimes.length;

    final result = BrowsingTestResult(
      avgLoadMs: double.parse(avgLoadMs.toStringAsFixed(0)),
      successRate: double.parse(successRate.toStringAsFixed(2)),
      pagesTested: pages.length,
      score: double.parse(_computeScore(successRate, avgLoadMs).toStringAsFixed(1)),
    );
    logger.i(result.toString());
    return result;
  }

  double _computeScore(double successRate, double avgLoadMs) {
    double score = 100 * successRate;
    // Pénalité de lenteur : -1 point par 100 ms au-delà de 2 s
    if (avgLoadMs > 2000) score -= (avgLoadMs - 2000) / 100;
    return score.clamp(0, 100);
  }

  String _hostOf(String url) => Uri.tryParse(url)?.host ?? url;
}
