import { ApiProperty } from "@nestjs/swagger";
import { Entity, Event, EventParticipant, Prisma } from "@news/db";
import { buildGroupStakes, buildSwissGroupStakes, VOTE_KIND, VoteResult } from "@news/domain";
import { outcomeOf, VoteOutcomeDto } from "../politics/politics.dto";

type EventWithRelations = Event & {
  competition: { id: string; name: string; format: string | null; game?: string | null; parent?: { name: string } | null };
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
  // Ligne de contexte des cartes (J22) : slug du jeu et nom du tournoi parent (« Champions 2026 »).
  @ApiProperty({ nullable: true, type: String }) game!: string | null;
  @ApiProperty({ nullable: true, type: String }) tournamentName!: string | null;
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
  // Résultat d'un vote de l'Assemblée (J29) : ses participants sont des groupes, pas des camps, donc la liste est vide.
  @ApiProperty({ nullable: true, type: VoteOutcomeDto }) voteOutcome!: VoteOutcomeDto | null;
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
      stakes: event.competition.format === "groups_gsl" ? buildGroupStakes() : event.competition.format === "swiss" ? (event.stakes ?? buildSwissGroupStakes()) : null,
      game: event.competition.game ?? null,
      tournamentName: event.competition.parent?.name ?? null,
    },
    voteOutcome: event.kind === VOTE_KIND && event.result ? outcomeOf(event.result as unknown as VoteResult) : null,
    // Une session de F1 compte une vingtaine de pilotes : les listes n'en montrent que le podium (J28), le détail
    // de l'événement porte le classement complet. Un vote n'a pas de camps : ses groupes sont dans le détail.
    participants: (event.kind === VOTE_KIND ? [] : event.kind === "session" ? event.participants.slice(0, 3) : event.participants).map((p) => ({
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
  competition: { select: { id: true, name: true, format: true, game: true, parent: { select: { name: true } } } },
  // Ordre stable des équipes (gauche/droite) : `side`, puis l'identifiant pour les anciennes lignes sans côté.
  participants: {
    include: { entity: { select: { id: true, name: true, shortName: true, imageUrl: true } } },
    orderBy: PARTICIPANT_ORDER,
  },
} as const;
