// Couche communautaire (J11) : pronostics en points fictifs, pseudos, codes de groupe.
// Règles pures, sans accès base ; le worker et l'API les partagent.

export const POINTS_CORRECT_WINNER = 3;
export const POINTS_EXACT_SCORE = 2;

export interface PredictionPick {
  pickedEntityId: string;
  // Score de série du point de vue de l'entité choisie (ex. 2-1), les deux ou aucun.
  pickedScore: number | null;
  otherScore: number | null;
}

export interface FinishedOutcome {
  winnerEntityId: string;
  scoreByEntity: Record<string, number | null>;
}

/**
 * Points d'un pronostic sur un match terminé : 3 pour le bon vainqueur, +2 si le score de
 * série prédit est exact (donné seulement avec le bon vainqueur, un score juste sur un
 * vainqueur faux n'a pas de sens). Mauvais vainqueur : 0.
 */
export function scorePrediction(pick: PredictionPick, outcome: FinishedOutcome): number {
  if (pick.pickedEntityId !== outcome.winnerEntityId) return 0;
  let points = POINTS_CORRECT_WINNER;
  if (pick.pickedScore !== null && pick.otherScore !== null) {
    const otherEntity = Object.keys(outcome.scoreByEntity).find((id) => id !== pick.pickedEntityId);
    const winnerScore = outcome.scoreByEntity[pick.pickedEntityId];
    const loserScore = otherEntity ? outcome.scoreByEntity[otherEntity] : null;
    if (winnerScore === pick.pickedScore && loserScore === pick.otherScore) points += POINTS_EXACT_SCORE;
  }
  return points;
}

/** Un pronostic se pose tant que le match n'a pas commencé (statut « à venir » et date future). */
export function canPredict(status: string, startsAt: Date | null, now: Date): boolean {
  return status === "scheduled" && startsAt !== null && startsAt.getTime() > now.getTime();
}

export const PSEUDO_MIN_LENGTH = 3;
export const PSEUDO_MAX_LENGTH = 20;
export const PSEUDO_CHANGE_DELAY_DAYS = 30;

// ponytail: liste minimale, à étoffer au fil des signalements (le forum du J13 aura sa
// propre modération). Comparée sur la clé normalisée, sans séparateurs.
const BANNED_WORDS = ["nazi", "hitler", "pute", "salope", "connard", "enculé", "encule", "fdp", "ntm", "pedo", "nigger", "nigga", "fuck", "shit", "admin", "modo", "moderateur"];

/** Clé d'unicité : minuscules, sans accents. « Théo_92 » et « theo_92 » sont le même pseudo. */
export function pseudoKeyOf(pseudo: string): string {
  return pseudo
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase();
}

export type PseudoProblem = "length" | "characters" | "forbidden";

/** `null` si le pseudo est acceptable, sinon la raison du refus. */
export function pseudoProblem(pseudo: string): PseudoProblem | null {
  if (pseudo.length < PSEUDO_MIN_LENGTH || pseudo.length > PSEUDO_MAX_LENGTH) return "length";
  if (!/^[\p{L}\p{N}_.-]+$/u.test(pseudo)) return "characters";
  const flat = pseudoKeyOf(pseudo).replace(/[_.-]/g, "");
  if (BANNED_WORDS.some((w) => flat.includes(pseudoKeyOf(w)))) return "forbidden";
  return null;
}

/** Nombre de jours restants avant de pouvoir changer de pseudo (0 = possible maintenant). */
export function pseudoChangeWaitDays(changedAt: Date | null, now: Date): number {
  if (!changedAt) return 0;
  const elapsedDays = (now.getTime() - changedAt.getTime()) / 86_400_000;
  return Math.max(0, Math.ceil(PSEUDO_CHANGE_DELAY_DAYS - elapsedDays));
}

// 31 caractères sans 0/O, 1/I/L : 31^8 ≈ 10^12 codes, invitation lisible à voix haute.
const GROUP_CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
export const GROUP_CODE_LENGTH = 8;
export const GROUP_MAX_MEMBERS = 20;

/** `random(n)` renvoie un entier dans [0, n) (injecté : `crypto.randomInt` côté API). */
export function generateGroupCode(random: (max: number) => number): string {
  let code = "";
  for (let i = 0; i < GROUP_CODE_LENGTH; i++) code += GROUP_CODE_ALPHABET[random(GROUP_CODE_ALPHABET.length)];
  return code;
}

export function normalizeGroupCode(input: string): string {
  return input.trim().toUpperCase();
}
