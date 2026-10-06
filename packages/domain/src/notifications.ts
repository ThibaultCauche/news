// Types et règles pures du moteur de notifications (docs/03 §6, J4). Aucun accès
// base/réseau ici : la résolution des destinataires et l'envoi restent dans le worker.
import { DomainEventType } from "./events";

export type SubscriptionTargetType = "category" | "competition" | "competition_family" | "entity" | "event";
export type SubscriptionLevel = "all" | "key_moments";
export type DevicePlatform = "android" | "ios";

export type NotificationType = "reminder" | "start" | "result" | "qualification" | "elimination";

// Ce que reçoit un nouveau suivi selon sa cible (J21) : une équipe → début et résultat ; une compétition,
// une famille ou une catégorie → le résultat seulement ; un match précis → tout, c'est une demande
// explicite. Le rappel T-15 d'une équipe ou d'une compétition ne vient que sur demande.
export function defaultSubscriptionNotifications(targetType: SubscriptionTargetType): { notifyReminder: boolean; notifyStart: boolean; notifyResult: boolean } {
  if (targetType === "event") return { notifyReminder: true, notifyStart: true, notifyResult: true };
  if (targetType === "entity") return { notifyReminder: false, notifyStart: true, notifyResult: true };
  return { notifyReminder: false, notifyStart: false, notifyResult: true };
}

// Réglages globaux par type de notification (J14, écran Réglages) ; chacun s'ajoute aux options du suivi.
export interface NotificationTypeSettings {
  notifyMatchReminder: boolean;
  notifyMatchStart: boolean;
  notifyMatchResult: boolean;
  notifyQualification: boolean;
  notifyPredictionReminders: boolean;
}

/** Le réglage global de l'utilisateur laisse-t-il passer ce type ? Sans ligne de réglages : oui. */
export function isTypeEnabled(type: NotificationType, setting: NotificationTypeSettings | null | undefined): boolean {
  if (!setting) return true;
  switch (type) {
    case "reminder":
      return setting.notifyMatchReminder;
    case "start":
      return setting.notifyMatchStart;
    case "result":
      return setting.notifyMatchResult;
    case "qualification":
    case "elimination":
      return setting.notifyQualification;
  }
}

export const SUBSCRIPTION_TARGET_TYPES: SubscriptionTargetType[] = ["category", "competition", "competition_family", "entity", "event"];
export const SUBSCRIPTION_LEVELS: SubscriptionLevel[] = ["all", "key_moments"];
export const DEVICE_PLATFORMS: DevicePlatform[] = ["android", "ios"];

// Mêmes seuils que les grands rendez-vous de l'accueil (`HIGHLIGHT_MIN_IMPORTANCE`
// côté API) : un abonné "grands moments" (ex. toute la catégorie Valorant) n'est
// notifié que pour les gros événements, sinon ce serait trop (docs/03 §6).
export const KEY_MOMENT_MIN_IMPORTANCE = 2;

export const MAX_NOTIFICATIONS_PER_HOUR = 3;

// EventScheduled/ScoreChanged n'ont pas de notification associée au J4 (absents
// de la table = ignorés par le worker).
export const DOMAIN_EVENT_NOTIFICATION_TYPES: Partial<Record<DomainEventType, NotificationType>> = {
  EventStartingSoon: "reminder",
  EventStarted: "start",
  EventFinished: "result",
  EntityQualified: "qualification",
  EntityEliminated: "elimination",
};

export interface NotificationCandidate {
  notifyEnabled: boolean;
  subscriptionLevel: SubscriptionLevel;
  eventImportance: number;
}

export function shouldNotify(candidate: NotificationCandidate): boolean {
  if (!candidate.notifyEnabled) return false;
  if (candidate.subscriptionLevel === "key_moments") return candidate.eventImportance >= KEY_MOMENT_MIN_IMPORTANCE;
  return true;
}

// Heures calmes en heure locale (0-23) avec repli possible sur la nuit (ex. 22 -> 7).
// Bornes égales ou absentes = pas d'heures calmes.
export function isQuietHour(localHour: number, quietStart: number | null, quietEnd: number | null): boolean {
  if (quietStart === null || quietEnd === null || quietStart === quietEnd) return false;
  if (quietStart < quietEnd) return localHour >= quietStart && localHour < quietEnd;
  return localHour >= quietStart || localHour < quietEnd;
}

