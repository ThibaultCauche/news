import { randomUUID } from "node:crypto";
import { Inject, Injectable } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { createLogger, isQuietHour, localHourFromOffsetMinutes, PICKEM_FORMATS } from "@news/domain";
import { PRISMA } from "../db/db.module";
import { FcmService } from "./fcm.service";

const logger = createLogger("worker:pickem-reminder");
// Le tableau se verrouille au premier match : on prévient 2 h avant, dans une fenêtre d'une minute (le job tourne chaque minute).
const WINDOW_START_MIN = 119;
const WINDOW_END_MIN = 120;
const TYPE = "pickem_reminder";

// Rappel de pick'em (J25) : à T-2 h du premier match d'un tournoi à tableau, ceux qui le suivent (équipe ou compétition)
// et n'ont pas rempli tout leur tableau sont prévenus. Même réglage que le rappel de pronostic. Déduplication par
// (personne, premier match, type) : la contrainte unique de `notification_log` fait foi, comme pour les autres rappels.
@Injectable()
export class PickemReminderService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly fcm: FcmService,
  ) {}

  async run(now = new Date()): Promise<void> {
    const from = new Date(now.getTime() + WINDOW_START_MIN * 60_000);
    const to = new Date(now.getTime() + WINDOW_END_MIN * 60_000);
    const candidates = await this.prisma.event.findMany({
      where: { status: "scheduled", startsAt: { gte: from, lt: to }, competition: { format: { in: PICKEM_FORMATS } } },
      select: { id: true, competitionId: true },
    });
    for (const first of candidates) await this.remind(first.id, first.competitionId, now);
  }

  private async remind(firstEventId: string, competitionId: string, now: Date): Promise<void> {
    const events = await this.prisma.event.findMany({
      where: { competitionId, status: { not: "cancelled" } },
      select: { id: true, status: true, startsAt: true, participants: { select: { entityId: true } } },
    });
    // Seulement le premier match du tournoi, et un tableau qu'on peut remplir (au moins une rencontre à deux équipes connues).
    const earliest = Math.min(...events.map((e) => e.startsAt?.getTime() ?? Infinity));
    const mine = events.find((e) => e.id === firstEventId);
    if (events.length < 3 || mine?.startsAt?.getTime() !== earliest || !events.some((e) => e.participants.length >= 2)) return;

    const chain: string[] = [];
    for (let id: string | null = competitionId; id; ) {
      chain.push(id);
      id = (await this.prisma.competition.findUnique({ where: { id }, select: { parentId: true } }))?.parentId ?? null;
    }
    const entityIds = [...new Set(events.flatMap((e) => e.participants.map((p) => p.entityId)))];
    const subs = await this.prisma.subscription.findMany({
      where: { OR: [{ targetType: "competition", targetId: { in: chain } }, { targetType: "entity", targetId: { in: entityIds } }] },
      include: { user: { include: { setting: true, devices: true } } },
    });
    const competition = await this.prisma.competition.findUniqueOrThrow({ where: { id: competitionId }, select: { name: true, parent: { select: { name: true } } } });
    const name = competition.parent ? `${competition.parent.name} · ${competition.name}` : competition.name;

    for (const user of new Map(subs.map((s) => [s.userId, s.user])).values()) {
      if (!user.pseudo || user.setting?.notifyPredictionReminders === false) continue;
      if ((await this.prisma.bracketPick.count({ where: { userId: user.id, competitionId } })) >= events.length) continue;
      try {
        await this.prisma.notificationLog.create({ data: { id: randomUUID(), userId: user.id, eventId: firstEventId, type: TYPE } });
      } catch (err) {
        if ((err as { code?: string }).code === "P2002") continue; // déjà prévenu
        throw err;
      }
      for (const device of user.devices) {
        if (!device.pushToken) continue;
        if (device.utcOffsetMinutes !== null && isQuietHour(localHourFromOffsetMinutes(now, device.utcOffsetMinutes), user.setting?.quietHoursStart ?? null, user.setting?.quietHoursEnd ?? null)) continue;
        const { tokenInvalid } = await this.fcm.send(
          device.pushToken,
          "Ton tableau n'est pas rempli",
          `${name} commence dans 2 h : remplis ton pick'em avant le premier match.`,
          { competitionId, kind: "pickem" },
          `pickem-${competitionId}`,
        );
        if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
      }
      logger.info({ userId: user.id, competitionId }, "rappel de pick'em traité");
    }
  }
}
