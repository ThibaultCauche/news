import { CompetitionDTO, DateWindow, EventDTO, Provider, StructureDTO } from "@news/domain";
import { PandaScoreClient } from "./client";
import { normalizeCompetitionsFromTournament, normalizeMatch, normalizeStructure } from "./normalize";
import { RawMatch, RawTournament } from "./types";

function dedupeById<T extends { id: number }>(items: T[]): T[] {
  const byId = new Map(items.map((item) => [item.id, item]));
  return [...byId.values()];
}

const DAY_MS = 24 * 60 * 60 * 1000;

// Un jeu PandaScore : `slug` = notre slug de jeu (`competition.game`), `path` = son préfixe d'URL.
// `tierOnly` : le jeu a des dizaines de petites ligues (LoL) ; on ne suit que les tournois de tier S/A, et les
// matchs sont demandés par tournoi (l'API ne filtre pas les matchs par tier). Valorant garde son rythme du J1.
interface GameSource {
  slug: string;
  path: string;
  tierOnly: boolean;
}

export const PANDASCORE_GAMES: GameSource[] = [
  { slug: "valorant", path: "valorant", tierOnly: false },
  { slug: "league-of-legends", path: "lol", tierOnly: true },
];

interface TrackedTournament {
  id: number;
  beginAt: Date | null;
  endAt: Date | null;
}

// Adaptateur PandaScore (docs/01-donnees-sources-valorant.md) : ligues → séries →
// tournois → matchs, filtré tier S/A pour rester dans le budget de quota (règle 5).
export class PandaScoreProvider implements Provider {
  // Tournois suivis par jeu `tierOnly`, remplis par le catalogue.
  private readonly tracked = new Map<string, TrackedTournament[]>();

  constructor(
    private readonly client: PandaScoreClient,
    private readonly games: GameSource[] = PANDASCORE_GAMES,
  ) {}

  get quota() {
    return this.client.quota;
  }

  async listCompetitions(): Promise<CompetitionDTO[]> {
    const perGame = await Promise.all(this.games.map((g) => this.listGameCompetitions(g)));
    return perGame.flat();
  }

  private async listGameCompetitions(game: GameSource): Promise<CompetitionDTO[]> {
    const tier = game.tierOnly ? "&filter[tier]=s,a" : "";
    const [running, tierSA] = await Promise.all([
      this.client.get<RawTournament[]>(`/${game.path}/tournaments/running?per_page=50${tier}`),
      this.client.get<RawTournament[]>(`/${game.path}/tournaments?filter[tier]=s,a&sort=-begin_at&per_page=50`),
    ]);
    const tournaments = dedupeById([...running, ...tierSA]);
    if (game.tierOnly) this.rememberTracked(game, tournaments);
    const competitions = tournaments.flatMap((t) => normalizeCompetitionsFromTournament({ ...t, videogame: t.videogame ?? { slug: game.slug } }));
    const seen = new Set<string>();
    return competitions.filter((c) => {
      const key = `${c.kind}:${c.externalId}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  // Tournois qui ont des matchs à ingérer : en cours, à venir dans le mois, ou finis depuis moins d'une semaine.
  private rememberTracked(game: GameSource, tournaments: RawTournament[]): void {
    const now = Date.now();
    this.tracked.set(
      game.slug,
      tournaments
        .map((t) => ({ id: t.id, beginAt: t.begin_at ? new Date(t.begin_at) : null, endAt: t.end_at ? new Date(t.end_at) : null }))
        .filter((t) => (!t.endAt || t.endAt.getTime() >= now - 7 * DAY_MS) && (!t.beginAt || t.beginAt.getTime() <= now + 30 * DAY_MS)),
    );
  }

  private async trackedOf(game: GameSource): Promise<TrackedTournament[]> {
    if (!this.tracked.has(game.slug)) await this.listGameCompetitions(game);
    return this.tracked.get(game.slug) ?? [];
  }

  async listEvents(window?: DateWindow): Promise<EventDTO[]> {
    const perGame = await Promise.all(this.games.map((g) => this.listGameEvents(g, window)));
    return perGame.flat();
  }

  private async listGameEvents(game: GameSource, window?: DateWindow): Promise<EventDTO[]> {
    if (!game.tierOnly) {
      if (window?.onlyLive) {
        const running = await this.client.get<RawMatch[]>(`/${game.path}/matches/running`);
        return running.map(normalizeMatch);
      }
      const [upcoming, past] = await Promise.all([
        this.client.get<RawMatch[]>(`/${game.path}/matches/upcoming?per_page=50&sort=begin_at`),
        this.client.get<RawMatch[]>(`/${game.path}/matches/past?per_page=50&filter[finished]=true`),
      ]);
      return dedupeById([...upcoming, ...past]).map(normalizeMatch);
    }

    const tracked = await this.trackedOf(game);
    const now = Date.now();
    if (window?.onlyLive) {
      // Pas d'appel au rythme du direct tant qu'aucun tournoi suivi n'a lieu : économise ~120 requêtes par heure.
      const playing = tracked.filter((t) => (!t.beginAt || t.beginAt.getTime() <= now + 60 * 60 * 1000) && (!t.endAt || t.endAt.getTime() >= now - 6 * 60 * 60 * 1000));
      if (playing.length === 0) return [];
      const running = await this.client.get<RawMatch[]>(`/${game.path}/matches/running?filter[tournament_id]=${playing.map((t) => t.id).join(",")}`);
      return running.map(normalizeMatch);
    }
    if (tracked.length === 0) return [];
    const ids = tracked.map((t) => t.id).join(",");
    const [upcoming, past] = await Promise.all([
      this.client.get<RawMatch[]>(`/${game.path}/matches/upcoming?per_page=100&sort=begin_at&filter[tournament_id]=${ids}`),
      this.client.get<RawMatch[]>(`/${game.path}/matches/past?per_page=100&filter[finished]=true&sort=-begin_at&filter[tournament_id]=${ids}`),
    ]);
    return dedupeById([...upcoming, ...past]).map(normalizeMatch);
  }

  async getEvent(externalId: string): Promise<EventDTO> {
    const match = await this.client.get<RawMatch>(`/matches/${externalId}`);
    return normalizeMatch(match);
  }

  // Bracket d'un tournoi (docs/01 : gratuit, clé pour l'arbre — job "structure" du J5).
  // Les classements ne sont pas demandés ici : recalculés depuis nos propres matchs.
  async getStructure(competitionExternalId: string): Promise<StructureDTO> {
    const matches = await this.client.get<RawMatch[]>(`/tournaments/${competitionExternalId}/brackets`);
    return normalizeStructure(matches);
  }
}
