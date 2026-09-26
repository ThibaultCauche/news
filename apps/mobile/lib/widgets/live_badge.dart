import "package:flutter/material.dart";
import "../theme/tokens.dart";
import "live_dot.dart";

/// Badge « EN DIRECT » / « CHAMPIONS · ICI » (`docs/maquettes/specs/commun.md`,
/// `17-accueil.md`, `01-valorant-saison.md`) : pilule, fond de la couleur à
/// 20 %, texte 10/700/+6 % plein, point animé en tête.
class LiveBadge extends StatelessWidget {
  const LiveBadge(this.text, {super.key, this.color = AppColors.live});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(AppRadii.pill)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            LiveDot(size: 6, color: color),
            const SizedBox(width: 4),
            Text(
              text,
              style: TextStyle(
                fontFamily: "Inter",
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 10 * 0.06,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
