import {
  CompetitionDTO,
  ELECTION_KIND,
  ELECTION_RESULT_KIND,
  ELECTIONS_LEAGUE_GAME,
  electionEmbargo,
  ElectionConfig,
  electionLabel,
  ElectionList,
  ElectionResult,
  electionRef,
  EventDTO,
  isComplete,
  LIVE_FEED_FORMAT,
  parisTime,
} from "@news/domain";
import { frNumber } from "./csv";

export const PROVIDER = "elections";
export const LEAGUE_EXTERNAL_ID = "league:elections";
export const resultRef = (electionId: string, code: string) => `result:${electionId}:${code}`;

export function normalizeLeague(): CompetitionDTO {
  return {
    provider: PROVIDER,
    externalId: LEAGUE_EXTERNAL_ID,
    parentExternalId: null,
    kind: "league",
    game: ELECTIONS_LEAGUE_GAME,
    imageUrl: null,
    name: "Élections",
    status: null,
    startsAt: null,
    endsAt: null,
    importance: 0,
    hasBracket: false,
    raw: { league: LEAGUE_EXTERNAL_ID },
  };
}

// Une élection est une compétition qui se suit en direct (format `live_feed`) : ses événements sont les résultats des
// territoires, publiés après 20 h.
export function normalizeElection(election: ElectionConfig, now: Date): CompetitionDTO {
  const { liftsAt } = electionEmbargo(election.date, now);
  const opens = parisTime(election.date, 8);
  const structure = { electionId: election.id, type: election.type, round: election.round, date: election.date, liftsAt: liftsAt.toISOString(), hasResults: election.datasetId !== null };
  return {
    provider: PROVIDER,
    externalId: electionRef(election.id),
    parentExternalId: LEAGUE_EXTERNAL_ID,
    kind: ELECTION_KIND,
    game: ELECTIONS_LEAGUE_GAME,
    imageUrl: null,
    name: electionLabel(election),
    status: now < opens ? "scheduled" : now < parisTime(election.date, 24) ? "live" : "finished",
    startsAt: opens,
    endsAt: liftsAt,
    importance: election.type === "presidentielle" ? 3 : 1,
    hasBracket: false,
    format: LIVE_FEED_FORMAT,
    structure,
    raw: structure,
  };
}

/** Rang de la première colonne de chaque liste, d'après l'en-tête (« Numéro de panneau 1 », « … 2 »…). */
function listCount(header: string[]): number {
  return header.filter((h) => /^Numéro de panneau \d+$/.test(h)).length;
}

// Une ligne du fichier « Résultats - Communes » des municipales : une commune, ses chiffres, puis ses listes à plat
// (numéro de panneau, tête de liste, libellé, voix, % des exprimés, élu, sièges…).
export function normalizeMunicipalesRow(header: string[], row: string[], election: ElectionConfig, sourceUrl: string): ElectionResult | null {
  const at = new Map(header.map((h, i) => [h, i]));
  const cell = (name: string) => row[at.get(name) ?? -1] ?? "";
  const code = cell("Code commune");
  if (!code) return null;

  const lists: ElectionList[] = [];
  for (let k = 1; k <= listCount(header); k++) {
    const panel = cell(`Numéro de panneau ${k}`);
    if (!panel) continue;
    const family = cell(`Prénom candidat ${k}`);
    const family2 = cell(`Nom candidat ${k}`);
    lists.push({
      panel: Number(panel),
      label: cell(`Libellé de liste ${k}`) || cell(`Libellé abrégé de liste ${k}`),
      head: [family, family2].filter(Boolean).join(" ") || null,
      votes: frNumber(cell(`Voix ${k}`)),
      pctExpressed: frNumber(cell(`% Voix/exprimés ${k}`)),
      elected: /^(élu|elu|oui)$/i.test(cell(`Elu ${k}`)),
      seatsCouncil: frNumber(cell(`Sièges au CM ${k}`)),
      seatsCommunity: frNumber(cell(`Sièges au CC ${k}`)),
    });
  }
  lists.sort((a, b) => b.votes - a.votes || a.panel - b.panel);
  return {
    type: "election_result",
    electionId: election.id,
    date: election.date,
    level: "commune",
    candidates: false,
    territory: { code, name: cell("Libellé commune"), department: cell("Libellé département") },
    registered: frNumber(cell("Inscrits")),
    voters: frNumber(cell("Votants")),
    turnoutPct: frNumber(cell("% Votants")),
    blank: frNumber(cell("Blancs")),
    nulls: frNumber(cell("Nuls")),
    expressed: frNumber(cell("Exprimés")),
    lists,
    complete: isComplete(lists),
    bureaux: null,
    sourceUrl,
  };
}

export function normalizeResult(result: ElectionResult): EventDTO {
  const at = parisTime(result.date, 20);
  return {
    provider: PROVIDER,
    externalId: resultRef(result.electionId, result.level === "commune" ? result.territory.code : `${result.level}-${result.territory.code}`),
    competitionExternalId: electionRef(result.electionId),
    kind: ELECTION_RESULT_KIND,
    name: result.territory.name,
    status: result.complete ? "finished" : "live",
    startsAt: at,
    endsAt: result.complete ? at : null,
    bestOf: null,
    streams: [],
    result,
    participants: [],
    raw: result,
  };
}
