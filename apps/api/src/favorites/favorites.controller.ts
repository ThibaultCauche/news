import { BadRequestException, Controller, Delete, Get, HttpCode, Inject, Param, Put, UseGuards } from "@nestjs/common";
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
