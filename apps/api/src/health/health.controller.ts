import { Controller, Get, Inject, ServiceUnavailableException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import Redis from "ioredis";
import { PRISMA } from "../db/db.module";

// GET /health : base + Redis (docs/03 §10). Le reste de l'API vient au J2.
@Controller("health")
export class HealthController {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly config: ConfigService,
  ) {}

  @Get()
  async check() {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
    } catch {
      throw new ServiceUnavailableException("base de données inaccessible");
    }

    const redis = new Redis(this.config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true, maxRetriesPerRequest: 1 });
    try {
      await redis.connect();
      await redis.ping();
    } catch {
      throw new ServiceUnavailableException("Redis inaccessible");
    } finally {
      redis.disconnect();
    }

    return { status: "ok" };
  }
}
