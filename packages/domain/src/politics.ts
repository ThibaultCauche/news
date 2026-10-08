// Politique (J29, docs/01c) : suivi d'une loi « façon colis », résultat d'un vote par groupe. Uniquement des règles
// pures sur des données officielles ; aucun texte libre (règle 9 de CLAUDE.md).

export const LAW_FORMAT = "law_process";
export const VOTE_KIND = "vote";
export const POLITICS_GAME = "assemblee-nationale";

// ---------- Position d'un groupe ----------

export type VotePosition = "pour" | "contre" | "abstention" | "non-votant";

// Le champ `positionMajoritaire` de l'open data n'est pas fiable (docs/01c) : la position se recalcule toujours depuis
// les voix. À égalité, `pour` l'emporte sur `contre`, qui l'emporte sur `abstention` : l'ordre est celui du bulletin,
// pas un jugement.
export function groupPosition(g: { pour: number; contre: number; abst: number }): VotePosition {
  const max = Math.max(g.pour, g.contre, g.abst);
  if (max === 0) return "non-votant";
  return g.pour === max ? "pour" : g.contre === max ? "contre" : "abstention";
}

export interface VoteGroupResult {
  /** Identifiant officiel de l'organe (« PO800490 »). */
  id: string;
  name: string;
  shortName: string | null;
  members: number;
  pour: number;
  contre: number;
  abst: number;
  nonVotants: number;
  position: VotePosition;
}

// `result` d'un événement `vote` (un scrutin public de l'Assemblée).
export interface VoteResult {
  numero: number;
  /** Date du scrutin, « AAAA-MM-JJ ». */
  date: string;
  sort: "adopté" | "rejeté";
  /** Libellé de l'annonce officielle (« L'Assemblée nationale a adopté »). */
  announcement: string;
  voteType: string | null;
  pour: number;
  contre: number;
  abst: number;
  nonVotants: number;
  votants: number;
  /** Majorité requise pour être adopté. */
  required: number;
  groups: VoteGroupResult[];
  sourceUrl: string;
}

// Phrase de gabarit d'un vote : « Adopté : 312 pour, 198 contre, 41 abstentions ».
export function voteSentence(v: { sort: "adopté" | "rejeté"; pour: number; contre: number; abst: number }): string {
  const tail = v.abst > 0 ? `, ${v.abst} ${v.abst > 1 ? "abstentions" : "abstention"}` : "";
  return `${v.sort === "adopté" ? "Adopté" : "Rejeté"} : ${v.pour} pour, ${v.contre} contre${tail}`;
}

// Notification d'un vote sur un texte suivi : le résultat est un fait public, jamais un spoil (le réglage « sans spoil » ne
// s'y applique pas).
export function buildVoteNotificationText(lawName: string, vote: { sort: "adopté" | "rejeté"; pour: number; contre: number; abst: number }): { title: string; body: string } {
  return { title: "Vote à l'Assemblée", body: `${lawName} — ${voteSentence(vote)}.` };
}

// Groupes dans l'ordre alphabétique de leur nom officiel : ni gauche-droite, ni taille (neutralité, docs/01c).
export function sortGroupsNeutral<T extends { name: string }>(groups: T[]): T[] {
  return [...groups].sort((a, b) => a.name.localeCompare(b.name, "fr"));
}

// ---------- Loi « façon colis » ----------

// Un acte du dossier législatif, à plat : `code` est le `codeActe` de l'open data (« AN1-COM-FOND-RAPPORT »).
export interface LawAct {
  code: string;
  /** « AAAA-MM-JJ » */
  date: string | null;
  conclusion?: string | null;
}

// Vote « sur l'ensemble » du texte à l'Assemblée, rattaché à l'étape de vote d'une lecture.
export interface LawVoteInput {
  numero: number;
  date: string;
  pour: number;
  contre: number;
  abst: number;
  sort: "adopté" | "rejeté";
}

export type LawStepKey = "deposit" | "committee1" | "vote1" | "committee2" | "vote2" | "agreement" | "council" | "promulgation";
export type LawStepState = "done" | "current" | "todo" | "skipped";
export type LawStatus = "in_progress" | "promulgated" | "rejected";
type Chamber = "AN" | "SN";

export interface LawStep {
  key: LawStepKey;
  label: string;
  state: LawStepState;
  date: string | null;
  detail: string | null;
  vote: LawVoteInput | null;
}

export interface LawProcess {
  status: LawStatus;
  /** Chambre qui a reçu le texte en premier. */
  firstChamber: Chamber;
  steps: LawStep[];
}

