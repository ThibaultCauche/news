import { randomUUID } from "node:crypto";
import { ForbiddenException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ForumThread, PrismaClient } from "@news/db";
import { dmTargetId, FORUM_NON_PUBLIC_KINDS, forumSnippet, GAME_NAMES } from "@news/domain";
import { PRISMA } from "../db/db.module";
import { ForumContactDto, ForumSearchResultDto, ForumThreadDto, InboxItemDto } from "./forum.dto";
import { ForumService } from "./forum.service";

const INBOX_SIZE = 100;
const SEARCH_SIZE = 15;
const forbidden = (code: string, message: string) => new ForbiddenException({ statusCode: 403, code, message });

const threadInclude = { _count: { select: { messages: { where: { hiddenAt: null } } } } } as const;
type ThreadRow = ForumThread & { _count: { messages: number } };

const SHARE_PREVIEWS: Record<string, string> = { event: "a partagé un match", competition: "a partagé une compétition", team: "a partagé une équipe", prediction: "a partagé un pronostic" };

// Boîte « Discussion » (J24) : mes fils (groupes, messages privés, fils suivis ou où j'ai écrit) avec leurs
// non-lus, contacts pour écrire en privé, recherche de discussions publiques. Les règles d'accès (membre
// du fil, groupe en commun) vivent dans `ForumService`.
@Injectable()
export class InboxService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly forum: ForumService,
  ) {}

  // ---- Boîte ----

  async inbox(userId: string): Promise<InboxItemDto[]> {
    const open = (await this.forum.getStatus(userId)).enabled;
    const groups = await this.prisma.friendGroup.findMany({ where: { members: { some: { userId } } }, select: { id: true, name: true } });
    for (const g of groups) await this.ensureGroupThread(g.id, g.name);

    // Fils publics : suivis ou où j'ai écrit (le direct des matchs reste hors boîte, c'est un tchat).
    const publicIds = new Set<string>();
    if (open) {
      for (const f of await this.prisma.forumThreadFollow.findMany({ where: { userId }, select: { threadId: true } })) publicIds.add(f.threadId);
      const written = await this.prisma.forumMessage.findMany({ where: { userId }, distinct: ["threadId"], orderBy: { createdAt: "desc" }, take: INBOX_SIZE, select: { threadId: true } });
      for (const w of written) publicIds.add(w.threadId);
    }
    const dmIds = (await this.prisma.forumThreadMember.findMany({ where: { userId }, select: { threadId: true } })).map((m) => m.threadId);

    const threads = await this.prisma.forumThread.findMany({
      where: {
        OR: [
          { kind: "group", groupId: { in: groups.map((g) => g.id) } },
          { kind: "dm", id: { in: dmIds } },
          ...(publicIds.size ? [{ id: { in: [...publicIds] }, kind: { notIn: ["group", "dm", "live"] } }] : []),
        ],
      },
      orderBy: [{ lastMessageAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }],
      take: INBOX_SIZE,
      include: threadInclude,
    });
    if (threads.length === 0) return [];

    const ids = threads.map((t) => t.id);
    const blocked = (await this.prisma.userBlock.findMany({ where: { blockerId: userId }, select: { blockedId: true } })).map((b) => b.blockedId);
    const unread = await this.prisma.$queryRaw<{ thread_id: string; n: number }[]>`
      SELECT m.thread_id, COUNT(*)::int AS n
      FROM forum_message m
      LEFT JOIN forum_thread_read r ON r.thread_id = m.thread_id AND r.user_id = ${userId}
      LEFT JOIN forum_thread_follow f ON f.thread_id = m.thread_id AND f.user_id = ${userId}
      WHERE m.thread_id = ANY(${ids}::text[]) AND m.user_id <> ${userId} AND m.hidden_at IS NULL
        AND m.user_id <> ALL(${blocked}::text[])
        AND m.created_at > COALESCE(r.last_read_at, f.created_at, 'epoch'::timestamp)
      GROUP BY m.thread_id`;
    const last = await this.prisma.$queryRaw<{ thread_id: string; body: string; kind: string; user_id: string }[]>`
      SELECT DISTINCT ON (m.thread_id) m.thread_id, m.body, m.kind, m.user_id
      FROM forum_message m
      WHERE m.thread_id = ANY(${ids}::text[]) AND m.hidden_at IS NULL AND m.user_id <> ALL(${blocked}::text[])
      ORDER BY m.thread_id, m.created_at DESC`;
    const authors = new Map((await this.prisma.appUser.findMany({ where: { id: { in: last.map((l) => l.user_id) } }, select: { id: true, pseudo: true } })).map((u) => [u.id, u.pseudo]));
    const dtos = await this.forum.toThreadDtos(threads, userId);

    return threads.map((thread, i) => {
      const m = last.find((l) => l.thread_id === thread.id);
      const preview = !m ? null : m.kind === "text" ? forumSnippet(m.body, 80) : m.kind === "poll" ? `Sondage : ${forumSnippet(m.body, 70)}` : (SHARE_PREVIEWS[m.kind] ?? null);
      return {
        thread: dtos[i],
        unreadCount: unread.find((u) => u.thread_id === thread.id)?.n ?? 0,
        preview,
        previewAuthor: m ? (authors.get(m.user_id) ?? null) : null,
        previewFromMe: m ? m.user_id === userId : false,
        previewIsText: m ? m.kind === "text" || m.kind === "poll" : false,
      };
    });
  }

  // ---- Fil d'un groupe ----

  private async ensureGroupThread(groupId: string, name: string): Promise<ThreadRow> {
    const existing = await this.prisma.forumThread.findUnique({ where: { kind_targetId: { kind: "group", targetId: groupId } }, include: threadInclude });
    if (existing) return existing;
    try {
      return await this.prisma.forumThread.create({ data: { id: randomUUID(), kind: "group", targetId: groupId, groupId, title: name }, include: threadInclude });
    } catch (err) {
      if ((err as { code?: string }).code !== "P2002") throw err;
      return this.prisma.forumThread.findUniqueOrThrow({ where: { kind_targetId: { kind: "group", targetId: groupId } }, include: threadInclude });
    }
  }

  async groupThread(userId: string, groupId: string): Promise<ForumThreadDto> {
    const group = await this.prisma.friendGroup.findFirst({ where: { id: groupId, members: { some: { userId } } }, select: { id: true, name: true } });
    if (!group) throw new NotFoundException("Groupe introuvable");
    return (await this.forum.toThreadDtos([await this.ensureGroupThread(group.id, group.name)], userId))[0];
  }

  // ---- Messages privés ----

  /** Joueurs avec qui on peut s'écrire : les membres de ses groupes, hors blocages dans un sens ou dans l'autre. */
  async contacts(userId: string): Promise<ForumContactDto[]> {
    const users = await this.prisma.appUser.findMany({
      where: {
        id: { not: userId },
        pseudo: { not: null },
        groupMemberships: { some: { group: { members: { some: { userId } } } } },
        blocking: { none: { blockedId: userId } },
        blockedBy: { none: { blockerId: userId } },
      },
      select: { id: true, pseudo: true, avatarEntityId: true },
      orderBy: { pseudoKey: "asc" },
    });
    const avatars = new Map(
      (await this.prisma.entity.findMany({ where: { id: { in: users.flatMap((u) => (u.avatarEntityId ? [u.avatarEntityId] : [])) } }, select: { id: true, imageUrl: true } })).map((e) => [e.id, e.imageUrl]),
    );
    return users.map((u) => ({ userId: u.id, pseudo: u.pseudo ?? "Joueur", avatarUrl: u.avatarEntityId ? (avatars.get(u.avatarEntityId) ?? null) : null }));
  }

  /** Ouvre (ou crée) le message privé avec `otherId` : réservé aux joueurs qui ont un groupe en commun. */
  async openDm(userId: string, otherId: string): Promise<ForumThreadDto> {
    const status = await this.forum.getStatus(userId);
    if (!status.canPost) throw forbidden(status.blockedReason ?? "SIGN_IN_REQUIRED", "Tu ne peux pas écrire pour l'instant");
    // Un seul message d'erreur pour « inconnu », « sans groupe commun » : on ne laisse pas deviner qui existe.
    const notAllowed = forbidden("DM_NOT_ALLOWED", "Tu ne peux écrire qu'aux membres de tes groupes");
    if (otherId === userId) throw notAllowed;
    const other = await this.prisma.appUser.findUnique({ where: { id: otherId }, select: { id: true, pseudo: true } });
    if (!other?.pseudo || !(await this.forum.sharesGroup(userId, otherId))) throw notAllowed;
    const block = await this.prisma.userBlock.findFirst({ where: { OR: [{ blockerId: userId, blockedId: otherId }, { blockerId: otherId, blockedId: userId }] }, select: { blockerId: true } });
    if (block) throw forbidden("DM_BLOCKED", "Tu ne peux pas écrire à ce joueur");

    const targetId = dmTargetId(userId, otherId);
    const find = () => this.prisma.forumThread.findUnique({ where: { kind_targetId: { kind: "dm", targetId } }, include: threadInclude });
    let thread: ThreadRow | null = await find();
    if (!thread) {
      try {
        thread = await this.prisma.forumThread.create({
          data: { id: randomUUID(), kind: "dm", targetId, title: "Message privé", members: { create: [{ userId }, { userId: otherId }] } },
          include: threadInclude,
        });
      } catch (err) {
        if ((err as { code?: string }).code !== "P2002") throw err;
        thread = await find();
      }
    }
    return (await this.forum.toThreadDtos([thread!], userId))[0];
  }

  // ---- Recherche de discussions publiques ----

  /** Discussions publiques dont le titre contient la recherche, plus les équipes, compétitions et jeux qui n'ont pas encore de fil. */
  async search(userId: string, q: string): Promise<ForumSearchResultDto[]> {
    if (!(await this.forum.getStatus(userId)).enabled) throw forbidden("FORUM_CLOSED", "Le forum n'est pas encore ouvert");
    const text = q.trim();
    if (text.length < 2) return [];
    const threads = await this.prisma.forumThread.findMany({
      where: { title: { contains: text, mode: "insensitive" }, kind: { notIn: [...FORUM_NON_PUBLIC_KINDS, "live"] } },
      orderBy: [{ lastMessageAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }],
      take: SEARCH_SIZE,
      include: threadInclude,
    });
    const results: ForumSearchResultDto[] = threads.map((t) => ({ kind: t.kind, targetId: t.targetId ?? t.id, title: t.title, game: t.game, threadId: t.id, messageCount: t._count.messages }));
    const known = new Set(threads.map((t) => `${t.kind}:${t.targetId}`));
    const add = (kind: string, targetId: string, title: string, game: string | null) => {
      if (known.has(`${kind}:${targetId}`)) return;
      known.add(`${kind}:${targetId}`);
      results.push({ kind, targetId, title, game, threadId: null, messageCount: 0 });
    };
    const needle = text.toLowerCase();
    for (const [slug, name] of Object.entries(GAME_NAMES)) if (name.toLowerCase().includes(needle)) add("game", slug, name, slug);
    for (const e of await this.prisma.entity.findMany({ where: { kind: "team", name: { contains: text, mode: "insensitive" } }, select: { id: true, name: true }, take: 8 })) add("entity", e.id, e.name, null);
    for (const c of await this.prisma.competition.findMany({ where: { name: { contains: text, mode: "insensitive" } }, select: { id: true, name: true, game: true }, take: 8 })) add("competition", c.id, c.name, c.game);
    return results.slice(0, SEARCH_SIZE + 10);
  }
}
