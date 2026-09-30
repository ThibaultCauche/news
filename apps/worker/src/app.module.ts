import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { ConfigModule, ConfigService } from "@nestjs/config";
import Redis from "ioredis";
import { AlertsModule } from "./alerts/alerts.module";
import { IngestionModule } from "./ingestion/ingestion.module";
import { LiquipediaModule } from "./liquipedia/liquipedia.module";
import { PredictionsModule } from "./predictions/predictions.module";
import { NotificationsModule } from "./notifications/notifications.module";

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true }),
    BullModule.forRootAsync({
      inject: [ConfigService],
      useFactory: (config: ConfigService) => ({
        connection: new Redis(config.getOrThrow<string>("REDIS_URL"), { maxRetriesPerRequest: null }),
      }),
    }),
    IngestionModule,
    NotificationsModule,
    PredictionsModule,
    LiquipediaModule,
    AlertsModule,
  ],
})
export class AppModule {}
