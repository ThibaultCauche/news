import { BracketFormat, computeStandings, standingsOptionsFor } from "./bracket";
import { EventStatus } from "./status";

// Classement global d'une compétition (docs/04 J23, #M1) : toutes les équipes de la série (phase suisse, play-in,
// phase finale…), chacune avec son statut. Calculé depuis nos propres matchs, étape par étape, avec les mêmes règles
// que les classements d'étape (`computeStandings`).

export interface RankingMatchInput {
  status: EventStatus;
  startsAt: Date | null;
  participants: { entityId: string; score: number | null; isWinner: boolean | null }[];
}

export interface RankingStageInput {
  name: string;
  format: BracketFormat | null;
  status: string | null;
  startsAt: Date | null;
  matches: RankingMatchInput[];
}

export type RankingStatus = "champion" | "in_race" | "eliminated";

export interface RankingEntry {
  entityId: string;
  rank: number;
  status: RankingStatus;
  /** Dernière étape jouée par l'équipe (« Group Stage », « Playoffs »…). */
  stage: string;
  /** Bilan de l'équipe dans cette étape. */
  wins: number;
  losses: number;
  /** Qualifiée pour la suite par les règles de son étape (3 victoires en phase suisse), sans avoir encore rejoué. */
  qualified: boolean;
}

export function computeCompetitionRanking(stagesInput: RankingStageInput[]): RankingEntry[] {
  const stages = stagesInput
    .filter((s) => s.matches.some((m) => m.participants.length > 0))
    .sort((a, b) => (a.startsAt?.getTime() ?? Infinity) - (b.startsAt?.getTime() ?? Infinity));
  if (stages.length === 0) return [];

  const finalStage = stages[stages.length - 1];
  const finalMatch = finalStage.status === "finished" ? lastFinishedMatch(finalStage.matches) : null;
  const championId = finalMatch?.participants.find((p) => p.isWinner === true)?.entityId ?? null;

  const byTeam = new Map<string, { stageIndex: number; wins: number; losses: number; mapDiff: number; eliminated: boolean; qualified: boolean }>();
  stages.forEach((stage, stageIndex) => {
    const standings = computeStandings(
      stage.matches.map((m) => ({
        status: m.status,
        participants: m.participants.map((p) => ({ entityExternalId: p.entityId, score: p.score, isWinner: p.isWinner })),
      })),
      standingsOptionsFor(stage.format),
    );
    for (const s of standings) {
      byTeam.set(s.entityExternalId, { stageIndex, wins: s.wins, losses: s.losses, mapDiff: s.mapDiff, eliminated: s.livesLeft === 0, qualified: s.qualified === true });
    }
  });

  const statusOf = (id: string, eliminated: boolean): RankingStatus => (id === championId ? "champion" : eliminated ? "eliminated" : "in_race");
  return [...byTeam.entries()]
    .map(([entityId, t]) => ({ entityId, t, status: statusOf(entityId, t.eliminated) }))
    .sort(
      (a, b) =>
        Number(b.status === "champion") - Number(a.status === "champion") ||
        b.t.stageIndex - a.t.stageIndex ||
        Number(b.status === "in_race") - Number(a.status === "in_race") ||
        b.t.wins - a.t.wins ||
        b.t.mapDiff - a.t.mapDiff ||
        a.entityId.localeCompare(b.entityId),
    )
    .map(({ entityId, t, status }, i) => ({ entityId, rank: i + 1, status, stage: stages[t.stageIndex].name, wins: t.wins, losses: t.losses, qualified: status === "in_race" && t.qualified }));
}

function lastFinishedMatch(matches: RankingMatchInput[]): RankingMatchInput | null {
  const finished = matches.filter((m) => m.status === "finished" && m.participants.length > 0);
  finished.sort((a, b) => (a.startsAt?.getTime() ?? 0) - (b.startsAt?.getTime() ?? 0));
  return finished.at(-1) ?? null;
}
