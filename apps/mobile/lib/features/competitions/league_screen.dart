import "package:flutter/material.dart";
import "../learn/learn_screen.dart";
import "package:news_api_client/news_api_client.dart";

import "../../theme/tokens.dart";
import "../../widgets/game_logo.dart";
import "follow_league_sheet.dart";
import "game_screen.dart";

/// Page d'une ligue (VCT, Esports World Cup…) : son logo, le bouton « Suivre » et la
/// liste de ses compétitions (docs/04 J10). Construite depuis le catalogue déjà chargé,
/// sans appel réseau de plus. « Suivre » ouvre le choix de ce qu'on suit (toute la ligue,
/// qui notifie pour tous ses matchs, ou certaines familles de compétitions) : c'est aussi
/// ici qu'on s'en désabonne.
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
        actions: [LearnHelpButton(articleId: "circuit", game: game.slug), LeagueFollowButton(league: league)],
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
          const SizedBox(height: AppSpacing.sm),
          Text(
            "Suivre la ligue : toutes ses compétitions, actuelles et futures. Ou seulement certaines, sans l'année.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textTertiary),
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
