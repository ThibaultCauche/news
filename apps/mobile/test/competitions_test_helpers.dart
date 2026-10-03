import "package:mobile/features/competitions/competitions_data.dart";
import "package:news_api_client/news_api_client.dart";

class _FixedFavoriteGamesNotifier extends FavoriteGamesNotifier {
  _FixedFavoriteGamesNotifier(this._value);
  final List<String> _value;

  @override
  Future<List<String>> build() async => _value;
}

/// Fige les jeux favoris dans les tests, même principe que `overrideFollowsWith`.
// ignore: strict_top_level_inference (le type `Override` n'est pas exporté par flutter_riverpod)
overrideFavoriteGamesWith(List<String> value) => favoriteGamesProvider.overrideWith(() => _FixedFavoriteGamesNotifier(value));

class _FixedFavoriteCompetitionsNotifier extends FavoriteCompetitionsNotifier {
  _FixedFavoriteCompetitionsNotifier(this._value);
  final List<FavoriteCompetitionDto> _value;

  @override
  Future<List<FavoriteCompetitionDto>> build() async => _value;
}

/// Fige les compétitions favorites dans les tests.
// ignore: strict_top_level_inference
overrideFavoriteCompetitionsWith(List<FavoriteCompetitionDto> value) => favoriteCompetitionsProvider.overrideWith(() => _FixedFavoriteCompetitionsNotifier(value));
