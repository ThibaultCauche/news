import "package:flutter/widgets.dart";

/// Tokens de la V2 des maquettes (`docs/02-design-maquettes-mobiles.md`).
/// Seul fichier à contenir des couleurs et des rayons en dur (règle 12 de
/// `CLAUDE.md`) : le reste de l'appli lit `AppColors`/`AppRadii`.
abstract final class AppColors {
  static const background = Color(0xFF08090B);
  static const surface = Color(0xFF16171B);
  static const surfaceBorder = Color(0x14FFFFFF); // blanc 8 %
  static const surfaceHighlight = Color(0x12FFFFFF); // reflet blanc 7 %
  static const glass = Color(0xFF1C1C21);

  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0x8CF5F5F7); // blanc 55 %
  static const textTertiary = Color(0x4DF5F5F7); // blanc 30 %

  /// Rouge : en direct, "tu es ici". Jamais utilisé pour distinguer une catégorie.
  static const live = Color(0xFFFF4655);

  /// Or : ce que je suis (mon équipe, mes suivis).
  static const gold = Color(0xFFFFC940);

  /// Vert : victoire, qualifié, validé.
  static const win = Color(0xFF30D158);
  static const loss = Color(0x66F5F5F7); // gris neutre pour une défaite
}

/// Dégradés sombres teintés pour les grandes cartes "événement" et les
/// vignettes, en attendant de vrais visuels (`docs/02`).
abstract final class AppGradients {
  static const highlights = [
    [Color(0xFF1B2340), Color(0xFF0B0F1E)],
    [Color(0xFF35301A), Color(0xFF14120A)],
    [Color(0xFF2A1B36), Color(0xFF120B18)],
    [Color(0xFF17322A), Color(0xFF0A1512)],
  ];
}

abstract final class AppRadii {
  static const card = 20.0;
  static const chip = 14.0;
  static const pill = 999.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
}

/// Entrées ease-out, jamais plus de 300 ms, `transform`/`opacity` uniquement
/// (docs/02 — passe "apple-design" + "emil-design-eng").
abstract final class AppMotion {
  static const enter = Cubic(0.23, 1, 0.32, 1);
  static const enterDuration = Duration(milliseconds: 250);
  static const microDuration = Duration(milliseconds: 120);
  static const livePulseDuration = Duration(milliseconds: 1200);
}
