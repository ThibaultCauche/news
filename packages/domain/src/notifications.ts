// Types et règles pures du moteur de notifications (docs/03 §6, J4). Aucun accès
// base/réseau ici : la résolution des destinataires et l'envoi restent dans le worker.
import { DomainEventType } from "./events";

export type SubscriptionTargetType = "category" | "competition" | "entity" | "event";
export type SubscriptionLevel = "all" | "key_moments";
export type DevicePlatform = "android" | "ios";

export type NotificationType = "reminder" | "start" | "result" | "qualification" | "elimination";

export const SUBSCRIPTION_TARGET_TYPES: SubscriptionTargetType[] = ["category", "competition", "entity", "event"];
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
export function buildNotificationText(type: NotificationType, subjectName: string, spoilerFree: boolean, winnerName: string | null): NotificationText {
  switch (type) {
    case "reminder":
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
