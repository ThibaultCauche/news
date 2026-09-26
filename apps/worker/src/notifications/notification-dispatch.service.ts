import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import {
  buildNotificationText,
  createLogger,
  DomainEventMessage,
  DOMAIN_EVENT_NOTIFICATION_TYPES,
  isQuietHour,
  localHourFromOffsetMinutes,
  MAX_NOTIFICATIONS_PER_HOUR,
  shouldNotify,
  SubscriptionLevel,
} from "@news/domain";
import { PRISMA } from "../db/db.module";
import { FcmService } from "./fcm.service";

const logger = createLogger("worker:notifications");

// 3ᵉ consommateur des événements métier, à côté du cache (docs/03 §3/§6) : qui
// est concerné -> réglages -> déduplication -> envoi FCM -> journal.
@Injectable()
export class NotificationDispatchService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly fcm: FcmService,
  ) {}

  async handle(message: DomainEventMessage): Promise<void> {
    const type = DOMAIN_EVENT_NOTIFICATION_TYPES[message.type];
    if (!type) return; // EventScheduled/ScoreChanged : pas de type de notif au J4

    const event = await this.prisma.event.findUnique({
      where: { id: message.eventId },
      include: { competition: { select: { id: true, categoryId: true } }, participants: { include: { entity: { select: { name: true } } } } },
    });
    if (!event) return;

    const winnerName = event.participants.find((p) => p.isWinner)?.entity.name ?? null;
    const entityIds = event.participants.map((p) => p.entityId);
    const competitionIds = await this.getCompetitionAncestorIds(event.competition.id);

    // Abonnements directs (événement, équipe) et hiérarchiques (compétition
    // parente, catégorie) — docs/03 §6.
    const subscriptions = await this.prisma.subscription.findMany({
      where: {
        OR: [
          { targetType: "event", targetId: event.id },
          { targetType: "entity", targetId: { in: entityIds } },
          { targetType: "competition", targetId: { in: competitionIds } },
          { targetType: "category", targetId: event.competition.categoryId },
        ],
      },
      include: { user: { include: { setting: true, devices: true } } },
    });

    for (const sub of subscriptions) {
      const notifyEnabled = type === "reminder" ? sub.notifyReminder : type === "start" ? sub.notifyStart : sub.notifyResult;
      if (!shouldNotify({ notifyEnabled, subscriptionLevel: sub.level as SubscriptionLevel, eventImportance: event.importance })) continue;

      // "hors équipe suivie en direct" (docs/03 §6) : un abonnement direct
      // (équipe/événement) n'est jamais plafonné, un abonnement large (catégorie/
      // compétition) l'est.
      const bypassRateLimit = sub.targetType === "entity" || sub.targetType === "event";
      if (!bypassRateLimit) {
        const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
        const recent = await this.prisma.notificationLog.count({ where: { userId: sub.userId, sentAt: { gte: oneHourAgo } } });
        if (recent >= MAX_NOTIFICATIONS_PER_HOUR) continue;
      }

      // Déduplication (règle 4 de CLAUDE.md) : on écrit le journal avant d'envoyer.
      // La contrainte unique (userId, eventId, type) fait foi, pas un check-then-act
      // — deux abonnements qui pointent vers le même événement, ou un traitement
      // concurrent, ne peuvent pas envoyer deux fois.
      try {
        await this.prisma.notificationLog.create({ data: { id: randomUUID(), userId: sub.userId, eventId: event.id, type } });
      } catch (err) {
        if ((err as { code?: string }).code === "P2002") continue; // déjà notifié
        throw err;
      }

      const { title, body } = buildNotificationText(type, event.name, sub.user.setting?.spoilerFree ?? true, winnerName);
      for (const device of sub.user.devices) {
        if (
          device.utcOffsetMinutes !== null &&
          isQuietHour(
            localHourFromOffsetMinutes(new Date(), device.utcOffsetMinutes),
            sub.user.setting?.quietHoursStart ?? null,
            sub.user.setting?.quietHoursEnd ?? null,
          )
        ) {
          continue; // regroupement dans un résumé du matin : écran Réglages pas encore construit (J6)
        }
        if (!device.pushToken) continue;
        const { tokenInvalid } = await this.fcm.send(device.pushToken, title, body, { eventId: event.id });
        if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
      }
      logger.info({ userId: sub.userId, eventId: event.id, type }, "notification traitée");
    }
  }

  private async getCompetitionAncestorIds(competitionId: string): Promise<string[]> {
    const ids = [competitionId];
    let currentId: string | null = competitionId;
    while (currentId) {
      const row: { parentId: string | null } | null = await this.prisma.competition.findUnique({ where: { id: currentId }, select: { parentId: true } });
      currentId = row?.parentId ?? null;
      if (currentId) ids.push(currentId);
    }
    return ids;
  }
}
