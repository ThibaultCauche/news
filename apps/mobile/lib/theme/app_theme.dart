import "package:flutter/material.dart";
import "package:google_fonts/google_fonts.dart";
import "tokens.dart";

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).copyWith(
    headlineLarge: GoogleFonts.inter(
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -34 * 0.025,
      color: AppColors.textPrimary,
    ),
    titleLarge: GoogleFonts.inter(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    bodyMedium: GoogleFonts.inter(fontSize: 15, color: AppColors.textPrimary),
    bodySmall: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
    labelSmall: GoogleFonts.inter(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 11 * 0.03,
      color: AppColors.textSecondary,
    ),
  );

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: base.colorScheme.copyWith(
      surface: AppColors.background,
      primary: AppColors.gold,
    ),
    textTheme: textTheme,
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadii.card)),
        side: BorderSide(color: AppColors.surfaceBorder),
      ),
    ),
    dividerColor: AppColors.surfaceBorder,
  );
}
