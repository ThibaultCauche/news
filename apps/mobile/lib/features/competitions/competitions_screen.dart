import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/navigation.dart";
import "../../theme/tokens.dart";
import "../../widgets/game_logo.dart";
import "competitions_data.dart";
import "game_screen.dart";
import "league_screen.dart";

void _openGame(BuildContext context, CatalogGameDto game) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => GameScreen(game: game)));
}

/// 5ᵉ onglet (J9) : recherche (jeux, ligues, séries), raccourci Favoris, puis les
/// catégories en accordéon. Une catégorie sans compétition n'est pas affichée : le
/// catalogue ne contient que celles qui ont des données.
class CompetitionsScreen extends ConsumerStatefulWidget {
  const CompetitionsScreen({super.key});

  @override
  ConsumerState<CompetitionsScreen> createState() => _CompetitionsScreenState();
}

class _CompetitionsScreenState extends ConsumerState<CompetitionsScreen> {
  String _query = "";
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // L'icône de recherche de l'Accueil (J10) ouvre cet onglet puis demande le focus.
    ref.listen(searchFocusRequestProvider, (_, _) => WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus()));
    final catalog = ref.watch(catalogProvider);
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Text("Compétitions", style: Theme.of(context).textTheme.headlineLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: TextField(
              focusNode: _searchFocus,
              onChanged: (v) => setState(() => _query = v),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: "Rechercher un jeu ou une compétition",
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.pill), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: switch (catalog) {
              AsyncData(:final value) => _query.trim().isEmpty ? _Browse(catalog: value) : _Results(results: searchCatalog(value, _query)),
              AsyncError() => const Center(child: Text("Impossible de charger les compétitions.")),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _Browse extends ConsumerWidget {
  const _Browse({required this.catalog});

  final CatalogDto catalog;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favorites = ref.watch(favoriteGamesProvider).value ?? const <String>[];
    final allGames = [for (final c in catalog.categories) ...c.games];
    final favoriteGames = [
      for (final g in allGames)
        if (favorites.contains(g.slug)) g,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        if (favoriteGames.isNotEmpty) ...[
          Text("FAVORIS", style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final game in favoriteGames)
                ActionChip(
                  avatar: GameLogo(slug: game.slug, size: 24),
                  label: Text(game.name),
                  onPressed: () => _openGame(context, game),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final category in catalog.categories)
          Card(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                title: Text(category.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                children: [
                  for (final game in category.games)
                    ListTile(
                      leading: GameLogo(slug: game.slug),
                      title: Text(game.name),
                      trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                      onTap: () => _openGame(context, game),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({required this.results});

  final List<SearchResult> results;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Center(
        child: Text("Aucun résultat.", style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        for (final r in results)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: r.kind == SearchKind.game ? GameLogo(slug: r.game.slug) : LeagueLogo(imageUrl: r.imageUrl),
            title: Text(r.name),
            subtitle: Text(switch (r.kind) {
              SearchKind.game => "Jeu",
              SearchKind.league => "Ligue · ${r.game.name}",
              SearchKind.serie => "Compétition · ${r.game.name}",
            }, style: const TextStyle(color: AppColors.textSecondary)),
            trailing: const Icon(Icons.chevron_right, color: AppColors.textTertiary),
            onTap: () {
              if (r.league != null) {
                openLeaguePage(context, league: r.league!, game: r.game);
              } else if (r.competitionId != null) {
                openCompetitionPage(context, id: r.competitionId!, name: r.name);
              } else {
                _openGame(context, r.game);
              }
            },
          ),
      ],
    );
  }
}
