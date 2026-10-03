import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { GAME_NAMES, isMajorEvent } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 60;

export class CatalogChildDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  // Famille de la série (« Champions » pour Champions 2026), `null` sans famille (J10).
  @ApiProperty({ nullable: true, type: String }) familyId!: string | null;
  // La série est en cours (dates de la série), pour la section « En cours » de l'onglet Compétitions (J20).
  @ApiProperty() live!: boolean;
  // Un grand rendez-vous mondial (Champions, Masters, Coupe du monde…) : seuls ceux-là vont dans « En cours », qui
  // resterait trop longue à mesure qu'on ajoute des jeux et des sports.
  @ApiProperty() major!: boolean;
}

// Une compétition qui revient d'année en année (J10) : suivre la famille suit toutes ses éditions.
export class CatalogFamilyDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
}

export class CatalogLeagueDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  @ApiProperty({ type: [CatalogChildDto] }) children!: CatalogChildDto[];
  @ApiProperty({ type: [CatalogFamilyDto] }) families!: CatalogFamilyDto[];
  // Une compétition de la ligue est en cours (dates de la série : le fournisseur ne donne pas de statut de série).
  @ApiProperty() live!: boolean;
}

export class CatalogGameDto {
  @ApiProperty() slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ type: [CatalogLeagueDto] }) leagues!: CatalogLeagueDto[];
}

export class CatalogCategoryDto {
  @ApiProperty() slug!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ type: [CatalogGameDto] }) games!: CatalogGameDto[];
}

export class CatalogDto {
  @ApiProperty({ type: [CatalogCategoryDto] }) categories!: CatalogCategoryDto[];
}

const isInProgress = (c: { startsAt: Date | null; endsAt: Date | null }, now: Date): boolean => c.startsAt !== null && c.startsAt <= now && (c.endsAt === null || c.endsAt >= now);

// Onglet Compétitions (J9) : catégorie → jeu → ligues (racines) et leurs séries
// directes. Une catégorie ou un jeu sans compétition n'apparaît pas (on part des
// compétitions, pas des catégories). La recherche se fait côté appli sur ce catalogue.
@Injectable()
export class CatalogService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
  ) {}

  async getCatalog(): Promise<CatalogDto> {
    const cached = await this.cache.get<CatalogDto>(CacheKeys.catalog());
    if (cached) return cached;

    const roots = await this.prisma.competition.findMany({
      where: { parentId: null, game: { not: null } },
      include: {
        category: true,
        children: { select: { id: true, name: true, familyId: true, startsAt: true, endsAt: true }, orderBy: { startsAt: "desc" } },
        families: { select: { id: true, name: true }, orderBy: { name: "asc" } },
      },
      orderBy: { name: "asc" },
    });

    const now = new Date();
    const categories = new Map<string, CatalogCategoryDto>();
    for (const root of roots) {
      const slug = root.game!;
      let category = categories.get(root.category.slug);
      if (!category) {
        category = { slug: root.category.slug, name: root.category.name, games: [] };
        categories.set(category.slug, category);
      }
      let game = category.games.find((g) => g.slug === slug);
      if (!game) {
        game = { slug, name: GAME_NAMES[slug] ?? slug, leagues: [] };
        category.games.push(game);
      }
      game.leagues.push({
        id: root.id,
        name: root.name,
        imageUrl: root.imageUrl,
        children: root.children.map((c) => ({ id: c.id, name: c.name, familyId: c.familyId, live: isInProgress(c, now), major: isMajorEvent(root.name, c.name) })),
        families: root.families,
        live: root.children.some((c) => isInProgress(c, now)),
      });
    }

    const catalog = { categories: [...categories.values()] };
    await this.cache.set(CacheKeys.catalog(), catalog, TTL_SECONDS);
    return catalog;
  }
}
