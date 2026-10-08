import "package:flutter/cupertino.dart" show CupertinoPageTransitionsBuilder;
import "package:flutter/material.dart";
import "../widgets/responsive.dart";
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
  /// Scores et gros chiffres (J16) : Cinzel en blanc, pour rester lisibles en 3 secondes.
  static TextStyle score(double size) => _cinzel(size, FontWeight.w700).copyWith(color: AppColors.textPrimary);
  static TextStyle get heroScore => score(AppTypography.heroScore);
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
    headlineMedium: _cinzel(28, FontWeight.w700),
    headlineSmall: _cinzel(22, FontWeight.w600),
    headlineLarge: _inter(AppTypography.display, FontWeight.w700, AppTypography.trackingDisplay),
    titleLarge: _inter(AppTypography.title, FontWeight.w700, AppTypography.trackingTitle),
    bodyMedium: _inter(AppTypography.bodyLarge, FontWeight.w400, AppTypography.trackingBodyLarge),
    bodySmall: _inter(AppTypography.caption, FontWeight.w400, AppTypography.trackingCaption, color: AppColors.textSecondary),
    labelSmall: _inter(
      AppTypography.eyebrow,
      FontWeight.w600,
      AppTypography.trackingEyebrow,
      color: AppColors.brass,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    // `secondary`/`error` par défaut de `ThemeData.dark()` restent le violet/
    // rouge Material générique si on ne les recouvre pas : aucun composant ne
    // doit laisser passer une couleur hors palette (règle 12 de CLAUDE.md).
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.background,
      primary: AppColors.brass,
      onPrimary: AppColors.background,
      secondary: AppColors.brass,
      onSecondary: AppColors.background,
      error: AppColors.live,
    ),
    textTheme: textTheme,
    appBarTheme: AppBarThemeData(
      titleTextStyle: AppTextStyles.sectionTitle,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      foregroundColor: AppColors.textPrimary,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadii.card))),
    ),
    dividerColor: AppColors.brass.withValues(alpha: 0.25),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brass,
        side: const BorderSide(color: AppColors.brass),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.chip)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.background : AppColors.textSecondary),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brass : AppColors.surface),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brass : AppColors.textTertiary),
    ),
    chipTheme: ChipThemeData(
      selectedColor: AppColors.brass.withValues(alpha: 0.25),
      checkmarkColor: AppColors.brass,
      side: BorderSide(color: AppColors.brass.withValues(alpha: 0.5)),
    ),
    checkboxTheme: CheckboxThemeData(
      side: const BorderSide(color: AppColors.brass, width: 1.2),
      checkColor: const WidgetStatePropertyAll(AppColors.background),
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? AppColors.brass : Colors.transparent),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: AppColors.brass)),
    expansionTileTheme: const ExpansionTileThemeData(iconColor: AppColors.brass, collapsedIconColor: AppColors.textSecondary),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.brass.withValues(alpha: 0.12),
        foregroundColor: AppColors.brass,
        side: const BorderSide(color: AppColors.brass),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadii.chip)),
        textStyle: const TextStyle(fontFamily: "Inter", fontWeight: FontWeight.w600),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: WidePageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.iOS: WidePageTransitions(CupertinoPageTransitionsBuilder()),
        TargetPlatform.windows: WidePageTransitions(ZoomPageTransitionsBuilder()),
        TargetPlatform.macOS: WidePageTransitions(CupertinoPageTransitionsBuilder()),
        TargetPlatform.linux: WidePageTransitions(ZoomPageTransitionsBuilder()),
      },
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      constraints: BoxConstraints(maxWidth: kPageMaxWidth),
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
