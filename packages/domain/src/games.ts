// Jeux connus de l'appli (slug de `competition.game`, J9). Le nom affiché vit ici
// plutôt qu'en base : pas de table par jeu (règle 3), et une seule source de vérité
// entre l'API (catalogue, favoris) et les adaptateurs.
export const GAME_NAMES: Record<string, string> = {
  valorant: "Valorant",
  "league-of-legends": "League of Legends",
};

export function isKnownGame(slug: string): boolean {
  return Object.prototype.hasOwnProperty.call(GAME_NAMES, slug);
}
