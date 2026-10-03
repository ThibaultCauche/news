import "../../widgets/ornate_frame.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../widgets/async_view.dart";
import "../../widgets/page_title.dart";
import "../../core/navigation.dart";
import "../../theme/tokens.dart";
import "../../widgets/game_logo.dart";
import "../bracket/bracket_provider.dart";
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
            child: const PageTitle("Compétitions"),
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
            child: AsyncView(
              value: catalog,
              errorMessage: "Impossible de charger les compétitions.",
              onRetry: () => ref.invalidate(catalogProvider),
              builder: (value) => _query.trim().isEmpty ? _Browse(catalog: value) : _Results(results: searchCatalog(value, _query)),
            ),
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
    final favoriteCompetitions = ref.watch(favoriteCompetitionsProvider).value ?? const <FavoriteCompetitionDto>[];
    final live = liveSeries(catalog);
    final allGames = [for (final c in catalog.categories) ...c.games];
    final favoriteGames = [
      for (final g in allGames)
        if (favorites.contains(g.slug)) g,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.xl + 80),
      children: [
        // Les grands rendez-vous en cours, repliés d'office : un geste pour les déplier, un autre pour le tableau (J20).
        if (live.isNotEmpty) ...[
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: Row(
                children: [
                  Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
                  const SizedBox(width: AppSpacing.sm),
                  Text("EN COURS (${live.length})", style: Theme.of(context).textTheme.labelSmall?.copyWith(color: AppColors.live)),
                ],
              ),
              children: [for (final item in live) _LiveSeriesCard(item: item)],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
        ],
        if (favoriteGames.isNotEmpty || favoriteCompetitions.isNotEmpty) ...[
          Text("FAVORIS", style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final competition in favoriteCompetitions)
                ActionChip(
                  avatar: LeagueLogo(imageUrl: competition.imageUrl, size: 24),
                  label: Text(competition.name),
                  onPressed: () => openCompetitionPage(context, id: competition.id, name: competition.name),
                ),
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
          FramedCard(
            margin: const EdgeInsets.only(bottom: 14),
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

/// Une grande compétition en cours : son nom, ses dates et une description (le résumé Liquipedia de la page
/// compétition, avec sa source : règle 8 de `CLAUDE.md`). Le détail n'est demandé qu'une fois la section dépliée.
class _LiveSeriesCard extends ConsumerWidget {
  const _LiveSeriesCard({required this.item});

  final ({CatalogChildDto serie, CatalogLeagueDto league, CatalogGameDto game}) item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(competitionDetailProvider(item.serie.id)).value;
    final dates = detail == null ? null : formatDateRange(detail.startsAt, detail.endsAt);
    final context_ = detail?.context;
    return FramedCard(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.card),
        onTap: () => openCompetitionPage(context, id: item.serie.id, name: item.serie.name),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  LeagueLogo(imageUrl: item.league.imageUrl),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.serie.name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                        Text("${item.league.name} · ${item.game.name}", style: const TextStyle(color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, color: AppColors.textTertiary),
                ],
              ),
              if (dates != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(dates, style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.w600)),
              ],
              if (context_ != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(context_.text, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary, height: 1.35)),
                const SizedBox(height: 2),
                Text("Source : ${context_.source_} (${context_.license})", style: const TextStyle(color: AppColors.textTertiary, fontSize: 11)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
