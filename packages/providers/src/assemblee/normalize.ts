import {
  CompetitionDTO,
  computeLawProcess,
  EntityDTO,
  EventDTO,
  groupPosition,
  isLawProcedure,
  LAW_FORMAT,
  LawAct,
  LawAuthor,
  LawStructure,
  lawTypeOf,
  LawVoteInput,
  POLITICS_GAME,
  reachedFloor,
  sortGroupsNeutral,
  VOTE_KIND,
  VoteGroupResult,
  VoteResult,
} from "@news/domain";
import { RawAct, RawActeur, RawDossier, RawMandat, RawOrgane, RawScrutin } from "./types";

export const PROVIDER = "assemblee";
export const LEAGUE_EXTERNAL_ID = "league:an17";
export const lawRef = (dossierUid: string) => `law:${dossierUid}`;
export const voteRef = (numero: number | string) => `vote:${numero}`;
export const groupRef = (organeUid: string) => `group:${organeUid}`;

const SITE = "https://www.assemblee-nationale.fr/dyn/17";

const arr = <T>(x: T | T[] | null | undefined): T[] => (x == null ? [] : Array.isArray(x) ? x : [x]);
const int = (s: string | undefined) => Number.parseInt(s ?? "0", 10) || 0;
const day = (s: string | null | undefined) => (s ? s.slice(0, 10) : null);
const at = (date: string) => new Date(`${date}T12:00:00Z`);

// Le groupe UDR a changé d'identifiant d'organe en cours de législature (docs/01c) : ses anciens scrutins gardent l'ancien.
const GROUP_ALIASES: Record<string, string> = { PO847173: "PO872880" };

export interface GroupInfo {
  name: string;
  shortName: string | null;
}

// Groupes politiques de la législature, par identifiant d'organe (« PO845401 »).
export function groupsOf(organes: RawOrgane[]): Map<string, GroupInfo> {
  return new Map(organes.filter((o) => o.codeType === "GP").map((o) => [o.uid, { name: o.libelle, shortName: o.libelleAbrev ?? null }]));
}

export function normalizeLeague(): CompetitionDTO {
  return {
    provider: PROVIDER,
    externalId: LEAGUE_EXTERNAL_ID,
    parentExternalId: null,
    kind: "league",
    game: POLITICS_GAME,
    imageUrl: null,
    name: "Assemblée nationale",
    status: null,
    startsAt: null,
    endsAt: null,
    importance: 0,
    hasBracket: false,
    raw: { league: LEAGUE_EXTERNAL_ID },
  };
}

// ---------- Scrutins ----------

export interface ParsedVote {
  dossierRef: string | null;
  /** Vote « sur l'ensemble » du texte : le seul qui compte dans le suivi d'une loi. */
  overall: boolean;
  result: VoteResult;
  title: string;
}

export const isOverallVote = (title: string) => /^l.ensemble d/i.test(title.trim());

export function parseScrutin(raw: RawScrutin, groups: Map<string, GroupInfo>): ParsedVote | null {
  const synthese = raw.syntheseVote;
  const sort = raw.sort?.code === "adopté" ? "adopté" : raw.sort?.code === "rejeté" ? "rejeté" : null;
  if (!synthese?.decompte || !sort) return null;
  const title = (raw.titre ?? raw.objet?.libelle ?? "").trim();
  const voteGroups: VoteGroupResult[] = arr(raw.ventilationVotes?.organe?.groupes?.groupe).map((g) => {
    const d = g.vote?.decompteVoix;
    const counts = { pour: int(d?.pour), contre: int(d?.contre), abst: int(d?.abstentions) };
    const id = GROUP_ALIASES[g.organeRef] ?? g.organeRef;
    const info = groups.get(id);
    return {
      id,
      name: info?.name ?? id,
      shortName: info?.shortName ?? null,
      members: int(g.nombreMembresGroupe),
      ...counts,
      nonVotants: int(d?.nonVotants),
      position: groupPosition(counts),
    };
  });
  const numero = int(raw.numero);
  return {
    dossierRef: raw.objet?.dossierLegislatif?.dossierRef ?? null,
    overall: isOverallVote(title),
    title,
    result: {
      numero,
      date: raw.dateScrutin,
      sort,
      announcement: synthese.annonce ?? raw.sort?.libelle ?? "",
      voteType: raw.typeVote?.libelleTypeVote ?? null,
      pour: int(synthese.decompte.pour),
      contre: int(synthese.decompte.contre),
      abst: int(synthese.decompte.abstentions),
      nonVotants: int(synthese.decompte.nonVotants),
      votants: int(synthese.nombreVotants),
      required: int(synthese.nbrSuffragesRequis),
      groups: sortGroupsNeutral(voteGroups),
      sourceUrl: `${SITE}/scrutins/${numero}`,
    },
  };
}

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function groupEntity(group: VoteGroupResult): EntityDTO {
  return { provider: PROVIDER, externalId: groupRef(group.id), kind: "party_group", name: group.name, shortName: group.shortName, imageUrl: null, region: null };
}

export function normalizeVote(vote: ParsedVote, lawExternalId: string): EventDTO {
  const { result } = vote;
  return {
    provider: PROVIDER,
    externalId: voteRef(result.numero),
    competitionExternalId: lawExternalId,
    kind: VOTE_KIND,
    name: capitalize(vote.title.replace(/\.$/, "")),
    status: "finished",
    startsAt: at(result.date),
    endsAt: at(result.date),
    bestOf: null,
    streams: [],
    result,
    // Un groupe par ligne, dans l'ordre alphabétique ; `score` = voix pour. Le détail vit dans `result`.
    participants: result.groups.map((g) => ({ entity: groupEntity(g), score: g.pour, isWinner: null })),
    raw: result,
  };
}