// Heure locale (0-23) d'un appareil à partir de son décalage UTC en minutes
// (`Device.utcOffsetMinutes`) — pas de fuseau IANA : l'appli envoie un simple
// décalage (`DateTime.now().timeZoneOffset`), rien à résoudre côté serveur.
export function localHourFromOffsetMinutes(date: Date, offsetMinutes: number): number {
  const totalMinutes = date.getUTCHours() * 60 + date.getUTCMinutes() + offsetMinutes;
  return (Math.floor(totalMinutes / 60) % 24 + 24) % 24;
}

export interface NotificationText {
  title: string;
  body: string;
}

// Sans spoil : le texte ne contient jamais le score ni le gagnant (règle 10 de
// CLAUDE.md) — appliqué ici côté serveur, contrairement au masquage côté appli
// pour l'affichage, qui reste réversible. `subjectName` est le nom du match pour
// reminder/start/result, celui de l'entité pour qualification/elimination (J5).
// `needsPrediction` : le rappel T-15 dit aussi que le pronostic manque (J21, remplace l'ancien rappel à T-30).
export function buildNotificationText(type: NotificationType, subjectName: string, spoilerFree: boolean, winnerName: string | null, needsPrediction = false): NotificationText {
  switch (type) {
    case "reminder":
      if (needsPrediction) return { title: "Bientôt, sans pronostic", body: `${subjectName} commence dans 15 minutes, tu n'as pas encore pronostiqué.` };
      return { title: "Bientôt", body: `${subjectName} commence dans 15 minutes.` };
    case "start":
      return { title: "Ça commence", body: `${subjectName} vient de commencer.` };
    case "result":
      if (spoilerFree || !winnerName) return { title: "Terminé", body: `${subjectName} est terminé.` };
      return { title: "Résultat", body: `${winnerName} a gagné : ${subjectName}.` };
    case "qualification":
      return { title: "Qualifiée !", body: `${subjectName} est qualifiée pour la suite.` };
    case "elimination":
      return { title: "Éliminée", body: `${subjectName} est éliminée.` };
  }
}

// Résumé du matin (J19) : un seul message par jour local, envoyé entre 8 h et 11 h (la fenêtre
// rattrape un redémarrage du worker et attend la fin des heures calmes), seulement s'il y a un
// match parmi les suivis. Le type du journal est à part de `NotificationType` : sa clé de
// déduplication est le premier match du jour, pas un match annoncé en particulier.
export const MORNING_DIGEST_TYPE = "morning_digest";
export const MORNING_DIGEST_FROM_HOUR = 8;
export const MORNING_DIGEST_TO_HOUR = 11;

/** Début et fin (UTC) du jour local d'un appareil, à partir de son décalage UTC en minutes. */
export function localDayBounds(date: Date, offsetMinutes: number): { start: Date; end: Date } {
  const dayMs = 24 * 60 * 60_000;
  const shifted = date.getTime() + offsetMinutes * 60_000;
  const start = Math.floor(shifted / dayMs) * dayMs - offsetMinutes * 60_000;
  return { start: new Date(start), end: new Date(start + dayMs) };
}

function formatLocalTime(date: Date, offsetMinutes: number): string {
  const total = (((Math.floor(date.getTime() / 60_000) + offsetMinutes) % 1440) + 1440) % 1440;
  const minutes = total % 60;
  return minutes === 0 ? `${Math.floor(total / 60)} h` : `${Math.floor(total / 60)} h ${String(minutes).padStart(2, "0")}`;
}

/** Texte du résumé du matin ; `matches` est trié par heure de début. Jamais de score : ce sont des matchs à venir. */
export function buildMorningDigestText(matches: { name: string; startsAt: Date }[], offsetMinutes: number): NotificationText {
  const first = matches[0];
  const at = formatLocalTime(first.startsAt, offsetMinutes);
  if (matches.length === 1) return { title: "Aujourd'hui", body: `1 match de tes suivis : ${first.name} à ${at}.` };
  return { title: "Aujourd'hui", body: `${matches.length} matchs de tes suivis, le premier à ${at} : ${first.name}.` };
}
