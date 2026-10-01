import { Inject, Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import {
  createLogger,
  FORUM_FOLLOW_NOTIFY_MINUTES,
  FORUM_REPLIES_CHANNEL,
  ForumReplyMessage,
  forumSnippet,
  isQuietHour,
  localHourFromOffsetMinutes,
} from "@news/domain";
import Redis from "ioredis";
import { PRISMA } from "../db/db.module";
import { FcmService } from "./fcm.service";

const logger = createLogger("worker:forum-replies");

// Notifications du forum (J13) : « quelqu'un t'a répondu », « quelqu'un t'a mentionné » et « nouveaux
// messages » d'une discussion suivie. L'API publie un signal sur Redis par message ; aucun journal de
// déduplication (un message ne déclenche qu'un signal), sauf les discussions suivies, limitées à une
// notification par tranche de 10 minutes. Mêmes règles que les autres notifications : réglages, heures
// calmes, blocages, sans spoil (le texte d'un message peut en contenir : pas d'aperçu alors).
@Injectable()
export class ForumRepliesSubscriber implements OnModuleInit, OnModuleDestroy {
  private readonly subscriber: Redis;

  constructor(
    config: ConfigService,
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly fcm: FcmService,
  ) {
    this.subscriber = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async onModuleInit(): Promise<void> {
    this.subscriber.on("message", (_channel, raw) => {
      this.handle(JSON.parse(raw) as ForumReplyMessage).catch((err) => logger.error(err, "échec de la notification du forum"));
    });
    await this.subscriber.subscribe(FORUM_REPLIES_CHANNEL);
  }

  async onModuleDestroy(): Promise<void> {
    this.subscriber.disconnect();
  }

  async handle(signal: ForumReplyMessage): Promise<void> {
    const message = await this.prisma.forumMessage.findUnique({
      where: { id: signal.messageId },
      include: { user: { select: { id: true, pseudo: true } }, thread: { select: { id: true, kind: true, targetId: true, title: true } } },
    });
    if (!message || message.hiddenAt) return;

    if (signal.kind === "thread") {
      const exclude = new Set([message.userId, ...(signal.excludeUserIds ?? [])]);
      const followers = await this.prisma.forumThreadFollow.findMany({ where: { threadId: message.threadId, userId: { notIn: [...exclude] } }, select: { userId: true } });
      for (const { userId } of followers) await this.notify(userId, message, "thread");
      return;
    }
    if (signal.toUserId && signal.toUserId !== message.userId) await this.notify(signal.toUserId, message, signal.kind);
  }

  private async notify(
    userId: string,
    message: { id: string; userId: string; body: string; user: { pseudo: string | null }; thread: { id: string; kind: string; targetId: string | null; title: string } },
    kind: "reply" | "mention" | "thread",
  ): Promise<void> {
    const target = await this.prisma.appUser.findUnique({ where: { id: userId }, include: { setting: true, devices: true } });
    if (!target) return;
    const enabled = kind === "thread" ? (target.setting?.notifyForumThreads ?? true) : (target.setting?.notifyForumReplies ?? true);
    if (!enabled) return;
    const blocked = await this.prisma.userBlock.findUnique({ where: { blockerId_blockedId: { blockerId: userId, blockedId: message.userId } } });
    if (blocked) return;

    // Discussion suivie : au plus une notification toutes les 10 minutes (atomique, deux messages
    // simultanés ne passent pas tous les deux).
    if (kind === "thread") {
      const limit = new Date(Date.now() - FORUM_FOLLOW_NOTIFY_MINUTES * 60_000);
      const claimed = await this.prisma.forumThreadFollow.updateMany({
        where: { threadId: message.thread.id, userId, OR: [{ lastNotifiedAt: null }, { lastNotifiedAt: { lt: limit } }] },
        data: { lastNotifiedAt: new Date() },
      });
      if (claimed.count === 0) return;
    }

    const spoilerFree = target.setting?.spoilerFree ?? false;
    const who = message.user.pseudo ?? "Quelqu'un";
    const title = kind === "reply" ? `${who} t'a répondu` : kind === "mention" ? `${who} t'a mentionné` : message.thread.title;
    const body = spoilerFree ? "Ouvre la discussion pour lire." : kind === "thread" ? `${who} : ${forumSnippet(message.body)}` : forumSnippet(message.body);
    const data: Record<string, string> = { threadId: message.thread.id };
    if (message.thread.kind === "event" && message.thread.targetId) data.eventId = message.thread.targetId;

    for (const device of target.devices) {
      if (device.utcOffsetMinutes !== null && isQuietHour(localHourFromOffsetMinutes(new Date(), device.utcOffsetMinutes), target.setting?.quietHoursStart ?? null, target.setting?.quietHoursEnd ?? null)) continue;
      if (!device.pushToken) continue;
      const { tokenInvalid } = await this.fcm.send(device.pushToken, title, body, data);
      if (tokenInvalid) await this.prisma.device.delete({ where: { id: device.id } }).catch(() => undefined);
    }
    logger.info({ userId, messageId: message.id, kind }, "notification du forum traitée");
  }
}
