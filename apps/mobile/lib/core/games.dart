/// Nom affiché d'un jeu à partir de son slug (`competition.game`), pour les écrans qui n'ont pas le catalogue sous la
/// main (fil d'Ariane, suivi d'une structure…). Les noms du catalogue (`CatalogGameDto.name`) viennent de la même
/// liste côté API (`GAME_NAMES`, packages/domain) : à compléter ici pour chaque nouveau jeu.
const _gameNames = {
  "valorant": "Valorant",
  "league-of-legends": "League of Legends",
  "super-smash-bros-ultimate": "Super Smash Bros. Ultimate",
};

/// Jeux qui ont un guide « l'essentiel en une page » (`assets/learn/<slug>.json`), dans l'ordre où l'Accueil les propose.
const learnableGames = ["valorant", "league-of-legends", "super-smash-bros-ultimate"];

String gameLabel(String? slug) => _gameNames[slug] ?? slug ?? "";

/// Jeux où l'on suit des joueurs plutôt que des équipes (tournois 1 contre 1) : l'onglet « Équipes » devient « Joueurs ».
bool gameIsSolo(String? slug) => slug == "super-smash-bros-ultimate";
