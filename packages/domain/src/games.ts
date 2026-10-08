// Jeux connus de l'appli (slug de `competition.game`, J9). Le nom affiché vit ici
// plutôt qu'en base : pas de table par jeu (règle 3), et une seule source de vérité
// entre l'API (catalogue, favoris) et les adaptateurs.
export const GAME_NAMES: Record<string, string> = {
  valorant: "Valorant",
  "league-of-legends": "League of Legends",
  "super-smash-bros-ultimate": "Super Smash Bros. Ultimate",
  "formula-1": "Formule 1",
  "assemblee-nationale": "Assemblée nationale",
  elections: "Élections",
};

// Catégorie d'un jeu ou d'un sport (J28) : tout ce qui n'est pas listé ici est de l'e-sport.
const SPORT_GAMES = new Set(["formula-1"]);

export function categoryOfGame(slug: string | null): { slug: string; name: string } {
  if (slug === "assemblee-nationale" || slug === "elections") return { slug: "politique", name: "Politique" };
  return slug && SPORT_GAMES.has(slug) ? { slug: "sport", name: "Sport" } : { slug: "esport", name: "E-sport" };
}

export function isKnownGame(slug: string): boolean {
  return Object.prototype.hasOwnProperty.call(GAME_NAMES, slug);
}
