import { EventStatus } from "./status";

// Canal Redis Pub/Sub par lequel le worker prévient l'API qu'un événement métier
// vient de se produire (docs/03 §3) — signal transitoire, pas une file persistante :
// le cache a de toute façon un TTL court (15-60s) qui sert de filet.
export const DOMAIN_EVENTS_CHANNEL = "news:domain-events";

// Seuls les types que le worker peut réellement détecter au J2 (statut et score
// d'un événement). BracketAdvanced/StandingChanged/CompetitionFinished viendront
// avec les brackets et classements au J5, EventStartingSoon avec les notifications au J4.
export type DomainEventType = "EventScheduled" | "EventStarted" | "EventFinished" | "ScoreChanged";

export interface DomainEventMessage {
  type: DomainEventType;
  eventId: string;
  competitionId: string;
}

// État observé d'un événement juste avant/après un upsert : suffisant pour décider
// quels événements métier émettre, sans avoir besoin de connaître le détail des
// participants (le hash du `result` JSON suffit à détecter un changement de score).
export interface EventStateSnapshot {
  status: EventStatus;
  resultHash: string | null;
}

// Compare l'état avant/après un upsert et décide quels événements métier émettre.
// `previous` vaut `null` à la création : seul `EventScheduled` est pertinent, on ne
// sait pas encore ce qui a "changé".
export function diffEventStatus(previous: EventStateSnapshot | null, next: EventStateSnapshot): DomainEventType[] {
  if (!previous) return ["EventScheduled"];

  const types: DomainEventType[] = [];
  if (previous.status !== next.status) {
    if (next.status === "live") types.push("EventStarted");
    if (next.status === "finished") types.push("EventFinished");
  }
  if (previous.resultHash !== next.resultHash && next.status !== "scheduled") {
    types.push("ScoreChanged");
  }
  return types;
}
