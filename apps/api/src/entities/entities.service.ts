import { BadRequestException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { Entity, PrismaClient } from "@news/db";
import { isKnownGame } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { eventSummaryInclude, EventSummaryDto, toEventSummary } from "../common/event-summary.mapper";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 30;
// Assez large pour couvrir une saison (bilan/série de victoires) sans pagination :
// une seule vraie compétition (Champions 2026) à ce stade du projet.
const HISTORY_LIMIT = 100;

// Fiche équipe (écran 10, docs/03 §4). Pas de "Carte 1 · Ascent" ni de détail par
// carte : `event.result.games[].winnerExternalId` n'est pas résolu vers notre
// `entityId` à l'ingestion (seul `EventParticipant.score`/`isWinner`, la série,
// l'est) — hors périmètre du J6, le score de série suffit au critère d'acceptation.
// Pas de "Transferts et effectif" non plus : aucune source de roster branchée.
// Structure d'une équipe (J23, #A4) : renvoyée seulement quand elle compte au moins deux équipes (une équipe
// seule dans sa structure n'a rien de plus à suivre), pour afficher « Suivre toute G2 ».
export class EntityOrganizationDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty() teamCount!: number;
  @ApiProperty({ type: [String], description: "Slugs des jeux où la structure a une équipe" }) games!: string[];
}

// Bilan d'un joueur dans un tournoi (J27) : « Genesis X3 : 6-2 ».
export class EntityTournamentDto {
  @ApiProperty() competitionId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() wins!: number;
  @ApiProperty() losses!: number;
}

// Adversaire fréquent d'un joueur (J27) : bilan contre lui.
export class EntityRivalDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() wins!: number;
  @ApiProperty() losses!: number;
}

// Poule d'un joueur (J27) : les sets du groupe où il joue, pas les centaines des autres groupes.
export class EntityPoolDto {
  @ApiProperty({ nullable: true, type: String }) group!: string | null;
  @ApiProperty({ nullable: true, type: String }) phaseName!: string | null;
  @ApiProperty({ nullable: true, type: String }) tournamentName!: string | null;
  @ApiProperty({ nullable: true, type: String }) tournamentId!: string | null;
  @ApiProperty({ type: [EventSummaryDto] }) events!: EventSummaryDto[];
}

export class EntityResponseDto {
  @ApiProperty() id!: string;
  @ApiProperty({ description: "team ou player" }) kind!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) region!: string | null;
  @ApiProperty({ nullable: true, type: String, description: "Slug du jeu de l'équipe" }) game!: string | null;
  @ApiProperty({ nullable: true, type: EntityOrganizationDto }) organization!: EntityOrganizationDto | null;
  @ApiProperty() wins!: number;
  @ApiProperty() losses!: number;
  @ApiProperty() winStreak!: number;
  @ApiProperty({ nullable: true, type: EventSummaryDto }) lastEvent!: EventSummaryDto | null;
  @ApiProperty({ nullable: true, type: EventSummaryDto }) nextEvent!: EventSummaryDto | null;
  @ApiProperty({ type: [EntityTournamentDto], description: "Joueurs : bilan par tournoi, le plus récent d'abord" }) tournaments!: EntityTournamentDto[];
  @ApiProperty({ type: [EntityRivalDto], description: "Joueurs : les trois adversaires les plus rencontrés" }) rivals!: EntityRivalDto[];
  @ApiProperty() sourceUpdatedAt!: string;
}

export class EntityListItemDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
}

@Injectable()
export class EntitiesService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getById(id: string): Promise<EntityResponseDto> {
    const cacheKey = CacheKeys.entity(id);
    const cached = await this.cache.get<EntityResponseDto>(cacheKey);
    if (cached) return cached;

    const entity = await this.prisma.entity.findUnique({ where: { id } });
    if (!entity) throw new NotFoundException("Équipe introuvable");

