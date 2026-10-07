import { CompetitionDTO, DateWindow, EventDTO, Provider, StructureDTO } from "@news/domain";
import { StartGgClient } from "./client";
import { isMajor, MajorRules, normalizeLeague, normalizePhase, phaseHasBracket, normalizeSet, normalizeStructure, normalizeTournamentSerie, phaseIdOf, pickSinglesEvent, setNumbers } from "./normalize";
import { EVENT_SETS_QUERY, PHASE_CHARACTERS_QUERY, PHASE_LINKS_QUERY, PHASES_QUERY, SET_QUERY, TOURNAMENTS_QUERY } from "./queries";
import { RawGame, RawPhase, RawSet, RawTournament } from "./types";

const DAY_S = 24 * 60 * 60;
const MAX_PAGES = 12;

export const DEFAULT_MAJOR_RULES: Omit<MajorRules, "staffPick"> = { minEntrants: 256, allowSlugs: [] };

interface Tracked {
  tournament: RawTournament;
  eventId: number;
  phases: RawPhase[];
}

// Adaptateur start.gg (docs/01b) : les majors de Smash Ultimate. Conditions d'utilisation : le minimum de données
// (tags de joueur seulement), des tournois choisis (jamais un balayage), des requêtes espacées.
export class StartGgProvider implements Provider {
  private tracked: Tracked[] = [];
  // Dernier passage complet par événement : les suivants ne demandent que les sets modifiés depuis.
  private readonly cursor = new Map<number, number>();
  // Rang de chaque set dans sa ronde (« semifinal 2 »), connu seulement d'un passage complet : un set encore inconnu
  // lors d'un passage partiel en redemande un, sans quoi son nom changerait d'un passage à l'autre.
  private readonly numbers = new Map<string, number | null>();

  constructor(
    private readonly client: StartGgClient,
    private readonly rules: Omit<MajorRules, "staffPick"> = DEFAULT_MAJOR_RULES,
  ) {}

  get quota() {
    return this.client.quota;
  }

  // Tournois à venir (4 mois) ou finis depuis moins de deux semaines, mis en avant par start.gg ou de plus de
  // `minEntrants` inscrits en Singles.
  private async findMajors(now: number): Promise<{ tournament: RawTournament; staffPick: boolean }[]> {
    const variables = { after: now - 14 * DAY_S, before: now + 120 * DAY_S };
    const found = new Map<number, { tournament: RawTournament; staffPick: boolean }>();
    for (const filter of [{ picks: true }, { featured: true }]) {
      for (let page = 1; page <= MAX_PAGES; page++) {
        const data = await this.client.query<{ tournaments: { pageInfo: { totalPages: number }; nodes: RawTournament[] } }>(TOURNAMENTS_QUERY, { ...variables, ...filter, page });
        for (const tournament of data.tournaments.nodes) {
          const known = found.get(tournament.id);
          found.set(tournament.id, { tournament, staffPick: Boolean(known?.staffPick || "picks" in filter) });
        }
        if (page >= data.tournaments.pageInfo.totalPages) break;
      }
    }
    return [...found.values()].filter((f) => isMajor(f.tournament, { ...this.rules, staffPick: f.staffPick }) && (f.tournament.endAt ?? now) >= variables.after);
  }

  async listCompetitions(): Promise<CompetitionDTO[]> {
    const now = new Date();
    const majors = await this.findMajors(Math.floor(now.getTime() / 1000));
    this.tracked = [];
    const competitions: CompetitionDTO[] = [];
    for (const { tournament } of majors) {
      const singles = pickSinglesEvent(tournament);
      if (!singles) continue;
      const data = await this.client.query<{ event: { phases: RawPhase[] | null } | null }>(PHASES_QUERY, { id: singles.id });
      const phases = [...(data.event?.phases ?? [])].sort((a, b) => a.phaseOrder - b.phaseOrder);
      this.tracked.push({ tournament, eventId: singles.id, phases });
      competitions.push(normalizeTournamentSerie(tournament, now), ...phases.map((p) => normalizePhase(tournament, p, now)));
    }
    return competitions.length ? [normalizeLeague(), ...competitions] : [];
  }

