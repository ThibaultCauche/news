// Familles de compétitions (docs/04 J10) : « Champions » regroupe Champions 2025,
// 2026, 2027…, pour suivre toutes les éditions, présentes et futures. Règles pures,
// sans accès base : le rattrapage SQL de la migration (`competition_family`) applique
// les mêmes expressions.

// Familles qui absorbent leur suffixe (une ville, ici) : « Masters Santiago 2026 » et
// « Masters London 2026 » sont deux éditions de « Masters », pas deux familles.
const PREFIX_FAMILIES = ["Masters"];

/**
 * Nom de famille d'une série, ou `null` si elle n'en a pas (nom réduit à l'année,
 * comme les séries « 2025 » de l'Esports World Cup).
 * « Champions 2026 » → « Champions » ; « Americas Stage 2 2026 » → « Americas Stage 2 » ;
 * « Masters London 2026 » → « Masters ».
 */
export function familyNameOf(serieName: string): string | null {
  const withoutYear = serieName.replace(/\s*\b\d{4}$/, "").trim();
  if (withoutYear === "" || /^\d{4}$/.test(serieName.trim())) return null;
  for (const prefix of PREFIX_FAMILIES) {
    if (withoutYear.startsWith(`${prefix} `)) return prefix;
  }
  return withoutYear;
}

export interface CompetitionRule {
  // Plus grand = plus proche du match (voir `competitionSpecificity`).
  specificity: number;
  // Sourdine : « je suis la ligue, sauf cette compétition ».
  muted: boolean;
}

/**
 * Précision d'une règle pour un match. `chainIndex` : rang dans la chaîne de
 * compétitions du match, 0 = sa propre compétition, puis chaque parent (tournoi →
 * série → ligue). Un abonnement à une compétition vaut son rang ; une famille est
 * attachée à la série et passe juste après un abonnement direct à cette série, mais
 * avant la ligue au-dessus.
 */
export function competitionSpecificity(kind: "competition" | "family", chainIndex: number): number {
  return 1000 - chainIndex * 10 - (kind === "family" ? 5 : 0);
}

/** La règle la plus proche du match l'emporte (ex. série en sourdine > ligue suivie). */
export function nearestCompetitionRule<T extends CompetitionRule>(rules: T[]): T | null {
  let best: T | null = null;
  for (const rule of rules) {
    if (best === null || rule.specificity > best.specificity) best = rule;
  }
  return best;
}

// Compétitions « majeures » (J20) : les grands rendez-vous mondiaux, ceux qui méritent la section « En
// cours » de l'onglet Compétitions (Champions, Masters, Coupe du monde…), pas chaque étape régionale ou
// qualification qui tourne en même temps. Reconnues par leur nom, faute de champ fournisseur fiable (la
// catégorie de tournoi ne distingue pas un Champions d'une étape régionale) ; à compléter mot à mot quand
// de nouveaux jeux et sports arrivent.
const MAJOR_WORDS = /\b(champions|masters|world cup|world championship|worlds|international|majors?|msi|mid-season invitational|first stand)\b/i;
const MINOR_WORDS = /\b(qualifiers?|open|closed|challengers|regional)\b/i;

export function isMajorEvent(leagueName: string, serieName: string): boolean {
  return MAJOR_WORDS.test(`${leagueName} ${serieName}`) && !MINOR_WORDS.test(serieName);
}
