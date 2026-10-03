import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { DbModule } from "../db/db.module";
import { FavoriteCompetitionsController, FavoritesController } from "./favorites.controller";

@Module({
  imports: [DbModule, AuthModule],
  controllers: [FavoritesController, FavoriteCompetitionsController],
})
export class FavoritesModule {}
