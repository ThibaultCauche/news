import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import {
  buildMorningDigestText,
  createLogger,
  isPracticeSession,
  isQuietHour,
  localDayBounds,
  localHourFromOffsetMinutes,
  MORNING_DIGEST_FROM_HOUR,
  MORNING_DIGEST_TO_HOUR,
  MORNING_DIGEST_TYPE,
  notificationSubject,
  shouldNotify,
  SubscriptionLevel,
} from "@news/domain";
import { PRISMA } from "../db/db.module";
import { FcmService } from "./fcm.service";
import { NotificationDispatchService } from "./notification-dispatch.service";

const logger = createLogger("worker:morning-digest");

// Résumé du matin (J19) : le réglage `user_setting.morning_digest` (J6) enfin branché. Entre 8 h et 11 h
// locales (décalage UTC du téléphone), un message liste les matchs du jour parmi les suivis, une fois par
// jour ; rien s'il n'y en a pas. Les heures calmes l'emportent : on réessaie à chaque minute jusqu'à 11 h.
// ponytail: la déduplication passe par le journal avec le premier match du jour comme clé (le journal
// exige un match ou une entité) ; un match ajouté plus tôt dans la journée pourrait déclencher un 2e résumé.
@Injectable()
export class MorningDigestService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly fcm: FcmService,
    private readonly dispatch: NotificationDispatchService,
  ) {}

  async run(now = new Date()): Promise<void> {
    const users = await this.prisma.appUser.findMany({
      where: { setting: { morningDigest: true }, devices: { some: { pushToken: { not: null }, utcOffsetMinutes: { not: null } } } },
      include: { setting: true, devices: true },
    });
    const chains = new Map<string, { id: string; familyId: string | null }[]>();
    for (const user of users) {
      const offset = user.devices.find((d) => d.utcOffsetMinutes !== null)?.utcOffsetMinutes;
      if (offset == null) continue;
      const hour = localHourFromOffsetMinutes(now, offset);
      if (hour < MORNING_DIGEST_FROM_HOUR || hour >= MORNING_DIGEST_TO_HOUR) continue;
      if (isQuietHour(hour, user.setting?.quietHoursStart ?? null, user.setting?.quietHoursEnd ?? null)) continue;
      await this.digest(user, offset, now, chains);
    }
  }

  private async digest(
    user: { id: string; devices: { id: string; pushToken: string | null }[] },
    offset: number,
    now: Date,
    chains: Map<string, { id: string; familyId: string | null }[]>,
  ): Promise<void> {
    const { start, end } = localDayBounds(now, offset);
    const [subscriptions, events] = await Promise.all([
      // ponytail: un suivi de compétition en sourdine est ignoré, sans la règle « la plus proche l'emporte » du J10.
      this.prisma.subscription.findMany({ where: { userId: user.id, muted: false } }),
      this.prisma.event.findMany({
        where: { status: "scheduled", startsAt: { gte: start, lt: end } },
        orderBy: { startsAt: "asc" },
        include: { competition: { select: { categoryId: true, name: true } }, participants: { select: { entityId: true } } },
      }),
    ]);
    if (subscriptions.length === 0) return;

    const matches: { id: string; name: string; startsAt: Date }[] = [];
    for (const event of events) {
      if (!event.startsAt) continue;
      let chain = chains.get(event.competitionId);
      if (!chain) {
        chain = await this.dispatch.getCompetitionChain(event.competitionId);
        chains.set(event.competitionId, chain);
      }
      const familyIds = chain.flatMap((c) => (c.familyId ? [c.familyId] : []));
      // Les essais libres de F1 (J28) n'entrent pas dans le résumé, sauf pour qui a mis une cloche sur la session.
      const practice = event.kind === "session" && isPracticeSession(event.name);
      const followed = subscriptions.some(
        (s) =>
          (!practice || s.targetType === "event") &&
          shouldNotify({ notifyEnabled: true, subscriptionLevel: s.level as SubscriptionLevel, eventImportance: event.importance }) &&
          ((s.targetType === "event" && s.targetId === event.id) ||
            (s.targetType === "entity" && event.participants.some((p) => p.entityId === s.targetId)) ||
            (s.targetType === "competition" && chain.some((c) => c.id === s.targetId)) ||
            (s.targetType === "competition_family" && familyIds.includes(s.targetId)) ||
            (s.targetType === "category" && s.targetId === event.competition.categoryId)),
      );
      if (followed) matches.push({ id: event.id, name: notificationSubject(event, event.competition.name), startsAt: event.startsAt });
    }
    if (matches.length === 0) return;

    try {
      await this.prisma.notificationLog.create({ data: { id: randomUUID(), userId: user.id, eventId: matches[0].id, type: MORNING_DIGEST_TYPE } });
    } catch (err) {
      if ((err as { code?: string }).code === "P2002") return; // déjà envoyé aujourd'hui
      throw err;
    }
    const { title, body } = buildMorningDigestText(matches, offset);
    for (const device of user.devices) {
      if (!device.pushToken) continue;
      const { tokenInvalid } = await this.fcm.send(device.pushToken, title, body, { eventId: matches[0].id });
      if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
    }
    logger.info({ userId: user.id, matches: matches.length }, "résumé du matin envoyé");
  }
}
