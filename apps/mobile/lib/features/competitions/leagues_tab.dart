import "package:flutter/material.dart";
import "package:news_api_client/news_api_client.dart";

import "../../theme/tokens.dart";
import "../../widgets/game_logo.dart";
import "../../widgets/live_dot.dart";
import "league_screen.dart";

/// Ligues en cours d'abord, puis par nom.
List<CatalogLeagueDto> sortLeagues(Iterable<CatalogLeagueDto> leagues) {
  final sorted = leagues.toList()
    ..sort((a, b) {
      if (a.live != b.live) return a.live ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
  return sorted;
}

/// Onglet « Ligues » de la page jeu (docs/04 J10) : les ligues du jeu, un tap ouvre la page de
/// la ligue (« Suivre », compétitions). Un point rouge qui respire marque une ligue dont une
/// compétition est en cours (`LiveDot` : figé en mouvement réduit).
class LeaguesTab extends StatelessWidget {
  const LeaguesTab({super.key, required this.game});

  final CatalogGameDto game;

  @override
  Widget build(BuildContext context) {
    final leagues = sortLeagues(game.leagues);
    if (leagues.isEmpty) {
      return const Center(child: Text("Aucune ligue pour l'instant.", style: TextStyle(color: AppColors.textSecondary)));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        for (final league in leagues)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: LeagueLogo(imageUrl: league.imageUrl, size: 44),
            title: Text(league.name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              league.children.length == 1 ? "1 compétition" : "${league.children.length} compétitions",
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (league.live) ...[
                  const LiveDot(),
                  const SizedBox(width: AppSpacing.xs),
                  const Text("En cours", style: TextStyle(color: AppColors.live, fontSize: AppTypography.caption, fontWeight: FontWeight.w600)),
                  const SizedBox(width: AppSpacing.sm),
                ],
                const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              ],
            ),
            onTap: () => openLeaguePage(context, league: league, game: game),
          ),
      ],
    );
  }
}
