import "package:flutter/material.dart";
import "package:news_api_client/news_api_client.dart";

import "../../theme/tokens.dart";
import "../../widgets/competition_follow_button.dart";
import "../../widgets/game_logo.dart";
import "game_screen.dart";

/// Page d'une ligue (VCT, Esports World Cup…) : son logo, le bouton « Suivre » et la
/// liste de ses compétitions (docs/04 J10). Construite depuis le catalogue déjà chargé,
/// sans appel réseau de plus. Suivre une ligue notifie pour tous ses matchs
/// (abonnement hiérarchique) : c'est ici qu'on s'en désabonne.
class LeagueScreen extends StatelessWidget {
  const LeagueScreen({super.key, required this.league, required this.game});

  final CatalogLeagueDto league;
  final CatalogGameDto game;

  @override
  Widget build(BuildContext context) {
    final series = league.children.toList();
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 160,
        leading: TextButton.icon(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
          label: Text(game.name, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
        ),
        actions: [CompetitionFollowButton(competitionId: league.id, name: league.name)],
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          Row(
            children: [
              LeagueLogo(imageUrl: league.imageUrl, size: 56),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(league.name, style: Theme.of(context).textTheme.headlineMedium),
                    Text("Ligue · ${game.name}", style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text("COMPÉTITIONS", style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          if (series.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: AppSpacing.sm),
              child: Text("Aucune compétition pour l'instant.", style: TextStyle(color: AppColors.textSecondary)),
            ),
          for (final serie in series)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(serie.name),
              trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
              onTap: () => openCompetitionPage(context, id: serie.id, name: serie.name),
            ),
        ],
      ),
    );
  }
}

/// Ouvre la page de la ligue [league] du jeu [game].
void openLeaguePage(BuildContext context, {required CatalogLeagueDto league, required CatalogGameDto game}) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeagueScreen(league: league, game: game)));
}
