import { BadRequestException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { Entity, PrismaClient } from "@news/db";
import { isKnownGame } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 30;
// Assez large pour couvrir une saison (bilan/série de victoires) sans pagination :
// une seule vraie compétition (Champions 2026) à ce stade du projet.
const HISTORY_LIMIT = 100;

// Fiche équipe (écran 10, docs/03 §4). Pas de "Carte 1 · Ascent" ni de détail par
// carte : `event.result.games[].winnerExternalId` n'est pas résolu vers notre
// `entityId` à l'ingestion (seul `EventParticipant.score`/`isWinner`, la série,
// l'est) — hors périmètre du J6, le score de série suffit au critère d'acceptation.
// Pas de "Transferts et effectif" non plus : aucune source de roster branchée.
export class EntityResponseDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) region!: string | null;
  @ApiProperty() wins!: number;
  @ApiProperty() losses!: number;
  @ApiProperty() winStreak!: number;
  @ApiProperty({ nullable: true, type: EventSummaryDto }) lastEvent!: EventSummaryDto | null;
  @ApiProperty({ nullable: true, type: EventSummaryDto }) nextEvent!: EventSummaryDto | null;
  @ApiProperty() sourceUpdatedAt!: string;
}

export class EntityListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
}

@Injectable()
export class EntitiesService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getById(id: string): Promise<EntityResponseDto> {
    const cacheKey = CacheKeys.entity(id);
    const cached = await this.cache.get<EntityResponseDto>(cacheKey);
    if (cached) return cached;

    const entity = await this.prisma.entity.findUnique({ where: { id } });
    if (!entity) throw new NotFoundException("Équipe introuvable");

    const response = await this.buildResponse(entity);
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }

  // Équipes ayant au moins un match dans une compétition de ce jeu (onglet Équipes,
  // J9) : pas de rattachement direct équipe → jeu dans le modèle, on le déduit des matchs.
  async listByGame(game: string): Promise<EntityListItemDto[]> {
    if (!isKnownGame(game)) throw new BadRequestException("Jeu inconnu");
    return this.prisma.entity.findMany({
      where: { kind: "team", participants: { some: { event: { competition: { game } } } } },
      select: { id: true, name: true, shortName: true, imageUrl: true },
      orderBy: { name: "asc" },
    });
  }

  // Résolution par nom court (ex. "G2", "KC") plutôt que par id interne :
  // sert à l'onboarding (écran 12, J6), qui suggère des équipes par leur nom
  // sans connaître leur id à l'avance (pas de recherche générique côté API,
  // ce cas précis suffit pour l'instant).
  async getByShortName(shortName: string): Promise<EntityResponseDto> {
    const entity = await this.prisma.entity.findFirst({ where: { shortName: { equals: shortName, mode: "insensitive" } } });
    if (!entity) throw new NotFoundException("Équipe introuvable");
    return this.getById(entity.id);
  }

  private async buildResponse(entity: Entity): Promise<EntityResponseDto> {
    const history = await this.prisma.eventParticipant.findMany({
      where: { entityId: entity.id, isWinner: { not: null }, event: { status: "finished" } },
      orderBy: { event: { startsAt: "desc" } },
      take: HISTORY_LIMIT,
    });
    const wins = history.filter((row) => row.isWinner).length;
    let winStreak = 0;
    for (const row of history) {
      if (!row.isWinner) break;
      winStreak += 1;
    }

    const [lastEvent, nextEvent] = await Promise.all([
      this.prisma.event.findFirst({
        where: { status: "finished", participants: { some: { entityId: entity.id } } },
        orderBy: { startsAt: "desc" },
        include: eventSummaryInclude,
      }),
      this.prisma.event.findFirst({
        where: { status: { in: ["scheduled", "live"] }, participants: { some: { entityId: entity.id } } },
        orderBy: { startsAt: "asc" },
        include: eventSummaryInclude,
      }),
    ]);

    const response: EntityResponseDto = {
      id: entity.id,
      name: entity.name,
      shortName: entity.shortName,
      region: entity.region,
      wins,
      losses: history.length - wins,
      winStreak,
      lastEvent: lastEvent ? toEventSummary(lastEvent) : null,
      nextEvent: nextEvent ? toEventSummary(nextEvent) : null,
      sourceUpdatedAt: entity.updatedAt.toISOString(),
    };
    return response;
  }
}
