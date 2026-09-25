import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { CompetitionsController } from "./competitions.controller";
import { CompetitionsService } from "./competitions.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [CompetitionsController],
  providers: [CompetitionsService],
})
export class CompetitionsModule {}
