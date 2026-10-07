import { EventStatus } from "./status";

// Formats de bracket gérés au J5 (docs/03 §2 ; round_robin/swiss/law_process… viendront
// avec d'autres catégories). Détecté depuis les noms de match PandaScore (pas de champ
// de format direct côté fournisseur) plutôt que codé en dur par compétition.
export type BracketFormat = "single_elim" | "double_elim" | "triple_elim" | "groups_gsl" | "swiss";

// Nombre d'équipes qualifiées d'une poule GSL : utilisé par le job "structure"
// du worker (J5) ET par la phrase d'enjeu de l'agenda (J8, `buildGroupStakes`
// dans `context.ts`) — une seule constante pour que les deux ne divergent pas.
// Toujours 2 pour l'instant (règle 3 de CLAUDE.md : pas de champ par poule).
export const GSL_QUALIFIED_COUNT = 2;

// Phase suisse (Worlds, MSI, Masters Toronto…) : 3 victoires qualifient, 3 défaites éliminent.
export const SWISS_WINS_TO_QUALIFY = 3;
export const SWISS_LOSSES_TO_ELIMINATE = 3;

// Vrai pour « Round 1: G2 vs T1 » ; PandaScore nomme ainsi chaque match d'une ronde suisse.
const SWISS_MATCH_NAME = /^round \d+:/i;

export function isSwissMatchName(name: string): boolean {
  return SWISS_MATCH_NAME.test(name.trim());
}

export interface BracketMatchInput {
  externalId: string;
  name: string;
  previousMatches: { type: "winner" | "loser"; matchExternalId: string }[];
}

export interface EventLinkDTO {
  fromExternalId: string;
  toExternalId: string;
  outcome: "winner" | "loser";
  slot: number;
}

// Heuristique sur les noms de match (vérifiée sur de vrais brackets PandaScore,
// tests-pandascore/samples/) : "Lower/Mid bracket" → double/triple élim, "Winners/
// Elimination/Decider Match" → poule GSL, sinon simple élimination.
export function detectBracketFormat(matches: Pick<BracketMatchInput, "name">[]): BracketFormat {
  // Suisse : presque tous les matchs s'appellent « Round N: … » (une poule GSL n'en a aucun).
  if (matches.length >= 4 && matches.filter((m) => isSwissMatchName(m.name)).length >= matches.length * 0.8) return "swiss";
  const names = matches.map((m) => m.name.toLowerCase());
  const hasLower = names.some((n) => n.includes("lower bracket"));
  const hasMid = names.some((n) => n.includes("mid bracket"));
  if (hasLower && hasMid) return "triple_elim";
  if (hasLower) return "double_elim";
  if (names.some((n) => /winners match|elimination match|decider match/.test(n))) return "groups_gsl";
  return "single_elim";
}

// Construit les liens de bracket ("le vainqueur de A va en B") à partir de
// `previous_matches` (docs/03 §2, event_link). `slot` = position parmi les
// prédécesseurs du match cible (0 ou 1), pour distinguer les deux entrées d'un match.
export function buildEventLinks(matches: BracketMatchInput[]): EventLinkDTO[] {
  return matches.flatMap((match) =>
    match.previousMatches.map((prev, slot) => ({
      fromExternalId: prev.matchExternalId,
      toExternalId: match.externalId,
      outcome: prev.type,
      slot,
    })),
  );
}

// Round radial : 0 = match(s) terminal(aux) (la finale, au centre de l'arbre — écran
// 02), croissant vers l'extérieur. Calculé par parcours en largeur à partir des
// matchs qui n'alimentent aucun autre match.
// ponytail: ne calcule que le round (l'anneau) ; la position angulaire dans un round
// est répartie côté appli (Flutter), un vrai calcul de slot croisé haut/bas tableau
// serait nettement plus complexe pour un gain visuel marginal à ce stade.
export function computeBracketRounds(matches: BracketMatchInput[]): Record<string, number> {
  const links = buildEventLinks(matches);
  const hasOutgoingLink = new Set(links.map((l) => l.fromExternalId));
  const predecessorsByTarget = new Map<string, string[]>();
  for (const link of links) {
    const list = predecessorsByTarget.get(link.toExternalId) ?? [];
    list.push(link.fromExternalId);
    predecessorsByTarget.set(link.toExternalId, list);
  }

  const rounds: Record<string, number> = {};
  const queue = matches.map((m) => m.externalId).filter((id) => !hasOutgoingLink.has(id));
  for (const id of queue) rounds[id] = 0;
  while (queue.length) {
    const id = queue.shift() as string;
    for (const predecessorId of predecessorsByTarget.get(id) ?? []) {
      if (rounds[predecessorId] === undefined) {
        rounds[predecessorId] = rounds[id] + 1;
        queue.push(predecessorId);
      }
    }
  }
  return rounds;
}

