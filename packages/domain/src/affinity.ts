// Appli modulée selon la personne (J28, #M6) : quelle catégorie (« esport », « sport ») elle suit le plus, et
// laquelle lui suggérer de temps en temps. Règles pures : le calcul des comptes (suivis, favoris) se fait côté API.

export type CategoryCounts = Record<string, number>;

/** La catégorie la plus suivie ; `null` sans aucun suivi ou en cas d'égalité (pas de préférence nette). */
export function favoriteCategory(counts: CategoryCounts): string | null {
  const ranked = Object.entries(counts).filter(([, n]) => n > 0).sort((a, b) => b[1] - a[1]);
  if (ranked.length === 0) return null;
  if (ranked.length > 1 && ranked[0][1] === ranked[1][1]) return null;
  return ranked[0][0];
}

export interface SuggestionCandidate {
  category: string;
  live: boolean;
  /** ISO 8601 ; sert à départager les candidats à venir. */
  startsAt: string | null;
}

/**
 * Une catégorie que la personne ne suit pas encore, avec un grand rendez-vous en cours ou à venir : on ne suggère
 * rien à qui n'a encore rien suivi (on ne sait pas ce qu'elle aime), ni une catégorie déjà suivie.
 * Le direct passe avant le plus proche à venir.
 */
export function pickSuggestion<T extends SuggestionCandidate>(counts: CategoryCounts, candidates: T[]): T | null {
  if (Object.values(counts).every((n) => n === 0)) return null;
  const fresh = candidates.filter((c) => !(counts[c.category] > 0));
  return (
    fresh.sort((a, b) => {
      if (a.live !== b.live) return a.live ? -1 : 1;
      return (a.startsAt ?? "9999").localeCompare(b.startsAt ?? "9999");
    })[0] ?? null
  );
}
