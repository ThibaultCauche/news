import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { Prisma, PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";
import { SubscriptionsService } from "../subscriptions/subscriptions.service";
import { AgendaQueryDto } from "./agenda.query.dto";

const TTL_SECONDS = 30;

export class AgendaResponseDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [EventSummaryDto] }) events!: EventSummaryDto[];
}

// "Abonné ou non" (docs/03 §4) viendra avec les comptes au J4.
@Injectable()
export class AgendaService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
    private readonly subscriptions: SubscriptionsService,
  ) {}

  async getAgenda(query: AgendaQueryDto, userId: string | null = null): Promise<AgendaResponseDto> {
    const mine = query.mine === "true";
    // « Mes suivis » est propre au compte : ni lu ni écrit dans le cache partagé.
    const cacheKey = CacheKeys.agenda(query.from, query.to, query.category, query.leagueIds);
    const cached = mine ? null : await this.cache.get<AgendaResponseDto>(cacheKey);
    if (cached) return cached;

    const categories = query.category?.split(",").filter(Boolean);
    const leagueIds = query.leagueIds?.split(",").filter(Boolean);
    const competitionWhere: Prisma.CompetitionWhereInput = {
      // Plusieurs catégories possibles, séparées par une virgule (J22, #D3).
      ...(categories?.length ? { category: { slug: { in: categories } } } : {}),
      // Ligue racine d'un jeu (ex. "VCT") : la compétition d'un match est à
      // 0, 1 ou 2 niveaux en dessous d'elle (ligue → série → tournoi →
      // match) dans toute la hiérarchie ingérée jusqu'ici (docs/03 §2) —
      // pas besoin d'une requête récursive pour cette profondeur bornée.
      ...(leagueIds?.length
        ? { OR: [{ id: { in: leagueIds } }, { parentId: { in: leagueIds } }, { parent: { parentId: { in: leagueIds } } }] }
        : {}),
    };
    if (mine) {
      const events = userId
        ? await this.subscriptions.listEventsInWindow(userId, new Date(query.from), new Date(query.to), 300, Object.keys(competitionWhere).length ? competitionWhere : undefined)
        : [];
      return { sourceUpdatedAt: new Date().toISOString(), events };
    }
    const where: Prisma.EventWhereInput = {
      startsAt: { gte: new Date(query.from), lte: new Date(query.to) },
      ...(Object.keys(competitionWhere).length ? { competition: competitionWhere } : {}),
    };
    const events = await this.prisma.event.findMany({ where, include: eventSummaryInclude, orderBy: { startsAt: "asc" } });

    const response: AgendaResponseDto = { sourceUpdatedAt: new Date().toISOString(), events: events.map(toEventSummary) };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }
}
