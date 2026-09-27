import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { IngestionModule } from "../ingestion/ingestion.module";
import { NotificationsModule } from "../notifications/notifications.module";
import { PandaScoreModule } from "../pandascore/pandascore.module";
import { AlertsProcessor } from "./alerts.processor";
import { AlertsScheduler } from "./alerts.scheduler";
import { AlertsService } from "./alerts.service";
import { ALERTS_QUEUE_NAME } from "./constants";

@Module({
  imports: [IngestionModule, PandaScoreModule, NotificationsModule, BullModule.registerQueue({ name: ALERTS_QUEUE_NAME })],
  providers: [AlertsService, AlertsScheduler, AlertsProcessor],
})
export class AlertsModule {}
