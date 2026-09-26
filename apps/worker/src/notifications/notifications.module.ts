import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { DbModule } from "../db/db.module";
import { EventBusModule } from "../events/event-bus.module";
import { FcmService } from "./fcm.service";
import { NotificationDispatchService } from "./notification-dispatch.service";
import { NotificationsSubscriber } from "./notifications.subscriber";
import { STARTING_SOON_QUEUE_NAME } from "./starting-soon.constants";
import { StartingSoonProcessor } from "./starting-soon.processor";
import { StartingSoonScheduler } from "./starting-soon.scheduler";
import { StartingSoonService } from "./starting-soon.service";

@Module({
  imports: [DbModule, EventBusModule, BullModule.registerQueue({ name: STARTING_SOON_QUEUE_NAME })],
  providers: [FcmService, NotificationDispatchService, NotificationsSubscriber, StartingSoonService, StartingSoonScheduler, StartingSoonProcessor],
})
export class NotificationsModule {}
