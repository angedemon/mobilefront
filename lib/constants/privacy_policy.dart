// Texte de la politique de confidentialité, affiché dans l'app
// (écran /privacy). Toute modification des données collectées doit être
// reportée ici ET s'accompagner d'une hausse de ConsentService.policyVersion.

/// Adresse à laquelle écrire pour exercer ses droits (accès, suppression).
/// TODO: renseigner avant publication sur le Play Store.
const String PRIVACY_CONTACT_EMAIL = '';

/// Date de dernière mise à jour affichée en tête de la politique.
const String PRIVACY_POLICY_DATE = '15 octobre 2026';

class PolicySection {
  final String title;
  final List<String> paragraphs;
  final List<String> bullets;

  const PolicySection(this.title,
      {this.paragraphs = const [], this.bullets = const []});
}

/// Ce qui est collecté, résumé pour l'écran de consentement.
const List<String> CONSENT_SUMMARY = [
  'les résultats des tests : débits, latence, navigation web, streaming',
  'votre position GPS au moment du test',
  'votre opérateur, le type de connexion et la technologie (2G à 5G)',
  'votre adresse IP publique et le fournisseur d\'accès qui lui correspond',
  'le modèle de votre téléphone',
  'votre avis sur la qualité ressentie, si vous le donnez',
];

const List<PolicySection> PRIVACY_POLICY = [
  PolicySection(
    'Qui sommes-nous',
    paragraphs: [
      'Yélé mesure la qualité des réseaux mobiles au Burkina Faso. Les '
          'mesures des utilisateurs alimentent une carte publique de '
          'couverture et des statistiques comparant les opérateurs.',
    ],
  ),
  PolicySection(
    'Données collectées lors d\'un test',
    paragraphs: [
      'À chaque test que vous lancez, Yélé enregistre sur votre téléphone '
          'puis envoie à son serveur :',
    ],
    bullets: CONSENT_SUMMARY,
  ),
  PolicySection(
    'Collecte en arrière-plan (facultative)',
    paragraphs: [
      'Si vous l\'activez dans les réglages, Yélé relève à intervalle '
          'régulier, même application fermée, votre position, la technologie '
          'réseau, l\'opérateur et la puissance du signal. Aucun test de débit '
          'n\'est alors effectué. Cette collecte est désactivée par défaut, '
          'demande un accord séparé et s\'arrête à tout moment depuis la '
          'notification ou les réglages.',
    ],
  ),
  PolicySection(
    'Ce que Yélé ne collecte pas',
    bullets: [
      'votre nom, votre numéro de téléphone ou votre adresse e-mail',
      'vos contacts, messages, photos ou fichiers',
      'l\'IMEI ou le numéro de série de votre téléphone',
      'aucune publicité ni outil de suivi publicitaire n\'est intégré',
    ],
  ),
  PolicySection(
    'Utilisation des données',
    bullets: [
      'construire la carte publique de couverture, où les mesures '
          'apparaissent comme des points sans nom ni identifiant',
      'calculer des statistiques par opérateur, par zone et par technologie',
      'détecter les anomalies et prévoir la qualité du réseau ; l\'analyse '
          'automatique n\'utilise pas votre adresse IP',
    ],
    paragraphs: [
      'Vos données ne sont ni vendues ni utilisées à des fins publicitaires.',
    ],
  ),
  PolicySection(
    'Services tiers',
    paragraphs: [
      'Pour fonctionner, Yélé fait appel à des services extérieurs qui voient '
          'passer votre adresse IP :',
    ],
    bullets: [
      'Render, qui héberge le serveur de mesure, et MongoDB Atlas, qui '
          'stocke les résultats',
      'OpenStreetMap, qui fournit le fond de la carte de couverture',
      'YouTube, pour le test de streaming, ainsi que les sites chargés par '
          'le test de navigation (Google, Wikipédia, Facebook, Bing, '
          'lefaso.net)',
    ],
  ),
  PolicySection(
    'Vos choix et vos droits',
    bullets: [
      'refuser : l\'app ne fait alors aucune mesure et n\'envoie rien',
      'retirer votre accord à tout moment depuis Réglages → Confidentialité',
      'effacer l\'historique enregistré sur votre téléphone depuis '
          'Réglages → Confidentialité',
      'désactiver le GPS dans Réglages → Général : seule la position '
          'approximative déduite de l\'adresse IP (niveau ville) accompagne '
          'alors vos mesures',
    ],
  ),
];
