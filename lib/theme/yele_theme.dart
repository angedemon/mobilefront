import 'package:flutter/material.dart';

import '../services/app_settings.dart';

/// Palette et styles repris de la maquette interactive Yélé.
class YeleColors {
  // Fonds & navigation (thème sombre)
  static const bg = Color(0xFF0E1726);
  static const header = Color(0xFF16213A);
  static const header2 = Color(0xFF1D2A47);
  static const drawerBg = Color(0xFF1B2030);

  // Marque
  static const primary = Color(0xFF0BB89C); // teal Yélé
  static const primaryDk = Color(0xFF089A83);
  static const accent = Color(0xFF19C3FF); // cyan data
  static const field = Color(0xFF0FA3DF); // bleu valeurs

  // Statuts
  static const good = Color(0xFF2BB673);
  static const warn = Color(0xFFF5A623);
  static const danger = Color(0xFFE0464B);

  // Écran de test : dégradé de fond selon le « Style de fond » choisi dans
  // les réglages (ISS-12) — vert (par défaut), bleu ou sombre.
  static const _styles = {
    'vert': [Color(0xFFCFE86B), Color(0xFFA9DD3B), Color(0xFF7FC91F)],
    'bleu': [Color(0xFF9ED8F5), Color(0xFF4FB3E8), Color(0xFF1E88C7)],
    // Gris ardoise plutôt que noir : le texte foncé des tableaux reste lisible.
    'sombre': [Color(0xFFB8C4D0), Color(0xFF8C9DAE), Color(0xFF5E7186)],
  };
  static List<Color> get _style =>
      _styles[AppSettings.backgroundStyle] ?? _styles['vert']!;
  static Color get testTop => _style[0];
  static Color get testMid => _style[1];
  static Color get testBot => _style[2];
  static const scoreRing = Color(0xFF9AD11F);

  // Surfaces claires
  static const panel = Color(0xFFF3F5F7);
  static const panel2 = Color(0xFFE7EBEF);
  static const line = Color(0xFFDDE3EA);
  static const ink = Color(0xFF1B2333);
  static const muted = Color(0xFF7C8AA0);

  // Couleurs par technologie réseau
  static const g2 = Color(0xFF1F7AE0);
  static const g3 = Color(0xFF7AC943);
  static const g4 = Color(0xFFF5921E);
  static const g4p = Color(0xFFD2353A);
  static const g5 = Color(0xFF8A3FFC);

  static LinearGradient get testGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [testTop, testMid, testBot],
      );
}

ThemeData buildYeleTheme() {
  return ThemeData(
    useMaterial3: true,
    scaffoldBackgroundColor: YeleColors.bg,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YeleColors.primary,
      primary: YeleColors.primary,
      brightness: Brightness.light,
    ),
    fontFamily: 'Roboto',
  );
}
