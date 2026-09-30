import "spoiler_hold.dart";
import "package:flutter/material.dart";
import "../theme/app_theme.dart";
import "../theme/tokens.dart";

/// Dégradé d'un match, directement de la couleur dominante d'une équipe à celle de
/// l'autre (`entityAccentColorProvider`). Partagé par la tuile de liste (`EventCard`),
/// la carte de grande finale et l'en-tête de l'écran du match : un seul rendu, et pas
/// de passage par `surface` au milieu, qui faisait une bande grise (J10). `null` si
/// aucune équipe n'a de couleur ; une seule couleur s'efface vers le fond de la carte.
LinearGradient? teamsGradient(Color? colorA, Color? colorB) {
  if (colorA == null && colorB == null) return null;
  return LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      colorA?.withValues(alpha: 0.26) ?? AppColors.surface.withValues(alpha: 0),
      colorB?.withValues(alpha: 0.26) ?? AppColors.surface.withValues(alpha: 0),
    ],
  );
}

/// Logo d'équipe dans sa case (coin arrondi, pas un cercle : bannières larges et blasons
/// non circulaires) avec, en option, son score dessous. Le logo est dimensionné à la
/// case moins une marge : sans taille explicite, un logo plus grand que la case la
/// débordait (écran du match, J10). [fallback] s'affiche sans logo (initiales).
class TeamBadge extends StatelessWidget {
  const TeamBadge({super.key, required this.imageUrl, this.score, this.scoreSigma = 0, this.diameter = 44, this.fallback, this.crowned});

  final String? imageUrl;
  final num? score;

  /// Flou du score (sans spoil, J11) : 0 = net.
  final double scoreSigma;
  final double diameter;
  final String? fallback;

  /// Couronne au-dessus du logo du vainqueur d'un match terminé (J10) : `null` = pas de
  /// couronne du tout, `false` = emplacement réservé mais vide (le perdant), pour que
  /// les deux logos restent alignés.
  final bool? crowned;

  @override
  Widget build(BuildContext context) {
    final inset = 3 * diameter / 44;
    final inner = diameter - 2 * inset;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (crowned != null) ...[
          SizedBox(
            height: diameter * 0.3,
            width: diameter * 0.4,
            child: crowned! ? CustomPaint(painter: _CrownPainter()) : null,
          ),
          const SizedBox(height: 2),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.chip * diameter / 44),
          child: Container(
            width: diameter,
            height: diameter,
            color: AppColors.surfaceBorder,
            padding: EdgeInsets.all(inset),
            alignment: Alignment.center,
            child: imageUrl != null
                ? Image.network(
                    imageUrl!,
                    width: inner,
                    height: inner,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => _initials(),
                  )
                : _initials(),
          ),
        ),
        if (score != null) ...[
          const SizedBox(height: 2),
          SpoilerBlur(
            sigma: scoreSigma,
            child: Text(
              "${score!.toInt()}",
              // Taille de score proportionnelle au logo (44 → 26, la tuile
              // réduite a un logo plus petit donc un score plus petit aussi).
              style: AppTextStyles.bodyLargeStrong.copyWith(fontSize: AppTypography.heroScore * diameter / 44, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ],
    );
  }

  Widget _initials() => fallback == null ? const SizedBox.shrink() : Text(fallback!, style: const TextStyle(fontWeight: FontWeight.w700));
}

/// Couronne dorée (trois pointes sur un bandeau), dessinée : Material n'a pas d'icône couronne.
class _CrownPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.85)
      ..lineTo(0, h * 0.15)
      ..lineTo(w * 0.26, h * 0.55)
      ..lineTo(w * 0.5, 0)
      ..lineTo(w * 0.74, h * 0.55)
      ..lineTo(w, h * 0.15)
      ..lineTo(w, h * 0.85)
      ..close();
    canvas.drawPath(path, Paint()..color = AppColors.gold);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.88, w, h * 0.12), Paint()..color = AppColors.gold);
  }

  @override
  bool shouldRepaint(_CrownPainter oldDelegate) => false;
}
