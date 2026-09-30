import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/api_providers.dart";
import "../../core/text_x.dart";

/// Catalogue catégorie → jeu → ligues → séries (`GET /v1/catalog`), chargé une
/// fois : la recherche de l'onglet Compétitions filtre dessus côté appli.
final catalogProvider = FutureProvider.autoDispose<CatalogDto>((ref) async {
  final response = await ref.watch(apiClientProvider).getCatalogApi().catalogControllerGet();
  return response.data!;
});

/// Équipes ayant joué dans un jeu (onglet Équipes de la page jeu).
final gameTeamsProvider = FutureProvider.autoDispose.family<List<EntityListItemDto>, String>((ref, game) async {
  final response = await ref.watch(apiClientProvider).getEntitiesApi().entitiesControllerListByGame(game: game);
  return response.data!.toList();
});

/// Jeux favoris : raccourci d'accès uniquement, sans abonnement ni notification.
/// `AsyncNotifier` pour le retour optimiste, comme `FollowsNotifier`.
class FavoriteGamesNotifier extends AsyncNotifier<List<String>> {
  @override
  Future<List<String>> build() async {
    final response = await ref.watch(apiClientProvider).getFavoritesApi().favoritesControllerList();
    return response.data!.map((f) => f.game).toList();
  }

  Future<void> toggle(String game) async {
    final previous = state;
    final current = previous.value ?? const <String>[];
    final adding = !current.contains(game);
    state = AsyncValue.data(adding ? [...current, game] : current.where((g) => g != game).toList());
    try {
      final api = ref.read(apiClientProvider).getFavoritesApi();
      if (adding) {
        await api.favoritesControllerAdd(game: game);
      } else {
        await api.favoritesControllerRemove(game: game);
      }
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final favoriteGamesProvider = AsyncNotifierProvider.autoDispose<FavoriteGamesNotifier, List<String>>(FavoriteGamesNotifier.new);

enum SearchKind { game, league, serie }

class SearchResult {
  const SearchResult({required this.kind, required this.name, required this.game, this.imageUrl, this.competitionId, this.league});

  final SearchKind kind;
  final String name;
  final CatalogGameDto game;

  /// Logo de la ligue (pour une ligue ou une de ses séries).
  final String? imageUrl;

  /// Renseigné pour une série (ouvre la page compétition).
  final String? competitionId;

  /// Renseignée pour une ligue (ouvre sa page) ; un jeu ouvre la page jeu.
  final CatalogLeagueDto? league;
}

/// Jeux, ligues et séries dont le nom contient la recherche (insensible à la
/// casse et aux accents). Vide si la recherche est vide.
List<SearchResult> searchCatalog(CatalogDto catalog, String query) {
  final needle = normalizeSearch(query.trim());
  if (needle.isEmpty) return const [];
  bool matches(String name) => normalizeSearch(name).contains(needle);

  final results = <SearchResult>[];
  for (final category in catalog.categories) {
    for (final game in category.games) {
      if (matches(game.name)) results.add(SearchResult(kind: SearchKind.game, name: game.name, game: game));
      for (final league in game.leagues) {
        if (matches(league.name)) results.add(SearchResult(kind: SearchKind.league, name: league.name, game: game, imageUrl: league.imageUrl, league: league));
        for (final serie in league.children) {
          if (matches(serie.name)) {
            results.add(SearchResult(kind: SearchKind.serie, name: serie.name, game: game, imageUrl: league.imageUrl, competitionId: serie.id));
          }
        }
      }
    }
  }
  return results;
}

/// La ligue du catalogue d'identifiant [competitionId], avec son jeu, ou `null` (une série,
/// une étape…) : sert à ouvrir la page ligue plutôt que la page compétition (docs/04 J10).
({CatalogLeagueDto league, CatalogGameDto game})? findLeague(CatalogDto? catalog, String competitionId) {
  if (catalog == null) return null;
  for (final category in catalog.categories) {
    for (final game in category.games) {
      for (final league in game.leagues) {
        if (league.id == competitionId) return (league: league, game: game);
      }
    }
  }
  return null;
}

/// Série du catalogue d'identifiant [competitionId] avec sa ligue, son jeu et sa famille
/// (`null` si ce n'est pas une série du catalogue) : sert à savoir si un suivi de ligue ou
/// de famille la couvre (docs/04 J10).
({CatalogChildDto serie, CatalogLeagueDto league, CatalogGameDto game})? findSerie(CatalogDto? catalog, String competitionId) {
  if (catalog == null) return null;
  for (final category in catalog.categories) {
    for (final game in category.games) {
      for (final league in game.leagues) {
        for (final serie in league.children) {
          if (serie.id == competitionId) return (serie: serie, league: league, game: game);
        }
      }
    }
  }
  return null;
}

/// La ligue du catalogue qui possède la famille [familyId].
({CatalogLeagueDto league, CatalogGameDto game})? findLeagueOfFamily(CatalogDto? catalog, String familyId) {
  if (catalog == null) return null;
  for (final category in catalog.categories) {
    for (final game in category.games) {
      for (final league in game.leagues) {
        if (league.families.any((f) => f.id == familyId)) return (league: league, game: game);
      }
    }
  }
  return null;
}
