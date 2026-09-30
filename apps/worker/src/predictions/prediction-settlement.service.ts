import { Inject, Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { createLogger, DomainEventMessage, DOMAIN_EVENTS_CHANNEL, scorePrediction } from "@news/domain";
import Redis from "ioredis";
import { PRISMA } from "../db/db.module";

const logger = createLogger("worker:predictions");

// Attribue les points des pronostics quand un match se termine (J11, docs/03 §3 : nouveau
// consommateur du canal d'événements métier). Idempotent : seules les lignes `settledAt IS NULL`
// sont traitées, et un rattrapage au démarrage couvre un `EventFinished` manqué (worker arrêté).
// Un match terminé sans vainqueur (annulé, forfait sans résultat) laisse le pronostic sans effet.
@Injectable()
export class PredictionSettlementService implements OnModuleInit, OnModuleDestroy {
  private readonly subscriber: Redis;

  constructor(
    config: ConfigService,
    @Inject(PRISMA) private readonly prisma: PrismaClient,
  ) {
    this.subscriber = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async onModuleInit(): Promise<void> {
    this.subscriber.on("message", (_channel, raw) => {
      const message = JSON.parse(raw) as DomainEventMessage;
      if (message.type !== "EventFinished" || !message.eventId) return;
      this.settleEvent(message.eventId).catch((err) => logger.error(err, "échec du règlement des pronostics"));
    });
    await this.subscriber.subscribe(DOMAIN_EVENTS_CHANNEL);
    this.settleAllFinished().catch((err) => logger.error(err, "échec du rattrapage des pronostics"));
  }

  async onModuleDestroy(): Promise<void> {
    this.subscriber.disconnect();
  }

  async settleAllFinished(): Promise<void> {
    const pending = await this.prisma.prediction.findMany({
      where: { settledAt: null, event: { status: "finished" } },
      select: { eventId: true },
      distinct: ["eventId"],
    });
    for (const { eventId } of pending) await this.settleEvent(eventId);
  }

  async settleEvent(eventId: string): Promise<number> {
    const event = await this.prisma.event.findUnique({ where: { id: eventId }, include: { participants: true } });
    if (!event || event.status !== "finished") return 0;
    const winner = event.participants.find((p) => p.isWinner);
    if (!winner) return 0;
    const outcome = {
      winnerEntityId: winner.entityId,
      scoreByEntity: Object.fromEntries(event.participants.map((p) => [p.entityId, p.score])),
    };
    const pending = await this.prisma.prediction.findMany({ where: { eventId, settledAt: null } });
    const now = new Date();
    for (const p of pending) {
      const points = scorePrediction({ pickedEntityId: p.pickedEntityId, pickedScore: p.pickedScore, otherScore: p.otherScore }, outcome);
      // `settledAt: null` dans le where : deux règlements simultanés ne comptent pas deux fois.
      await this.prisma.prediction.updateMany({ where: { id: p.id, settledAt: null }, data: { points, settledAt: now } });
    }
    if (pending.length > 0) logger.info({ eventId, count: pending.length }, "pronostics réglés");
    return pending.length;
  }
}
