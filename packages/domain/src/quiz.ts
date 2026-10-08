import { VotePosition } from "./politics";

// Quiz « Qui a voté ? » (J29b, docs/01c) : « Comment ce groupe a-t-il voté sur ce texte ? ». Tirage sans hasard caché :
// même jour, mêmes questions pour tout le monde ; les groupes tournent à tour de rôle (quotas, aucun n'est interrogé
// plus qu'un autre) et les bonnes réponses sont réparties entre pour, contre et abstention (docs/01c, garde-fous).

export const QUIZ_SIZE = 5;
export const QUIZ_CHOICES = ["pour", "contre", "abstention"] as const;
export type QuizChoice = (typeof QUIZ_CHOICES)[number];

export const isQuizChoice = (value: unknown): value is QuizChoice => QUIZ_CHOICES.includes(value as QuizChoice);

export const quizQuestionId = (eventId: string, groupId: string) => `${eventId}:${groupId}`;

export function parseQuizQuestionId(id: string): { eventId: string; groupId: string } | null {
  const [eventId, groupId, ...rest] = id.split(":");
  return eventId && groupId && rest.length === 0 ? { eventId, groupId } : null;
}

/** Jour du quiz, « AAAA-MM-JJ » à Paris : il change à minuit, heure de Paris, pour tout le monde. */
export function quizDay(date: Date): string {
  return new Intl.DateTimeFormat("sv-SE", { timeZone: "Europe/Paris", year: "numeric", month: "2-digit", day: "2-digit" }).format(date);
}

const dayNumber = (day: string) => Math.floor(Date.parse(`${day}T00:00:00Z`) / 86_400_000);

// Petit générateur déterministe (mulberry32) : le tirage d'un jour ne dépend que de sa date.
function seeded(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export interface QuizVote {
  eventId: string;
  groups: { id: string; position: VotePosition }[];
}

export interface QuizPick {
  eventId: string;
  groupId: string;
}

/**
 * Les questions d'un jour. `groupIds` : les groupes dans l'ordre alphabétique de leur nom officiel ; la question i du
 * jour interroge le groupe numéro (jour × taille + i) modulo leur nombre, donc chacun revient à son tour. La réponse
 * attendue suit le cycle pour / contre / pour / abstention / contre, décalé chaque jour, puis retombe sur n'importe
 * quel vote de ce groupe quand aucun ne correspond (l'abstention est rare).
 */
export function pickQuizQuestions(votes: QuizVote[], groupIds: string[], day: string, count = QUIZ_SIZE): QuizPick[] {
  if (votes.length === 0 || groupIds.length === 0) return [];
  const n = dayNumber(day);
  const random = seeded(n * 7919 + 13);
  const targets: QuizChoice[] = ["pour", "contre", "pour", "abstention", "contre"];
  const picks: QuizPick[] = [];
  const used = new Set<string>();
  const sorted = [...votes].sort((a, b) => a.eventId.localeCompare(b.eventId));

  for (let i = 0; i < count; i++) {
    const groupId = groupIds[(((n * count + i) % groupIds.length) + groupIds.length) % groupIds.length];
    const positionIn = (vote: QuizVote) => vote.groups.find((g) => g.id === groupId)?.position;
    const askable = sorted.filter((v) => !used.has(v.eventId) && positionIn(v) !== undefined && positionIn(v) !== "non-votant");
    if (askable.length === 0) continue;
    const target = targets[(i + n) % targets.length];
    const matching = askable.filter((v) => positionIn(v) === target);
    const pool = matching.length > 0 ? matching : askable;
    const vote = pool[Math.floor(random() * pool.length)];
    used.add(vote.eventId);
    picks.push({ eventId: vote.eventId, groupId });
  }
  return picks;
}

/** Position d'un groupe → réponse attendue (un groupe qui n'a pas voté n'est jamais interrogé). */
export const quizAnswerOf = (position: VotePosition): QuizChoice | null => (position === "non-votant" ? null : position);

/**
 * Série de jours : `current` = jours d'affilée avec au moins une réponse, jusqu'à aujourd'hui (ou hier tant qu'on n'a
 * pas encore joué aujourd'hui) ; `best` = la plus longue série.
 */
export function quizStreak(days: string[], today: string): { current: number; best: number } {
  const set = [...new Set(days)].map(dayNumber).sort((a, b) => a - b);
  let best = 0;
  let run = 0;
  for (const [i, d] of set.entries()) {
    run = i > 0 && d === set[i - 1] + 1 ? run + 1 : 1;
    best = Math.max(best, run);
  }
  const todayN = dayNumber(today);
  const last = set.at(-1);
  if (last === undefined || last < todayN - 1) return { current: 0, best };
  let current = 0;
  for (let d = last; set.includes(d); d--) current++;
  return { current, best };
}
