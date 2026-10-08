import { CompetitionDTO, createLogger, DateWindow, electionEmbargo, ElectionConfig, ElectionResult, ELECTIONS, EventDTO, isElectionDay, parisTime, Provider, TerritoryLevel } from "@news/domain";
import { BureauxByCommune, countBureaux, isBureauResource } from "./bureaux";
import { DatasetResource, ElectionsClient } from "./client";
import { decodeCsv, eachCsvRow } from "./csv";
import { normalizeElection, normalizeLeague, normalizeMunicipalesRow, normalizeResult } from "./normalize";
import { matchElectionDataset, normalizePresidentialRow, pickPresidentialResource } from "./presidential";

const logger = createLogger("providers:elections");

// Le soir du scrutin les fichiers sont remplacés au fil du dépouillement : on les relit chaque minute. Après coup ils ne
// bougent plus (« sous réserve de recours »), six heures suffisent. Le fichier par bureau pèse 10 à 37 Mo : relu toutes
// les cinq minutes le soir même.
const NIGHT_REFRESH_MS = 60_000;
const BUREAUX_NIGHT_REFRESH_MS = 5 * 60_000;
const IDLE_REFRESH_MS = 6 * 3600_000;
const DATASET_SEARCH_MS = 30 * 60_000;

/** La ressource à lire : celle dont le titre contient le fragment attendu, la plus récente (hors Polynésie et arrondissements). */
export function pickResource(resources: DatasetResource[], match: string): DatasetResource | null {
  return (
    resources
      .filter((r) => r.title.includes(match) && !/Polyn[ée]sie|arrondissement/i.test(r.title))
      .sort((a, b) => (b.lastModified ?? "").localeCompare(a.lastModified ?? ""))[0] ?? null
  );
}

// Adaptateur des résultats d'élections (docs/01c, J29c). Municipales : les 35 000 communes ne tiennent pas dans l'appli,
// seules les `featured` plus peuplées sont gardées. Présidentielle : la France entière et les départements. Jamais de
// lecture avant 20 h le jour du scrutin (article L52-2) : le fichier n'existe pas encore, mais la règle est aussi codée
// ici, pas seulement dans l'API.
export class ElectionsProvider implements Provider {
  private readonly cache = new Map<string, { fetchedAt: number; events: EventDTO[] }>();
  private readonly bureauxCache = new Map<string, { fetchedAt: number; value: BureauxByCommune }>();
  private readonly datasetCache = new Map<string, { fetchedAt: number; id: string | null }>();

