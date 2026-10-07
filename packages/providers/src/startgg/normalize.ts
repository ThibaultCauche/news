import { CompetitionDTO, EntityDTO, EventDTO, EventLinkDTO, EventStatus, StructureDTO } from "@news/domain";
import { RawEvent, RawPhase, RawSet, RawSlot, RawTournament } from "./types";

export const PROVIDER = "startgg";
export const GAME = "super-smash-bros-ultimate";
export const LEAGUE_EXTERNAL_ID = "game:1386";

// Compétitions : ligue unique du jeu → tournoi start.gg (série) → phase (« Top 8 »), comme ligue → série → tournoi
// chez PandaScore. Les identifiants sont préfixés : trois sortes d'objets partagent la même clé `provider_ref`.
export const tournamentRef = (id: number) => `tournament:${id}`;
export const phaseRef = (id: number | string) => `phase:${id}`;
export const phaseIdOf = (ref: string) => ref.replace(/^phase:/, "");

// ponytail: nom libre côté organisateur, détecté au mot « singles » ; à compléter si un major l'écrit autrement.
const SINGLES = /singles|シングルス/i;
const NOT_SINGLES = /doubles|team|crew|squad|amateur|redemption|ladder|side/i;

export function pickSinglesEvent(tournament: Pick<RawTournament, "events">): RawEvent | null {
  const candidates = tournament.events.filter((e) => SINGLES.test(e.name) && !NOT_SINGLES.test(e.name));
  return candidates.sort((a, b) => (b.numEntrants ?? 0) - (a.numEntrants ?? 0))[0] ?? null;
}

export interface MajorRules {
  minEntrants: number;
  // Tournoi mis en avant par start.gg (`staffPicks`).
  staffPick: boolean;
  // Ajouts à la main : préfixes de slug.
  allowSlugs: string[];
}

