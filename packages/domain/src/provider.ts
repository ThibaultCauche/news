import { BracketFormat, EventLinkDTO } from "./bracket";
import { EventStatus } from "./status";
import { StreamDTO } from "./streams";

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
  // Slug du jeu (ex. "valorant"), voir `competition.game` (J9).
  game: string | null;
  imageUrl: string | null;
  name: string;
  status: EventStatus | null;
  startsAt: Date | null;
  endsAt: Date | null;
  importance: number;
  // Vrai si le fournisseur expose un bracket pour ce tournoi (cible le job "structure", J5).
  hasBracket: boolean;
  // Lieu de la compétition (circuit d'un Grand Prix, J28) ; absent chez les fournisseurs d'e-sport.
  location?: string | null;
  // Format et structure propres à la compétition quand ce n'est pas un bracket (suivi d'une loi, J29).
  format?: string | null;
  structure?: unknown;
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
  /** Chaînes de diffusion de l'éditeur (une par langue). */
  streams: StreamDTO[];
  result: unknown;
  participants: EventParticipantDTO[];
  raw: unknown;
}

// Structure d'une compétition (brackets — docs/03 §2/§4, J5). Les classements ne
// sont pas demandés au fournisseur : recalculés depuis nos propres event/event_participant
// (règle : le standings gratuit de PandaScore ne donne que le rang, docs/01).
export interface StructureDTO {
  format: BracketFormat;
  links: EventLinkDTO[];
}

// Ligne de classement fournie telle quelle par la source (championnat de F1, plus tard football) : pas recalculée
// depuis nos matchs, contrairement aux classements d'e-sport (J28).
export interface StandingDTO {
  competitionExternalId: string;
  entity: EntityDTO;
  rank: number;
  points: number;
  wins: number | null;
}

// Interface commune à tous les adaptateurs de fournisseur (docs/03 §3).
export interface Provider {
  listCompetitions(window?: DateWindow): Promise<CompetitionDTO[]>;
  listEvents(window?: DateWindow): Promise<EventDTO[]>;
  getEvent(externalId: string): Promise<EventDTO>;
  getStructure?(competitionExternalId: string): Promise<StructureDTO>;
  // Classements donnés par la source (J28) ; sans cette méthode, ils sont recalculés depuis les matchs.
  listStandings?(): Promise<StandingDTO[]>;
}
