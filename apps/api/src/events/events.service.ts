import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { buildMatchStakes } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 20;
const RECENT_FORM_LIMIT = 5;

export class RecentFormEntryDto {
  @ApiProperty() entityId!: string;
  // Plus récent d'abord, "V"/"D" (docs/02 écran 04 "Forme récente").
  @ApiProperty({ type: [String] }) results!: string[];
}

export class HeadToHeadDto {
  @ApiProperty() entityAId!: string;
  @ApiProperty() entityAWins!: number;
  @ApiProperty() entityBId!: string;
  @ApiProperty() entityBWins!: number;
}

// "Pourquoi ce match compte" (docs/03 §7) : calculé par des règles à partir du
// bracket (`event_link`), `null` hors phase à élimination (une poule n'a pas de
// lien de bracket : pas de phrase plutôt qu'une phrase fausse). Forme récente et
// face-à-face : nos propres `event`/`event_participant`, pas de source externe.
export class EventContextDto {
  @ApiProperty({ nullable: true, type: String }) stakes!: string | null;
  @ApiProperty({ type: [RecentFormEntryDto] }) recentForm!: RecentFormEntryDto[];
  @ApiProperty({ nullable: true, type: HeadToHeadDto }) headToHead!: HeadToHeadDto | null;
}

export class EventDetailResponseDto extends EventSummaryDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: Object }) result!: unknown;
  @ApiProperty({ type: EventContextDto }) context!: EventContextDto;
}

// "Pourquoi ce match compte" n'a de sens que pour un format à élimination : une
// poule (`groups_gsl`) n'a pas de "finale" au sens de `event_link` — son
// "Winners Match" sans lien sortant "winner" qualifie directement, ce n'est pas
// une grande finale. Un `event_link` de type "loser" (vers le "Decider Match")
// existe bien pour les poules, donc `linksFrom.length === 0` ne suffit pas à
// distinguer les deux cas.
const ELIMINATION_FORMATS = ["single_elim", "double_elim", "triple_elim"];

type EventWithLinks = Parameters<typeof toEventSummary>[0] & {
  competition: { format: string | null };
  linksFrom: { outcome: string; toEvent: { name: string } }[];
};

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

    const event = await this.prisma.event.findUnique({
      where: { id },
      include: {
        ...eventSummaryInclude,
        competition: { select: { ...eventSummaryInclude.competition.select, format: true } },
        linksFrom: { include: { toEvent: { select: { name: true } } } },
      },
    });
    if (!event) throw new NotFoundException("Événement introuvable");

    const response: EventDetailResponseDto = {
      ...toEventSummary(event),
      sourceUpdatedAt: event.updatedAt.toISOString(),
      result: event.result,
      context: await this.buildContext(event),
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }

  private async buildContext(event: EventWithLinks): Promise<EventContextDto> {
    const winnerTarget = event.linksFrom.find((l) => l.outcome === "winner")?.toEvent.name ?? null;
    const loserTarget = event.linksFrom.find((l) => l.outcome === "loser")?.toEvent.name ?? null;
    const stakes =
      event.linksFrom.length === 0 || !ELIMINATION_FORMATS.includes(event.competition.format ?? "")
        ? null
        : buildMatchStakes({ bestOf: event.bestOf, winnerTargetName: winnerTarget, loserTargetName: loserTarget });

    const entityIds = event.participants.map((p) => p.entityId);
    const recentForm = await Promise.all(entityIds.map((entityId) => this.recentFormFor(entityId, event.id)));
    const headToHead = entityIds.length === 2 ? await this.headToHeadFor(entityIds[0], entityIds[1]) : null;

    return { stakes, recentForm, headToHead };
  }

  private async recentFormFor(entityId: string, excludeEventId: string): Promise<RecentFormEntryDto> {
    const rows = await this.prisma.eventParticipant.findMany({
      where: { entityId, isWinner: { not: null }, event: { status: "finished", id: { not: excludeEventId } } },
      orderBy: { event: { startsAt: "desc" } },
      take: RECENT_FORM_LIMIT,
    });
    return { entityId, results: rows.map((r) => (r.isWinner ? "V" : "D")) };
  }

  private async headToHeadFor(entityAId: string, entityBId: string): Promise<HeadToHeadDto> {
    const rows = await this.prisma.eventParticipant.findMany({
      where: { entityId: entityAId, isWinner: { not: null }, event: { status: "finished", participants: { some: { entityId: entityBId } } } },
    });
    const entityAWins = rows.filter((r) => r.isWinner).length;
    return { entityAId, entityAWins, entityBId, entityBWins: rows.length - entityAWins };
  }
}
