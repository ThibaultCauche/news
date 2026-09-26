import { Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { createLogger, DomainEventMessage, DOMAIN_EVENTS_CHANNEL } from "@news/domain";
import Redis from "ioredis";
import { NotificationDispatchService } from "./notification-dispatch.service";

const logger = createLogger("worker:notifications");

// S'abonne aux événements métier publiés par l'ingestion et le job de rappels T-15
// (docs/03 §3) : 3ᵉ consommateur du canal, à côté du cache côté API et du contexte
// (J6, pas encore construit).
@Injectable()
export class NotificationsSubscriber implements OnModuleInit, OnModuleDestroy {
  private readonly subscriber: Redis;

  constructor(
    config: ConfigService,
    private readonly dispatch: NotificationDispatchService,
  ) {
    this.subscriber = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async onModuleInit(): Promise<void> {
    this.subscriber.on("message", (_channel, raw) => {
      this.dispatch.handle(JSON.parse(raw) as DomainEventMessage).catch((err) => logger.error(err, "échec de traitement des notifications"));
    });
    await this.subscriber.subscribe(DOMAIN_EVENTS_CHANNEL);
  }

  async onModuleDestroy(): Promise<void> {
    this.subscriber.disconnect();
  }
}
