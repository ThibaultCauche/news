// Élections (J29c, docs/01c) : résultats officiels du ministère de l'Intérieur (data.gouv.fr), le soir du scrutin.
// Règles pures : blocage avant 20 h (article L52-2 du code électoral), forme d'un résultat de territoire.

export const ELECTION_KIND = "election";
export const ELECTION_RESULT_KIND = "election_result";
export const ELECTIONS_LEAGUE_GAME = "elections";
/** Format d'une compétition qui se suit en direct, résultat après résultat (docs/03 §2). */
export const LIVE_FEED_FORMAT = "live_feed";

/** Heure (de Paris) avant laquelle aucun résultat ne peut être publié le jour du scrutin : fermeture des derniers bureaux de la métropole. */
export const EMBARGO_HOUR_PARIS = 20;

export interface ElectionConfig {
  id: string;
  name: string;
  /** « municipales », « presidentielle » : choisit le format de fichier à lire. */
  type: "municipales" | "presidentielle";
  round: 1 | 2;
  /** Jour du scrutin (dimanche), « AAAA-MM-JJ ». */
  date: string;
  /** Jeu de données data.gouv.fr du ministère ; `null` tant qu'il n'est pas publié (présidentielle 2027). */
  datasetId: string | null;
  /** Fragment du titre de la ressource à lire parmi celles du jeu de données. */
  resourceMatch: string | null;
  /** Nombre de territoires gardés (les plus peuplés) : les 35 000 communes ne tiennent pas dans l'appli. */
  featured: number;
  /**
   * Recherche du jeu de données sur data.gouv.fr tant que `datasetId` est inconnu (présidentielle 2027) : mots du titre
   * à retrouver parmi les jeux du ministère de l'Intérieur. `null` pour un jeu déjà connu.
   */
  search: string | null;
}

// Les scrutins connus. Le jeu de données de la présidentielle 2027 sera ajouté à sa publication : le format des fichiers
// est à vérifier sur un scrutin partiel avant (docs/04 J29).
export const ELECTIONS: ElectionConfig[] = [
  { id: "municipales-2026-t1", name: "Municipales 2026", type: "municipales", round: 1, date: "2026-03-15", datasetId: "69b82a7de5d58cc06ad35ce0", resourceMatch: "Municipales 2026 - Résultats - Communes_", featured: 20, search: null },
  { id: "municipales-2026-t2", name: "Municipales 2026", type: "municipales", round: 2, date: "2026-03-22", datasetId: "69c17fed9f18c7781fd11a14", resourceMatch: "Municipales 2026 - Résultats - Communes_", featured: 20, search: null },
  { id: "presidentielle-2027-t1", name: "Présidentielle 2027", type: "presidentielle", round: 1, date: "2027-04-18", datasetId: null, resourceMatch: null, featured: 0, search: "présidentielle 2027 1er tour" },
  { id: "presidentielle-2027-t2", name: "Présidentielle 2027", type: "presidentielle", round: 2, date: "2027-05-02", datasetId: null, resourceMatch: null, featured: 0, search: "présidentielle 2027 2nd tour" },
];

export const electionRef = (id: string) => `election:${id}`;
export const electionLabel = (e: Pick<ElectionConfig, "name" | "round">) => `${e.name} · ${e.round === 1 ? "1ᵉʳ" : "2ᵈ"} tour`;

// Décalage de Paris par rapport à UTC un jour donné (+1 h l'hiver, +2 h l'été), lu dans la base de fuseaux du système.
function parisOffsetMinutes(at: Date): number {
  const part = new Intl.DateTimeFormat("en-US", { timeZone: "Europe/Paris", timeZoneName: "shortOffset" }).formatToParts(at).find((p) => p.type === "timeZoneName")?.value ?? "GMT+1";
  const m = part.match(/GMT([+-])(\d+)(?::(\d+))?/);
  return m ? (m[1] === "-" ? -1 : 1) * (Number(m[2]) * 60 + Number(m[3] ?? 0)) : 60;
}

/** Instant (UTC) où il est `hour` h à Paris le jour `day`. */
export function parisTime(day: string, hour: number): Date {
  const guess = new Date(`${day}T${String(hour).padStart(2, "0")}:00:00Z`);
  // Le décalage dépend de l'instant : on le lit à l'instant deviné puis on corrige une fois.
  const first = new Date(guess.getTime() - parisOffsetMinutes(guess) * 60_000);
  return new Date(guess.getTime() - parisOffsetMinutes(first) * 60_000);
}

export interface Embargo {
  /** Vrai le jour du scrutin avant 20 h : aucun résultat ne doit sortir de l'API. */
  embargoed: boolean;
  /** Instant où le blocage se lève. */
  liftsAt: Date;
}

/**
 * Article L52-2 du code électoral : aucun résultat, estimation ni projection avant la fermeture du dernier bureau de vote
 * de la métropole. On bloque donc tout, codé en dur, jusqu'à 20 h (heure de Paris) le jour du scrutin. La veille et les
 * jours d'avant, il n'y a rien à bloquer (rien n'existe) ; après 20 h, tout est public.
 */
export function electionEmbargo(date: string, now: Date): Embargo {
  const liftsAt = parisTime(date, EMBARGO_HOUR_PARIS);
  const dayStart = parisTime(date, 0);
  return { embargoed: now >= dayStart && now < liftsAt, liftsAt };
}

/** Le jour du scrutin (jusqu'à minuit, heure de Paris) : le rythme rapide de l'ingestion ne sert qu'à ça. */
export function isElectionDay(date: string, now: Date): boolean {
  return now >= parisTime(date, 0) && now < parisTime(date, 24);
}

export interface ElectionList {
  /** Numéro de panneau officiel. */
  panel: number;
  label: string;
  head: string | null;
  votes: number;
  /** % des suffrages exprimés. */
  pctExpressed: number;
  elected: boolean;
  /** Sièges au conseil municipal. */
  seatsCouncil: number;
  /** Sièges au conseil communautaire. */
  seatsCommunity: number;
}

export type TerritoryLevel = "commune" | "department" | "national";

// `result` d'un événement `election_result` : le résultat d'un territoire (commune, département ou France entière).
export interface ElectionResult {
  type: "election_result";
  electionId: string;
  date: string;
  level: TerritoryLevel;
  /** Les « listes » sont des candidats (présidentielle) : pas de sièges, pas de tête de liste. */
  candidates: boolean;
  territory: { code: string; name: string; department: string };
  registered: number;
  voters: number;
  turnoutPct: number;
  blank: number;
  nulls: number;
  expressed: number;
  /** Listes ou candidats, du plus de voix au moins. */
  lists: ElectionList[];
  /** Tous les sièges sont attribués (municipales) ou la saisie est complète (présidentielle) : le résultat est définitif. */
  complete: boolean;
  /** Bureaux de vote dépouillés sur le total, quand le fichier par bureau est lu. */
  bureaux: { counted: number; total: number } | null;
  sourceUrl: string;
}

/** Sièges nécessaires pour la majorité absolue d'un conseil de `total` sièges (la moitié plus un). */
export const majoritySeats = (total: number) => Math.floor(total / 2) + 1;

/** Un résultat est définitif quand des sièges sont attribués (municipales) : sinon le dépouillement continue. */
export const isComplete = (lists: Pick<ElectionList, "seatsCouncil" | "elected">[]) => lists.some((l) => l.seatsCouncil > 0 || l.elected);
