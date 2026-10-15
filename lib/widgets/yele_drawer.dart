import 'package:flutter/material.dart';
import '../services/app_settings.dart';
import '../theme/yele_theme.dart';

/// Tiroir de navigation latéral, repris de la maquette.
class YeleDrawer extends StatelessWidget {
  /// Route actuellement affichée (pour surligner l'entrée active).
  final String current;
  const YeleDrawer({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: YeleColors.drawerBg,
      child: SafeArea(
        child: Column(
          children: [
            _header(),
            _item(context, Icons.hexagon_outlined, tr('Test complet', 'Full test'), '/full'),
            _item(context, Icons.speed, 'Speed test', '/speed'),
            _item(context, Icons.public, tr('Test de navigation', 'Browsing test'), '/browsing'),
            _item(context, Icons.play_circle_outline, tr('Test de streaming', 'Streaming test'),
                '/streaming'),
            _item(context, Icons.history, tr('Historique', 'History'), '/history'),
            _item(context, Icons.map_outlined, tr('Cartes de couverture', 'Coverage maps'),
                '/coverage'),
            _item(context, Icons.settings, tr('Réglages', 'Settings'), '/settings'),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 21,
            backgroundColor: YeleColors.primary,
            child: Text('Ye',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Yélé',
                  style: TextStyle(
                      color: YeleColors.ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              Text(tr('Mesure de la qualité réseau', 'Network quality testing'),
                  style: const TextStyle(color: YeleColors.muted, fontSize: 12)),
            ],
          ),
          const Spacer(),
          const Text('v1.0.0',
              style: TextStyle(color: YeleColors.muted, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String label, String route) {
    final active = route == current;
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // ferme le tiroir
        if (route != current) {
          Navigator.of(context).pushReplacementNamed(route);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: active ? YeleColors.primary : const Color(0xFFE7ECF4)),
            const SizedBox(width: 14),
            Text(label,
                style: TextStyle(
                    fontSize: 15,
                    color: active ? YeleColors.primary : const Color(0xFFE7ECF4))),
          ],
        ),
      ),
    );
  }
}
