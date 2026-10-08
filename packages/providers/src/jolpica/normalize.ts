import { CompetitionDTO, EntityDTO, EventDTO, EventStatus, StandingDTO } from "@news/domain";
import { RawConstructor, RawConstructorStanding, RawDriver, RawDriverStanding, RawQualifying, RawRace, RawResult, RawSession } from "./types";

export const PROVIDER = "jolpica";
export const GAME = "formula-1";
export const LEAGUE_EXTERNAL_ID = "league:f1";

// Compétitions : ligue → saison → Grand Prix, comme ligue → série → tournoi chez PandaScore. Une saison = une série ;
// un Grand Prix = un tournoi dont les événements sont les sessions du week-end.
export const seasonRef = (season: string) => `season:${season}`;
export const raceRef = (season: string, round: string) => `race:${season}-${round}`;

export type SessionKind = "fp1" | "fp2" | "fp3" | "sprint_qualifying" | "sprint" | "qualifying" | "race";
export const sessionRef = (season: string, round: string, kind: SessionKind) => `${season}-${round}-${kind}`;

export function parseSessionRef(ref: string): { season: string; round: string; kind: SessionKind } {
  const [season, round, kind] = ref.split("-");
  return { season, round, kind: kind as SessionKind };
}

const SESSION_NAMES: Record<SessionKind, string> = {
  fp1: "Essais libres 1",
  fp2: "Essais libres 2",
  fp3: "Essais libres 3",
  sprint_qualifying: "Qualifications sprint",
  sprint: "Sprint",
  qualifying: "Qualifications",
  race: "Course",
};

// Durée supposée d'une session sans direct : au-delà, elle est considérée comme terminée.
const SESSION_HOURS: Record<SessionKind, number> = { fp1: 2, fp2: 2, fp3: 2, sprint_qualifying: 2, sprint: 2, qualifying: 2, race: 4 };

const at = (s: RawSession | undefined) => (s ? new Date(`${s.date}T${s.time ?? "00:00:00Z"}`) : null);
const endOf = (startsAt: Date, kind: SessionKind) => new Date(startsAt.getTime() + SESSION_HOURS[kind] * 3600_000);

// Sessions du week-end dans l'ordre chronologique ; le calendrier de Jolpica ne liste que celles qui existent.
export function sessionsOf(race: RawRace): { kind: SessionKind; startsAt: Date }[] {
  const list: [SessionKind, Date | null][] = [
    ["fp1", at(race.FirstPractice)],
    ["fp2", at(race.SecondPractice)],
    ["fp3", at(race.ThirdPractice)],
    ["sprint_qualifying", at(race.SprintQualifying)],
    ["sprint", at(race.Sprint)],
    ["qualifying", at(race.Qualifying)],
    ["race", at({ date: race.date, time: race.time })],
  ];
  return list.flatMap(([kind, startsAt]) => (startsAt ? [{ kind, startsAt }] : [])).sort((a, b) => a.startsAt.getTime() - b.startsAt.getTime());
}

function weekendStatus(race: RawRace, now: Date): EventStatus {
  const sessions = sessionsOf(race);
  const first = sessions[0]?.startsAt;
  const last = sessions[sessions.length - 1];
  if (!first || !last || now < first) return "scheduled";
  return now > endOf(last.startsAt, last.kind) ? "finished" : "live";
}

export function normalizeLeague(): CompetitionDTO {
  return {
    provider: PROVIDER,
    externalId: LEAGUE_EXTERNAL_ID,
    parentExternalId: null,
    kind: "league",
    game: GAME,
    imageUrl: null,
    name: "Formule 1",
    status: null,
    startsAt: null,
    endsAt: null,
    importance: 0,
    hasBracket: false,
    raw: { id: LEAGUE_EXTERNAL_ID },
  };
}

export function normalizeSeason(season: string, races: RawRace[], now: Date = new Date()): CompetitionDTO {
  const all = races.flatMap((r) => sessionsOf(r));
  const startsAt = all[0]?.startsAt ?? null;
  const lastRace = races[races.length - 1];
  const lastSession = lastRace ? sessionsOf(lastRace).pop() : undefined;
  const endsAt = lastSession ? endOf(lastSession.startsAt, lastSession.kind) : null;
  const status: EventStatus = startsAt && now < startsAt ? "scheduled" : endsAt && now > endsAt ? "finished" : "live";
  return {
    provider: PROVIDER,
    externalId: seasonRef(season),
    parentExternalId: LEAGUE_EXTERNAL_ID,
    kind: "serie",
    game: GAME,
    imageUrl: null,
    name: `Formule 1 ${season}`,
    status,
    startsAt,
    endsAt,
    importance: 3,
    hasBracket: false,
    raw: { season, rounds: races.length },
  };
}

