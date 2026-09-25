import { Module } from "@nestjs/common";
import { CacheModule } from "../cache/cache.module";
import { DbModule } from "../db/db.module";
import { EventsController } from "./events.controller";
import { EventsService } from "./events.service";

@Module({
  imports: [DbModule, CacheModule],
  controllers: [EventsController],
  providers: [EventsService],
})
export class EventsModule {}
