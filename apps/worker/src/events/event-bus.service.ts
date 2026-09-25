import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { DomainEventMessage, DOMAIN_EVENTS_CHANNEL } from "@news/domain";
import Redis from "ioredis";

// Publie les événements métier sur un canal Redis Pub/Sub : l'API s'y abonne pour
// invalider son cache (docs/03 §3). `lazyConnect` : pas de connexion tant qu'aucun
// événement n'est publié.
@Injectable()
export class EventBusService implements OnModuleDestroy {
  private readonly redis: Redis;

  constructor(config: ConfigService) {
    this.redis = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async publish(message: DomainEventMessage): Promise<void> {
    await this.redis.publish(DOMAIN_EVENTS_CHANNEL, JSON.stringify(message));
  }

  async onModuleDestroy(): Promise<void> {
    this.redis.disconnect();
  }
}