const CHAMBER_LABEL: Record<Chamber, { voters: string; at: string; deposit: string }> = {
  AN: { voters: "les députés", at: "à l'Assemblée", deposit: "Déposé à l'Assemblée" },
  SN: { voters: "les sénateurs", at: "au Sénat", deposit: "Déposé au Sénat" },
};

const capitalize = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
const isRejection = (c: string | null | undefined) => /rejet/i.test(c ?? "");

// Les lectures s'enchaînent dans l'ordre du fichier : la première lecture (AN1, SN1 ou lecture unique) donne la
// chambre saisie en premier.
function firstChamberOf(acts: LawAct[]): Chamber {
  const first = acts.find((a) => /^(AN|SN)(1|LUNI)\b/.test(a.code.split("-")[0]));
  return first?.code.startsWith("SN") ? "SN" : "AN";
}

// Étapes du suivi d'un texte (maquette 19). Une étape est faite si elle ou une étape suivante est faite (un texte
// peut sauter la commission) ; la première étape non faite est « en ce moment ». Le Conseil constitutionnel n'apparaît
// que s'il a été saisi.
export function computeLawProcess(acts: LawAct[], votes: LawVoteInput[] = []): LawProcess {
  const c1 = firstChamberOf(acts);
  const c2: Chamber = c1 === "AN" ? "SN" : "AN";
  const reading = (c: Chamber) => `${c}1`;
  const find = (code: string) => acts.find((a) => a.code === code);
  const reading1 = c1 === "AN" && !acts.some((a) => a.code.startsWith("AN1")) ? "ANLUNI" : reading(c1);
  const dec = (r: string) => find(`${r}-DEBATS-DEC`);
  const matchVote = (act: LawAct | undefined, chamber: Chamber): LawVoteInput | null => {
    if (!act?.date || chamber !== "AN") return null;
    const end = Date.parse(act.date);
    const candidates = votes.filter((v) => Date.parse(v.date) <= end && end - Date.parse(v.date) <= 14 * 86_400_000);
    return candidates.sort((a, b) => b.date.localeCompare(a.date))[0] ?? null;
  };

  const dec1 = dec(reading1);
  const dec2 = dec(reading(c2));
  const cmp = find("CMP-DEC");
  const definitive = acts.find((a) => /^(AN|SN)LDEF-DEBATS-DEC$/.test(a.code));
  const council = find("CC-CONCLUSION");
  const hasCouncil = acts.some((a) => a.code === "CC" || a.code === "CC-CONCLUSION");
  const promulgation = find("PROM-PUB");

  const raw: (Omit<LawStep, "state"> & { done: boolean })[] = [];
  const add = (key: LawStepKey, label: string, done: boolean, date: string | null, detail: string | null, vote: LawVoteInput | null = null) =>
    raw.push({ key, label, date, detail, vote, done });

  const depositAct = acts.find((a) => a.code === `${reading1}-DEPOT`);
  add("deposit", CHAMBER_LABEL[c1].deposit, Boolean(depositAct), depositAct?.date ?? null, null);
  const com1 = find(`${reading1}-COM-FOND-RAPPORT`);
  add("committee1", `Examiné en commission ${CHAMBER_LABEL[c1].at}`, Boolean(com1), com1?.date ?? null, null);
  const vote1 = matchVote(dec1, c1);
  add("vote1", `Voté par ${CHAMBER_LABEL[c1].voters}`, Boolean(dec1), dec1?.date ?? null, dec1 && !vote1 ? conclusionLabel(dec1.conclusion) : null, vote1);
  const com2 = find(`${reading(c2)}-COM-FOND-RAPPORT`);
  add("committee2", `Examiné en commission ${CHAMBER_LABEL[c2].at}`, Boolean(com2), com2?.date ?? null, null);
  const vote2 = matchVote(dec2, c2);
  add("vote2", `Voté par ${CHAMBER_LABEL[c2].voters}`, Boolean(dec2), dec2?.date ?? null, dec2 && !vote2 ? conclusionLabel(dec2.conclusion) : null, vote2);

  // Accord : commission mixte, texte adopté sans modification par la 2ᵉ chambre, ou dernier mot (lecture définitive).
  const conform = dec2 && /sans modification/i.test(dec2.conclusion ?? "");
  const agreed = (cmp && /^accord/i.test(cmp.conclusion ?? "")) || conform || definitive;
  const agreementAct = cmp && /^accord/i.test(cmp.conclusion ?? "") ? cmp : conform ? dec2 : definitive;
  const disagreement = cmp && /d[ée]saccord/i.test(cmp.conclusion ?? "");
  add(
    "agreement",
    "Accord final entre les deux chambres",
    Boolean(agreed),
    agreementAct?.date ?? null,
    disagreement && !agreed ? "Désaccord en commission mixte, nouvelle lecture" : conform ? "Texte adopté sans modification" : definitive && !cmp ? "Dernier mot à l'Assemblée" : null,
  );
  if (hasCouncil) add("council", "Contrôle du Conseil constitutionnel", Boolean(council), council?.date ?? null, council?.conclusion ? capitalize(council.conclusion) : null);
  add("promulgation", "Promulgation", Boolean(promulgation), promulgation?.date ?? null, promulgation?.conclusion ?? null);

  // « Fait » se propage vers l'arrière (une étape sautée est comptée faite, sans date).
  const done = raw.map((_, i) => raw.slice(i).some((s) => s.done));
  // Un rejet clôt le texte : tout ce qui suit est sauté.
  const rejectedAt = [dec1 && ["vote1", dec1], dec2 && ["vote2", dec2]].flatMap((x) => (x && isRejection((x[1] as LawAct).conclusion) ? [x[0] as LawStepKey] : []))[0];
  const rejected = rejectedAt && !promulgation && !(rejectedAt === "vote1" && (dec2 || cmp));
  const rejectedIndex = rejected ? raw.findIndex((s) => s.key === rejectedAt) : -1;

  let currentSet = false;
  const steps: LawStep[] = raw.map((s, i) => {
    let state: LawStepState;
    if (rejectedIndex >= 0 && i > rejectedIndex) state = "skipped";
    else if (done[i]) state = "done";
    else if (!currentSet) {
      state = "current";
      currentSet = true;
    } else state = "todo";
    return { key: s.key, label: s.label, state, date: s.date, detail: s.detail, vote: s.vote };
  });
  const status: LawStatus = promulgation ? "promulgated" : rejected ? "rejected" : "in_progress";
  return { status, firstChamber: c1, steps };
}