// Major = événement Singles d'au moins `minEntrants` inscrits (`numAttendees` compte tous les jeux, inutilisable),
// ou sélection de start.gg, ou liste manuelle. Jamais un tournoi en ligne.
export function isMajor(tournament: RawTournament, rules: MajorRules): boolean {
  if (tournament.isOnline) return false;
  if (!pickSinglesEvent(tournament)) return false;
  if (rules.staffPick) return true;
  if (rules.allowSlugs.some((s) => tournament.slug.replace(/^tournament\//, "").startsWith(s))) return true;
  return (pickSinglesEvent(tournament)?.numEntrants ?? 0) >= rules.minEntrants;
}

const sec = (value: number | null | undefined) => (value ? new Date(value * 1000) : null);

function statusFromDates(startsAt: Date | null, endsAt: Date | null, now: Date): EventStatus {
  if (endsAt && now > endsAt) return "finished";
  if (startsAt && now < startsAt) return "scheduled";
  return "live";
}

export function normalizeLeague(): CompetitionDTO {
  return {
    provider: PROVIDER,
    externalId: LEAGUE_EXTERNAL_ID,
    parentExternalId: null,
    kind: "league",
    game: GAME,
    imageUrl: null,
    name: "Majors Smash Ultimate",
    status: null,
    startsAt: null,
    endsAt: null,
    importance: 0,
    hasBracket: false,
    raw: { id: LEAGUE_EXTERNAL_ID },
  };
}

export function normalizeTournamentSerie(tournament: RawTournament, now: Date = new Date()): CompetitionDTO {
  const startsAt = sec(tournament.startAt);
  const endsAt = sec(tournament.endAt);
  return {
    provider: PROVIDER,
    externalId: tournamentRef(tournament.id),
    parentExternalId: LEAGUE_EXTERNAL_ID,
    kind: "serie",
    game: GAME,
    imageUrl: null,
    name: tournament.name,
    status: statusFromDates(startsAt, endsAt, now),
    startsAt,
    endsAt,
    importance: 3,
    hasBracket: false,
    raw: { id: tournament.id, name: tournament.name, slug: tournament.slug, startAt: tournament.startAt, endAt: tournament.endAt },
  };
}

// Un seul groupe en double ou simple élimination = un arbre à afficher ; les poules (32 groupes) n'en ont pas.
export function phaseHasBracket(phase: RawPhase): boolean {
  return phase.groupCount === 1 && /^(DOUBLE|SINGLE)_ELIMINATION$/.test(phase.bracketType);
}

export function bracketFormatOf(bracketType: string): StructureDTO["format"] {
  return bracketType === "SINGLE_ELIMINATION" ? "single_elim" : "double_elim";
}

export function normalizePhase(tournament: RawTournament, phase: RawPhase, now: Date = new Date()): CompetitionDTO {
  const startsAt = sec(tournament.startAt);
  const endsAt = sec(tournament.endAt);
  // La phase n'a pas de dates propres : celles du tournoi. Son état vient de start.gg.
  const status: EventStatus =
    phase.state === "COMPLETED" ? "finished" : phase.state === "ACTIVE" ? "live" : statusFromDates(startsAt, endsAt, now) === "finished" ? "finished" : "scheduled";
  return {
    provider: PROVIDER,
    externalId: phaseRef(phase.id),
    parentExternalId: tournamentRef(tournament.id),
    kind: "tournament",
    game: GAME,
    imageUrl: null,
    name: phase.name,
    status,
    startsAt,
    endsAt,
    importance: 3,
    hasBracket: phaseHasBracket(phase),
    raw: phase,
  };
}

// États de set : 1 créé, 2 en cours, 3 terminé, 4 prêt, 5 invalide, 6 appelé, 7 en file.
function setStatus(state: number): EventStatus {
  if (state === 2) return "live";
  if (state === 3) return "finished";
  if (state === 5) return "cancelled";
  return "scheduled";
}

function playerEntity(slot: RawSlot): EntityDTO | null {
  const entrant = slot.entrant;
  if (!entrant) return null;
  const participant = entrant.participants[0];
  return {
    provider: PROVIDER,
    // Le compte start.gg identifie le joueur d'un tournoi à l'autre ; sans compte, l'inscription ne vaut que pour cet événement.
    externalId: participant?.user ? `user:${participant.user.id}` : `entrant:${entrant.id}`,
    kind: "player",
    name: participant?.gamerTag || entrant.name,
    shortName: null,
    imageUrl: null,
    region: null,
  };
}

// Score -1 = disqualifié : pas de score.
const scoreOf = (slot: RawSlot) => {
  const value = slot.standing?.stats?.score?.value ?? null;
  return value != null && value >= 0 ? value : null;
};

// Noms de rondes à la manière de PandaScore (« Upper bracket semifinal 2 », « Lower bracket round 1 match 3 », « Grand
// final ») : l'appli, les phrases d'enjeu et les notifications s'appuient sur ces noms, et un seul vocabulaire évite de
// les doubler. `number` = rang du set dans sa ronde (absent quand elle n'a qu'un set ou pour une poule).
export function bracketName(fullRoundText: string | null, number?: number): string {
  const text = (fullRoundText ?? "").trim().toLowerCase();
  if (text === "grand final reset") return "Grand final reset";
  if (text === "grand final") return "Grand final";
  const m = /^(winners|losers) (?:round (\d+)|(quarter-final|semi-final|final))$/.exec(text);
  if (!m) return fullRoundText?.trim() || "Set";
  const side = m[1] === "winners" ? "Upper bracket" : "Lower bracket";
  if (m[2]) return `${side} round ${m[2]}${number ? ` match ${number}` : ""}`;
  const stage = m[3] === "quarter-final" ? "quarterfinal" : m[3] === "semi-final" ? "semifinal" : "final";
  return `${side} ${stage}${number && stage !== "final" ? ` ${number}` : ""}`;
}

// Rang de chaque set dans sa ronde, par ordre d'identifiant (A, B, … AA) : les identifiants sont attribués dans l'ordre
// du tableau. Calculé sur un passage complet ; un set seul dans sa ronde n'a pas de numéro.
export function setNumbers(sets: Pick<RawSet, "id" | "identifier" | "round" | "phaseGroup">[]): Map<string, number | null> {
  const groups = new Map<string, Pick<RawSet, "id" | "identifier">[]>();
  for (const s of sets) {
    const key = `${s.phaseGroup?.id ?? ""}|${s.round ?? ""}`;
    groups.set(key, [...(groups.get(key) ?? []), s]);
  }
  const numbers = new Map<string, number | null>();
  for (const group of groups.values()) {
    if (group.length < 2) {
      for (const s of group) numbers.set(String(s.id), null);
      continue;
    }
    const ordered = [...group].sort((a, b) => (a.identifier ?? "").length - (b.identifier ?? "").length || (a.identifier ?? "").localeCompare(b.identifier ?? ""));
    ordered.forEach((s, i) => numbers.set(String(s.id), i + 1));
  }
  return numbers;
}

const slotName = (slot?: RawSlot): string => playerEntity(slot ?? { prereqType: null, prereqId: null, prereqPlacement: null })?.name ?? "TBD";

export function normalizeSet(set: RawSet, number?: number): EventDTO | null {
  const phaseId = set.phaseGroup?.phase?.id;
  if (phaseId == null) return null;
  const status = setStatus(set.state);
  const slots = [...set.slots].sort((a, b) => (a.slotIndex ?? 0) - (b.slotIndex ?? 0));
  const participants = slots.flatMap((slot) => {
    const entity = playerEntity(slot);
    if (!entity || !slot.entrant) return [];
    return [{ entity, score: scoreOf(slot), isWinner: status === "finished" ? set.winnerId != null && set.winnerId === slot.entrant.id : null, entrantId: slot.entrant.id }];
  });
  const idOf = (entrantId: number | null) => participants.find((p) => p.entrantId === entrantId)?.entity.externalId ?? null;
  // Un set se joue au meilleur des 3 ou 5 : un nombre pair de manches (set terminé 3-1) n'est pas le format.
  const bestOf = set.totalGames != null && set.totalGames % 2 === 1 ? set.totalGames : null;
  return {
    provider: PROVIDER,
    externalId: String(set.id),
    competitionExternalId: phaseRef(phaseId),
    kind: "match",
    // « Ronde : A vs B » comme chez PandaScore : les notifications et les listes affichent ce nom tel quel, l'appli en
    // retire le suffixe quand elle n'a besoin que de la ronde.
    name: `${bracketName(set.fullRoundText, number)}: ${slotName(slots[0])} vs ${slotName(slots[1])}`,
    status,
    // Pas d'horaire prévu pour la plupart des sets : sans heure de début réelle, `startsAt` reste vide (sinon des
    // centaines de sets de poule s'empileraient à la même minute dans l'Agenda).
    startsAt: sec(set.startedAt) ?? sec(set.startAt) ?? sec(set.completedAt),
    endsAt: sec(set.completedAt),
    bestOf,
    streams: [],
    result: {
      // État « appelé » : les joueurs sont convoqués à leur station, le set va commencer (notification).
      called: set.state === 6,
      // Poule d'un set (« ULT1 ») : sert à montrer la poule d'un joueur.
      group: set.phaseGroup?.displayIdentifier ?? null,
      seriesScore: participants.map((p) => ({ team_id: p.entity.externalId, score: p.score })),
      games: (set.games ?? []).map((g) => ({
        position: g.orderNum,
        status: "finished",
        winnerExternalId: idOf(g.winnerId),
        durationSeconds: null,
        // { joueur → personnage }, seulement ce qui est saisi.
        characters: Object.fromEntries((g.selections ?? []).flatMap((s) => (s.entrant && s.character?.name && idOf(s.entrant.id) ? [[idOf(s.entrant.id) as string, s.character.name]] : []))),
      })),
    },
    participants: participants.map(({ entity, score, isWinner }) => ({ entity, score, isWinner })),
    raw: set,
  };
}

// Liens du bracket : chaque place d'un set vient du gagnant (prereqPlacement 1) ou du perdant (2) d'un set précédent.
export function normalizeStructure(bracketType: string, sets: Pick<RawSet, "id" | "slots">[]): StructureDTO {
  const links: EventLinkDTO[] = [];
  for (const set of sets) {
    set.slots.forEach((slot, index) => {
      if (slot.prereqType !== "set" || slot.prereqId == null) return;
      links.push({
        fromExternalId: String(slot.prereqId),
        toExternalId: String(set.id),
        outcome: slot.prereqPlacement === 2 ? "loser" : "winner",
        slot: slot.slotIndex ?? index,
      });
    });
  }
  return { format: bracketFormatOf(bracketType), links };
}
