import { PARTICIPANT_ORDER } from "../common/event-summary.mapper";
import { Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { BracketFormat, BracketMatchInput, computeBracketRounds, computeCompetitionRanking, EventStatus } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { seriesWithEvents } from "../common/series-with-events";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 30;

// Une ligue racine par jeu (ex. "VCT" pour Valorant) : sert de choix dans le
// filtre "E-sport" de l'Agenda (écran 09) — pas de champ "jeu" dans le
// modèle générique (règle 3 de CLAUDE.md), la racine de la hiérarchie en
// tient lieu.
export class CompetitionRootDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
}

export class CompetitionChildDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() kind!: string;
  @ApiProperty({ nullable: true, type: String }) status!: string | null;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  @ApiProperty({ nullable: true, type: String }) endsAt!: string | null;
  // Au moins un match en base (dans la série ou ses tournois) : l'appli cache une étape passée qui n'en a aucun.
  @ApiProperty() hasEvents!: boolean;
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

// Contexte Liquipedia (docs/03 §7, J6) : `null` tant que le job worker ne l'a pas
// encore trouvé/rafraîchi (recherche + infobox, jusqu'à 24h de décalage) — pas
// d'attente bloquante côté API. Attribution obligatoire (CC-BY-SA, règle 8 de
// CLAUDE.md) : `source`/`license` toujours affichés avec le texte.
export class CompetitionContextDto {
  @ApiProperty() text!: string;
  @ApiProperty() source!: string;
  @ApiProperty() license!: string;
}

// `event_link`/`standing` alimentés au J5 (docs/04) : `standings` est vide et
// `structure` reste `null` jusque-là.
export class CompetitionResponseDto {
  @ApiProperty() id!: string;
  @ApiProperty({ nullable: true, type: String }) parentId!: string | null;
  @ApiProperty() name!: string;
  @ApiProperty() kind!: string;
  @ApiProperty({ nullable: true, type: String }) format!: string | null;
  // Slug du jeu (`valorant`, `league-of-legends`), `null` hors e-sport (J23).
  @ApiProperty({ nullable: true, type: String }) game!: string | null;
  @ApiProperty({ nullable: true, type: String }) status!: string | null;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  @ApiProperty({ nullable: true, type: String }) endsAt!: string | null;
  @ApiProperty({ type: Object, nullable: true }) structure!: unknown;
  @ApiProperty() sourceUpdatedAt!: string;
  @ApiProperty({ type: [CompetitionChildDto] }) children!: CompetitionChildDto[];
  @ApiProperty({ type: [CompetitionStandingDto] }) standings!: CompetitionStandingDto[];
  @ApiProperty({ nullable: true, type: CompetitionContextDto }) context!: CompetitionContextDto | null;
}

export class BracketParticipantDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  @ApiProperty({ nullable: true, type: Number }) score!: number | null;
  @ApiProperty({ nullable: true, type: Boolean }) isWinner!: boolean | null;
}

export class BracketNodeDto {
  @ApiProperty() eventId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() status!: string;
  // Anneau de l'arbre radial (écran 02) : 0 = finale au centre, croissant vers l'extérieur.
  @ApiProperty() round!: number;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  @ApiProperty({ type: [BracketParticipantDto] }) participants!: BracketParticipantDto[];
}

export class BracketLinkDto {
  @ApiProperty() fromEventId!: string;
  @ApiProperty() toEventId!: string;
  @ApiProperty() outcome!: string;
  @ApiProperty({ nullable: true, type: Number }) slot!: number | null;
}

export class BracketResponseDto {
  @ApiProperty({ nullable: true, type: String }) format!: string | null;
  @ApiProperty({ type: [BracketNodeDto] }) nodes!: BracketNodeDto[];
  @ApiProperty({ type: [BracketLinkDto] }) links!: BracketLinkDto[];
  @ApiProperty() sourceUpdatedAt!: string;
}

// Classement global (J23, #M1) : toutes les équipes de la compétition, dans l'ordre.
export class RankingEntryDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  @ApiProperty() rank!: number;
  @ApiProperty({ enum: ["champion", "in_race", "eliminated"] }) status!: "champion" | "in_race" | "eliminated";
  // Dernière étape jouée (« Group Stage », « Playoffs »…) et son format (`swiss`, `single_elim`…).
  @ApiProperty() stage!: string;
  @ApiProperty({ nullable: true, type: String }) stageFormat!: string | null;
  @ApiProperty() wins!: number;
  @ApiProperty() losses!: number;
  // Qualifiée pour la suite par les règles de son étape (3 victoires en phase suisse), pas encore éliminée ni championne.
  @ApiProperty() qualified!: boolean;
}

export class RankingResponseDto {
  @ApiProperty() finished!: boolean;
  @ApiProperty({ type: [RankingEntryDto] }) entries!: RankingEntryDto[];
  @ApiProperty() sourceUpdatedAt!: string;
}

@Injectable()
export class CompetitionsService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getRoots(category: string): Promise<CompetitionRootDto[]> {
    const cacheKey = CacheKeys.competitionRoots(category);
    const cached = await this.cache.get<CompetitionRootDto[]>(cacheKey);
    if (cached) return cached;

