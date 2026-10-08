import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { buildMatchStakes, buildSwissMatchStakes, moreStreamersUrl, StreamDTO } from "@news/domain";
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

// Gagnant de chaque carte, rien de plus (règle 6 de CLAUDE.md — pas de score en
// rounds, pas de nom de carte, plan gratuit PandaScore). `winnerExternalId`
// (`event.result.games`) est un identifiant PandaScore, résolu ici vers notre
// `entityId` via `provider_ref` : l'appli ne doit jamais voir d'identifiant
// fournisseur (règle 1 de CLAUDE.md).
// Personnage joué par un joueur dans une manche (J27, Smash), quand il est saisi.
export class MapCharacterDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() character!: string;
}

export class MapResultDto {
  @ApiProperty() position!: number;
  @ApiProperty({ type: [MapCharacterDto] }) characters!: MapCharacterDto[];
  @ApiProperty({ nullable: true, type: String }) winnerEntityId!: string | null;
  @ApiProperty({ nullable: true, type: Number }) durationSeconds!: number | null;
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

export class StreamDto {
  @ApiProperty() channel!: string;
  @ApiProperty() url!: string;
  @ApiProperty({ nullable: true, type: String }) language!: string | null;
  @ApiProperty({ nullable: true, type: String }) displayName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  /** `null` tant que Twitch n'a pas été interrogé (pas de clé, ou match encore lointain). */
  @ApiProperty({ nullable: true, type: Boolean }) live!: boolean | null;
}

// Une ligne du classement d'une session de F1 (J28) : arrivée de la course ou du sprint, ou qualifications (q1 à q3).
export class ClassificationRowDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() position!: number;
  /** « R » (abandon), « D » (disqualifié)… ; le numéro de position sinon. */
  @ApiProperty() positionText!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) code!: string | null;
  @ApiProperty({ nullable: true, type: String }) number!: string | null;
  @ApiProperty({ nullable: true, type: String }) constructorName!: string | null;
  @ApiProperty({ nullable: true, type: Number }) grid!: number | null;
  @ApiProperty({ nullable: true, type: Number }) laps!: number | null;
  @ApiProperty({ nullable: true, type: String }) time!: string | null;
  @ApiProperty({ nullable: true, type: String }) status!: string | null;
  @ApiProperty({ nullable: true, type: Number }) points!: number | null;
  @ApiProperty({ nullable: true, type: String }) q1!: string | null;
  @ApiProperty({ nullable: true, type: String }) q2!: string | null;
  @ApiProperty({ nullable: true, type: String }) q3!: string | null;
}

