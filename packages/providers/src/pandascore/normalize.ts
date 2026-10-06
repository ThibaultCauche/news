import { buildEventLinks, CompetitionDTO, detectBracketFormat, EntityDTO, EventDTO, EventStatus, StructureDTO } from "@news/domain";
import { RawLeague, RawMatch, RawSerie, RawTeam, RawTournament } from "./types";

const PROVIDER = "pandascore";

// Statuts observés côté PandaScore : not_started, running, finished, canceled.
// ponytail: pas de statut "postponed" vu côté PandaScore ; on retombe sur "scheduled"
// si un statut inconnu apparaît, à revoir si un cas réel se présente.
function mapMatchStatus(raw: string): EventStatus {
  switch (raw) {
    case "not_started":
      return "scheduled";
    case "running":
      return "live";
    case "finished":
      return "finished";
    case "canceled":
    case "cancelled":
      return "cancelled";
    default:
      return "scheduled";
  }
}

function tierToImportance(tier?: string | null): number {
  switch (tier) {
    case "s":
      return 3;
    case "a":
      return 2;
    case "b":
      return 1;
    default:
      return 0;
  }
}

function computeCompetitionStatus(startsAt: Date | null, endsAt: Date | null, hasWinner: boolean, now: Date): EventStatus {
  if (hasWinner) return "finished";
  if (endsAt && now > endsAt) return "finished";
  if (startsAt && now < startsAt) return "scheduled";
  return "live";
}

export function normalizeTeamEntity(team: RawTeam): EntityDTO {
  return {
    provider: PROVIDER,
    externalId: String(team.id),
    kind: "team",
    name: team.name,
    shortName: team.acronym ?? null,
    imageUrl: team.image_url ?? null,
    region: team.location ?? null,
  };
}

// L'adaptateur ne couvre que Valorant pour l'instant (`provider.ts`) ; à lire depuis
// `videogame` quand d'autres jeux arriveront.
const GAME = "valorant";

export function normalizeLeague(league: RawLeague): CompetitionDTO {
  return {
    provider: PROVIDER,
    externalId: String(league.id),
    parentExternalId: null,
    kind: "league",
    game: GAME,
    imageUrl: league.image_url ?? null,
    name: league.name,
    status: null,
    startsAt: null,
    endsAt: null,
    importance: 0,
    hasBracket: false,
    raw: league,
  };
}

export function normalizeSerie(serie: RawSerie): CompetitionDTO {
  return {
    provider: PROVIDER,
    externalId: String(serie.id),
    parentExternalId: String(serie.league_id),
    kind: "serie",
    game: GAME,
    imageUrl: null,
    name: serie.full_name ?? serie.name,
    status: null,
    startsAt: serie.begin_at ? new Date(serie.begin_at) : null,
    endsAt: serie.end_at ? new Date(serie.end_at) : null,
    importance: 0,
    hasBracket: false,
    raw: serie,
  };
}

export function normalizeTournament(tournament: RawTournament, now: Date = new Date()): CompetitionDTO {
  const startsAt = tournament.begin_at ? new Date(tournament.begin_at) : null;
  const endsAt = tournament.end_at ? new Date(tournament.end_at) : null;
  return {
    provider: PROVIDER,
    externalId: String(tournament.id),
    parentExternalId: String(tournament.serie_id),
    kind: "tournament",
    game: GAME,
    imageUrl: null,
    name: tournament.name,
    status: computeCompetitionStatus(startsAt, endsAt, tournament.winner_id != null, now),
    startsAt,
    endsAt,
    importance: tierToImportance(tournament.tier),
    hasBracket: tournament.has_bracket ?? false,
    raw: tournament,
  };
}

// Compétitions dérivées d'un seul tournoi (ligue → série → tournoi imbriqués dans
// la réponse PandaScore) : une requête de catalogue suffit pour toute la hiérarchie.
export function normalizeCompetitionsFromTournament(tournament: RawTournament, now: Date = new Date()): CompetitionDTO[] {
  return [normalizeLeague(tournament.league), normalizeSerie(tournament.serie), normalizeTournament(tournament, now)];
}

// Le direct officiel (J21) : celui marqué `main`, sinon un officiel. Jamais un co-streamer.
export function pickOfficialStream(streams: RawMatch["streams_list"]): string | null {
  const official = (streams ?? []).filter((s) => s.official && s.raw_url);
  return (official.find((s) => s.main) ?? official[0])?.raw_url ?? null;
}

// Score de série et gagnant de chaque carte uniquement (plan gratuit, règle 6 de
// CLAUDE.md) : pas de score en rounds, pas de nom de carte.
export function normalizeMatch(match: RawMatch): EventDTO {
  const winnerId = match.winner_id ?? null;
  const status = mapMatchStatus(match.status);
  const participants = (match.opponents ?? []).map((o) => {
    const externalId = String(o.opponent.id);
    const result = match.results?.find((r) => String(r.team_id) === externalId);
    return {
      entity: normalizeTeamEntity(o.opponent),
      score: result?.score ?? null,
      isWinner: status === "finished" ? winnerId != null && String(winnerId) === externalId : null,
    };
  });

  return {
    provider: PROVIDER,
    externalId: String(match.id),
    competitionExternalId: String(match.tournament_id),
    kind: "match",
    name: match.name,
    status,
    startsAt: match.begin_at ? new Date(match.begin_at) : match.scheduled_at ? new Date(match.scheduled_at) : null,
    endsAt: match.end_at ? new Date(match.end_at) : null,
    bestOf: match.number_of_games ?? null,
    streamUrl: pickOfficialStream(match.streams_list),
    result: {
      seriesScore: match.results ?? [],
      games: (match.games ?? []).map((g) => ({
        position: g.position,
        status: g.status,
        winnerExternalId: g.winner?.id != null ? String(g.winner.id) : null,
        durationSeconds: g.length ?? null,
      })),
    },
    participants,
    raw: match,
  };
}

// Bracket d'un tournoi (`/tournaments/:id/brackets`, docs/01) : liens gagnant/perdant
// à partir de `previous_matches`, format détecté depuis les noms de match (J5).
export function normalizeStructure(matches: RawMatch[]): StructureDTO {
  const inputs = matches.map((m) => ({
    externalId: String(m.id),
    name: m.name,
    previousMatches: (m.previous_matches ?? []).map((p) => ({ type: p.type, matchExternalId: String(p.match_id) })),
  }));
  return { format: detectBracketFormat(inputs), links: buildEventLinks(inputs) };
}