  async listEvents(window?: DateWindow): Promise<EventDTO[]> {
    if (this.tracked.length === 0) await this.listCompetitions();
    const now = Math.floor(Date.now() / 1000);
    const events: EventDTO[] = [];
    for (const t of this.tracked) {
      const start = t.tournament.startAt ?? 0;
      const end = t.tournament.endAt ?? start;
      if (window?.onlyLive) {
        // Direct : seulement pendant le tournoi, et seulement les sets modifiés ces dernières minutes.
        if (now < start - 2 * 3600 || now > end + 12 * 3600) continue;
        events.push(...(await this.fetchSets(t.eventId, now - 180)));
        continue;
      }
      const last = this.cursor.get(t.eventId);
      // Un tournoi fini depuis plus de trois jours n'est repris qu'une fois par démarrage du worker.
      if (last !== undefined && now > end + 3 * DAY_S) continue;
      events.push(...(await this.fetchSets(t.eventId, last !== undefined ? last - 60 : undefined)));
      this.cursor.set(t.eventId, now);
    }
    return events;
  }

  private async fetchRawSets(eventId: number, updatedAfter?: number): Promise<RawSet[]> {
    const raws: RawSet[] = [];
    for (let page = 1; page <= 200; page++) {
      const data = await this.client.query<{ event: { sets: { pageInfo: { totalPages: number }; nodes: RawSet[] } | null } | null }>(EVENT_SETS_QUERY, { id: eventId, page, updatedAfter: updatedAfter ?? null });
      const sets = data.event?.sets;
      if (!sets) break;
      raws.push(...sets.nodes);
      if (page >= sets.pageInfo.totalPages) break;
    }
    return raws;
  }

  // Personnages des sets d'une phase à arbre (Top 64, Top 8) : quelques dizaines de sets, donc quelques requêtes.
  private async fetchCharacters(phaseId: number, updatedAfter?: number): Promise<Map<string, RawGame[]>> {
    const byset = new Map<string, RawGame[]>();
    for (let page = 1; page <= MAX_PAGES; page++) {
      const data = await this.client.query<{ phase: { sets: { pageInfo: { totalPages: number }; nodes: { id: number | string; games: RawGame[] | null }[] } | null } | null }>(PHASE_CHARACTERS_QUERY, { id: phaseId, page, updatedAfter: updatedAfter ?? null });
      const sets = data.phase?.sets;
      if (!sets) break;
      for (const node of sets.nodes) if (node.games) byset.set(String(node.id), node.games);
      if (page >= sets.pageInfo.totalPages) break;
    }
    return byset;
  }

  private async fetchSets(eventId: number, updatedAfter?: number): Promise<EventDTO[]> {
    let raws = await this.fetchRawSets(eventId, updatedAfter);
    if (updatedAfter !== undefined && raws.some((r) => !this.numbers.has(String(r.id)))) {
      raws = await this.fetchRawSets(eventId);
      updatedAfter = undefined; // passage complet : les personnages aussi
    }
    if (updatedAfter === undefined || raws.some((r) => !this.numbers.has(String(r.id)))) {
      for (const [id, n] of setNumbers(raws)) this.numbers.set(id, n);
    }
    // Personnages : seulement pour les phases à arbre qui ont des sets dans ce passage.
    const bracketPhases = (this.tracked.find((t) => t.eventId === eventId)?.phases ?? []).filter(phaseHasBracket);
    const inPass = new Set(raws.map((r) => r.phaseGroup?.phase?.id));
    for (const phase of bracketPhases.filter((p) => inPass.has(p.id))) {
      const games = await this.fetchCharacters(phase.id, updatedAfter);
      for (const raw of raws) if (raw.phaseGroup?.phase?.id === phase.id && games.has(String(raw.id))) raw.games = games.get(String(raw.id));
    }
    return raws.flatMap((raw) => normalizeSet(raw, this.numbers.get(String(raw.id)) ?? undefined) ?? []);
  }

  async getEvent(externalId: string): Promise<EventDTO> {
    const data = await this.client.query<{ set: RawSet | null }>(SET_QUERY, { id: externalId });
    const dto = data.set ? normalizeSet(data.set) : null;
    if (!dto) throw new Error(`start.gg : set ${externalId} introuvable`);
    return dto;
  }

  async getStructure(competitionExternalId: string): Promise<StructureDTO> {
    const id = phaseIdOf(competitionExternalId);
    const sets: Pick<RawSet, "id" | "slots">[] = [];
    let bracketType = "DOUBLE_ELIMINATION";
    for (let page = 1; page <= MAX_PAGES; page++) {
      const data = await this.client.query<{ phase: { bracketType: string; sets: { pageInfo: { totalPages: number }; nodes: Pick<RawSet, "id" | "slots">[] } } }>(PHASE_LINKS_QUERY, { id, page });
      bracketType = data.phase.bracketType;
      sets.push(...data.phase.sets.nodes);
      if (page >= data.phase.sets.pageInfo.totalPages) break;
    }
    return normalizeStructure(bracketType, sets);
  }
}
