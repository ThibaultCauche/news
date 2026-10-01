import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { FORUM_MAX_PINNED, forumSnippet } from "@news/domain";
import { PRISMA } from "../db/db.module";
import { ModerationLogDto, ReportedMessageDto } from "./forum.dto";
import { ForumService } from "./forum.service";

const QUEUE_SIZE = 100;

// Outils de modération du forum (J13), réservés aux comptes `is_moderator` (posé à la main en base) :
// file des signalements, masquage, exclusion d'un utilisateur, verrouillage d'un fil.
@Injectable()
export class ModerationService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly forum: ForumService,
  ) {}

  private async requireModerator(userId: string): Promise<void> {
    const user = await this.prisma.appUser.findUnique({ where: { id: userId }, select: { isModerator: true } });
    if (!user?.isModerator) throw new ForbiddenException({ statusCode: 403, code: "NOT_MODERATOR", message: "Réservé aux modérateurs" });
  }

  /** Messages signalés non traités, les plus signalés d'abord (messages déjà masqués automatiquement compris). */
  async listReports(userId: string): Promise<ReportedMessageDto[]> {
    await this.requireModerator(userId);
    const reports = await this.prisma.forumReport.findMany({
      where: { resolvedAt: null },
      include: { message: { include: { user: { select: { id: true, pseudo: true } }, thread: { select: { title: true } } } } },
      orderBy: { createdAt: "desc" },
    });
    const byMessage = new Map<string, ReportedMessageDto>();
    for (const r of reports) {
      const entry = byMessage.get(r.messageId);
      if (entry) {
        entry.reportCount++;
        if (!entry.reasons.includes(r.reason)) entry.reasons.push(r.reason);
        continue;
      }
      byMessage.set(r.messageId, {
        messageId: r.messageId,
        threadId: r.message.threadId,
        threadTitle: r.message.thread.title,
        authorId: r.message.user.id,
        authorPseudo: r.message.user.pseudo ?? "Joueur",
        body: r.message.body,
        hidden: r.message.hiddenAt !== null,
        reportCount: 1,
        reasons: [r.reason],
        createdAt: r.message.createdAt,
      });
    }
    return [...byMessage.values()].sort((a, b) => b.reportCount - a.reportCount).slice(0, QUEUE_SIZE);
  }

  /** Les signalements étaient infondés : le message revient s'il avait été masqué automatiquement. */
  async dismiss(userId: string, messageId: string): Promise<void> {
    await this.requireModerator(userId);
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId }, select: { userId: true, threadId: true, body: true } });
    await this.prisma.$transaction([
      this.prisma.forumReport.updateMany({ where: { messageId, resolvedAt: null }, data: { resolvedAt: new Date() } }),
      this.prisma.forumMessage.updateMany({ where: { id: messageId, hiddenReason: "reports" }, data: { hiddenAt: null, hiddenReason: null } }),
    ]);
    if (message) await this.forum.logModeration(userId, "dismiss", { messageId, targetUserId: message.userId, threadId: message.threadId, detail: forumSnippet(message.body) });
  }

  async hide(userId: string, messageId: string): Promise<void> {
    await this.requireModerator(userId);
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId }, select: { userId: true, threadId: true, body: true } });
    if (!message) throw new NotFoundException("Message introuvable");
    await this.forum.hideMessage(messageId, "moderator");
    await this.forum.logModeration(userId, "hide", { messageId, targetUserId: message.userId, threadId: message.threadId, detail: forumSnippet(message.body) });
  }

  async setBan(userId: string, targetId: string, banned: boolean): Promise<void> {
    await this.requireModerator(userId);
    const target = await this.prisma.appUser.findUnique({ where: { id: targetId }, select: { isModerator: true } });
    if (!target) throw new NotFoundException("Joueur introuvable");
    if (target.isModerator) throw new ForbiddenException({ statusCode: 403, code: "CANNOT_BAN_MODERATOR", message: "Impossible d'exclure un modérateur" });
    await this.prisma.appUser.update({ where: { id: targetId }, data: { forumBannedAt: banned ? new Date() : null } });
    await this.forum.logModeration(userId, banned ? "ban" : "unban", { targetUserId: targetId });
  }

  async setLock(userId: string, threadId: string, locked: boolean): Promise<void> {
    await this.requireModerator(userId);
    const thread = await this.prisma.forumThread.findUnique({ where: { id: threadId }, select: { id: true } });
    if (!thread) throw new NotFoundException("Discussion introuvable");
    await this.prisma.forumThread.update({ where: { id: threadId }, data: { lockedAt: locked ? new Date() : null } });
    await this.forum.logModeration(userId, locked ? "lock" : "unlock", { threadId });
  }

  /** Épingle un message racine en tête de sa discussion (deux au plus). */
  async setPin(userId: string, messageId: string, pinned: boolean): Promise<void> {
    await this.requireModerator(userId);
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId } });
    if (!message || message.hiddenAt) throw new NotFoundException("Message introuvable");
    if (pinned) {
      if (message.parentId) throw new BadRequestException({ statusCode: 400, code: "PIN_ROOT_ONLY", message: "Seul un message de premier niveau peut être épinglé" });
      if (message.pinnedAt) return;
      const count = await this.prisma.forumMessage.count({ where: { threadId: message.threadId, pinnedAt: { not: null } } });
      if (count >= FORUM_MAX_PINNED) throw new ForbiddenException({ statusCode: 403, code: "PIN_LIMIT", message: `Deux messages épinglés au plus par discussion` });
    }
    await this.prisma.forumMessage.update({ where: { id: messageId }, data: { pinnedAt: pinned ? new Date() : null } });
    await this.forum.logModeration(userId, pinned ? "pin" : "unpin", { messageId, targetUserId: message.userId, threadId: message.threadId, detail: forumSnippet(message.body) });
  }

  /** Les 100 dernières décisions de modération. */
  async listLog(userId: string): Promise<ModerationLogDto[]> {
    await this.requireModerator(userId);
    const rows = await this.prisma.moderationLog.findMany({ orderBy: { createdAt: "desc" }, take: 100, include: { moderator: { select: { pseudo: true } } } });
    const targets = new Map((await this.prisma.appUser.findMany({ where: { id: { in: rows.flatMap((r) => (r.targetUserId ? [r.targetUserId] : [])) } }, select: { id: true, pseudo: true } })).map((u) => [u.id, u.pseudo]));
    return rows.map((r) => ({ id: r.id, moderatorPseudo: r.moderator?.pseudo ?? null, action: r.action, targetPseudo: r.targetUserId ? (targets.get(r.targetUserId) ?? null) : null, detail: r.detail, createdAt: r.createdAt }));
  }
}