// Contenu de `competition.structure` d'une loi (format `law_process`).
export interface LawAuthor {
  kind: "government" | "deputy" | "senators";
  name: string | null;
  group: string | null;
  cosigners: number;
}

export interface LawStructure {
  process: LawProcess;
  officialTitle: string;
  /** « Proposition de loi organique ». */
  lawType: string;
  author: LawAuthor | null;
  /** « 2024-1177 », une fois promulguée. */
  lawNumber: string | null;
  legifranceUrl: string | null;
  sourceUrl: string;
}

// ---------- Choix des textes et intitulés ----------

// Seuls les textes de loi comptent : propositions, projets, ratifications. Les résolutions, rapports, missions,
// commissions d'enquête et engagements de responsabilité du gouvernement n'ont pas de suivi.
export function isLawProcedure(label: string): boolean {
  return /^(Proposition de loi|Projet de loi|Projet ou proposition de loi|Projet de ratification)/i.test(label);
}

// Type du texte pour le sous-titre : « Proposition de loi organique ». Le titre officiel commence toujours par lui.
export function lawTypeOf(title: string, procedureLabel: string): string {
  const m = title.match(/^(Proposition de loi|Projet de loi)(\s+(?:organique|constitutionnelle|de finances rectificative|de finances|de financement de la sécurité sociale))?/i);
  if (m) return capitalize(m[0].toLowerCase());
  return /ratification/i.test(procedureLabel) ? "Projet de loi de ratification" : "Proposition de loi";
}

// Un texte entre dans le suivi dès qu'il a été débattu en séance publique (ou promulgué) : les milliers de textes
// seulement déposés n'ont encore rien à raconter.
export function reachedFloor(acts: LawAct[]): boolean {
  return acts.some((a) => /-DEBATS-(SEANCE|DEC)$/.test(a.code) || a.code === "PROM-PUB");
}

// Issue d'une lecture, au masculin (« le texte ») : « adoptée avec modifications » → « Adopté avec modifications ».
export function conclusionLabel(conclusion: string | null | undefined): string | null {
  const c = (conclusion ?? "").trim().toLowerCase();
  if (!c) return null;
  if (/rejet/.test(c)) return "Rejeté";
  if (/sans modification/.test(c)) return "Adopté sans modification";
  if (/modifi/.test(c)) return "Adopté avec modifications";
  if (/adopt|d[ée]finitive/.test(c)) return "Adopté";
  return capitalize(c);
}
