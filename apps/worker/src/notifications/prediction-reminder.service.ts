import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import {
  buildNotificationText,
  createLogger,
  isQuietHour,
  localHourFromOffsetMinutes,
  PREDICTION_REMINDER_MINUTES,
  shouldNotify,
  SubscriptionLevel,
} from "@news/domain";
import { PRISMA } from "../db/db.module";
import { FcmService } from "./fcm.service";
import { NotificationDispatchService } from "./notification-dispatch.service";

const logger = createLogger("worker:prediction-reminder");

// Rappel « tu n'as pas pronostiqué » (J14) : 30 minutes avant le coup d'envoi, pour les matchs des
// suivis de l'utilisateur (équipe, match, compétition) où il n'a pas encore de pronostic. Même fenêtre
// d'une minute que le rappel T-15 ; la déduplication (user, event, type) protège du reste.
@Injectable()
export class PredictionReminderService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly fcm: FcmService,
    private readonly dispatch: NotificationDispatchService,
  ) {}

  async run(now = new Date()): Promise<void> {
    const from = new Date(now.getTime() + (PREDICTION_REMINDER_MINUTES - 1) * 60_000);
    const to = new Date(now.getTime() + PREDICTION_REMINDER_MINUTES * 60_000);
    const events = await this.prisma.event.findMany({
      where: { status: "scheduled", startsAt: { gte: from, lt: to } },
      include: { participants: { select: { entityId: true } } },
    });
    for (const event of events) {
      if (event.participants.length === 2) await this.remind(event);
    }
  }

  private async remind(event: { id: string; name: string; competitionId: string; importance: number; participants: { entityId: string }[] }): Promise<void> {
    const competitionIds = (await this.dispatch.getCompetitionChain(event.competitionId)).map((c) => c.id);
    const subscriptions = await this.prisma.subscription.findMany({
      where: {
        // ponytail: un suivi de compétition en sourdine est ignoré, sans la règle « la plus proche l'emporte » du J10.
        muted: false,
        user: { pseudo: { not: null }, predictions: { none: { eventId: event.id } } },
        OR: [
          { targetType: "event", targetId: event.id },
          { targetType: "entity", targetId: { in: event.participants.map((p) => p.entityId) } },
          { targetType: "competition", targetId: { in: competitionIds } },
        ],
      },
      include: { user: { include: { setting: true, devices: true } } },
    });

    const done = new Set<string>();
    for (const sub of subscriptions) {
      if (done.has(sub.userId)) continue;
      if (!shouldNotify({ notifyEnabled: true, subscriptionLevel: sub.level as SubscriptionLevel, eventImportance: event.importance })) continue;
      if (sub.user.setting && !sub.user.setting.notifyPredictionReminders) continue;
      done.add(sub.userId);
      try {
        await this.prisma.notificationLog.create({ data: { id: randomUUID(), userId: sub.userId, eventId: event.id, type: "prediction_reminder" } });
      } catch (err) {
        if ((err as { code?: string }).code === "P2002") continue; // déjà rappelé
        throw err;
      }
      const { title, body } = buildNotificationText("prediction_reminder", event.name, false, null);
      for (const device of sub.user.devices) {
        if (
          device.utcOffsetMinutes !== null &&
          isQuietHour(localHourFromOffsetMinutes(new Date(), device.utcOffsetMinutes), sub.user.setting?.quietHoursStart ?? null, sub.user.setting?.quietHoursEnd ?? null)
        ) {
          continue;
        }
        if (!device.pushToken) continue;
        const { tokenInvalid } = await this.fcm.send(device.pushToken, title, body, { eventId: event.id });
        if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
      }
      logger.info({ userId: sub.userId, eventId: event.id }, "rappel de pronostic traité");
    }
  }
}
