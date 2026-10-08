import { CompetitionDTO, createLogger, DateWindow, EventDTO, Provider } from "@news/domain";
import { AssembleeClient, ASSEMBLEE_FILES } from "./client";
import { actorsOf, BuiltLaw, groupsOf, normalizeLaw, normalizeLeague, normalizeVote, parseScrutin, ParsedVote, titleKey } from "./normalize";
import { RawActeur, RawDocument, RawDossier, RawOrgane, RawScrutin } from "./types";
import { eachZipJson } from "./zip";

const logger = createLogger("providers:assemblee");

// L'Assemblée met ses archives à jour une fois par jour : inutile de les retélécharger plus souvent que ça.
const REFRESH_MS = 6 * 3600_000;

interface Snapshot {
  fetchedAt: number;
  competitions: CompetitionDTO[];
  events: EventDTO[];
}

// Adaptateur de l'open data de l'Assemblée nationale (docs/01c, J29) : textes de loi débattus en séance et votes sur
// leur ensemble. Pas de direct (les archives ne changent qu'une fois par jour) ; `onlyLive` ne renvoie donc rien.
export class AssembleeProvider implements Provider {
  private snapshot: Snapshot | null = null;
  private loading: Promise<Snapshot> | null = null;

  constructor(private readonly client: AssembleeClient) {}

  get quota() {
    return this.client.quota;
  }

  private current(): Promise<Snapshot> {
    if (this.snapshot && Date.now() - this.snapshot.fetchedAt < REFRESH_MS) return Promise.resolve(this.snapshot);
    // Un seul téléchargement à la fois : le job du catalogue et celui du calendrier arrivent souvent ensemble.
    this.loading ??= this.build()
      .then((snapshot) => (this.snapshot = snapshot))
      .finally(() => (this.loading = null));
    return this.loading;
  }

  private async build(): Promise<Snapshot> {
    const started = Date.now();
    const organes: RawOrgane[] = [];
    const acteurs: RawActeur[] = [];
    eachZipJson(await this.client.download(ASSEMBLEE_FILES.organes), (name, json) => {
      const doc = json as { organe?: RawOrgane; acteur?: RawActeur };
      if (doc.organe?.codeType === "GP") organes.push(doc.organe);
      else if (doc.acteur) acteurs.push(doc.acteur);
    });
    const groups = groupsOf(organes);
    const actors = actorsOf(acteurs);

    // Votes sur l'ensemble d'un texte, rattachés à leur dossier : par `dossierRef` quand le scrutin l'indique, sinon par
    // le titre du texte (les trois quarts des scrutins sur l'ensemble ne disent pas leur dossier).
    const overall: ParsedVote[] = [];
    eachZipJson(await this.client.download(ASSEMBLEE_FILES.scrutins), (_, json) => {
      const parsed = parseScrutin((json as { scrutin: RawScrutin }).scrutin, groups);
      if (parsed?.overall) overall.push(parsed);
    });

    const dossiers: RawDossier[] = [];
    const dossiersByTitle = new Map<string, Set<string>>();
    eachZipJson(await this.client.download(ASSEMBLEE_FILES.dossiers), (name, json) => {
      if (name.includes("/document/")) {
        const doc = (json as { document?: RawDocument }).document;
        const title = doc?.titres?.titrePrincipal;
        if (doc?.dossierRef && title) dossiersByTitle.set(titleKey(title), (dossiersByTitle.get(titleKey(title)) ?? new Set()).add(doc.dossierRef));
      } else if (name.includes("DLR5L17")) {
        dossiers.push((json as { dossierParlementaire: RawDossier }).dossierParlementaire);
      }
    });

    const votesByDossier = new Map<string, ParsedVote[]>();
    for (const vote of overall) {
      const byTitle = dossiersByTitle.get(titleKey(vote.title));
      // Un titre partagé par plusieurs dossiers est ambigu : le vote reste sans rattachement.
      const ref = vote.dossierRef ?? (byTitle?.size === 1 ? [...byTitle][0] : null);
      if (ref) votesByDossier.set(ref, [...(votesByDossier.get(ref) ?? []), vote]);
    }

    const laws: BuiltLaw[] = [];
    const events: EventDTO[] = [];
    for (const dossier of dossiers) {
      const votes = votesByDossier.get(dossier.uid) ?? [];
      const law = normalizeLaw(dossier, votes, actors, groups);
      if (!law) continue;
      laws.push(law);
      events.push(...votes.map((v) => normalizeVote(v, law.competition.externalId)));
    }
    logger.info({ laws: laws.length, votes: events.length, groups: groups.size, ms: Date.now() - started }, "archives de l'Assemblée lues");
    return { fetchedAt: Date.now(), competitions: [normalizeLeague(), ...laws.map((l) => l.competition)], events };
  }

  async listCompetitions(): Promise<CompetitionDTO[]> {
    return (await this.current()).competitions;
  }

  async listEvents(window?: DateWindow): Promise<EventDTO[]> {
    if (window?.onlyLive) return [];
    return (await this.current()).events;
  }

  async getEvent(externalId: string): Promise<EventDTO> {
    const event = (await this.current()).events.find((e) => e.externalId === externalId);
    if (!event) throw new Error(`Assemblée : ${externalId} introuvable`);
    return event;
  }
}
