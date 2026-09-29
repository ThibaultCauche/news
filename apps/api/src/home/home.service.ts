import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { buildMatchStakes } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";
import { FollowStateDto } from "../subscriptions/subscription.dto";
import { SubscriptionsService } from "../subscriptions/subscriptions.service";

const HIGHLIGHT_MIN_IMPORTANCE = 2;
const UPCOMING_LIMIT = 20;
const GRAND_FINAL_LIMIT = 3;
// La Home ne montre que les finales des 7 prochains jours (docs/04 J10) : plus loin, ce n'est pas encore « un rendez-vous ».
const GRAND_FINAL_HORIZON_MS = 7 * 24 * 3600 * 1000;
const TTL_SECONDS = 30;
// Même liste que `events.service.ts` : la « finale » n'a de sens que pour un format à élimination.
const ELIMINATION_FORMATS = ["single_elim", "double_elim", "triple_elim"];

// « Grands rendez-vous » (docs/04 J10) : la grande finale d'une phase finale, avec
// sa phrase « pourquoi ça compte » (`buildMatchStakes`, mots `[[terme]]` du glossaire).
export class GrandFinalDto {
  @ApiProperty({ type: EventSummaryDto }) event!: EventSummaryDto;
  // Nom du tournoi parent ("Champions 2026") : celui de l'étape ("Playoffs") est trop générique seul.
  @ApiProperty() tournamentName!: string;
  @ApiProperty({ nullable: true, type: String }) stakes!: string | null;
}

export class HomeResponseDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [EventSummaryDto] }) liveNow!: EventSummaryDto[];
  @ApiProperty({ type: [EventSummaryDto] }) upcoming!: EventSummaryDto[];
  @ApiProperty({ type: [GrandFinalDto] }) grandFinals!: GrandFinalDto[];
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
    const [live, upcoming, finals] = await Promise.all([
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
        // Grande finale = un match d'un format à élimination sans lien « winner »
        // sortant mais alimenté par d'autres matchs (`linksTo`) : exclut un match isolé
        // et la finale du tableau bas (son vainqueur va en grande finale). `finished`
        // exclu : la section disparaît une fois la finale jouée.
        where: {
          competition: { importance: { gte: HIGHLIGHT_MIN_IMPORTANCE }, format: { in: ELIMINATION_FORMATS } },
          status: { notIn: ["cancelled", "finished"] },
          startsAt: { lte: new Date(now.getTime() + GRAND_FINAL_HORIZON_MS) },
          linksFrom: { none: { outcome: "winner" } },
          linksTo: { some: {} },
        },
        include: {
          ...eventSummaryInclude,
          competition: { select: { id: true, name: true, format: true, parent: { select: { name: true } } } },
          linksFrom: { include: { toEvent: { select: { name: true } } } },
        },
        orderBy: { startsAt: "asc" },
        take: GRAND_FINAL_LIMIT,
      }),
    ]);

    const response = {
      sourceUpdatedAt: now.toISOString(),
      liveNow: live.map(toEventSummary),
      upcoming: upcoming.map(toEventSummary),
      grandFinals: finals.map((event) => ({
        event: toEventSummary(event),
        tournamentName: event.competition.parent?.name ?? event.competition.name,
        stakes: buildMatchStakes({
          bestOf: event.bestOf,
          winnerTargetName: null,
          loserTargetName: event.linksFrom.find((l) => l.outcome === "loser")?.toEvent.name ?? null,
        }),
      })),
    };
    await this.cache.set(CacheKeys.home(), response, TTL_SECONDS);
    return response;
  }
}
