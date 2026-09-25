import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 20;

// `moments`, `contexte`, `forme récente`, `où regarder` (docs/03 §4) demandent des
// tables (`event_moment`, `context_snippet`) pas encore créées (reportées après le
// J1) : seuls participants/score/résultat sont renvoyés pour l'instant.
export class EventDetailResponseDto extends EventSummaryDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: Object }) result!: unknown;
}

@Injectable()
export class EventsService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getById(id: string): Promise<EventDetailResponseDto> {
    const cacheKey = CacheKeys.event(id);
    const cached = await this.cache.get<EventDetailResponseDto>(cacheKey);
    if (cached) return cached;

    const event = await this.prisma.event.findUnique({ where: { id }, include: eventSummaryInclude });
    if (!event) throw new NotFoundException("Événement introuvable");

    const response: EventDetailResponseDto = {
      ...toEventSummary(event),
      sourceUpdatedAt: event.updatedAt.toISOString(),
      result: event.result,
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }
}
