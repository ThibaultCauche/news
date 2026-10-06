import { Module } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { APP_FILTER, APP_GUARD } from "@nestjs/core";
import { ThrottlerGuard, ThrottlerModule } from "@nestjs/throttler";
import { SentryGlobalFilter } from "@sentry/nestjs/setup";
import { AgendaModule } from "./agenda/agenda.module";
import { AppVersionController } from "./app-version/app-version.controller";
import { AuthModule } from "./auth/auth.module";
import { CacheModule } from "./cache/cache.module";
import { CatalogModule } from "./catalog/catalog.module";
import { CommunityModule } from "./community/community.module";
import { CompetitionsModule } from "./competitions/competitions.module";
import { DbModule } from "./db/db.module";
import { DevicesModule } from "./devices/devices.module";
import { EntitiesModule } from "./entities/entities.module";
import { EventsModule } from "./events/events.module";
import { FavoritesModule } from "./favorites/favorites.module";
import { ForumModule } from "./forum/forum.module";
import { GlossaryModule } from "./glossary/glossary.module";
import { HealthController } from "./health/health.controller";
import { HomeModule } from "./home/home.module";
import { MeModule } from "./me/me.module";
import { SubscriptionsModule } from "./subscriptions/subscriptions.module";

@Module({
  imports: [
    // `../../.env` : cas des tests/e2e lancés depuis apps/api (cwd du package),
    // `.env` : cas où le process a déjà pour cwd la racine du dépôt.
    ConfigModule.forRoot({ isGlobal: true, envFilePath: ["../../.env", ".env"] }),
    // 120 requêtes par minute et par IP (60 avant le J19 : un téléphone en consomme déjà 5 à 6 par minute au repos) ; `THROTTLE_LIMIT` relève la limite pour les tests e2e (suites longues).
    ThrottlerModule.forRootAsync({ useFactory: () => [{ ttl: 60_000, limit: Number(process.env.THROTTLE_LIMIT ?? 120) }] }),
    DbModule,
    CacheModule,
    AuthModule,
    DevicesModule,
    SubscriptionsModule,
    MeModule,
    CommunityModule,
    ForumModule,
    HomeModule,
    AgendaModule,
    EventsModule,
    CompetitionsModule,
    CatalogModule,
    FavoritesModule,
    EntitiesModule,
    GlossaryModule,
  ],
  controllers: [HealthController, AppVersionController],
  providers: [
    // Doit être déclaré avant tout autre filtre d'exception (docs Sentry/NestJS).
    { provide: APP_FILTER, useClass: SentryGlobalFilter },
    { provide: APP_GUARD, useClass: ThrottlerGuard },
  ],
})
export class AppModule {}
