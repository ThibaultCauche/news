import { BadRequestException, Controller, Delete, Get, HttpCode, Inject, NotFoundException, Param, ParseUUIDPipe, Put, UseGuards } from "@nestjs/common";
import { ApiOkResponse, ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { isKnownGame } from "@news/domain";
import { AuthUser } from "../auth/auth.types";
import { CurrentUser } from "../auth/current-user.decorator";
import { JwtAuthGuard } from "../auth/jwt-auth.guard";
import { PRISMA } from "../db/db.module";

export class FavoriteGameDto {
  @ApiProperty() game!: string;
}

// Jeux favoris (J9) : raccourci d'accès uniquement, jamais de notification — d'où une
// table à part de `subscription`, dont la portée est hiérarchique.
@Controller("favorites/games")
@UseGuards(JwtAuthGuard)
export class FavoritesController {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  @Get()
  @ApiOkResponse({ type: [FavoriteGameDto] })
  async list(@CurrentUser() user: AuthUser): Promise<FavoriteGameDto[]> {
    return this.prisma.favoriteGame.findMany({ where: { userId: user.id }, orderBy: { createdAt: "asc" }, select: { game: true } });
  }

  @Put(":game")
  @HttpCode(204)
  async add(@CurrentUser() user: AuthUser, @Param("game") game: string): Promise<void> {
    if (!isKnownGame(game)) throw new BadRequestException("Jeu inconnu");
    await this.prisma.favoriteGame.upsert({
      where: { userId_game: { userId: user.id, game } },
      create: { userId: user.id, game },
      update: {},
    });
  }

  @Delete(":game")
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthUser, @Param("game") game: string): Promise<void> {
    await this.prisma.favoriteGame.deleteMany({ where: { userId: user.id, game } });
  }
}

export class FavoriteCompetitionDto {
  @ApiProperty() id!: string;
  @ApiProperty() name!: string;
  // Logo de la ligue de la série (pastille de la section « Favoris »), `null` sans logo.
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
}

// Compétitions favorites (J20) : même principe que les jeux, un raccourci sans notification.
@Controller("favorites/competitions")
@UseGuards(JwtAuthGuard)
export class FavoriteCompetitionsController {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  @Get()
  @ApiOkResponse({ type: [FavoriteCompetitionDto] })
  async list(@CurrentUser() user: AuthUser): Promise<FavoriteCompetitionDto[]> {
    const rows = await this.prisma.favoriteCompetition.findMany({
      where: { userId: user.id },
      orderBy: { createdAt: "asc" },
      select: { competition: { select: { id: true, name: true, imageUrl: true, parent: { select: { imageUrl: true } } } } },
    });
    return rows.map(({ competition: c }) => ({ id: c.id, name: c.name, imageUrl: c.imageUrl ?? c.parent?.imageUrl ?? null }));
  }

  @Put(":id")
  @HttpCode(204)
  async add(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    if (!(await this.prisma.competition.findUnique({ where: { id }, select: { id: true } }))) throw new NotFoundException("Compétition introuvable");
    await this.prisma.favoriteCompetition.upsert({
      where: { userId_competitionId: { userId: user.id, competitionId: id } },
      create: { userId: user.id, competitionId: id },
      update: {},
    });
  }

  @Delete(":id")
  @HttpCode(204)
  async remove(@CurrentUser() user: AuthUser, @Param("id", ParseUUIDPipe) id: string): Promise<void> {
    await this.prisma.favoriteCompetition.deleteMany({ where: { userId: user.id, competitionId: id } });
  }
}