export class EventDetailResponseDto extends EventSummaryDto {
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [StreamDto] }) streams!: StreamDto[];
  /** Page du jeu chez Twitch, pour « Autres streamers » ; `null` si on ne la connaît pas. */
  @ApiProperty({ nullable: true, type: String }) moreStreamersUrl!: string | null;
  @ApiProperty({ type: Object }) result!: unknown;
  @ApiProperty({ type: [MapResultDto] }) maps!: MapResultDto[];
  /** Classement complet d'une session de F1 ; vide pour un duel et tant que la source n'a rien publié. */
  @ApiProperty({ type: [ClassificationRowDto] }) classification!: ClassificationRowDto[];
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
        linksFrom: { include: { toEvent: { select: { name: true } } } },
      },
    });
    if (!event) throw new NotFoundException("Événement introuvable");

    const response: EventDetailResponseDto = {
      ...toEventSummary(event),
      sourceUpdatedAt: event.updatedAt.toISOString(),
      streams: await this.buildStreams(event.streams),
      moreStreamersUrl: moreStreamersUrl(event.competition.game),
      result: event.result,
      maps: await this.buildMaps(event.result, event.participants.map((p) => p.entityId)),
      classification: this.buildClassification(event.result, event.participants),
      context: await this.buildContext(event),
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }

  // Classement d'une session (J28) : les lignes sont dans `event.result.rows`, le pilote de chacune se retrouve par sa
  // position, qui est le score de son `event_participant`.
  private buildClassification(result: unknown, participants: { entityId: string; score: number | null; entity: { name: string } }[]): ClassificationRowDto[] {
    type Row = { position: number; positionText?: string; code?: string | null; number?: string | null; constructor?: string | null; grid?: number | null; laps?: number | null; time?: string | null; status?: string | null; points?: number | null; q1?: string | null; q2?: string | null; q3?: string | null };
    const data = result as { type?: string; rows?: Row[] } | null;
    if (data?.type !== "classification") return [];
    const byPosition = new Map(participants.map((p) => [p.score, p]));
    return (data.rows ?? []).flatMap((r) => {
      const driver = byPosition.get(r.position);
      if (!driver) return [];
      return [{
        entityId: driver.entityId,
        position: r.position,
        positionText: r.positionText ?? String(r.position),
        name: driver.entity.name,
        code: r.code ?? null,
        number: r.number ?? null,
        constructorName: r.constructor ?? null,
        grid: r.grid ?? null,
        laps: r.laps ?? null,
        time: r.time ?? null,
        status: r.status ?? null,
        points: r.points ?? null,
        q1: r.q1 ?? null,
        q2: r.q2 ?? null,
        q3: r.q3 ?? null,
      }];
    });
  }

  private async buildStreams(raw: unknown): Promise<StreamDto[]> {
    const streams = ((raw as StreamDTO[] | null) ?? []).filter((s) => s.channel);
    if (streams.length === 0) return [];
    const profiles = await this.prisma.streamChannel.findMany({ where: { login: { in: streams.map((s) => s.channel!) } } });
    const byLogin = new Map(profiles.map((p) => [p.login, p]));
    return streams.map((s) => {
      const p = byLogin.get(s.channel!);
      return { channel: s.channel!, url: s.url, language: s.language, displayName: p?.displayName ?? null, imageUrl: p?.imageUrl ?? null, live: p?.liveCheckedAt ? p.live : null };
    });
  }

  private async buildMaps(result: unknown, participantEntityIds: string[]): Promise<MapResultDto[]> {
    type Game = { position: number; winnerExternalId: string | null; durationSeconds?: number | null; characters?: Record<string, string> };
    const games = (result as { games?: Game[] } | null)?.games ?? [];
    // Identifiants du fournisseur (équipe PandaScore, joueur start.gg) : résolus vers nos entités, jamais montrés à l'appli.
    const externalIds = [...new Set(games.flatMap((g) => [g.winnerExternalId, ...Object.keys(g.characters ?? {})]).filter((id): id is string => id != null))];
    const refs = externalIds.length ? await this.prisma.providerRef.findMany({ where: { objectType: "entity", externalId: { in: externalIds }, objectId: { in: participantEntityIds } } }) : [];
    const entityIdByExternalId = new Map(refs.map((r) => [r.externalId, r.objectId]));
    return games.map((g) => ({
      position: g.position,
      characters: Object.entries(g.characters ?? {}).flatMap(([externalId, character]) => {
        const entityId = entityIdByExternalId.get(externalId);
        return entityId ? [{ entityId, character }] : [];
      }),
      winnerEntityId: g.winnerExternalId != null ? (entityIdByExternalId.get(g.winnerExternalId) ?? null) : null,
      durationSeconds: g.durationSeconds ?? null,
    }));
  }

  private async buildContext(event: EventWithLinks): Promise<EventContextDto> {
    const winnerTarget = event.linksFrom.find((l) => l.outcome === "winner")?.toEvent.name ?? null;
    const loserTarget = event.linksFrom.find((l) => l.outcome === "loser")?.toEvent.name ?? null;
    const stakes =
      event.competition.format === "swiss"
        ? await this.swissStakes(event)
        : event.linksFrom.length === 0 || !ELIMINATION_FORMATS.includes(event.competition.format ?? "")
          ? null
          : buildMatchStakes({ bestOf: event.bestOf, winnerTargetName: winnerTarget, loserTargetName: loserTarget });

    const entityIds = event.participants.map((p) => p.entityId);
    const recentForm = await Promise.all(entityIds.map((entityId) => this.recentFormFor(entityId, event.id)));
    const headToHead = entityIds.length === 2 ? await this.headToHeadFor(entityIds[0], entityIds[1]) : null;

    return { stakes, recentForm, headToHead };
  }

  // Bilan de chaque équipe dans la phase suisse avant ce match (les matchs terminés qui le précèdent).
  private async swissStakes(event: EventWithLinks): Promise<string> {
    const teams = await Promise.all(
      event.participants.map(async (p) => {
        const rows = await this.prisma.eventParticipant.findMany({
          where: {
            entityId: p.entityId,
            isWinner: { not: null },
            event: { competitionId: event.competitionId, status: "finished", id: { not: event.id }, ...(event.startsAt ? { startsAt: { lt: event.startsAt } } : {}) },
          },
          select: { isWinner: true },
        });
        const wins = rows.filter((r) => r.isWinner).length;
        return { name: p.entity.shortName ?? p.entity.name, wins, losses: rows.length - wins };
      }),
    );
    return buildSwissMatchStakes(teams, event.bestOf);
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
