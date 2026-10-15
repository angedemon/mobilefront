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

Source : cahiers des charges des licences technologiquement neutres
d'Orange Burkina Faso, de l'ONATEL et de Telecel Faso, **annexe n° 3**
« Engagements de couverture et de qualité de service du titulaire ». Les trois
opérateurs ont les mêmes seuils. Ils sont regroupés dans la classe
`ArcepThresholds` de `scoring.dart`, seul endroit à modifier s'ils changent.

| Indicateur ARCEP | Seuil | Usage dans Yélé |
|---|---|---|
| Chargement des pages web en 30 s (page Kepler) | > 95 % des pages | Une page est réussie sous 30 s |
| Pré-chargement vidéo (première image) | < 5 s | Au-delà, la session vidéo est non conforme |
| Connexion à Internet réussie en 20 s | > 98 % | — |
| Puissance 4G (RSRP) | ≥ -102 dBm | Couverture conforme ou non |
| Puissance 3G (RSCP) / 2G (RxLev) | ≥ -96 / ≥ -92 dBm | Couverture conforme ou non |
| Débits 4G | 90 % des mesures > 2 Mb/s ↓ et > 1 Mb/s ↑ | Débit conforme ou non |
| Débits 3G | 90 % des mesures > 1 Mb/s ↓ et > 512 kb/s ↑ | Débit conforme ou non |
| Catégories de débits | D1 > 50/30 kb/s, D2 > 1 Mb/s / 512 kb/s, D3 > 2/1 Mb/s, D4 > 4/2 Mb/s | Catégorie atteinte par la mesure |

Les seuils en « 90 % des mesures » s'appliquent à une zone, sur l'ensemble
des tests ; le bilan d'un test indique si **cette** mesure les respecte.

**Navigation web.** Chaque page vaut :

- 100 si elle se charge en moins de **5 s** (repère interne de rapidité) ;
- de 100 à 50, linéairement, entre 5 s et **30 s** (seuil ARCEP de réussite) ;
- 0 au-delà de 30 s ou en cas d'échec.

Le score de navigation est la moyenne sur toutes les pages tentées.

**Streaming vidéo.** Base selon la meilleure résolution réellement tenue :
2160p = 100, 1080p = 90, 720p = 75, 480p = 55, en dessous = 35. Ensuite :

- −40 × la part du temps passée en mise en tampon, et −5 par interruption ;
- première image au-delà de **5 s** (seuil ARCEP) : −25 points et note
  plafonnée à 50.

**Bilan.** La carte « Référentiel ARCEP » du bilan affiche, pour la mesure :
la catégorie de débit et la conformité au seuil de la technologie, la
couverture radio, le taux de pages réussies et le délai de première image,
chacun avec « Conforme » ou « Non conforme » écrit en toutes lettres.

## Différence avec nPerf

nPerf publie un score en points sans plafond, et sa formule n'est pas
publique. Le score Yélé reste sur 0-100 pour être lisible et comparable d'un
test à l'autre. Pour comparer les deux applications (ISS-05), comparer les
mesures brutes (débits, latence, perte) exportées, pas les scores.
