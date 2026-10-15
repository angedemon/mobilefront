import 'package:flutter/material.dart';

import '../constants/privacy_policy.dart';
import '../theme/yele_theme.dart';

/// Politique de confidentialité complète. Ouverte depuis l'écran de
/// consentement et depuis les réglages, d'où un simple bouton retour plutôt
/// que le tiroir de navigation.
class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.panel,
      appBar: AppBar(
        backgroundColor: YeleColors.header,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Politique de confidentialité',
            style: TextStyle(fontSize: 17)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          const Text('Dernière mise à jour : $PRIVACY_POLICY_DATE',
              style: TextStyle(fontSize: 13, color: YeleColors.muted)),
          for (final section in PRIVACY_POLICY) ..._section(section),
          if (PRIVACY_CONTACT_EMAIL.isNotEmpty)
            ..._section(const PolicySection('Nous contacter', paragraphs: [
              'Pour consulter ou faire supprimer les mesures envoyées depuis '
                  'votre téléphone, écrivez à $PRIVACY_CONTACT_EMAIL.',
            ])),
        ],
      ),
    );
  }

  List<Widget> _section(PolicySection section) => [
        const SizedBox(height: 22),
        Text(section.title,
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: YeleColors.ink)),
        const SizedBox(height: 8),
        for (final p in section.paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(p, style: _body),
          ),
        for (final b in section.bullets) PolicyBullet(b),
      ];
}

const _body = TextStyle(fontSize: 14, height: 1.45, color: YeleColors.ink);

/// Ligne à puce, partagée avec l'écran de consentement.
class PolicyBullet extends StatelessWidget {
  final String text;
  final Color color;
  const PolicyBullet(this.text, {super.key, this.color = YeleColors.ink});

  @override
  Widget build(BuildContext context) {
    final style = _body.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('•  ', style: style),
          Expanded(child: Text(text, style: style)),
        ],
      ),
    );
  }
}
