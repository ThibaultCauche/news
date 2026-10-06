import { Module } from "@nestjs/common";
import { AuthModule } from "../auth/auth.module";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { SubscriptionsModule } from "../subscriptions/subscriptions.module";
import { AgendaController } from "./agenda.controller";
import { AgendaService } from "./agenda.service";

@Module({
  imports: [DbModule, CacheModule, AuthModule, SubscriptionsModule],
  controllers: [AgendaController],
  providers: [AgendaService],
})
export class AgendaModule {}
