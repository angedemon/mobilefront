import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../constants/config.dart';
import '../services/device_identity_service.dart';
import '../theme/yele_theme.dart';

/// Assistance (IMP-02) : questions fréquentes et formulaire de contact.
///
/// Le formulaire envoie le message au backend Yélé (POST /api/feedback) :
/// aucune messagerie à configurer sur le téléphone.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faq = [
    (
      'Pourquoi le GPS est-il obligatoire ?',
      'Chaque mesure est placée sur la carte publique de couverture. Sans '
          'position, elle ne servirait à rien : le test est donc bloqué tant '
          'que la localisation est désactivée.'
    ),
    (
      'Combien de données un test consomme-t-il ?',
      'Cela dépend de votre débit : quelques dizaines de Mo pour un test '
          'complet en 4G, davantage en 5G ou en Wi-Fi rapide. La consommation '
          'exacte s\'affiche à la fin de chaque test et dans l\'historique. '
          'Réglages → Paramètres techniques permet de raccourcir les mesures '
          'et de désactiver le test 4K.'
    ),
    (
      'Pourquoi mes résultats diffèrent-ils de nPerf ?',
      'Le débit se mesure jusqu\'à un serveur : un serveur différent, plus ou '
          'moins éloigné, donne un résultat différent. L\'heure, la position et '
          'l\'encombrement du réseau comptent aussi. Comparez des tests faits '
          'au même endroit, à la même heure, avec le même téléphone.'
    ),
    (
      'Que signifie le score sur 100 ?',
      'Il combine débits, latence, navigation web et streaming. 80 et plus : '
          'excellent ; 60 à 79 : bon ; 40 à 59 : moyen ; 20 à 39 : faible ; '
          'moins de 20 : très faible.'
    ),
    (
      'Que sont RSRP, RSRQ et SINR ?',
      'Des mesures de la qualité radio en 4G/5G. RSRP : puissance reçue '
          '(au-dessus de -90 dBm, c\'est bon). RSRQ : qualité du signal '
          '(au-dessus de -10 dB, c\'est bon). SINR : rapport signal/bruit (plus '
          'il est élevé, mieux c\'est). Ils ne sont relevés que pour un test '
          'sur le réseau mobile.'
    ),
    (
      'J\'ai deux SIM : laquelle est testée ?',
      'Celle que vous avez choisie pour les données mobiles dans les '
          'paramètres Android. Son emplacement (SIM 1 ou SIM 2) est indiqué '
          'dans le résultat.'
    ),
    (
      'Mes données personnelles sont-elles partagées ?',
      'Non. Yélé ne collecte ni votre nom, ni votre numéro, ni vos contacts. '
          'Le détail est dans Réglages → Confidentialité.'
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.panel,
      appBar: AppBar(
        backgroundColor: YeleColors.header,
        foregroundColor: Colors.white,
        title: const Text('Aide et contact', style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 18, 18, 6),
            child: Text('Questions fréquentes',
                style: TextStyle(
                    color: YeleColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          for (final (q, a) in _faq)
            ExpansionTile(
              title: Text(q, style: const TextStyle(fontSize: 15)),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              children: [
                Text(a, style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 22, 18, 6),
            child: Text('Contactez-nous',
                style: TextStyle(
                    color: YeleColors.primary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
          ),
          const _ContactForm(),
        ],
      ),
    );
  }
}

class _ContactForm extends StatefulWidget {
  const _ContactForm();

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _message = TextEditingController();
  final _email = TextEditingController();
  String _topic = 'Problème';
  bool _sending = false;

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.length < 5) {
      _snack('Écrivez votre message (au moins quelques mots).');
      return;
    }
    setState(() => _sending = true);
    try {
      await Dio(BaseOptions(
        baseUrl: API_BASE_URL,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 90),
      )).post('/api/feedback', data: {
        'topic': _topic,
        'message': text,
        'email': _email.text.trim(),
        'deviceId': await DeviceIdentityService().deviceId(),
        'appVersion': APP_VERSION,
      });
      _message.clear();
      _snack('Message envoyé. Merci !');
    } catch (_) {
      _snack('Envoi impossible. Vérifiez la connexion et réessayez.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _topic,
            decoration: const InputDecoration(labelText: 'Sujet'),
            items: const ['Problème', 'Suggestion', 'Question', 'Autre']
                .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                .toList(),
            onChanged: (v) => setState(() => _topic = v ?? _topic),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _message,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
                labelText: 'Votre message', alignLabelWithHint: true),
          ),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'E-mail (facultatif, pour vous répondre)'),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: _sending ? null : _send,
            icon: _sending
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Envoyer'),
          ),
        ],
      ),
    );
  }
}
