import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { PandaScoreProvider, StartGgProvider } from "@news/providers";
import { DbModule } from "../db/db.module";
import { EventBusModule } from "../events/event-bus.module";
import { PANDASCORE_PROVIDER, PandaScoreModule } from "../pandascore/pandascore.module";
import { STARTGG_PROVIDER, StartGgModule } from "../startgg/startgg.module";
import { QUEUE_NAME } from "./constants";
import { IngestionHeartbeatService } from "./heartbeat.service";
import { IngestionProcessor } from "./ingestion.processor";
import { IngestionScheduler } from "./ingestion.scheduler";
import { IngestionService } from "./ingestion.service";
import { INGESTION_PROVIDERS, IngestionProviders } from "./providers";

@Module({
  imports: [DbModule, PandaScoreModule, StartGgModule, EventBusModule, BullModule.registerQueue({ name: QUEUE_NAME })],
  providers: [
    {
      provide: INGESTION_PROVIDERS,
      useFactory: (pandascore: PandaScoreProvider, startgg: StartGgProvider | null): IngestionProviders => ({ pandascore, ...(startgg ? { startgg } : {}) }),
      inject: [PANDASCORE_PROVIDER, STARTGG_PROVIDER],
    },
    IngestionService,
    IngestionProcessor,
    IngestionScheduler,
    IngestionHeartbeatService,
  ],
  exports: [IngestionHeartbeatService],
})
export class IngestionModule {}
