import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { EntitiesController } from "./entities.controller";
import { EntitiesService } from "./entities.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [EntitiesController],
  providers: [EntitiesService],
})
export class EntitiesModule {}
