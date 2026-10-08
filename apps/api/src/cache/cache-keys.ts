// Clés de cache Redis par écran (docs/03 §4). L'agenda n'a pas de clé dédiée par
// événement : trop de combinaisons from/to/category à énumérer pour une
// invalidation explicite, son TTL court (15-60s) sert de filet — comme prévu au J2.
export const CacheKeys = {
  home: () => "cache:v1:home",
  agenda: (from: string, to: string, category?: string, leagueIds?: string) =>
    `cache:v1:agenda:${from}:${to}:${category ?? "all"}:${leagueIds ?? "all"}`,
  catalog: () => "cache:v1:catalog",
  politics: () => "cache:v1:politics",
  competitionRoots: (category: string) => `cache:v1:competition-roots:${category}`,
  competition: (id: string) => `cache:v1:competition:${id}`,
  bracket: (id: string) => `cache:v1:bracket:${id}`,
  event: (id: string) => `cache:v1:event:${id}`,
  glossary: (term: string) => `cache:v1:glossary:${term}`,
  entity: (id: string) => `cache:v1:entity:${id}`,
};