export function normalizeGrandPrix(race: RawRace, now: Date = new Date()): CompetitionDTO {
  const sessions = sessionsOf(race);
  const last = sessions[sessions.length - 1];
  return {
    provider: PROVIDER,
    externalId: raceRef(race.season, race.round),
    parentExternalId: seasonRef(race.season),
    kind: "tournament",
    game: GAME,
    imageUrl: null,
    name: race.raceName,
    status: weekendStatus(race, now),
    startsAt: sessions[0]?.startsAt ?? null,
    endsAt: last ? endOf(last.startsAt, last.kind) : null,
    importance: 3,
    hasBracket: false,
    location: `${race.Circuit.circuitName}, ${race.Circuit.Location.locality}`,
    raw: { season: race.season, round: race.round, circuit: race.Circuit.circuitName, locality: race.Circuit.Location.locality, country: race.Circuit.Location.country },
  };
}

export function driverEntity(driver: RawDriver): EntityDTO {
  return {
    provider: PROVIDER,
    externalId: `driver:${driver.driverId}`,
    kind: "driver",
    name: `${driver.givenName} ${driver.familyName}`,
    shortName: driver.code ?? null,
    imageUrl: null,
    region: driver.nationality ?? null,
  };
}

export function constructorEntity(team: RawConstructor): EntityDTO {
  return {
    provider: PROVIDER,
    externalId: `constructor:${team.constructorId}`,
    kind: "constructor",
    name: team.name,
    shortName: null,
    imageUrl: null,
    region: team.nationality ?? null,
  };
}

export interface SessionResults {
  results?: RawResult[];
  sprint?: RawResult[];
  qualifying?: RawQualifying[];
}

// Ligne d'arrivée, telle que l'API l'expose (`event.result.rows`).
function resultRow(r: RawResult) {
  return {
    position: Number(r.position),
    positionText: r.positionText,
    driverId: r.Driver.driverId,
    code: r.Driver.code ?? null,
    number: r.Driver.permanentNumber ?? null,
    constructorId: r.Constructor.constructorId,
    constructor: r.Constructor.name,
    grid: r.grid != null ? Number(r.grid) : null,
    laps: r.laps != null ? Number(r.laps) : null,
    time: r.Time?.time ?? null,
    status: r.status,
    points: Number(r.points),
  };
}

function qualifyingRow(r: RawQualifying) {
  return {
    position: Number(r.position),
    driverId: r.Driver.driverId,
    code: r.Driver.code ?? null,
    number: r.Driver.permanentNumber ?? null,
    constructorId: r.Constructor.constructorId,
    constructor: r.Constructor.name,
    q1: r.Q1 ?? null,
    q2: r.Q2 ?? null,
    q3: r.Q3 ?? null,
  };
}

// Un événement par session. Course, sprint et qualifications se remplissent quand Jolpica publie le classement ;
// les essais libres n'en ont jamais (pas de route chez Jolpica). Le gagnant de chaque session est le premier.
export function normalizeSession(race: RawRace, kind: SessionKind, startsAt: Date, data: SessionResults, now: Date = new Date()): EventDTO {
  const classified: { Driver: RawDriver; position: string }[] =
    (kind === "race" ? data.results : kind === "sprint" ? data.sprint : kind === "qualifying" ? data.qualifying : undefined) ?? [];
  const hasResult = classified.length > 0;
  const status: EventStatus = hasResult ? "finished" : now < startsAt ? "scheduled" : now > endOf(startsAt, kind) ? "finished" : "live";
  const rows = kind === "qualifying" ? (data.qualifying ?? []).map(qualifyingRow) : ((classified as RawResult[]).map(resultRow));
  return {
    provider: PROVIDER,
    externalId: sessionRef(race.season, race.round, kind),
    competitionExternalId: raceRef(race.season, race.round),
    kind: "session",
    name: SESSION_NAMES[kind],
    status,
    startsAt,
    endsAt: hasResult ? endOf(startsAt, kind) : null,
    bestOf: null,
    streams: [],
    result: { type: "classification", session: kind, rows },
    participants: classified.map((r) => ({ entity: driverEntity(r.Driver), score: Number(r.position), isWinner: Number(r.position) === 1 })),
    raw: { season: race.season, round: race.round, session: kind },
  };
}

export function normalizeRace(race: RawRace, data: SessionResults, now: Date = new Date()): EventDTO[] {
  return sessionsOf(race).map((s) => normalizeSession(race, s.kind, s.startsAt, data, now));
}

export function normalizeDriverStandings(season: string, rows: RawDriverStanding[]): StandingDTO[] {
  return rows.map((r) => ({ competitionExternalId: seasonRef(season), entity: driverEntity(r.Driver), rank: Number(r.position), points: Number(r.points), wins: Number(r.wins) }));
}

export function normalizeConstructorStandings(season: string, rows: RawConstructorStanding[]): StandingDTO[] {
  return rows.map((r) => ({ competitionExternalId: seasonRef(season), entity: constructorEntity(r.Constructor), rank: Number(r.position), points: Number(r.points), wins: Number(r.wins) }));
}
