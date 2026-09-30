import { Inject, Injectable } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { GAME_NAMES } from "@news/domain";
import { CacheKeys } from "../cache/cache-keys";
import { CacheService } from "../cache/cache.service";
import { PRISMA } from "../db/db.module";

const TTL_SECONDS = 60;

export class CatalogChildDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  // Famille de la série (« Champions » pour Champions 2026), `null` sans famille (J10).
  @ApiProperty({ nullable: true, type: String }) familyId!: string | null;
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
        children: { select: { id: true, name: true, familyId: true }, orderBy: { startsAt: "desc" } },
        families: { select: { id: true, name: true }, orderBy: { name: "asc" } },
      },
      orderBy: { name: "asc" },
    });

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
      game.leagues.push({ id: root.id, name: root.name, imageUrl: root.imageUrl, children: root.children, families: root.families });
    }

    const catalog = { categories: [...categories.values()] };
    await this.cache.set(CacheKeys.catalog(), catalog, TTL_SECONDS);
    return catalog;
  }
}
