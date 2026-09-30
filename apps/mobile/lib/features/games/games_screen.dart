import "package:flutter/material.dart";
import "../../theme/app_theme.dart";
import "../../theme/tokens.dart";
import "../../widgets/page_title.dart";
import "../../widgets/section_card.dart";
import "../predictions/predictions_screen.dart";

/// Onglet « Jeux » (docs/04 J11, ex-placeholder « Jeu du jour ») : la porte d'entrée de tous les
/// jeux de l'appli. Pour l'instant un seul, les pronostics ; d'autres viendront s'ajouter à la liste.
class GamesScreen extends StatelessWidget {
  const GamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          const PageTitle("Jeux"),
          const SizedBox(height: AppSpacing.xs),
          const Text("Joue avec les matchs de l'appli, seul ou entre amis.", style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.lg),
          _GameTile(
            icon: Icons.emoji_events_outlined,
            title: "Pronostics",
            caption: "Devine les résultats en points fictifs et compare-toi à tes amis.",
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PredictionsScreen())),
          ),
        ],
      ),
    );
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({required this.icon, required this.title, required this.caption, required this.onTap});

  final IconData icon;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, color: AppColors.gold, size: 32),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.cardTitle),
                  Text(caption, style: const TextStyle(color: AppColors.textSecondary, fontSize: AppTypography.caption)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
