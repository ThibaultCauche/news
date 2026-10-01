import "package:flutter/material.dart";
import "tokens.dart";

/// Un style Inter construit depuis `AppTypography` (taille, tracking en em
/// converti en px, hauteur de ligne mesurée). `docs/maquettes/specs/commun.md`.
/// Inter est chargée en asset local (`pubspec.yaml`), pas via `google_fonts`.
TextStyle _inter(double size, FontWeight weight, double trackingEm, {Color? color}) {
  return TextStyle(
    fontFamily: "Inter",
    fontSize: size,
    fontWeight: weight,
    letterSpacing: size * trackingEm,
    height: AppTypography.lineHeight,
    color: color ?? AppColors.textPrimary,
  );
}

/// Cinzel, police d'affichage réservée aux titres et au « VS » (J16), toujours en laiton ; le texte, les scores
/// et les chiffres restent en Inter.
TextStyle _cinzel(double size, FontWeight weight) {
  return TextStyle(fontFamily: "Cinzel", fontSize: size, fontWeight: weight, height: AppTypography.lineHeight, color: AppColors.brass);
}

/// Styles texte mesurés sur les maquettes sans équivalent direct dans le
/// `TextTheme` Material (`docs/maquettes/specs/commun.md`). Utilisés en
/// `.copyWith(color: ...)` selon le contexte (texte primaire/secondaire/or…).
abstract final class AppTextStyles {
  static TextStyle get pageTitle => _cinzel(AppTypography.display, FontWeight.w700);
  static TextStyle get sectionTitle => _cinzel(AppTypography.title, FontWeight.w600);
  static TextStyle versus(double size) => _cinzel(size, FontWeight.w700);
  static TextStyle get heroScore =>
      _inter(AppTypography.heroScore, FontWeight.w700, AppTypography.trackingHeroScore);
  static TextStyle get cardTitle =>
      _inter(AppTypography.cardTitle, FontWeight.w700, AppTypography.trackingCardTitle);
  static TextStyle get bodyLargeStrong =>
      _inter(AppTypography.bodyLarge, FontWeight.w600, AppTypography.trackingBodyLarge);
  static TextStyle get body => _inter(AppTypography.body, FontWeight.w400, AppTypography.trackingBody);
  static TextStyle get bodyStrong => _inter(AppTypography.body, FontWeight.w600, AppTypography.trackingBody);
  static TextStyle get captionStrong =>
      _inter(AppTypography.caption, FontWeight.w600, AppTypography.trackingCaption);
  static TextStyle get label => _inter(AppTypography.label, FontWeight.w500, AppTypography.trackingLabel);
  static TextStyle get tabLabel =>
      _inter(AppTypography.tabLabel, FontWeight.w500, AppTypography.trackingTabLabel);
  static TextStyle get tabLabelActive =>
      _inter(AppTypography.tabLabel, FontWeight.w600, AppTypography.trackingTabLabel);
}

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = base.textTheme.apply(fontFamily: "Inter").copyWith(
    headlineLarge: _inter(AppTypography.display, FontWeight.w700, AppTypography.trackingDisplay),
    titleLarge: _inter(AppTypography.title, FontWeight.w700, AppTypography.trackingTitle),
    bodyMedium: _inter(AppTypography.bodyLarge, FontWeight.w400, AppTypography.trackingBodyLarge),
    bodySmall: _inter(AppTypography.caption, FontWeight.w400, AppTypography.trackingCaption, color: AppColors.textSecondary),
    labelSmall: _inter(
      AppTypography.eyebrow,
      FontWeight.w600,
      AppTypography.trackingEyebrow,
      color: AppColors.textSecondary,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    // `secondary`/`error` par défaut de `ThemeData.dark()` restent le violet/
    // rouge Material générique si on ne les recouvre pas : aucun composant ne
    // doit laisser passer une couleur hors palette (règle 12 de CLAUDE.md).
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.background,
      primary: AppColors.gold,
      onPrimary: AppColors.background,
      secondary: AppColors.gold,
      onSecondary: AppColors.background,
      error: AppColors.live,
    ),
    textTheme: textTheme,
    appBarTheme: const AppBarThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
        side: BorderSide(color: AppColors.surfaceBorder),
      ),
    ),
    dividerColor: AppColors.brass.withValues(alpha: 0.25),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brass.withValues(alpha: 0.12),
        foregroundColor: AppColors.brass,
        side: const BorderSide(color: AppColors.brass),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.chip)),
        textStyle: const TextStyle(fontFamily: "Inter", fontWeight: FontWeight.w600),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: AppColors.brass,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
        side: BorderSide(color: AppColors.brass, width: 0.8),
      ),
    ),
  );
}
