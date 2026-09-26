import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { createLogger } from "@news/domain";
import { PRISMA } from "../db/db.module";
import { EventBusService } from "../events/event-bus.service";

const logger = createLogger("worker:notifications");
const REMINDER_WINDOW_START_MIN = 14;
const REMINDER_WINDOW_END_MIN = 15;

// Détecte les matchs qui commencent dans 15 minutes et publie `EventStartingSoon`
// (docs/03 §3/§6, rappel T-15). Fenêtre d'une minute alignée sur le rythme du job
// (`STARTING_SOON_INTERVAL_MS`) : chaque match n'y tombe normalement qu'une fois,
// la déduplication par (user, event, type) protège du reste (double publication,
// redémarrage du worker pendant la fenêtre...).
@Injectable()
export class StartingSoonService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly eventBus: EventBusService,
  ) {}

  async run(): Promise<void> {
    const now = Date.now();
    const from = new Date(now + REMINDER_WINDOW_START_MIN * 60 * 1000);
    const to = new Date(now + REMINDER_WINDOW_END_MIN * 60 * 1000);
    const events = await this.prisma.event.findMany({
      where: { status: "scheduled", startsAt: { gte: from, lt: to } },
      select: { id: true, competitionId: true },
    });
    for (const event of events) {
      await this.eventBus.publish({ type: "EventStartingSoon", eventId: event.id, competitionId: event.competitionId });
    }
    if (events.length > 0) logger.info({ count: events.length }, "rappels T-15 publiés");
  }
}