export interface StandingMatchInput {
  status: EventStatus;
  participants: { entityExternalId: string; score: number | null; isWinner: boolean | null }[];
}

export interface StandingResult {
  entityExternalId: string;
  wins: number;
  losses: number;
  mapDiff: number;
  livesLeft: number;
  rank: number;
  qualified: boolean | null;
}

// Recalcule victoires/défaites/écart de cartes à partir des matchs déjà en base
// (le standings gratuit de PandaScore ne donne que le rang — docs/01). `maxLives`
// généralise le nombre de défaites tolérées (1 = simple élim, 2 = double élim/GSL,
// 3 = triple élim) : une seule fonction pour tous les formats à bracket.
export interface StandingsOptions {
  maxLives: number;
  qualifiedCount?: number;
  // Phase suisse : qualifié dès ce nombre de victoires, quel que soit le classement.
  qualifyAtWins?: number;
}

/** Réglages de `computeStandings` pour chaque format (un seul endroit : le worker et le classement global s'en servent). */
export function standingsOptionsFor(format: BracketFormat | null | undefined): StandingsOptions {
  switch (format) {
    case "swiss":
      return { maxLives: SWISS_LOSSES_TO_ELIMINATE, qualifyAtWins: SWISS_WINS_TO_QUALIFY };
    case "triple_elim":
      return { maxLives: 3 };
    case "single_elim":
      return { maxLives: 1 };
    case "groups_gsl":
      return { maxLives: 2, qualifiedCount: GSL_QUALIFIED_COUNT };
    default:
      return { maxLives: 2 };
  }
}

export function computeStandings(matches: StandingMatchInput[], options: StandingsOptions): StandingResult[] {
  const stats = new Map<string, { wins: number; losses: number; mapDiff: number }>();
  const get = (id: string) => stats.get(id) ?? { wins: 0, losses: 0, mapDiff: 0 };

  for (const match of matches) {
    if (match.status !== "finished") continue;
    for (const participant of match.participants) {
      const opponents = match.participants.filter((p) => p !== participant);
      const opponentScore = opponents.reduce((sum, o) => sum + (o.score ?? 0), 0);
      const entry = get(participant.entityExternalId);
      entry.mapDiff += (participant.score ?? 0) - opponentScore;
      if (participant.isWinner === true) entry.wins += 1;
      if (participant.isWinner === false) entry.losses += 1;
      stats.set(participant.entityExternalId, entry);
    }
  }

  const results = [...stats.entries()]
    .map(([entityExternalId, s]) => ({
      entityExternalId,
      wins: s.wins,
      losses: s.losses,
      mapDiff: s.mapDiff,
      livesLeft: Math.max(0, options.maxLives - s.losses),
      rank: 0,
      qualified: null as boolean | null,
    }))
    .sort((a, b) => b.wins - a.wins || b.mapDiff - a.mapDiff || a.entityExternalId.localeCompare(b.entityExternalId));

  return results.map((r, i) => ({
    ...r,
    rank: i + 1,
    qualified:
      options.qualifyAtWins != null
        ? r.wins >= options.qualifyAtWins
        : options.qualifiedCount != null
          ? i < options.qualifiedCount
          : null,
  }));
}

export interface StandingSnapshot {
  entityId: string;
  qualified: boolean | null;
  livesLeft: number | null;
}

// Compare l'ancien et le nouveau classement pour décider qui vient de passer
// qualifié ou d'être éliminé (0 vie) — notifications "qualification"/"élimination"
// (docs/03 §6, reportées du J4 au J5). Comme `diffEventStatus`, ne déclenche que
// sur un vrai changement d'état, pas sur chaque recalcul.
export function diffStandings(
  previous: StandingSnapshot[],
  next: StandingSnapshot[],
): { qualifiedEntityIds: string[]; eliminatedEntityIds: string[] } {
  const previousById = new Map(previous.map((s) => [s.entityId, s]));
  const qualifiedEntityIds: string[] = [];
  const eliminatedEntityIds: string[] = [];
  for (const s of next) {
    const before = previousById.get(s.entityId);
    if (s.qualified === true && before?.qualified !== true) qualifiedEntityIds.push(s.entityId);
    if (s.livesLeft === 0 && before?.livesLeft !== 0) eliminatedEntityIds.push(s.entityId);
  }
  return { qualifiedEntityIds, eliminatedEntityIds };
}
