import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:news_api_client/news_api_client.dart";

import "../../core/api_providers.dart";
import "../../core/auth/account.dart";
import "../account/account_gate.dart";
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
    // Invité : pas de favoris (il faut un compte, docs/04 J11).
    if (!ref.watch(signedInProvider)) return [];
    final response = await ref.watch(apiClientProvider).getFavoritesApi().favoritesControllerList();
    return response.data!.map((f) => f.game).toList();
  }

  Future<void> toggle(String game) async {
    if (!await ensureAccount(ref)) return;
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

/// Compétitions favorites (J20) : comme les jeux, un raccourci sans abonnement ni notification, affiché
/// dans « Favoris » de l'onglet Compétitions.
class FavoriteCompetitionsNotifier extends AsyncNotifier<List<FavoriteCompetitionDto>> {
  @override
  Future<List<FavoriteCompetitionDto>> build() async {
    if (!ref.watch(signedInProvider)) return [];
    final response = await ref.watch(apiClientProvider).getFavoriteCompetitionsApi().favoriteCompetitionsControllerList();
    return response.data!.toList();
  }

  Future<void> toggle(String id, {required String name, String? imageUrl}) async {
    if (!await ensureAccount(ref)) return;
    final previous = state;
    final current = previous.value ?? const <FavoriteCompetitionDto>[];
    final adding = !current.any((f) => f.id == id);
    state = AsyncValue.data(
      adding
          ? [
              ...current,
              FavoriteCompetitionDto((b) => b
                ..id = id
                ..name = name
                ..imageUrl = imageUrl),
            ]
          : current.where((f) => f.id != id).toList(),
    );
    try {
      final api = ref.read(apiClientProvider).getFavoriteCompetitionsApi();
      if (adding) {
        await api.favoriteCompetitionsControllerAdd(id: id);
      } else {
        await api.favoriteCompetitionsControllerRemove(id: id);
      }
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

final favoriteCompetitionsProvider = AsyncNotifierProvider.autoDispose<FavoriteCompetitionsNotifier, List<FavoriteCompetitionDto>>(FavoriteCompetitionsNotifier.new);

/// Les grandes séries en cours du catalogue (Champions, Masters, Coupe du monde…), avec leur ligue et leur jeu :
/// la section « En cours » de l'onglet Compétitions (J20), sans rien à configurer. Les étapes régionales et les
/// qualifications n'y sont pas : la section resterait trop longue à mesure qu'on ajoute des jeux et des sports.
List<({CatalogChildDto serie, CatalogLeagueDto league, CatalogGameDto game})> liveSeries(CatalogDto catalog) => [
      for (final category in catalog.categories)
        for (final game in category.games)
          for (final league in game.leagues)
            for (final serie in league.children)
              if (serie.live && serie.major) (serie: serie, league: league, game: game),
    ];

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

/// « 24 sept. – 18 oct. 2026 » (ou « 24 – 31 oct. 2026 » dans un même mois) ; `null` sans date de début.
String? formatDateRange(String? startsAt, String? endsAt) {
  if (startsAt == null) return null;
  const months = ["janv.", "févr.", "mars", "avr.", "mai", "juin", "juil.", "août", "sept.", "oct.", "nov.", "déc."];
  final start = DateTime.parse(startsAt).toLocal();
  if (endsAt == null) return "À partir du ${start.day} ${months[start.month - 1]} ${start.year}";
  final end = DateTime.parse(endsAt).toLocal();
  final sameMonth = start.year == end.year && start.month == end.month;
  final from = sameMonth ? "${start.day}" : "${start.day} ${months[start.month - 1]}${start.year == end.year ? "" : " ${start.year}"}";
  return "$from – ${end.day} ${months[end.month - 1]} ${end.year}";
}
