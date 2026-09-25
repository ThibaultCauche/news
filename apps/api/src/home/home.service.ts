import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";

const HIGHLIGHT_MIN_IMPORTANCE = 2;
const UPCOMING_LIMIT = 20;
const HIGHLIGHT_LIMIT = 10;
const TTL_SECONDS = 30;

export class HomeResponseDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [EventSummaryDto] }) liveNow!: EventSummaryDto[];
  @ApiProperty({ type: [EventSummaryDto] }) upcoming!: EventSummaryDto[];
  @ApiProperty({ type: [EventSummaryDto] }) highlights!: EventSummaryDto[];
}

// Version sans utilisateur du J2 (docs/04 J2) : grands rendez-vous + en direct +
// à venir. La personnalisation ("tes suivis", "maintenant pour toi") viendra
// avec les comptes au J4.
@Injectable()
export class HomeService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getHome(): Promise<HomeResponseDto> {
    const cached = await this.cache.get<HomeResponseDto>(CacheKeys.home());
    if (cached) return cached;

    const now = new Date();
    const [live, upcoming, highlights] = await Promise.all([
      this.prisma.event.findMany({ where: { status: "live" }, include: eventSummaryInclude, orderBy: { startsAt: "asc" } }),
      this.prisma.event.findMany({
        where: { status: "scheduled", startsAt: { gte: now } },
        include: eventSummaryInclude,
        orderBy: { startsAt: "asc" },
        take: UPCOMING_LIMIT,
      }),
      this.prisma.event.findMany({
        // L'ingestion (J1) ne renseigne l'importance qu'au niveau de la compétition
        // (tier PandaScore) : `event.importance` reste toujours à 0 pour l'instant.
        where: { competition: { importance: { gte: HIGHLIGHT_MIN_IMPORTANCE } }, status: { not: "cancelled" } },
        include: eventSummaryInclude,
        orderBy: { startsAt: "asc" },
        take: HIGHLIGHT_LIMIT,
      }),
    ]);

    const response: HomeResponseDto = {
      sourceUpdatedAt: now.toISOString(),
      liveNow: live.map(toEventSummary),
      upcoming: upcoming.map(toEventSummary),
      highlights: highlights.map(toEventSummary),
    };
    await this.cache.set(CacheKeys.home(), response, TTL_SECONDS);
    return response;
  }
}
