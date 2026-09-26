import { BullModule } from "@nestjs/bullmq";
import { Module } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { LiquipediaClient } from "@news/providers";
import { DbModule } from "../db/db.module";
import { LIQUIPEDIA_CLIENT, LIQUIPEDIA_QUEUE_NAME } from "./constants";
import { LiquipediaContextService } from "./liquipedia-context.service";
import { LiquipediaProcessor } from "./liquipedia.processor";
import { LiquipediaScheduler } from "./liquipedia.scheduler";

@Module({
  imports: [DbModule, BullModule.registerQueue({ name: LIQUIPEDIA_QUEUE_NAME })],
  providers: [
    {
      provide: LIQUIPEDIA_CLIENT,
      useFactory: (config: ConfigService) => new LiquipediaClient(config.getOrThrow<string>("LIQUIPEDIA_USER_AGENT")),
      inject: [ConfigService],
    },
    LiquipediaContextService,
    LiquipediaProcessor,
    LiquipediaScheduler,
  ],
})
export class LiquipediaModule {}
