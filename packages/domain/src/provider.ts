import { EventStatus } from "./status";

// Fenêtre de temps pour une requête d'ingestion (bornes optionnelles).
// `onlyLive` : ne renvoyer que les événements en cours (un seul appel, pour le
// job à cadence rapide réservé aux matchs en direct — règle 5 de CLAUDE.md).
export interface DateWindow {
  from?: Date;
  to?: Date;
  onlyLive?: boolean;
}

// Compétition générique : ligue, série ou tournoi (docs/03 §2, hiérarchie via parentExternalId).
export interface CompetitionDTO {
  provider: string;
  externalId: string;
  parentExternalId: string | null;
  kind: string;
  name: string;
  status: EventStatus | null;
  startsAt: Date | null;
  endsAt: Date | null;
  importance: number;
  raw: unknown;
}

// Entité générique : équipe, joueur, parti… (docs/03 §2).
export interface EntityDTO {
  provider: string;
  externalId: string;
  kind: string;
  name: string;
  shortName: string | null;
  imageUrl: string | null;
  region: string | null;
}

export interface EventParticipantDTO {
  entity: EntityDTO;
  score: number | null;
  isWinner: boolean | null;
}

// Événement générique : match, vote, lancement… (docs/03 §2).
export interface EventDTO {
  provider: string;
  externalId: string;
  competitionExternalId: string;
  kind: string;
  name: string;
  status: EventStatus;
  startsAt: Date | null;
  endsAt: Date | null;
  bestOf: number | null;
  result: unknown;
  participants: EventParticipantDTO[];
  raw: unknown;
}

// Structure d'une compétition (brackets, standings) — précisé au J5.
export type StructureDTO = unknown;

// Interface commune à tous les adaptateurs de fournisseur (docs/03 §3).
export interface Provider {
  listCompetitions(window?: DateWindow): Promise<CompetitionDTO[]>;
  listEvents(window?: DateWindow): Promise<EventDTO[]>;
  getEvent(externalId: string): Promise<EventDTO>;
  getStructure?(competitionExternalId: string): Promise<StructureDTO>;
}
