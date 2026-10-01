import { Injectable, OnModuleDestroy } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import Redis from "ioredis";

const DEFAULT_TTL_SECONDS = 30;

// Cache Redis court (15-60s, docs/03 §4) pour les réponses publiques, invalidé
// explicitement par DomainEventsSubscriber quand le worker détecte un changement.
// `lazyConnect` : pas de connexion tant qu'aucune requête ne passe par le cache
// (utile pour la génération de la spec OpenAPI, qui n'a pas besoin de Redis).
@Injectable()
export class CacheService implements OnModuleDestroy {
  private readonly redis: Redis;

  constructor(config: ConfigService) {
    this.redis = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async get<T>(key: string): Promise<T | null> {
    const raw = await this.redis.get(key);
    return raw ? (JSON.parse(raw) as T) : null;
  }

  async set(key: string, value: unknown, ttlSeconds = DEFAULT_TTL_SECONDS): Promise<void> {
    await this.redis.set(key, JSON.stringify(value), "EX", ttlSeconds);
  }

  async del(...keys: string[]): Promise<void> {
    if (keys.length) await this.redis.del(keys);
  }

  /** Signal Pub/Sub transitoire vers le worker (ex. réponse au forum, J13). */
  async publish(channel: string, payload: unknown): Promise<void> {
    await this.redis.publish(channel, JSON.stringify(payload));
  }

  async onModuleDestroy(): Promise<void> {
    this.redis.disconnect();
  }
}
