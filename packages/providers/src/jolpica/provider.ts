import { CompetitionDTO, DateWindow, EventDTO, Provider, StandingDTO } from "@news/domain";
import { JolpicaClient } from "./client";
import {
  normalizeConstructorStandings,
  normalizeDriverStandings,
  normalizeGrandPrix,
  normalizeLeague,
  normalizeRace,
  normalizeSeason,
  parseSessionRef,
  SessionResults,
} from "./normalize";
import { RawConstructorStanding, RawDriverStanding, RawRace } from "./types";

const DAY_MS = 24 * 3600_000;
// Pendant les trois jours qui suivent une course, ses classements ne sont redemandés qu'après ce délai.
const REFRESH_MS = 10 * 60_000;

type RaceTable = { RaceTable: { season: string; Races: RawRace[] } };
type StandingsTable<T> = { StandingsTable: { season: string; StandingsLists: T[] } };

const startOf = (race: RawRace) => new Date(`${race.date}T${race.time ?? "00:00:00Z"}`).getTime();

// Adaptateur Jolpica-F1 (docs/01b) : calendrier, résultats et classements de la saison en cours. Pas de direct :
// un classement n'apparaît qu'une fois publié (quelques minutes après l'arrivée).
export class JolpicaProvider implements Provider {
  private season = "";
  private races: RawRace[] = [];
  private readonly results = new Map<string, { data: SessionResults; fetchedAt: number }>();

  constructor(private readonly client: JolpicaClient) {}

  get quota() {
    return this.client.quota;
  }

  private async loadSchedule(): Promise<void> {
    const data = await this.client.get<RaceTable>("/current");
    this.season = data.RaceTable.season;
    this.races = data.RaceTable.Races;
  }

  async listCompetitions(): Promise<CompetitionDTO[]> {
    await this.loadSchedule();
    const now = new Date();
    return [normalizeLeague(), normalizeSeason(this.season, this.races, now), ...this.races.map((r) => normalizeGrandPrix(r, now))];
  }

  // Classements de course, de sprint et de qualification d'un week-end. Un week-end encore lointain n'a rien à
  // demander ; un week-end fini depuis plus de trois jours n'est lu qu'une fois par démarrage du worker.
  private async resultsOf(race: RawRace, now: number): Promise<SessionResults> {
    const start = startOf(race);
    if (now < start - 2 * DAY_MS) return {};
    const cached = this.results.get(race.round);
    if (cached && (now > start + 3 * DAY_MS || now - cached.fetchedAt < REFRESH_MS)) return cached.data;
    const route = `/${race.season}/${race.round}`;
    const races = async (name: string) => (await this.client.get<RaceTable>(`${route}/${name}`)).RaceTable.Races[0];
    const data: SessionResults = {
      results: (await races("results"))?.Results,
      qualifying: (await races("qualifying"))?.QualifyingResults,
      sprint: race.Sprint ? (await races("sprint"))?.SprintResults : undefined,
    };
    this.results.set(race.round, { data, fetchedAt: now });
    return data;
  }

  async listEvents(window?: DateWindow): Promise<EventDTO[]> {
    if (this.races.length === 0) await this.loadSchedule();
    const now = Date.now();
    const events: EventDTO[] = [];
    for (const race of this.races) {
      // Pas de direct chez Jolpica : le job rapide ne relit que le week-end en cours, pour que les statuts suivent l'horloge.
      if (window?.onlyLive && (now < startOf(race) - 3 * DAY_MS || now > startOf(race) + DAY_MS)) continue;
      events.push(...normalizeRace(race, await this.resultsOf(race, now), new Date(now)));
    }
    return events;
  }

  async getEvent(externalId: string): Promise<EventDTO> {
    if (this.races.length === 0) await this.loadSchedule();
    const { round } = parseSessionRef(externalId);
    const race = this.races.find((r) => r.round === round);
    const event = race && normalizeRace(race, await this.resultsOf(race, Date.now())).find((e) => e.externalId === externalId);
    if (!event) throw new Error(`Jolpica : session ${externalId} introuvable`);
    return event;
  }

  async listStandings(): Promise<StandingDTO[]> {
    if (!this.season) await this.loadSchedule();
    const drivers = await this.client.get<StandingsTable<{ DriverStandings: RawDriverStanding[] }>>(`/${this.season}/driverstandings`);
    const teams = await this.client.get<StandingsTable<{ ConstructorStandings: RawConstructorStanding[] }>>(`/${this.season}/constructorstandings`);
    return [
      ...normalizeDriverStandings(this.season, drivers.StandingsTable.StandingsLists[0]?.DriverStandings ?? []),
      ...normalizeConstructorStandings(this.season, teams.StandingsTable.StandingsLists[0]?.ConstructorStandings ?? []),
    ];
  }
}
