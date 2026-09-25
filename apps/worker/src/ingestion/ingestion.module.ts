import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { DbModule } from "../db/db.module";
import { EventBusModule } from "../events/event-bus.module";
import { PandaScoreModule } from "../pandascore/pandascore.module";
import { QUEUE_NAME } from "./constants";
import { IngestionProcessor } from "./ingestion.processor";
import { IngestionScheduler } from "./ingestion.scheduler";
import { IngestionService } from "./ingestion.service";

@Module({
  imports: [DbModule, PandaScoreModule, EventBusModule, BullModule.registerQueue({ name: QUEUE_NAME })],
  providers: [IngestionService, IngestionProcessor, IngestionScheduler],
})
export class IngestionModule {}
