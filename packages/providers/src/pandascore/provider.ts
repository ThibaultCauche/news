import { CompetitionDTO, DateWindow, EventDTO, Provider } from "@news/domain";
import { PandaScoreClient } from "./client";
import { normalizeCompetitionsFromTournament, normalizeMatch } from "./normalize";
import { RawMatch, RawTournament } from "./types";

function dedupeById<T extends { id: number }>(items: T[]): T[] {
  const byId = new Map(items.map((item) => [item.id, item]));
  return [...byId.values()];
}

// Adaptateur PandaScore (docs/01-donnees-sources-valorant.md) : ligues → séries →
// tournois → matchs, filtré tier S/A pour rester dans le budget de quota (règle 5).
export class PandaScoreProvider implements Provider {
  constructor(private readonly client: PandaScoreClient) {}

  get quota() {
    return this.client.quota;
  }

  async listCompetitions(): Promise<CompetitionDTO[]> {
    const [running, tierSA] = await Promise.all([
      this.client.get<RawTournament[]>("/valorant/tournaments/running?per_page=50"),
      this.client.get<RawTournament[]>("/valorant/tournaments?filter[tier]=s,a&sort=-begin_at&per_page=50"),
    ]);
    const tournaments = dedupeById([...running, ...tierSA]);
    const competitions = tournaments.flatMap((t) => normalizeCompetitionsFromTournament(t));
    const seen = new Set<string>();
    return competitions.filter((c) => {
      const key = `${c.kind}:${c.externalId}`;
      if (seen.has(key)) return false;
      seen.add(key);
      return true;
    });
  }

  async listEvents(window?: DateWindow): Promise<EventDTO[]> {
    if (window?.onlyLive) {
      const running = await this.client.get<RawMatch[]>("/valorant/matches/running");
      return running.map(normalizeMatch);
    }
    const [upcoming, past] = await Promise.all([
      this.client.get<RawMatch[]>("/valorant/matches/upcoming?per_page=50&sort=begin_at"),
      this.client.get<RawMatch[]>("/valorant/matches/past?per_page=50&filter[finished]=true"),
    ]);
    return dedupeById([...upcoming, ...past]).map(normalizeMatch);
  }

  async getEvent(externalId: string): Promise<EventDTO> {
    const match = await this.client.get<RawMatch>(`/valorant/matches/${externalId}`);
    return normalizeMatch(match);
  }
}
