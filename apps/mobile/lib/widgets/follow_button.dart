import "package:flutter/material.dart";
import "../theme/tokens.dart";
import "../theme/app_theme.dart";

/// Bouton Suivre/Suivi (`docs/maquettes/specs/commun.md`,
/// `01-valorant-saison.md`, `17-accueil.md`) : pilule (`AppRadii.pill`).
/// - `following: false` (pas encore suivi, sur fond sombre/carte à dégradé) :
///   fond blanc plein, texte sombre — un appel à l'action visible.
/// - `following: true` : fond or 14 %, texte or, avec une coche — discret,
///   on ne suit déjà plus l'attention.
class FollowButton extends StatelessWidget {
  const FollowButton({super.key, required this.following, this.onPressed, this.label});

  final bool following;

  /// Remplace « Suivre »/« Suivi » (ex. « Suivi via VCT »).
  final String? label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final textStyle = AppTextStyles.captionStrong.copyWith(color: following ? AppColors.gold : AppColors.background);
    return GestureDetector(
      onTap: onPressed,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: following ? AppColors.gold.withValues(alpha: 0.14) : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (following) ...[
                Icon(Icons.check, size: 14, color: AppColors.gold),
                const SizedBox(width: 4),
              ],
              Flexible(child: Text(label ?? (following ? "Suivi" : "Suivre"), style: textStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}
