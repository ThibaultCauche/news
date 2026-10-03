import "package:flutter/widgets.dart";

/// Tokens de la V2 des maquettes (`docs/02-design-maquettes-mobiles.md`).
/// Seul fichier à contenir des couleurs et des rayons en dur (règle 12 de
/// `CLAUDE.md`) : le reste de l'appli lit `AppColors`/`AppRadii`.
abstract final class AppColors {
  static const background = Color(0xFF08090B);
  static const surface = Color(0xFF16171B);
  static const surfaceBorder = Color(0x14FFFFFF); // blanc 8 %, carte standard
  static const surfaceBorderHighlight = Color(0x1AFFFFFF); // blanc 10 %, carte à dégradé / mise en avant
  static const surfaceHighlight = Color(0x12FFFFFF); // reflet blanc 7 %
  static const glass = Color(0xFF1C1C21);
  static const glassOpacity = 0.72; // mesuré sur 01/03/06/09/17 (docs/maquettes/specs/commun.md)
  static const glassBorder = Color(0x1FFFFFFF); // blanc 12 %

  static const textPrimary = Color(0xFFF5F5F7);
  static const textSecondary = Color(0x8CF5F5F7); // blanc 55 %
  static const textTertiary = Color(0x4DF5F5F7); // blanc 30 %

  /// Rouge : en direct, "tu es ici". Jamais utilisé pour distinguer une catégorie.
  static const live = Color(0xFFFF4655);

  /// Or : ce que je suis (mon équipe, mes suivis).
  static const gold = Color(0xFFFFC940);

  /// Laiton mat : décoratif seulement (titres, filets, cadre de grande finale,
  /// J16). Ne dit rien de « mon équipe » : cela reste le rôle de `gold`.
  static const brass = Color(0xFFB79B62);

  /// Vert : victoire, qualifié, validé.
  static const win = Color(0xFF30D158);

  /// Vert mousse, assorti au laiton : la ligne gagnante et les qualifiés des cases de bracket
  /// (J20). Le vert vif `win` reste celui des scores et des résultats ailleurs.
  static const moss = Color(0xFF7C9A5E);
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
  /// Rayon dominant, mesuré 21 fois sur les cartes pleine largeur (358 px)
  /// des écrans 01/03/06/09/17 (docs/maquettes/specs/commun.md).
  static const card = 16.0;
  static const chip = 14.0;
  static const pill = 999.0;
}

abstract final class AppSpacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;

  /// Écart entre cartes d'une même rangée (grille de stats, grille 2×2),
  /// mesuré identique sur plusieurs écrans — distinct de `sm` (8).
  static const cardGap = 10.0;
}

/// Échelle typographique mesurée sur les `<text>` réels des SVG de
/// `docs/maquettes/svg/` (police Inter partout) — voir
/// `docs/maquettes/specs/commun.md`. Tailles en px, tracking en em (à
/// multiplier par la taille pour obtenir un `letterSpacing` Flutter en px).
/// `app_theme.dart` construit les `TextStyle` à partir de ces valeurs.
abstract final class AppTypography {
  static const display = 34.0;
  static const heroScore = 26.0;
  static const title = 20.0;
  static const cardTitle = 19.0;
  static const bodyLarge = 15.0;
  static const body = 14.0;
  static const caption = 13.0;
  static const label = 12.0;
  static const eyebrow = 12.0;
  static const tabLabel = 10.0;

  static const trackingDisplay = -0.025;
  static const trackingHeroScore = -0.02;
  static const trackingTitle = -0.015;
  static const trackingCardTitle = -0.012;
  static const trackingBodyLarge = -0.006;
  static const trackingBody = 0.0;
  static const trackingCaption = 0.0;
  static const trackingLabel = 0.0;
  static const trackingEyebrow = 0.04;
  static const trackingTabLabel = 0.01;

  /// Ratio hauteur de ligne / taille de police, mesuré identique (×1,2) sur
  /// les 3 blocs multi-lignes trouvés dans les maquettes (14, 19 et 12 px).
  static const lineHeight = 1.2;
}

/// Entrées ease-out, jamais plus de 300 ms, `transform`/`opacity` uniquement
/// (docs/02 — passe "apple-design" + "emil-design-eng").
abstract final class AppMotion {
  static const enter = Cubic(0.23, 1, 0.32, 1);
  static const enterDuration = Duration(milliseconds: 250);
  static const microDuration = Duration(milliseconds: 120);
  static const livePulseDuration = Duration(milliseconds: 1200);
}
