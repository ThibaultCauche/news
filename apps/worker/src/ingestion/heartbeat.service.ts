import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

const HEARTBEAT_KEY = "ingestion:heartbeat";

// Distinct de provider_ref.last_synced_at (mis à jour uniquement quand un
// payload change, règle 4 de CLAUDE.md) : ce battement marque qu'un poll a
// RÉUSSI, changement ou non, pour que l'alerte "ingestion arrêtée" (docs/03
// §10) ne se déclenche pas juste parce que rien n'a changé chez le fournisseur
// (vécu en vrai au J7 : fausse alerte après 15 min sans match en direct).
@Injectable()
export class IngestionHeartbeatService implements OnModuleDestroy {
  private readonly redis: Redis;

  constructor(config: ConfigService) {
    this.redis = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async touch(): Promise<void> {
    await this.redis.set(HEARTBEAT_KEY, Date.now().toString());
  }

  async getLastSeenAt(): Promise<Date | null> {
    const value = await this.redis.get(HEARTBEAT_KEY);
    return value ? new Date(Number(value)) : null;
  }

  async onModuleDestroy(): Promise<void> {
    this.redis.disconnect();
  }
}
