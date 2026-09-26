import { EventStatus } from "./status";

// Canal Redis Pub/Sub par lequel le worker prévient l'API qu'un événement métier
// vient de se produire (docs/03 §3) — signal transitoire, pas une file persistante :
// le cache a de toute façon un TTL court (15-60s) qui sert de filet.
export const DOMAIN_EVENTS_CHANNEL = "news:domain-events";

// EventStartingSoon (T-15 min, docs/03 §3/§6) est publié par un job dédié plutôt que
// par l'ingestion (voir `starting-soon` dans apps/worker). BracketAdvanced et
// StandingChanged sont publiés par le job "structure" du J5 quand `event_link`/
// `standing` changent réellement (même logique d'upsert idempotent que le reste).
// EntityQualified/EntityEliminated (J5, reporté du J4) : une entité précise d'une
// compétition passe qualifiée ou est éliminée (`standing.qualified`/`lives_left`) —
// pas de match unique derrière, donc `entityId` plutôt que `eventId`.
export type DomainEventType =
  | "EventScheduled"
  | "EventStarted"
  | "EventFinished"
  | "ScoreChanged"
  | "EventStartingSoon"
  | "BracketAdvanced"
  | "StandingChanged"
  | "EntityQualified"
  | "EntityEliminated";

export interface DomainEventMessage {
  type: DomainEventType;
  eventId?: string;
  entityId?: string;
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
