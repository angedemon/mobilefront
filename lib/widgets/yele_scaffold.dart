import 'package:flutter/material.dart';
import '../theme/yele_theme.dart';
import 'yele_drawer.dart';

/// Échafaudage partagé : app bar sombre + tiroir, repris de la maquette.
class YeleScaffold extends StatelessWidget {
  final String title;
  final String route;
  final Widget body;

  const YeleScaffold({
    super.key,
    required this.title,
    required this.route,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: YeleColors.bg,
      drawer: YeleDrawer(current: route),
      appBar: AppBar(
        backgroundColor: YeleColors.header,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFFCFD6E0)),
        title: Row(
          children: [
            const Text.rich(
              TextSpan(
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: Colors.white),
                children: [
                  TextSpan(text: 'Yé'),
                  TextSpan(text: 'lé', style: TextStyle(color: YeleColors.primary)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF9FB0C6)),
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
      body: body,
    );
  }
}
