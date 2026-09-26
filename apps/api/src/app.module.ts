import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_GUARD } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { AgendaModule } from "./agenda/agenda.module";
import { AuthModule } from "./auth/auth.module";
import { CacheModule } from "./cache/cache.module";
import { CompetitionsModule } from "./competitions/competitions.module";
import { DbModule } from "./db/db.module";
import { DevicesModule } from "./devices/devices.module";
import { EventsModule } from "./events/events.module";
import { HealthController } from "./health/health.controller";
import { HomeModule } from "./home/home.module";
import { MeModule } from "./me/me.module";
import { SubscriptionsModule } from "./subscriptions/subscriptions.module";

@Module({
  imports: [
    // `../../.env` : cas des tests/e2e lancés depuis apps/api (cwd du package),
    // `.env` : cas où le process a déjà pour cwd la racine du dépôt.
    ConfigModule.forRoot({ isGlobal: true, envFilePath: ["../../.env", ".env"] }),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 60 }]),
    DbModule,
    CacheModule,
    AuthModule,
    DevicesModule,
    SubscriptionsModule,
    MeModule,
    HomeModule,
    AgendaModule,
    EventsModule,
    CompetitionsModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
