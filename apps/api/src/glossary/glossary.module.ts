import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { GlossaryController } from "./glossary.controller";
import { GlossaryService } from "./glossary.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [GlossaryController],
  providers: [GlossaryService],
})
export class GlossaryModule {}
