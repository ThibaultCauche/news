import { ApiProperty } from "@nestjs/swagger";
import { Entity, Event, EventParticipant, Prisma } from "@news/db";
import { buildGroupStakes } from "@news/domain";

type EventWithRelations = Event & {
  competition: { id: string; name: string; format: string | null };
  participants: (EventParticipant & { entity: Pick<Entity, "id" | "name" | "shortName" | "imageUrl"> })[];
};

// Classes (pas de simples interfaces) : nécessaire pour que @nestjs/swagger génère
// un schéma de réponse, donc un modèle Dart typé (règle 11 de CLAUDE.md — pas de
// modèle écrit à la main côté Flutter).
export class CompetitionRefDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  // Phrase d'enjeu courte pour une poule GSL, `null` sinon (docs/04 J8) : pas
  // de calcul par match ici, `buildMatchStakes` (par lien de bracket) reste
  // réservé à l'écran Prochain match (`GET /v1/events/:id`).
  @ApiProperty({ nullable: true, type: String }) stakes!: string | null;
}

export class EventParticipantDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  @ApiProperty({ nullable: true, type: Number }) score!: number | null;
  @ApiProperty({ nullable: true, type: Boolean }) isWinner!: boolean | null;
}

export class EventSummaryDto {
  @ApiProperty() id!: string;
  @ApiProperty() kind!: string;
  @ApiProperty() name!: string;
  @ApiProperty() status!: string;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  @ApiProperty({ nullable: true, type: String }) endsAt!: string | null;
  @ApiProperty({ nullable: true, type: Number }) bestOf!: number | null;
  @ApiProperty() importance!: number;
  @ApiProperty({ type: CompetitionRefDto }) competition!: CompetitionRefDto;
  @ApiProperty({ type: [EventParticipantDto] }) participants!: EventParticipantDto[];
}

// Représentation partagée d'un événement, réutilisée par home/agenda/events/competitions
// (docs/03 §4) : pas de score en rounds ni de nom de carte, seulement ce que le plan
// gratuit PandaScore fournit (règle 6 de CLAUDE.md).
export function toEventSummary(event: EventWithRelations): EventSummaryDto {
  return {
    id: event.id,
    kind: event.kind,
    name: event.name,
    status: event.status,
    startsAt: event.startsAt?.toISOString() ?? null,
    endsAt: event.endsAt?.toISOString() ?? null,
    bestOf: event.bestOf,
    importance: event.importance,
    competition: {
      id: event.competition.id,
      name: event.competition.name,
      stakes: event.competition.format === "groups_gsl" ? buildGroupStakes() : null,
    },
    participants: event.participants.map((p) => ({
      entityId: p.entityId,
      name: p.entity.name,
      shortName: p.entity.shortName,
      imageUrl: p.entity.imageUrl,
      score: p.score,
      isWinner: p.isWinner,
    })),
  };
}

// Typé explicitement : `as const` rendrait le tableau en lecture seule, refusé par Prisma.
export const PARTICIPANT_ORDER: Prisma.EventParticipantOrderByWithRelationInput[] = [{ side: { sort: "asc", nulls: "last" } }, { entityId: "asc" }];

// Inclusion Prisma correspondante, partagée pour rester cohérente avec le mapper.
export const eventSummaryInclude = {
  competition: { select: { id: true, name: true, format: true } },
  // Ordre stable des équipes (gauche/droite) : `side`, puis l'identifiant pour les anciennes lignes sans côté.
  participants: {
    include: { entity: { select: { id: true, name: true, shortName: true, imageUrl: true } } },
    orderBy: PARTICIPANT_ORDER,
  },
} as const;
