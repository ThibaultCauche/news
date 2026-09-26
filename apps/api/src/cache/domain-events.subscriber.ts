import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { createLogger, DomainEventMessage, DOMAIN_EVENTS_CHANNEL } from "@news/domain";
import Redis from "ioredis";
import { CacheKeys } from "./cache-keys";
import { CacheService } from "./cache.service";

const logger = createLogger("api:cache");

// S'abonne aux événements métier publiés par le worker et invalide les clés
// concernées : accueil, compétition, événement (docs/03 §3).
@Injectable()
export class DomainEventsSubscriber implements OnModuleInit, OnModuleDestroy {
  private readonly subscriber: Redis;

  constructor(
    config: ConfigService,
    private readonly cache: CacheService,
  ) {
    this.subscriber = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async onModuleInit(): Promise<void> {
    this.subscriber.on("message", (_channel, raw) => {
      this.handle(JSON.parse(raw) as DomainEventMessage).catch((err) => logger.error(err, "échec d'invalidation du cache"));
    });
    await this.subscriber.subscribe(DOMAIN_EVENTS_CHANNEL);
  }

  private async handle(message: DomainEventMessage): Promise<void> {
    const keys = [CacheKeys.home(), CacheKeys.competition(message.competitionId), CacheKeys.bracket(message.competitionId)];
    if (message.eventId) keys.push(CacheKeys.event(message.eventId));
    await this.cache.del(...keys);
    logger.info({ message }, "cache invalidé");
  }

  async onModuleDestroy(): Promise<void> {
    this.subscriber.disconnect();
  }
}
