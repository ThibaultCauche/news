import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 30;

export class CompetitionChildDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() kind!: string;
  @ApiProperty({ nullable: true, type: String }) status!: string | null;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  @ApiProperty({ nullable: true, type: String }) endsAt!: string | null;
}

export class CompetitionStandingDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() entityName!: string;
  @ApiProperty({ nullable: true, type: Number }) rank!: number | null;
  @ApiProperty({ nullable: true, type: Number }) wins!: number | null;
  @ApiProperty({ nullable: true, type: Number }) losses!: number | null;
  @ApiProperty({ nullable: true, type: Number }) livesLeft!: number | null;
  @ApiProperty({ nullable: true, type: Boolean }) qualified!: boolean | null;
}

// `event_link`/`standing` alimentés au J5 (docs/04) : `standings` est vide et
// `structure` reste `null` jusque-là.
export class CompetitionResponseDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true, type: String }) parentId!: string | null;
  @ApiProperty() name!: string;
  @ApiProperty() kind!: string;
  @ApiProperty({ nullable: true, type: String }) format!: string | null;
  @ApiProperty({ nullable: true, type: String }) status!: string | null;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  @ApiProperty({ nullable: true, type: String }) endsAt!: string | null;
  @ApiProperty({ type: Object, nullable: true }) structure!: unknown;
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [CompetitionChildDto] }) children!: CompetitionChildDto[];
  @ApiProperty({ type: [CompetitionStandingDto] }) standings!: CompetitionStandingDto[];
}

@Injectable()
export class CompetitionsService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getById(id: string): Promise<CompetitionResponseDto> {
    const cacheKey = CacheKeys.competition(id);
    const cached = await this.cache.get<CompetitionResponseDto>(cacheKey);
    if (cached) return cached;

    const competition = await this.prisma.competition.findUnique({
      where: { id },
      include: {
        children: true,
        standings: { include: { entity: { select: { id: true, name: true } } }, orderBy: { rank: "asc" } },
      },
    });
    if (!competition) throw new NotFoundException("Compétition introuvable");

    const response: CompetitionResponseDto = {
      id: competition.id,
      parentId: competition.parentId,
      name: competition.name,
      kind: competition.kind,
      format: competition.format,
      status: competition.status,
      startsAt: competition.startsAt?.toISOString() ?? null,
      endsAt: competition.endsAt?.toISOString() ?? null,
      structure: competition.structure,
      sourceUpdatedAt: competition.updatedAt.toISOString(),
      children: competition.children.map((c) => ({
        id: c.id,
        name: c.name,
        kind: c.kind,
        status: c.status,
        startsAt: c.startsAt?.toISOString() ?? null,
        endsAt: c.endsAt?.toISOString() ?? null,
      })),
      standings: competition.standings.map((s) => ({
        entityId: s.entityId,
        entityName: s.entity.name,
        rank: s.rank,
        wins: s.wins,
        losses: s.losses,
        livesLeft: s.livesLeft,
        qualified: s.qualified,
      })),
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }
}