  constructor(
    private readonly client: ElectionsClient,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  get quota() {
    return this.client.quota;
  }

  async listCompetitions(): Promise<CompetitionDTO[]> {
    const now = this.clock();
    return [normalizeLeague(), ...ELECTIONS.map((e) => normalizeElection(e, now))];
  }

  // Le jeu de données d'un scrutin : celui de la configuration, sinon retrouvé par recherche (présidentielle 2027), à partir de
  // la veille du scrutin.
  private async datasetOf(election: ElectionConfig, now: Date): Promise<string | null> {
    if (election.datasetId) return election.datasetId;
    if (!election.search || now.getTime() < parisTime(election.date, 0).getTime() - 24 * 3600_000) return null;
    const cached = this.datasetCache.get(election.id);
    if (cached && now.getTime() - cached.fetchedAt < DATASET_SEARCH_MS) return cached.id;
    const found = matchElectionDataset(election, await this.client.search(election.search.replace(/\b1er tour|2nd tour/, "").trim()));
    this.datasetCache.set(election.id, { fetchedAt: now.getTime(), id: found?.id ?? null });
    if (found) logger.info({ election: election.id, dataset: found.title }, "jeu de données trouvé");
    return found?.id ?? null;
  }

  private async resultsOf(election: ElectionConfig): Promise<EventDTO[]> {
    const now = this.clock();
    // Rien avant 20 h le jour du scrutin, ni avant le jour même.
    if (electionEmbargo(election.date, now).embargoed || now < new Date(`${election.date}T00:00:00Z`)) return [];
    const ttl = isElectionDay(election.date, now) ? NIGHT_REFRESH_MS : IDLE_REFRESH_MS;
    const cached = this.cache.get(election.id);
    if (cached && now.getTime() - cached.fetchedAt < ttl) return cached.events;

    const datasetId = await this.datasetOf(election, now);
    if (!datasetId) return [];
    const resources = await this.client.resources(datasetId);
    const results = election.type === "municipales" ? await this.municipales(election, resources, now) : await this.presidential(election, resources);
    // Au 1ᵉʳ tour, une grande ville n'a aucun siège attribué : le résultat est pourtant définitif une fois la journée passée.
    const past = now >= parisTime(election.date, 24);
    const events = results.map((r) => normalizeResult({ ...r, complete: r.complete || past }));
    this.cache.set(election.id, { fetchedAt: now.getTime(), events });
    return events;
  }

  private async csvRows(url: string, onRow: (header: string[], row: string[]) => void): Promise<void> {
    let header: string[] | null = null;
    eachCsvRow(decodeCsv(await this.client.download(url)), (row) => {
      if (!header) header = row;
      else onRow(header, row);
    });
  }

  private async municipales(election: ElectionConfig, resources: DatasetResource[], now: Date): Promise<ElectionResult[]> {
    const resource = election.resourceMatch ? pickResource(resources, election.resourceMatch) : null;
    if (!resource) {
      logger.warn({ election: election.id }, "aucune ressource de résultats trouvée");
      return [];
    }
    const results: ElectionResult[] = [];
    await this.csvRows(resource.url, (header, row) => {
      const result = normalizeMunicipalesRow(header, row, election, resource.url);
      if (result) results.push(result);
    });
    // Les communes les plus peuplées d'abord ; en cas d'égalité l'ordre du code commune rend le tri stable.
    const kept = results.sort((a, b) => b.registered - a.registered || a.territory.code.localeCompare(b.territory.code)).slice(0, election.featured);
    logger.info({ election: election.id, communes: results.length, kept: kept.length, file: resource.title }, "résultats lus");

    const bureaux = await this.bureauxOf(election, resources, now);
    return kept.map((r) => ({ ...r, bureaux: bureaux?.get(r.territory.code) ?? null }));
  }

  // Bureaux dépouillés des communes gardées : un fichier lourd, lu moins souvent ; un échec ne bloque pas les résultats.
  private async bureauxOf(election: ElectionConfig, resources: DatasetResource[], now: Date): Promise<BureauxByCommune | null> {
    const resource = election.resourceMatch ? resources.filter((r) => isBureauResource(r.title, election.resourceMatch!)).sort((a, b) => (b.lastModified ?? "").localeCompare(a.lastModified ?? ""))[0] : undefined;
    if (!resource) return null;
    const cached = this.bureauxCache.get(election.id);
    const ttl = isElectionDay(election.date, now) ? BUREAUX_NIGHT_REFRESH_MS : IDLE_REFRESH_MS;
    if (cached && now.getTime() - cached.fetchedAt < ttl) return cached.value;
    try {
      const value = countBureaux(decodeCsv(await this.client.download(resource.url)));
      this.bureauxCache.set(election.id, { fetchedAt: now.getTime(), value });
      return value;
    } catch (err) {
      logger.warn({ err, election: election.id }, "fichier par bureau illisible, bureaux non affichés");
      return cached?.value ?? null;
    }
  }

  // Présidentielle : la France entière puis les départements, deux petits fichiers.
  private async presidential(election: ElectionConfig, resources: DatasetResource[]): Promise<ElectionResult[]> {
    const results: ElectionResult[] = [];
    for (const level of ["national", "department"] as const satisfies readonly TerritoryLevel[]) {
      const resource = pickPresidentialResource(resources, level, election.round);
      if (!resource) {
        logger.warn({ election: election.id, level }, "aucune ressource de résultats trouvée");
        continue;
      }
      await this.csvRows(resource.url, (header, row) => {
        const result = normalizePresidentialRow(header, row, election, level, resource.url);
        if (result) results.push(result);
      });
    }
    logger.info({ election: election.id, territories: results.length }, "résultats de la présidentielle lus");
    return results;
  }

  async listEvents(window?: DateWindow): Promise<EventDTO[]> {
    const now = this.clock();
    const events: EventDTO[] = [];
    for (const election of ELECTIONS) {
      // Le job rapide (toutes les 30 s) ne sert que le soir même.
      if (window?.onlyLive && !isElectionDay(election.date, now)) continue;
      events.push(...(await this.resultsOf(election)));
    }
    return events;
  }

  async getEvent(externalId: string): Promise<EventDTO> {
    const event = (await this.listEvents()).find((e) => e.externalId === externalId);
    if (!event) throw new Error(`Élections : ${externalId} introuvable`);
    return event;
  }
}
