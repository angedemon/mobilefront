# Échelle de score Yélé

Toutes les notes de Yélé sont sur **0 à 100**. La même formule sert dans
l'application (bilan et historique) et sur le tableau de bord. Le code de
référence est `lib/services/scoring.dart`, couvert par `test/scoring_test.dart`.
Le tableau de bord en reprend la formule dans `New_web/js/score.js`.

## Libellés

| Score | Libellé |
|---|---|
| 80 à 100 | Excellent |
| 60 à 79 | Bon |
| 40 à 59 | Moyen |
| 20 à 39 | Faible |
| 0 à 19 | Très faible |

## Score global

Moyenne pondérée des composantes mesurées pendant le test :

| Composante | Poids | Note |
|---|---|---|
| Débit descendant | 30 % | Échelle logarithmique : 0 à 0,25 Mb/s, 100 à partir de 100 Mb/s |
| Débit montant | 15 % | Échelle logarithmique : 0 à 0,1 Mb/s, 100 à partir de 50 Mb/s |
| Latence | 15 % | 100 jusqu'à 20 ms, 0 à partir de 500 ms (échelle logarithmique) |
| Navigation web | 20 % | Score de navigation ci-dessous |
| Streaming vidéo | 20 % | Score de streaming ci-dessous |

Une composante non mesurée (test de débit seul, par exemple) est retirée et
les poids restants sont renormalisés : un test partiel garde un score sur 100.

L'échelle logarithmique traduit l'usage : passer de 1 à 10 Mb/s change bien
plus l'expérience que passer de 50 à 60 Mb/s.

## Seuils ARCEP

Regroupés dans la classe `ArcepThresholds` de `scoring.dart`. C'est le seul
endroit à modifier si le référentiel validé fixe d'autres valeurs.

**Navigation web.** Chaque page vaut :

- 100 si elle se charge en moins de **5 s** ;
- de 100 à 50, linéairement, entre 5 et **10 s** ;
- 0 au-delà de 10 s ou en cas d'échec (critère de réussite ARCEP).

Le score de navigation est la moyenne sur toutes les pages tentées.

**Streaming vidéo.** Base selon la meilleure résolution réellement tenue :
2160p = 100, 1080p = 90, 720p = 75, 480p = 55, en dessous = 35. Ensuite :

- −10 si la vidéo démarre en plus de **5 s** ;
- −40 × la part du temps passée en mise en tampon, et −5 par interruption ;
- plafonné à 20 si le démarrage dépasse **10 s** (échec au sens ARCEP).

## Différence avec nPerf

nPerf publie un score en points sans plafond, et sa formule n'est pas
publique. Le score Yélé reste sur 0-100 pour être lisible et comparable d'un
test à l'autre. Pour comparer les deux applications (ISS-05), comparer les
mesures brutes (débits, latence, perte) exportées, pas les scores.