// ---------- Dossiers législatifs ----------

// Arbre d'actes → liste à plat dans l'ordre du fichier (= chronologique).
export function flattenActs(root: RawDossier["actesLegislatifs"]): LawAct[] {
  const out: LawAct[] = [];
  const walk = (acts: RawAct | RawAct[] | undefined) =>
    arr(acts).forEach((a) => {
      const conclusion = a.codeActe === "PROM-PUB" && a.codeLoi ? `Loi n° ${a.codeLoi}` : (a.statutConclusion?.libelle ?? null);
      out.push({ code: a.codeActe, date: day(a.dateActe), conclusion });
      walk(a.actesLegislatifs?.acteLegislatif);
    });
  walk(root?.acteLegislatif);
  return out;
}

export interface ActorInfo {
  name: string;
  groupId: string | null;
}

export function actorsOf(raws: RawActeur[]): Map<string, ActorInfo> {
  const map = new Map<string, ActorInfo>();
  for (const a of raws) {
    const ident = a.etatCivil?.ident;
    if (!ident?.nom) continue;
    const group = arr<RawMandat>(a.mandats?.mandat)
      .filter((m) => m.typeOrgane === "GP")
      .sort((x, y) => String(y.dateDebut).localeCompare(String(x.dateDebut)))[0];
    map.set(typeof a.uid === "string" ? a.uid : a.uid["#text"], { name: `${ident.prenom ?? ""} ${ident.nom}`.trim(), groupId: group?.organes?.organeRef ?? null });
  }
  return map;
}

function authorOf(dossier: RawDossier, acts: LawAct[], actors: Map<string, ActorInfo>, groups: Map<string, GroupInfo>): LawAuthor | null {
  if (/^Projet/i.test(dossier.procedureParlementaire.libelle)) return { kind: "government", name: null, group: null, cosigners: 0 };
  const refs = arr(dossier.initiateur?.acteurs?.acteur).map((a) => a.acteurRef);
  if (refs.length === 0) return null;
  if (acts.find((a) => /^(AN|SN)1?(LUNI)?-DEPOT$/.test(a.code))?.code.startsWith("SN")) return { kind: "senators", name: null, group: null, cosigners: refs.length - 1 };
  const first = actors.get(refs[0]);
  return { kind: "deputy", name: first?.name ?? null, group: (first?.groupId && groups.get(first.groupId)?.name) || null, cosigners: refs.length - 1 };
}

export interface BuiltLaw {
  competition: CompetitionDTO;
  /** Votes sur l'ensemble du texte à rattacher (numéros). */
  voteNumeros: number[];
}

// Un dossier devient une compétition (kind `law`) seulement s'il s'agit d'un texte de loi débattu en séance. `votes` :
// scrutins sur l'ensemble de ce dossier.
export function normalizeLaw(dossier: RawDossier, votes: ParsedVote[], actors: Map<string, ActorInfo>, groups: Map<string, GroupInfo>): BuiltLaw | null {
  if (!isLawProcedure(dossier.procedureParlementaire.libelle)) return null;
  const acts = flattenActs(dossier.actesLegislatifs);
  if (!reachedFloor(acts) && votes.length === 0) return null;

  const lawVotes: LawVoteInput[] = votes.map((v) => ({ numero: v.result.numero, date: v.result.date, pour: v.result.pour, contre: v.result.contre, abst: v.result.abst, sort: v.result.sort }));
  const process = computeLawProcess(acts, lawVotes);
  const promulgation = acts.find((a) => a.code === "PROM-PUB");
  const promulgated = flattenPromulgation(dossier);
  const title = dossier.titreDossier.titre.trim();
  const structure: LawStructure = {
    process,
    officialTitle: title,
    lawType: lawTypeOf(title, dossier.procedureParlementaire.libelle),
    author: authorOf(dossier, acts, actors, groups),
    lawNumber: promulgated?.codeLoi ?? null,
    legifranceUrl: promulgated?.infoJO?.urlLegifrance ?? null,
    sourceUrl: `${SITE}/dossiers/${dossier.titreDossier.titreChemin ?? dossier.uid}`,
  };
  const deposit = process.steps[0]?.date ?? null;
  return {
    voteNumeros: votes.map((v) => v.result.numero),
    competition: {
      provider: PROVIDER,
      externalId: lawRef(dossier.uid),
      parentExternalId: LEAGUE_EXTERNAL_ID,
      kind: "law",
      game: POLITICS_GAME,
      imageUrl: null,
      name: title,
      status: process.status === "in_progress" ? null : "finished",
      startsAt: deposit ? at(deposit) : null,
      endsAt: promulgation?.date ? at(promulgation.date) : null,
      importance: process.status === "promulgated" ? 2 : 1,
      hasBracket: false,
      format: LAW_FORMAT,
      structure,
      raw: structure,
    },
  };
}

function flattenPromulgation(dossier: RawDossier): RawAct | undefined {
  let found: RawAct | undefined;
  const walk = (acts: RawAct | RawAct[] | undefined) =>
    arr(acts).forEach((a) => {
      if (a.codeActe === "PROM-PUB") found = a;
      walk(a.actesLegislatifs?.acteLegislatif);
    });
  walk(dossier.actesLegislatifs?.acteLegislatif);
  return found;
}

// Clé de comparaison entre le titre d'un scrutin (« l'ensemble de la proposition de loi relative au… (première
// lecture). ») et le titre principal d'un texte (« proposition de loi relative au… ») : beaucoup de scrutins sur
// l'ensemble n'indiquent pas leur dossier (scrutin 1308 par exemple).
export function titleKey(title: string): string {
  return title
    .replace(/\([^)]*\)/g, " ")
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .replace(/^\s*l.ensemble d(e la|e l|u|es)\s+/, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
}
