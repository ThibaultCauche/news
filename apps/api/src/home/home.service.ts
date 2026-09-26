import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";
import { FollowStateDto } from "../subscriptions/subscription.dto";
import { SubscriptionsService } from "../subscriptions/subscriptions.service";

const HIGHLIGHT_MIN_IMPORTANCE = 2;
const UPCOMING_LIMIT = 20;
const HIGHLIGHT_LIMIT = 10;
const TTL_SECONDS = 30;

export class HomeResponseDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [EventSummaryDto] }) liveNow!: EventSummaryDto[];
  @ApiProperty({ type: [EventSummaryDto] }) upcoming!: EventSummaryDto[];
  @ApiProperty({ type: [EventSummaryDto] }) highlights!: EventSummaryDto[];
  @ApiProperty({ nullable: true, type: EventSummaryDto }) nowForYou!: EventSummaryDto | null;
  @ApiProperty({ type: [FollowStateDto] }) follows!: FollowStateDto[];
}

// Les blocs partagés (en direct, à venir, grands rendez-vous) restent en cache
// Redis, communs à tout le monde ; la personnalisation ("maintenant pour toi",
// "tes suivis", docs/02 écran 17) se calcule à chaque appel à partir des
// abonnements, sans utilisateur si aucun jeton n'est fourni (docs/04 J2 → J4).
@Injectable()
export class HomeService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
    private readonly subscriptions: SubscriptionsService,
  ) {}

  async getHome(userId: string | null): Promise<HomeResponseDto> {
    const shared = await this.getSharedBlocks();
    const follows = userId ? await this.subscriptions.listWithState(userId) : [];
    const nowForYou = follows.find((f) => f.currentEvent?.status === "live")?.currentEvent ?? follows.find((f) => f.currentEvent)?.currentEvent ?? null;
    return { ...shared, nowForYou, follows };
  }

  private async getSharedBlocks(): Promise<Omit<HomeResponseDto, "nowForYou" | "follows">> {
    const cached = await this.cache.get<Omit<HomeResponseDto, "nowForYou" | "follows">>(CacheKeys.home());
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

    const response = {
      sourceUpdatedAt: now.toISOString(),
      liveNow: live.map(toEventSummary),
      upcoming: upcoming.map(toEventSummary),
      highlights: highlights.map(toEventSummary),
    };
    await this.cache.set(CacheKeys.home(), response, TTL_SECONDS);
    return response;
  }
}
