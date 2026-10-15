# Politique de confidentialité — Yélé

*Dernière mise à jour : 15 octobre 2026 (version 2)*

> Ce texte est la version publique de celle affichée dans l'application
> (`lib/constants/privacy_policy.dart`). Les deux doivent rester identiques.

## Qui sommes-nous

Yélé mesure la qualité des réseaux mobiles au Burkina Faso. Les mesures des
utilisateurs alimentent une carte publique de couverture et des statistiques
comparant les opérateurs.

## Données collectées lors d'un test

À chaque test que vous lancez, Yélé enregistre sur votre téléphone puis envoie
à son serveur :

- les résultats des tests : débits, latence, navigation web, streaming
- votre position GPS au moment du test
- votre opérateur, le type de connexion et la technologie (2G à 5G)
- votre adresse IP publique et le fournisseur d'accès qui lui correspond
- le modèle de votre téléphone et un identifiant anonyme de l'appareil,
  calculé de façon irréversible (il ne révèle ni votre identité ni votre numéro)
- les données consommées par le test et la qualité du signal radio
- votre avis sur la qualité ressentie, si vous le donnez

## Collecte en arrière-plan (facultative)

Si vous l'activez dans les réglages, Yélé relève à intervalle régulier, même
application fermée, votre position, la technologie réseau, l'opérateur et la
puissance du signal. Aucun test de débit n'est alors effectué. Cette collecte
est désactivée par défaut, demande un accord séparé et s'arrête à tout moment
depuis la notification ou les réglages.

## Compte (facultatif)

Si vous créez un compte, Yélé conserve votre adresse e-mail, le nom que vous
choisissez et un mot de passe chiffré de façon irréversible, pour vous
permettre de retrouver vos mesures. Vous pouvez supprimer votre compte à tout
moment depuis « Mon compte » : vos mesures restent alors sur la carte, sans
lien avec vous.

## Ce que Yélé ne collecte pas

- votre numéro de téléphone ; ni votre nom ni votre e-mail sans compte
- vos contacts, messages, photos ou fichiers
- l'IMEI ou le numéro de série de votre téléphone
- aucune publicité ni outil de suivi publicitaire n'est intégré

## Utilisation des données

- construire la carte publique de couverture, où les mesures apparaissent
  comme des points sans nom ni identifiant
- calculer des statistiques par opérateur, par zone et par technologie
- détecter les anomalies et prévoir la qualité du réseau ; l'analyse
  automatique n'utilise pas votre adresse IP

Vos données ne sont ni vendues ni utilisées à des fins publicitaires.

## Services tiers

Pour fonctionner, Yélé fait appel à des services extérieurs qui voient passer
votre adresse IP :

- Render, qui héberge le serveur de mesure, et MongoDB Atlas, qui stocke les
  résultats
- OpenStreetMap, qui fournit le fond de la carte de couverture et traduit la
  position d'un test en adresse lisible pour votre historique
- YouTube, pour le test de streaming, ainsi que les sites chargés par le test
  de navigation (Google, Wikipédia, Facebook, Bing, lefaso.net)

## Vos choix et vos droits

- refuser : l'app ne fait alors aucune mesure et n'envoie rien
- retirer votre accord à tout moment depuis Réglages → Confidentialité
- effacer l'historique enregistré sur votre téléphone depuis Réglages →
  Confidentialité
- désactiver la localisation dans les paramètres Android : les tests sont
  alors bloqués, car une mesure doit être localisée pour figurer sur la carte
