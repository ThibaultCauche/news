/// Nom affiché d'un jeu à partir de son slug (`competition.game`), pour les écrans qui n'ont pas le catalogue sous la
/// main (fil d'Ariane, suivi d'une structure…). Les noms du catalogue (`CatalogGameDto.name`) viennent de la même
/// liste côté API (`GAME_NAMES`, packages/domain) : à compléter ici pour chaque nouveau jeu.
const _gameNames = {
  "valorant": "Valorant",
  "league-of-legends": "League of Legends",
};

/// Jeux qui ont un guide « l'essentiel en une page » (`assets/learn/<slug>.json`), dans l'ordre où l'Accueil les propose.
const learnableGames = ["valorant", "league-of-legends"];

String gameLabel(String? slug) => _gameNames[slug] ?? slug ?? "";
