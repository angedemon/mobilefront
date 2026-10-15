import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../constants/privacy_policy.dart';
import '../services/consent_service.dart';
import '../theme/yele_theme.dart';
import 'privacy_policy_screen.dart';

/// Écran affiché au premier lancement, et à nouveau si la politique change
/// ou si l'utilisateur retire son accord. Aucun test — donc aucun envoi au
/// serveur — n'est possible avant d'avoir accepté.
class ConsentScreen extends StatelessWidget {
  const ConsentScreen({super.key});

  Future<void> _accept(BuildContext context) async {
    await ConsentService().accept();
    if (!context.mounted) return;
    Navigator.of(context).pushReplacementNamed('/full');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
                children: [
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                      children: [
                        TextSpan(text: 'Yé'),
                        TextSpan(
                            text: 'lé',
                            style: TextStyle(color: YeleColors.primary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text('Mesure de la qualité réseau',
                      style: TextStyle(fontSize: 14, color: Color(0xFF9FB0C6))),
                  const SizedBox(height: 28),
                  const Text('Avant de commencer',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 12),
                  const Text(
                    'Vos mesures alimentent la carte publique de couverture '
                    'du Burkina Faso. Pour cela, chaque test que vous lancez '
                    'envoie au serveur Yélé :',
                    style: _text,
                  ),
                  const SizedBox(height: 12),
                  for (final item in CONSENT_SUMMARY)
                    PolicyBullet(item, color: const Color(0xFFE7ECF4)),
                  const SizedBox(height: 12),
                  const Text(
                    'Yélé ne collecte ni votre nom, ni votre numéro, ni vos '
                    'contacts, et ne contient aucune publicité. La collecte en '
                    'arrière-plan reste désactivée tant que vous ne l\'activez '
                    'pas dans les réglages.',
                    style: _text,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: YeleColors.accent),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyScreen())),
                      child: const Text('Lire la politique de confidentialité'),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: YeleColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () => _accept(context),
                    child: const Text('J\'accepte et je continue',
                        style: TextStyle(fontSize: 16)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF9FB0C6)),
                    // Refuser ferme l'app : sans envoi au serveur, aucune
                    // fonction de Yélé n'a de sens.
                    onPressed: () => SystemNavigator.pop(),
                    child: const Text('Refuser et quitter'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _text = TextStyle(fontSize: 15, height: 1.45, color: Color(0xFFCFD6E0));
