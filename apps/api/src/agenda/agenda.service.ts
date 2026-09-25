import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { Prisma, PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";
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
  ) {}

  async getAgenda(query: AgendaQueryDto): Promise<AgendaResponseDto> {
    const cacheKey = CacheKeys.agenda(query.from, query.to, query.category);
    const cached = await this.cache.get<AgendaResponseDto>(cacheKey);
    if (cached) return cached;

    const where: Prisma.EventWhereInput = {
      startsAt: { gte: new Date(query.from), lte: new Date(query.to) },
      ...(query.category ? { competition: { category: { slug: query.category } } } : {}),
    };
    const events = await this.prisma.event.findMany({ where, include: eventSummaryInclude, orderBy: { startsAt: "asc" } });

    const response: AgendaResponseDto = { sourceUpdatedAt: new Date().toISOString(), events: events.map(toEventSummary) };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }
}
