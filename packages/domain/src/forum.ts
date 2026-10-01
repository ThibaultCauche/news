// Forum (J13) : fils de discussion, texte seul. Règles pures, sans accès base ; l'API les applique.

export const FORUM_MESSAGE_MAX_LENGTH = 500;
export const FORUM_TITLE_MIN_LENGTH = 3;
export const FORUM_TITLE_MAX_LENGTH = 80;
export const FORUM_ACCOUNT_MIN_AGE_HOURS = 24;
// Signalements distincts qui masquent un message en attendant un modérateur.
export const FORUM_REPORT_HIDE_THRESHOLD = 3;
// Fils libres qu'un compte peut créer par jour (évite l'inondation, sans mode lent).
export const FORUM_FREE_THREADS_PER_DAY = 5;
// Profondeur maximale d'un fil de réponses (le message racine compte pour 1) : au-delà, une réponse
// s'attache au même niveau que le message auquel on répond.
export const FORUM_MAX_REPLY_DEPTH = 6;
export const CAMP_CHANGE_DELAY_DAYS = 7;
// Un message se modifie pendant 5 minutes.
export const FORUM_EDIT_WINDOW_MINUTES = 5;
// Plafond souple par compte (pas de mode lent) : au-delà, on attend la minute suivante.
export const FORUM_MESSAGES_PER_MINUTE = 10;
// Messages racines épinglés par discussion.
export const FORUM_MAX_PINNED = 2;
// Au plus une notification « nouveaux messages » par discussion suivie et par tranche de 10 minutes.
export const FORUM_FOLLOW_NOTIFY_MINUTES = 10;
export const FORUM_MAX_MENTIONS = 5;
// Version des conditions d'utilisation (texte dans l'appli) : la monter force une nouvelle acceptation.
export const FORUM_TERMS_VERSION = 1;

// Canal Redis Pub/Sub : l'API prévient le worker qu'un message répond à un autre (notification push).
export const FORUM_REPLIES_CHANNEL = "news:forum-replies";
// `reply` : on répond à `toUserId` ; `mention` : `toUserId` est cité par @pseudo ; `thread` : nouveau message
// d'une discussion suivie (le worker retrouve les abonnés, `toUserId` absent).
export interface ForumReplyMessage {
  messageId: string;
  kind: "reply" | "mention" | "thread";
  toUserId?: string;
  // Pour `thread` : déjà prévenus par une réponse ou une mention, à ne pas notifier une seconde fois.
  excludeUserIds?: string[];
}

// `live` : le fil du direct d'un match (écriture ouverte seulement pendant le match) ; `event` reste la
// discussion d'avant et d'après match.
export const FORUM_THREAD_KINDS = ["event", "live", "entity", "competition", "game", "free"] as const;
export type ForumThreadKind = (typeof FORUM_THREAD_KINDS)[number];

export const FORUM_REACTIONS = ["up", "fire", "laugh", "wow", "sad"] as const;
export type ForumReaction = (typeof FORUM_REACTIONS)[number];

export const FORUM_REPORT_REASONS = ["insult", "spam", "spoiler", "other"] as const;
export type ForumReportReason = (typeof FORUM_REPORT_REASONS)[number];

// ponytail: liste minimale, à étoffer au fil des signalements. Comparée mot entier par mot entier
// (« compute » ne doit pas être bloqué à cause de « pute »), sans accents ni casse.
const FORBIDDEN_WORDS = ["nazi", "hitler", "pute", "putes", "salope", "salopes", "connard", "connards", "connasse", "enculé", "enculés", "encule", "fdp", "ntm", "pedo", "pd", "nigger", "nigga", "negre", "fuck", "shit", "suicide", "tg"];
const STRIP_ACCENTS = /\p{Diacritic}/gu;

function words(text: string): string[] {
  return text.normalize("NFD").replace(STRIP_ACCENTS, "").toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
}

export function containsForbiddenWord(text: string): boolean {
  const forbidden = new Set(FORBIDDEN_WORDS.map((w) => words(w)[0]));
  return words(text).some((w) => forbidden.has(w));
}

// Liens libres interdits : schéma explicite, « www. », ou nom de domaine courant.
const LINK = /(https?:\/\/|www\.|\b[a-z0-9-]+\.(com|fr|net|org|gg|tv|io|co|me|ly|be|xyz|gl|link)\b)/i;

export type TextProblem = "empty" | "length" | "link" | "forbidden";

/** `null` si le message est acceptable, sinon la raison du refus. */
export function messageProblem(body: string): TextProblem | null {
  const text = body.trim();
  if (!text) return "empty";
  if (text.length > FORUM_MESSAGE_MAX_LENGTH) return "length";
  if (LINK.test(text)) return "link";
  if (containsForbiddenWord(text)) return "forbidden";
  return null;
}

export function titleProblem(title: string): TextProblem | null {
  const text = title.trim();
  if (text.length < FORUM_TITLE_MIN_LENGTH || text.length > FORUM_TITLE_MAX_LENGTH) return "length";
  if (LINK.test(text)) return "link";
  if (containsForbiddenWord(text)) return "forbidden";
  return null;
}

/** Ancienneté minimale du compte avant d'écrire. */
export function accountOldEnough(createdAt: Date, now: Date): boolean {
  return now.getTime() - createdAt.getTime() >= FORUM_ACCOUNT_MIN_AGE_HOURS * 3_600_000;
}

/** Jours restants avant de pouvoir changer de camp (0 = possible maintenant). */
export function campChangeWaitDays(changedAt: Date | null, now: Date): number {
  if (!changedAt) return 0;
  const elapsedDays = (now.getTime() - changedAt.getTime()) / 86_400_000;
  return Math.max(0, Math.ceil(CAMP_CHANGE_DELAY_DAYS - elapsedDays));
}

/** Aperçu d'un message pour une notification : une ligne, tronquée. */
export function forumSnippet(body: string, max = 90): string {
  const flat = body.replace(/\s+/g, " ").trim();
  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
}

/** Un message se modifie dans les 5 minutes suivant sa publication. */
export function canEditMessage(createdAt: Date, now: Date): boolean {
  return now.getTime() - createdAt.getTime() <= FORUM_EDIT_WINDOW_MINUTES * 60_000;
}

const MENTION = /(?:^|[^\p{L}\p{N}_.-])@([\p{L}\p{N}_.-]{3,20})/gu;

/** Pseudos cités par `@pseudo` dans un message (sans doublon, `FORUM_MAX_MENTIONS` au plus). */
export function extractMentions(body: string): string[] {
  const found = new Set<string>();
  for (const match of body.matchAll(MENTION)) {
    found.add(match[1]);
    if (found.size >= FORUM_MAX_MENTIONS) break;
  }
  return [...found];
}