    const response = await this.buildResponse(entity);
    await this.cache.set(cacheKey, response, TTL_SECONDS);
    return response;
  }

  // Équipes ayant au moins un match dans une compétition de ce jeu (onglet Équipes,
  // J9) : pas de rattachement direct équipe → jeu dans le modèle, on le déduit des matchs. Les joueurs (J27) sont des
  // centaines par tournoi : seuls ceux qui ont atteint une phase à arbre (Top 64, Top 8) y figurent.
  async listByGame(game: string): Promise<EntityListItemDto[]> {
    if (!isKnownGame(game)) throw new BadRequestException("Jeu inconnu");
    return this.prisma.entity.findMany({
      where: {
        OR: [
          { kind: "team", participants: { some: { event: { competition: { game } } } } },
          { kind: "player", participants: { some: { event: { competition: { game, hasBracket: true } } } } },
        ],
      },
      select: { id: true, name: true, shortName: true, imageUrl: true },
      orderBy: { name: "asc" },
    });
  }

  // Résolution par nom court (ex. "G2", "KC") plutôt que par id interne :
  // sert à l'onboarding (écran 12, J6), qui suggère des équipes par leur nom
  // sans connaître leur id à l'avance (pas de recherche générique côté API,
  // ce cas précis suffit pour l'instant).
  async getByShortName(shortName: string, game?: string): Promise<EntityResponseDto> {
    // `game` départage « G2 » de Valorant et « G2 » de League of Legends (J23).
    const entity = await this.prisma.entity.findFirst({
      where: {
        shortName: { equals: shortName, mode: "insensitive" },
        ...(game ? { participants: { some: { event: { competition: { game } } } } } : {}),
      },
    });
    if (!entity) throw new NotFoundException("Équipe introuvable");
    return this.getById(entity.id);
  }

  private async organizationOf(organizationId: string | null): Promise<EntityOrganizationDto | null> {
    if (!organizationId) return null;
    const organization = await this.prisma.organization.findUnique({
      where: { id: organizationId },
      select: {
        id: true,
        name: true,
        entities: { select: { participants: { take: 1, select: { event: { select: { competition: { select: { game: true } } } } } } } },
      },
    });
    if (!organization || organization.entities.length < 2) return null;
    const games = new Set<string>();
    for (const team of organization.entities) {
      const game = team.participants[0]?.event.competition.game;
      if (game) games.add(game);
    }
    return { id: organization.id, name: organization.name, teamCount: organization.entities.length, games: [...games].sort() };
  }

  // Résultats d'un joueur par tournoi et adversaires les plus rencontrés (J27), depuis nos propres sets terminés.
  private async playerHistory(entityId: string): Promise<{ tournaments: EntityTournamentDto[]; rivals: EntityRivalDto[] }> {
    const rows = await this.prisma.eventParticipant.findMany({
      where: { entityId, isWinner: { not: null }, event: { status: "finished" } },
      orderBy: { event: { startsAt: "desc" } },
      take: HISTORY_LIMIT,
      select: {
        isWinner: true,
        event: {
          select: {
            startsAt: true,
            competition: { select: { id: true, name: true, parent: { select: { id: true, name: true } } } },
            participants: { select: { entityId: true, entity: { select: { name: true } } } },
          },
        },
      },
    });
    const byTournament = new Map<string, EntityTournamentDto>();
    const byRival = new Map<string, EntityRivalDto>();
    for (const row of rows) {
      // Le tournoi est la série (« Genesis X3 »), pas la phase (« Top 8 »).
      const tournament = row.event.competition.parent ?? row.event.competition;
      const t = byTournament.get(tournament.id) ?? { competitionId: tournament.id, name: tournament.name, wins: 0, losses: 0 };
      if (row.isWinner) t.wins += 1;
      else t.losses += 1;
      byTournament.set(tournament.id, t);
      for (const other of row.event.participants.filter((p) => p.entityId !== entityId)) {
        const r = byRival.get(other.entityId) ?? { entityId: other.entityId, name: other.entity.name, wins: 0, losses: 0 };
        if (row.isWinner) r.wins += 1;
        else r.losses += 1;
        byRival.set(other.entityId, r);
      }
    }
    // Un adversaire n'est « fréquent » qu'à partir de deux rencontres.
    const rivals = [...byRival.values()].filter((r) => r.wins + r.losses >= 2).sort((a, b) => b.wins + b.losses - (a.wins + a.losses) || a.name.localeCompare(b.name)).slice(0, 3);
    return { tournaments: [...byTournament.values()], rivals };
  }

  // Poule d'un joueur (J27) : son groupe le plus récent dans une phase sans arbre, avec tous les sets de ce groupe.
  async poolOf(id: string): Promise<EntityPoolDto> {
    const entity = await this.prisma.entity.findUnique({ where: { id }, select: { id: true } });
    if (!entity) throw new NotFoundException("Joueur introuvable");
    const recent = await this.prisma.event.findMany({
      where: { participants: { some: { entityId: id } }, competition: { hasBracket: false } },
      orderBy: [{ startsAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }],
      take: 20,
      select: { competitionId: true, result: true },
    });
    const latest = recent.find((e) => (e.result as { group?: string | null } | null)?.group);
    const group = (latest?.result as { group?: string | null } | null)?.group ?? null;
    if (!latest || !group) return { group: null, phaseName: null, tournamentName: null, tournamentId: null, events: [] };
    const events = await this.prisma.event.findMany({
      where: { competitionId: latest.competitionId, result: { path: ["group"], equals: group } },
      orderBy: [{ startsAt: { sort: "asc", nulls: "last" } }, { name: "asc" }],
      include: eventSummaryInclude,
    });
    const competition = await this.prisma.competition.findUnique({ where: { id: latest.competitionId }, select: { name: true, parent: { select: { id: true, name: true } } } });
    return { group, phaseName: competition?.name ?? null, tournamentName: competition?.parent?.name ?? null, tournamentId: competition?.parent?.id ?? null, events: events.map(toEventSummary) };
  }

  private async buildResponse(entity: Entity): Promise<EntityResponseDto> {
    const history = await this.prisma.eventParticipant.findMany({
      where: { entityId: entity.id, isWinner: { not: null }, event: { status: "finished" } },
      orderBy: { event: { startsAt: "desc" } },
      take: HISTORY_LIMIT,
    });
    const wins = history.filter((row) => row.isWinner).length;
    let winStreak = 0;
    for (const row of history) {
      if (!row.isWinner) break;
      winStreak += 1;
    }

    const [lastEvent, nextEvent] = await Promise.all([
      this.prisma.event.findFirst({
        where: { status: "finished", participants: { some: { entityId: entity.id } } },
        orderBy: { startsAt: "desc" },
        include: eventSummaryInclude,
      }),
      this.prisma.event.findFirst({
        where: { status: { in: ["scheduled", "live"] }, participants: { some: { entityId: entity.id } } },
        orderBy: { startsAt: "asc" },
        include: eventSummaryInclude,
      }),
    ]);

    const { tournaments, rivals } = entity.kind === "player" ? await this.playerHistory(entity.id) : { tournaments: [], rivals: [] };
    const response: EntityResponseDto = {
      id: entity.id,
      kind: entity.kind,
      name: entity.name,
      shortName: entity.shortName,
      region: entity.region,
      game: lastEvent?.competition.game ?? nextEvent?.competition.game ?? null,
      organization: await this.organizationOf(entity.organizationId),
      wins,
      losses: history.length - wins,
      winStreak,
      lastEvent: lastEvent ? toEventSummary(lastEvent) : null,
      nextEvent: nextEvent ? toEventSummary(nextEvent) : null,
      tournaments,
      rivals,
      sourceUpdatedAt: entity.updatedAt.toISOString(),
    };
    return response;
  }
}
