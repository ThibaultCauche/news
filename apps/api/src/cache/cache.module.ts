import { Module } from "@nestjs/common";
import { CacheService } from "./cache.service";
import { DomainEventsSubscriber } from "./domain-events.subscriber";

@Module({
  providers: [CacheService, DomainEventsSubscriber],
  exports: [CacheService],
})
export class CacheModule {}
