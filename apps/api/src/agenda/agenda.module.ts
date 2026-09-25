import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { AgendaController } from "./agenda.controller";
import { AgendaService } from "./agenda.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [AgendaController],
  providers: [AgendaService],
})
export class AgendaModule {}