    const roots = await this.prisma.competition.findMany({
      where: { parentId: null, category: { slug: category } },
      select: { id: true, name: true },
      orderBy: { name: "asc" },
    });
    await this.cache.set(cacheKey, roots, TTL_SECONDS);
    return roots;
  }

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

    const withEvents = await seriesWithEvents(this.prisma, competition.children.map((c) => c.id));
    const liquipedia = await this.prisma.contextSnippet.findUnique({
      where: { targetType_targetId_kind: { targetType: "competition", targetId: id, kind: "liquipedia_intro" } },
    });

    const response: CompetitionResponseDto = {
      id: competition.id,
      parentId: competition.parentId,
      name: competition.name,
      kind: competition.kind,
      format: competition.format,
      game: competition.game,
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
        hasEvents: withEvents.has(c.id),
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
      context: liquipedia ? { text: liquipedia.text, source: liquipedia.source ?? "Liquipedia", license: liquipedia.license ?? "CC-BY-SA" } : null,
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }

  // Nœuds (événements) et liens gagnant/perdant pour l'arbre radial (02), le
  // repêchage (05) et l'arbre terminé (07) — docs/03 §4.
  async getBracket(id: string): Promise<BracketResponseDto> {
    const cacheKey = CacheKeys.bracket(id);
    const cached = await this.cache.get<BracketResponseDto>(cacheKey);
    if (cached) return cached;

    const competition = await this.prisma.competition.findUnique({ where: { id }, select: { format: true, updatedAt: true } });
    if (!competition) throw new NotFoundException("Compétition introuvable");

    const events = await this.prisma.event.findMany({
      where: { competitionId: id },
      include: {
        participants: {
          include: { entity: { select: { id: true, name: true, shortName: true, imageUrl: true } } },
          orderBy: PARTICIPANT_ORDER,
        },
        linksTo: true,
      },
    });

    const matchInputs: BracketMatchInput[] = events.map((e) => ({
      externalId: e.id,
      name: e.name,
      previousMatches: e.linksTo.map((l) => ({ type: l.outcome as "winner" | "loser", matchExternalId: l.fromEventId })),
    }));
    const rounds = computeBracketRounds(matchInputs);

    const response: BracketResponseDto = {
      format: competition.format,
      nodes: events.map((e) => ({
        eventId: e.id,
        name: e.name,
        status: e.status,
        round: rounds[e.id] ?? 0,
        startsAt: e.startsAt?.toISOString() ?? null,
        participants: e.participants.map((p) => ({
          entityId: p.entityId,
          name: p.entity.name,
          shortName: p.entity.shortName,
          imageUrl: p.entity.imageUrl,
          score: p.score,
          isWinner: p.isWinner,
        })),
      })),
      links: events.flatMap((e) => e.linksTo.map((l) => ({ fromEventId: l.fromEventId, toEventId: l.toEventId, outcome: l.outcome, slot: l.slot }))),
      sourceUpdatedAt: competition.updatedAt.toISOString(),
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }

  // Classement global d'une série (ou d'un tournoi seul) : chaque équipe avec son statut — en course, éliminée en
  // telle étape, championne — et son bilan dans sa dernière étape. Recalculé des matchs en base (`computeCompetitionRanking`).
  async getRanking(id: string): Promise<RankingResponseDto> {
    const cacheKey = `cache:v1:ranking:${id}`;
    const cached = await this.cache.get<RankingResponseDto>(cacheKey);
    if (cached) return cached;

    const competition = await this.prisma.competition.findUnique({
      where: { id },
      select: { kind: true, updatedAt: true, children: { where: { kind: "tournament" }, select: { id: true } } },
    });
    if (!competition) throw new NotFoundException("Compétition introuvable");

    const stageIds = competition.kind === "tournament" ? [id] : competition.children.map((c) => c.id);
    const stages = await this.prisma.competition.findMany({
      where: { id: { in: stageIds } },
      select: {
        name: true,
        format: true,
        status: true,
        startsAt: true,
        events: {
          where: { status: { not: "cancelled" } },
          select: { status: true, startsAt: true, participants: { select: { entityId: true, score: true, isWinner: true } } },
        },
      },
    });
    const ranking = computeCompetitionRanking(
      stages.map((s) => ({
        name: s.name,
        format: s.format as BracketFormat | null,
        status: s.status,
        startsAt: s.startsAt,
        matches: s.events.map((e) => ({ status: e.status as EventStatus, startsAt: e.startsAt, participants: e.participants })),
      })),
    );
    const formatByStage = new Map(stages.map((s) => [s.name, s.format]));
    const entities = await this.prisma.entity.findMany({
      where: { id: { in: ranking.map((r) => r.entityId) } },
      select: { id: true, name: true, shortName: true, imageUrl: true },
    });
    const byId = new Map(entities.map((e) => [e.id, e]));

    const response: RankingResponseDto = {
      // Le statut d'une série n'est pas renseigné par le fournisseur : elle est finie quand toutes ses étapes le sont.
      finished: stages.length > 0 && stages.every((s) => s.status === "finished"),
      entries: ranking.flatMap((r) => {
        const entity = byId.get(r.entityId);
        if (!entity) return [];
        return [{ ...r, name: entity.name, shortName: entity.shortName, imageUrl: entity.imageUrl, stageFormat: formatByStage.get(r.stage) ?? null }];
      }),
      sourceUpdatedAt: competition.updatedAt.toISOString(),
    };
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }
}
