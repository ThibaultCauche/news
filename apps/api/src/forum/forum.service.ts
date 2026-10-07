import { randomUUID } from "node:crypto";
import { BadRequestException, ForbiddenException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { AppUser, ForumMessage, ForumThread, PrismaClient } from "@news/db";
import {
  accountOldEnough,
  campChangeWaitDays,
  canEditMessage,
  canSeeFriendsPicks,
  createLogger,
  extractMentions,
  FORUM_FREE_THREADS_PER_DAY,
  FORUM_TYPING_TTL_SECONDS,
  FORUM_MAX_REPLY_DEPTH,
  FORUM_MESSAGES_PER_MINUTE,
  FORUM_REPLIES_CHANNEL,
  FORUM_REPORT_HIDE_THRESHOLD,
  FORUM_TERMS_VERSION,
  ForumReplyMessage,
  GAME_NAMES,
  FORUM_NON_PUBLIC_KINDS,
  forumSnippet,
  isChatThreadKind,
  isKnownGame,
  isPrivateThreadKind,
  messageProblem,
  pollClosed,
  pollProblem,
  pseudoKeyOf,
  titleProblem,
} from "@news/domain";
import { CacheService } from "../cache/cache.service";
import { PickemService } from "../community/pickem.service";
import { PRISMA } from "../db/db.module";
import {
  BlockedUserDto,
  CreateThreadDto,
  ForumAuthorDto,
  ForumCampDto,
  ForumMessageDto,
  ForumMessagesPageDto,
  ForumPollDto,
  ForumSharedDto,
  ForumStatusDto,
  ForumThreadDto,
  ListThreadsQueryDto,
  MessagesQueryDto,
  PostMessageDto,
  PutCampDto,
  ReportMessageDto,
  ResolveThreadQueryDto,
} from "./forum.dto";

const logger = createLogger("api:forum");

const DEFAULT_PAGE_SIZE = 30;
const THREAD_LIST_SIZE = 50;

// Erreurs à code stable : l'appli affiche son propre texte selon `code`.
const forbidden = (code: string, message: string) => new ForbiddenException({ statusCode: 403, code, message });
const badRequest = (code: string, message: string) => new BadRequestException({ statusCode: 400, code, message });

const PROBLEM_MESSAGES = {
  empty: "Le message est vide",
  length: "Le texte est trop long ou trop court",
  link: "Les liens ne sont pas autorisés",
  forbidden: "Ce message contient un mot interdit",
} as const;

type MessageRow = ForumMessage & {
  user: Pick<AppUser, "id" | "pseudo" | "avatarEntityId">;
  reactions: { userId: string; emoji: string }[];
};

// Forum (J13) : fils de discussion texte seul, réponses, réactions, signalements, blocages, camps.
// Lecture ouverte (aux invités aussi) quand le forum est ouvert ; écrire exige un compte avec
// pseudo, conditions acceptées et une ancienneté minimale. Bêta fermée : `FORUM_OPEN` ou
// `app_user.forum_beta`.
@Injectable()
export class ForumService {
  constructor(
    @Inject(PRISMA) private readonly prisma: PrismaClient,
    private readonly cache: CacheService,
    private readonly config: ConfigService,
    private readonly pickem: PickemService,
  ) {}

  // ---- Accès ----

  private async findUser(userId: string | null): Promise<AppUser | null> {
    return userId ? this.prisma.appUser.findUnique({ where: { id: userId } }) : null;
  }

  private isOpen(user: AppUser | null): boolean {
    return this.config.get<string>("FORUM_OPEN") === "true" || (user?.forumBeta ?? false);
  }

  private async requireOpen(userId: string | null): Promise<AppUser | null> {
    const user = await this.findUser(userId);
    if (!this.isOpen(user)) throw forbidden("FORUM_CLOSED", "Le forum n'est pas encore ouvert");
    return user;
  }

  private blockedReason(user: AppUser | null): string | null {
    if (!user) return "SIGN_IN_REQUIRED";
    if (!user.pseudo) return "PROFILE_REQUIRED";
    if (user.forumBannedAt) return "BANNED";
    if (user.termsVersion !== FORUM_TERMS_VERSION) return "TERMS_REQUIRED";
    if (!accountOldEnough(user.createdAt, new Date())) return "ACCOUNT_TOO_NEW";
    return null;
  }

  // `privateThread` : un fil de groupe ou un message privé s'écrit même si le forum public reste en bêta
  // fermée (J24) ; les conditions d'écriture (pseudo, conditions, ancienneté, exclusion) restent les mêmes.
  private async requirePoster(userId: string, privateThread = false): Promise<AppUser> {
    const user = privateThread ? await this.findUser(userId) : await this.requireOpen(userId);
    const reason = this.blockedReason(user);
    if (reason || !user) throw forbidden(reason ?? "SIGN_IN_REQUIRED", "Tu ne peux pas écrire pour l'instant");
    return user;
  }

  /** Membre d'un fil privé : du groupe (fil de groupe) ou l'un des deux participants (message privé). */
  async isThreadMember(userId: string | null, thread: Pick<ForumThread, "id" | "kind" | "groupId">): Promise<boolean> {
    if (!userId) return false;
    if (thread.kind === "group") {
      return thread.groupId !== null && (await this.prisma.friendGroupMember.findUnique({ where: { groupId_userId: { groupId: thread.groupId, userId } }, select: { userId: true } })) !== null;
    }
    if (thread.kind === "dm") return (await this.prisma.forumThreadMember.findUnique({ where: { threadId_userId: { threadId: thread.id, userId } }, select: { userId: true } })) !== null;
    return false;
  }

  /** Lire ou agir dans un fil : un fil privé n'existe que pour ses membres (404 pour les autres), les autres suivent la règle du forum. */
  async requireThreadAccess(userId: string | null, thread: Pick<ForumThread, "id" | "kind" | "groupId">): Promise<void> {
    if (isPrivateThreadKind(thread.kind)) {
      if (!(await this.isThreadMember(userId, thread))) throw new NotFoundException("Discussion introuvable");
      return;
    }
    await this.requireOpen(userId);
  }

  /** Deux joueurs ont au moins un groupe en commun : la seule condition pour s'écrire en privé. */
  async sharesGroup(a: string, b: string): Promise<boolean> {
    return (await this.prisma.friendGroupMember.findFirst({ where: { userId: b, group: { members: { some: { userId: a } } } }, select: { userId: true } })) !== null;
  }

  // Message privé : écrire exige toujours un groupe en commun (vérifié à chaque message, pas seulement
  // à l'ouverture) et aucun blocage dans un sens ou dans l'autre.
  private async requireDmAllowed(userId: string, threadId: string): Promise<void> {
    const members = await this.prisma.forumThreadMember.findMany({ where: { threadId }, select: { userId: true } });
    const other = members.find((m) => m.userId !== userId)?.userId;
    if (!other || !(await this.sharesGroup(userId, other))) throw forbidden("DM_NOT_ALLOWED", "Vous n'avez plus de groupe en commun");
    const block = await this.prisma.userBlock.findFirst({ where: { OR: [{ blockerId: userId, blockedId: other }, { blockerId: other, blockedId: userId }] }, select: { blockerId: true } });
    if (block) throw forbidden("DM_BLOCKED", "Tu ne peux pas écrire à ce joueur");
  }

  async getStatus(userId: string | null): Promise<ForumStatusDto> {
    const user = await this.findUser(userId);
    const reason = this.blockedReason(user);
    return {
      enabled: this.isOpen(user),
      signedIn: user !== null,
      canPost: reason === null,
      blockedReason: reason,
      termsVersion: FORUM_TERMS_VERSION,
      termsAccepted: user?.termsVersion === FORUM_TERMS_VERSION,
      isModerator: user?.isModerator ?? false,
      userId: user?.id ?? null,
    };
  }

  async acceptTerms(userId: string, version: number): Promise<ForumStatusDto> {
    if (version !== FORUM_TERMS_VERSION) throw badRequest("TERMS_VERSION", "Ces conditions ne sont plus à jour");
    await this.prisma.appUser.update({ where: { id: userId }, data: { termsVersion: version, termsAcceptedAt: new Date() } });
    return this.getStatus(userId);
  }

  // ---- Fils ----

  // Ajoute à chaque fil ce qui dépend du visiteur (suivi) et du match (le fil du direct est en lecture
  // seule hors du direct).
  // Titre d'un fil privé selon le visiteur : nom du groupe, ou pseudo de l'autre participant.
  private async privateTitles(threads: ForumThread[], viewerId: string | null): Promise<Map<string, string>> {
    const titles = new Map<string, string>();
    const groupIds = threads.flatMap((t) => (t.kind === "group" && t.groupId ? [t.groupId] : []));
    if (groupIds.length) for (const g of await this.prisma.friendGroup.findMany({ where: { id: { in: groupIds } }, select: { id: true, name: true } })) titles.set(g.id, g.name);
    const dmIds = threads.filter((t) => t.kind === "dm").map((t) => t.id);
    if (dmIds.length) {
      const members = await this.prisma.forumThreadMember.findMany({ where: { threadId: { in: dmIds }, userId: { not: viewerId ?? "" } }, select: { threadId: true, user: { select: { pseudo: true } } } });
      for (const m of members) titles.set(m.threadId, m.user.pseudo ?? "Joueur");
    }
    return titles;
  }

  async toThreadDtos(threads: (ForumThread & { _count: { messages: number } })[], viewerId: string | null): Promise<ForumThreadDto[]> {
    const privateTitles = await this.privateTitles(threads, viewerId);
    const privateIds = threads.filter((t) => isPrivateThreadKind(t.kind)).map((t) => t.id);
    const muted =
      viewerId && privateIds.length
        ? new Set((await this.prisma.forumThreadRead.findMany({ where: { userId: viewerId, muted: true, threadId: { in: privateIds } }, select: { threadId: true } })).map((r) => r.threadId))
        : new Set<string>();
    const followed =
      viewerId && threads.length
        ? new Set((await this.prisma.forumThreadFollow.findMany({ where: { userId: viewerId, threadId: { in: threads.map((t) => t.id) } }, select: { threadId: true } })).map((f) => f.threadId))
        : new Set<string>();
    const liveIds = threads.flatMap((t) => (t.kind === "live" && t.targetId ? [t.targetId] : []));
    const statuses = liveIds.length ? new Map((await this.prisma.event.findMany({ where: { id: { in: liveIds } }, select: { id: true, status: true } })).map((e) => [e.id, e.status])) : new Map<string, string>();
    return threads.map((thread) => ({
      id: thread.id,
      kind: thread.kind,
      targetId: thread.targetId,
      game: thread.game,
      title: (thread.kind === "group" ? privateTitles.get(thread.groupId ?? "") : thread.kind === "dm" ? privateTitles.get(thread.id) : undefined) ?? thread.title,
      messageCount: thread._count.messages,
      lastMessageAt: thread.lastMessageAt,
      locked: thread.lockedAt !== null,
      following: followed.has(thread.id),
      muted: muted.has(thread.id),
      readOnly: thread.kind === "live" && statuses.get(thread.targetId ?? "") !== "live",
      createdAt: thread.createdAt,
    }));
  }

  private async toThreadDto(thread: ForumThread & { _count: { messages: number } }, viewerId: string | null): Promise<ForumThreadDto> {
    return (await this.toThreadDtos([thread], viewerId))[0];
  }

  private readonly threadInclude = { _count: { select: { messages: { where: { hiddenAt: null } } } } } as const;

  /** Fil d'un match, d'une équipe, d'une compétition ou d'un jeu, créé à la première demande. */
  async resolveThread(userId: string | null, q: ResolveThreadQueryDto): Promise<ForumThreadDto> {
    await this.requireOpen(userId);
    if (q.kind === "free" || isPrivateThreadKind(q.kind)) throw badRequest("KIND_INVALID", "Ce fil ne se résout pas par son identifiant");
    if (q.kind === "feature" && q.targetId !== "ideas") throw badRequest("KIND_INVALID", "Fil inconnu");
    const existing = await this.prisma.forumThread.findUnique({ where: { kind_targetId: { kind: q.kind, targetId: q.targetId } }, include: this.threadInclude });
    if (existing) return this.toThreadDto(existing, userId);

    const { title, game } = await this.describeTarget(q.kind, q.targetId);
    try {
      const created = await this.prisma.forumThread.create({ data: { id: randomUUID(), kind: q.kind, targetId: q.targetId, title, game }, include: this.threadInclude });
      return this.toThreadDto(created, userId);
    } catch (err) {
      // Deux ouvertures simultanées du même fil : la contrainte unique tranche.
      if ((err as { code?: string }).code !== "P2002") throw err;
      const raced = await this.prisma.forumThread.findUniqueOrThrow({ where: { kind_targetId: { kind: q.kind, targetId: q.targetId } }, include: this.threadInclude });
      return this.toThreadDto(raced, userId);
    }
  }

  private async describeTarget(kind: string, targetId: string): Promise<{ title: string; game: string | null }> {
    if (kind === "feature") return { title: "Boîte à idées", game: null };
    if (kind === "game") {
      if (!isKnownGame(targetId)) throw new NotFoundException("Jeu introuvable");
      return { title: GAME_NAMES[targetId], game: targetId };
    }
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(targetId);
    if (!isUuid) throw new NotFoundException("Introuvable");
    if (kind === "event" || kind === "live") {
      const event = await this.prisma.event.findUnique({ where: { id: targetId }, select: { name: true, competition: { select: { game: true } } } });
      if (!event) throw new NotFoundException("Match introuvable");
      return { title: kind === "live" ? `Direct · ${event.name}` : event.name, game: event.competition.game };
    }
    if (kind === "competition") {
      const competition = await this.prisma.competition.findUnique({ where: { id: targetId }, select: { name: true, game: true } });
      if (!competition) throw new NotFoundException("Compétition introuvable");
      return { title: competition.name, game: competition.game };
    }
    const entity = await this.prisma.entity.findUnique({ where: { id: targetId }, select: { name: true } });
    if (!entity) throw new NotFoundException("Équipe introuvable");
    // Pas de rattachement direct équipe → jeu dans le modèle : on le déduit de ses matchs.
    const match = await this.prisma.eventParticipant.findFirst({ where: { entityId: targetId, event: { competition: { game: { not: null } } } }, select: { event: { select: { competition: { select: { game: true } } } } } });
    return { title: entity.name, game: match?.event.competition.game ?? null };
  }

  async listThreads(userId: string | null, q: ListThreadsQueryDto): Promise<ForumThreadDto[]> {
    await this.requireOpen(userId);
    const sort = q.sort ?? "recent";
    if (q.kind && FORUM_NON_PUBLIC_KINDS.includes(q.kind)) throw badRequest("KIND_INVALID", "Ce type de fil ne se liste pas");
    const candidates = await this.prisma.forumThread.findMany({
      where: { game: q.game, kind: q.kind ?? { notIn: [...FORUM_NON_PUBLIC_KINDS] }, OR: [{ kind: "free" }, { lastMessageAt: { not: null } }] },
      orderBy: [{ lastMessageAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }],
      take: sort === "recent" ? THREAD_LIST_SIZE : 200,
      include: this.threadInclude,
    });
    if (sort === "recent" || candidates.length === 0) return this.toThreadDtos(candidates, userId);

    // ponytail: tri en mémoire sur les 200 fils les plus récents ; passer en SQL si le forum grossit.
    const ids = candidates.map((t) => t.id);
    const score = new Map<string, number>();
    if (sort === "active") {
      const rows = await this.prisma.forumMessage.groupBy({ by: ["threadId"], where: { threadId: { in: ids }, hiddenAt: null, createdAt: { gte: new Date(Date.now() - 86_400_000) } }, _count: { _all: true } });
      for (const r of rows) score.set(r.threadId, r._count._all);
    } else {
      const rows = await this.prisma.$queryRaw<{ thread_id: string; n: bigint }[]>`SELECT m.thread_id, COUNT(*) AS n FROM forum_reaction r JOIN forum_message m ON m.id = r.message_id WHERE m.thread_id = ANY(${ids}::text[]) GROUP BY m.thread_id`;
      for (const r of rows) score.set(r.thread_id, Number(r.n));
      for (const t of candidates) score.set(t.id, (score.get(t.id) ?? 0) + t._count.messages);
    }
    const sorted = [...candidates].sort((a, b) => (score.get(b.id) ?? 0) - (score.get(a.id) ?? 0)).slice(0, THREAD_LIST_SIZE);
    return this.toThreadDtos(sorted, userId);
  }

  async createThread(userId: string, dto: CreateThreadDto): Promise<ForumThreadDto> {
    await this.requirePoster(userId);
    const title = dto.title.trim();
    const problem = titleProblem(title);
    if (problem) throw badRequest(`TITLE_${problem.toUpperCase()}`, PROBLEM_MESSAGES[problem]);
    if (dto.game !== undefined && !isKnownGame(dto.game)) throw badRequest("GAME_UNKNOWN", "Jeu inconnu");
    const recent = await this.prisma.forumThread.count({ where: { createdById: userId, createdAt: { gte: new Date(Date.now() - 86_400_000) } } });
    if (recent >= FORUM_FREE_THREADS_PER_DAY) throw forbidden("THREAD_LIMIT", "Tu as créé beaucoup de discussions aujourd'hui, réessaie demain");
    const created = await this.prisma.forumThread.create({ data: { id: randomUUID(), kind: "free", title, game: dto.game ?? null, createdById: userId }, include: this.threadInclude });
    // Le créateur suit sa discussion : il est prévenu des réponses des autres.
    await this.prisma.forumThreadFollow.create({ data: { threadId: created.id, userId } });
    return this.toThreadDto(created, userId);
  }

  async followThread(userId: string, threadId: string): Promise<void> {
    const thread = await this.prisma.forumThread.findUnique({ where: { id: threadId } });
    if (!thread) throw new NotFoundException("Discussion introuvable");
    if (isPrivateThreadKind(thread.kind)) throw badRequest("PRIVATE_THREAD", "Les fils privés préviennent déjà leurs membres");
    await this.requireOpen(userId);
    await this.prisma.forumThreadFollow.upsert({ where: { threadId_userId: { threadId, userId } }, create: { threadId, userId }, update: {} });
    // Les non-lus de la boîte « Discussion » comptent à partir du suivi.
    await this.prisma.forumThreadRead.upsert({ where: { threadId_userId: { threadId, userId } }, create: { threadId, userId }, update: {} });
  }

  async unfollowThread(userId: string, threadId: string): Promise<void> {
    await this.prisma.forumThreadFollow.deleteMany({ where: { threadId, userId } });
  }

  // ---- Messages ----

  async listMessages(userId: string | null, threadId: string, q: MessagesQueryDto): Promise<ForumMessagesPageDto> {
    const thread = await this.prisma.forumThread.findUnique({ where: { id: threadId }, include: this.threadInclude });
    if (!thread) throw new NotFoundException("Discussion introuvable");
    await this.requireThreadAccess(userId, thread);
    // Date de dernière lecture AVANT de marquer lu : sert à repérer les nouveaux messages d'un fil privé.
    const priorRead = userId && !q.before && isPrivateThreadKind(thread.kind) ? await this.prisma.forumThreadRead.findUnique({ where: { threadId_userId: { threadId: thread.id, userId } } }) : null;
    if (userId && !q.before) await this.markRead(userId, thread);
    const before = q.before ? new Date(q.before) : null;
    if (before && Number.isNaN(before.getTime())) throw badRequest("CURSOR_INVALID", "Curseur invalide");
    const limit = q.limit ?? DEFAULT_PAGE_SIZE;
    const include = { user: { select: { id: true, pseudo: true, avatarEntityId: true } }, reactions: { select: { userId: true, emoji: true } } } as const;
    if (isChatThreadKind(thread.kind)) return this.listLive(userId, thread, before, limit, include, priorRead ? priorRead.lastReadAt : new Date(0), !before && isPrivateThreadKind(thread.kind));
    if (thread.kind === "feature") return this.listIdeas(userId, thread, include);

    // Messages épinglés : en tête de la première page seulement.
    const pinned = before ? [] : await this.prisma.forumMessage.findMany({ where: { threadId, parentId: null, pinnedAt: { not: null } }, orderBy: { pinnedAt: "asc" }, include });
    const rootsPlusOne = await this.prisma.forumMessage.findMany({
      where: { threadId, parentId: null, pinnedAt: null, ...(before ? { createdAt: { lt: before } } : {}) },
      orderBy: { createdAt: "desc" },
      take: limit + 1,
      include,
    });
    const roots = rootsPlusOne.slice(0, limit);
    // Réponses imbriquées : un niveau par requête, jusqu'à la profondeur maximale.
    const all = [...pinned, ...roots];
    const childrenOf = new Map<string, typeof roots>();
    let level = all;
    for (let depth = 1; depth < FORUM_MAX_REPLY_DEPTH && level.length > 0; depth++) {
      const kids = await this.prisma.forumMessage.findMany({ where: { parentId: { in: level.map((m) => m.id) } }, orderBy: { createdAt: "asc" }, include });
      for (const kid of kids) childrenOf.set(kid.parentId!, [...(childrenOf.get(kid.parentId!) ?? []), kid]);
      all.push(...kids);
      level = kids;
    }

    const ctx = await this.buildContext(userId, thread, all);
    // Un message masqué reste en place (texte retiré) seulement s'il a encore des réponses visibles.
    const build = (row: (typeof roots)[number]): ForumMessageDto | null => {
      const replies = (childrenOf.get(row.id) ?? []).map(build).filter((m): m is ForumMessageDto => m !== null);
      return this.isMasked(row, ctx) && replies.length === 0 ? null : this.toMessageDto(row, ctx, replies);
    };
    const messages = [...pinned, ...roots].map(build).filter((m): m is ForumMessageDto => m !== null);
    return { thread: await this.toThreadDto(thread, userId), messages, nextBefore: rootsPlusOne.length > limit ? roots[roots.length - 1].createdAt.toISOString() : null };
  }

  // Fil du direct : un tchat à plat, du plus récent au plus ancien, sans imbrication ; répondre ne fait
  // que citer le message d'origine (`replyTo`). Les messages masqués disparaissent.
  private async listLive(
    userId: string | null,
    thread: ForumThread & { _count: { messages: number } },
    before: Date | null,
    limit: number,
    include: { user: { select: { id: true; pseudo: true; avatarEntityId: true } }; reactions: { select: { userId: true; emoji: true } } },
    lastRead: Date = new Date(0),
    firstPageOfPrivate = false,
  ): Promise<ForumMessagesPageDto> {
    const rowsPlusOne = await this.prisma.forumMessage.findMany({
      where: { threadId: thread.id, hiddenAt: null, ...(before ? { createdAt: { lt: before } } : {}) },
      orderBy: { createdAt: "desc" },
      take: limit + 1,
      include,
    });
    const rows = rowsPlusOne.slice(0, limit);
    const parentIds = [...new Set(rows.flatMap((r) => (r.parentId ? [r.parentId] : [])))];
    const parents = parentIds.length ? await this.prisma.forumMessage.findMany({ where: { id: { in: parentIds } }, select: { id: true, body: true, hiddenAt: true, user: { select: { pseudo: true } } } }) : [];
    const ctx = await this.buildContext(userId, thread, rows);
    const messages = rows
      .filter((row) => !this.isMasked(row, ctx))
      .map((row) => {
        const parent = parents.find((p) => p.id === row.parentId);
        const replyTo = !row.parentId
          ? null
          : parent && !parent.hiddenAt
            ? { messageId: parent.id, pseudo: parent.user.pseudo ?? "Joueur", snippet: forumSnippet(parent.body, 60) }
            : { messageId: row.parentId, pseudo: null, snippet: "Message masqué" };
        return { ...this.toMessageDto(row, ctx, []), replyTo };
      });
    const page = { thread: await this.toThreadDto(thread, userId), messages, nextBefore: rowsPlusOne.length > limit ? rows[rows.length - 1].createdAt.toISOString() : null };
    if (!userId || !isPrivateThreadKind(thread.kind)) return page;

    // Fil privé (tchat) : nouveaux messages, « vu » et « écrit… » du message privé.
    const unread = firstPageOfPrivate ? rows.filter((r) => r.userId !== userId && r.createdAt > lastRead && !this.isMasked(r, ctx)) : [];
    const unreadCount = firstPageOfPrivate ? await this.prisma.forumMessage.count({ where: { threadId: thread.id, userId: { not: userId }, hiddenAt: null, createdAt: { gt: lastRead } } }) : 0;
    let seenAt: Date | null = null;
    let typing: string | null = null;
    if (thread.kind === "dm") {
      const other = await this.prisma.forumThreadMember.findFirst({ where: { threadId: thread.id, userId: { not: userId } }, select: { userId: true } });
      if (other) {
        seenAt = (await this.prisma.forumThreadRead.findUnique({ where: { threadId_userId: { threadId: thread.id, userId: other.userId } }, select: { lastReadAt: true } }))?.lastReadAt ?? null;
        typing = await this.cache.get<string>(`forum:typing:${thread.id}:${other.userId}`);
      }
    }
    return { ...page, unreadCount, firstUnreadId: unread.length ? unread[unread.length - 1].id : null, seenAt, typing };
  }

  /** « X écrit… » d'un message privé : valable quelques secondes, renouvelé à chaque frappe de l'appli. */
  async putTyping(userId: string, threadId: string): Promise<void> {
    const thread = await this.prisma.forumThread.findUnique({ where: { id: threadId } });
    if (!thread || thread.kind !== "dm" || !(await this.isThreadMember(userId, thread))) return;
    const user = await this.findUser(userId);
    if (user?.pseudo) await this.cache.set(`forum:typing:${threadId}:${userId}`, user.pseudo, FORUM_TYPING_TTL_SECONDS);
  }

  /** Sourdine d'un fil privé : plus de notification de nouveaux messages (mentions et réponses comprises restent). */
  async setMuted(userId: string, threadId: string, muted: boolean): Promise<void> {
    const thread = await this.prisma.forumThread.findUnique({ where: { id: threadId } });
    if (!thread || !isPrivateThreadKind(thread.kind) || !(await this.isThreadMember(userId, thread))) throw new NotFoundException("Discussion introuvable");
    await this.prisma.forumThreadRead.upsert({
      where: { threadId_userId: { threadId, userId } },
      create: { threadId, userId, lastReadAt: new Date(0), muted },
      update: { muted },
    });
  }

  // Lire un fil le marque lu (non-lus de la boîte « Discussion ») : toujours pour un fil privé, sinon
  // seulement si la personne l'a déjà dans sa boîte (suivi ou message écrit).
  private async markRead(userId: string, thread: ForumThread): Promise<void> {
    const now = new Date();
    if (isPrivateThreadKind(thread.kind)) {
      await this.prisma.forumThreadRead.upsert({ where: { threadId_userId: { threadId: thread.id, userId } }, create: { threadId: thread.id, userId, lastReadAt: now }, update: { lastReadAt: now } });
    } else {
      await this.prisma.forumThreadRead.updateMany({ where: { threadId: thread.id, userId }, data: { lastReadAt: now } });
    }
  }

  // Tableau des idées : à plat (pas de réponses), les idées encore ouvertes d'abord, les plus votées en tête
  // (le vote est la réaction 👍). Pas de pagination : quelques centaines d'idées au plus.
  private async listIdeas(
    userId: string | null,
    thread: ForumThread & { _count: { messages: number } },
    include: { user: { select: { id: true; pseudo: true; avatarEntityId: true } }; reactions: { select: { userId: true; emoji: true } } },
  ): Promise<ForumMessagesPageDto> {
    const rows = await this.prisma.forumMessage.findMany({ where: { threadId: thread.id, parentId: null, hiddenAt: null }, orderBy: { createdAt: "desc" }, take: 200, include });
    const ctx = await this.buildContext(userId, thread, rows);
    const votes = (r: MessageRow) => r.reactions.filter((x) => x.emoji === "up").length;
    const closed = (r: MessageRow) => (r.ideaStatus === "done" || r.ideaStatus === "declined" ? 1 : 0);
    const sorted = rows.filter((r) => !this.isMasked(r, ctx)).sort((a, b) => closed(a) - closed(b) || votes(b) - votes(a));
    return { thread: await this.toThreadDto(thread, userId), messages: sorted.map((r) => this.toMessageDto(r, ctx, [])), nextBefore: null };
  }

  // Contenu d'un message : texte, carte partagée (identifiant seulement) ou sondage (modérateurs).
  private async prepareContent(user: AppUser, thread: ForumThread, dto: PostMessageDto): Promise<{ body: string; kind: string; refId: string | null; payload: { options: string[]; endsAt?: string } | undefined }> {
    const body = dto.body.trim();
    const checkText = () => {
      const problem = messageProblem(body);
      if (problem) throw badRequest(`MESSAGE_${problem.toUpperCase()}`, PROBLEM_MESSAGES[problem]);
    };
    if (dto.share && dto.pollOptions) throw badRequest("MESSAGE_KIND_CONFLICT", "Un message est un partage ou un sondage, pas les deux");
    if (thread.kind === "feature" && (dto.share || dto.pollOptions || dto.parentId)) throw badRequest("IDEA_TEXT_ONLY", "Une idée est un texte simple");
    if (dto.pollOptions) {
      if (!user.isModerator) throw forbidden("NOT_MODERATOR", "Seule l'équipe de l'appli lance des sondages");
      checkText();
      const options = dto.pollOptions.map((o) => o.trim());
      const issue = pollProblem(options);
      if (issue) throw badRequest(`POLL_${issue.toUpperCase()}`, "Les options du sondage ne sont pas valides");
      const endsAt = dto.pollHours ? new Date(Date.now() + dto.pollHours * 3_600_000).toISOString() : undefined;
      return { body, kind: "poll", refId: null, payload: { options, ...(endsAt ? { endsAt } : {}) } };
    }
    if (dto.share) {
      if (thread.kind === "live") throw badRequest("SHARE_NOT_ALLOWED", "On ne partage pas dans le direct");
      if (body) checkText();
      const { kind, refId } = dto.share;
      if (kind === "competition" || kind === "pickem") {
        if (!(await this.prisma.competition.findUnique({ where: { id: refId }, select: { id: true } }))) throw new NotFoundException("Compétition introuvable");
      } else if (kind === "team") {
        if (!(await this.prisma.entity.findFirst({ where: { id: refId, kind: "team" }, select: { id: true } }))) throw new NotFoundException("Équipe introuvable");
      } else {
        if (!(await this.prisma.event.findUnique({ where: { id: refId }, select: { id: true } }))) throw new NotFoundException("Match introuvable");
      }
      if (kind === "pickem") {
        if (!isPrivateThreadKind(thread.kind)) throw badRequest("SHARE_PRIVATE_ONLY", "Un tableau se partage dans un groupe ou en message privé");
        if (!(await this.prisma.bracketPick.findFirst({ where: { userId: user.id, competitionId: refId }, select: { id: true } }))) throw badRequest("NO_PICKEM", "Tu n'as pas rempli de tableau pour cette compétition");
      }
      if (kind === "prediction") {
        if (!isPrivateThreadKind(thread.kind)) throw badRequest("SHARE_PRIVATE_ONLY", "Un pronostic se partage dans un groupe ou en message privé");
        if (!(await this.prisma.prediction.findUnique({ where: { userId_eventId: { userId: user.id, eventId: refId } }, select: { id: true } }))) throw badRequest("NO_PREDICTION", "Tu n'as pas de pronostic sur ce match");
      }
      return { body, kind, refId, payload: undefined };
    }
    checkText();
    return { body, kind: "text", refId: null, payload: undefined };
  }

  async postMessage(userId: string, threadId: string, dto: PostMessageDto): Promise<ForumMessageDto> {
    const thread = await this.prisma.forumThread.findUnique({ where: { id: threadId } });
    if (!thread) throw new NotFoundException("Discussion introuvable");
    const isPrivate = isPrivateThreadKind(thread.kind);
    if (isPrivate) await this.requireThreadAccess(userId, thread);
    const user = await this.requirePoster(userId, isPrivate);
    if (thread.kind === "dm") await this.requireDmAllowed(userId, thread.id);
    if (thread.lockedAt) throw forbidden("THREAD_LOCKED", "Cette discussion est verrouillée");
    if (thread.kind === "live") {
      const event = await this.prisma.event.findUnique({ where: { id: thread.targetId ?? "" }, select: { status: true } });
      if (event?.status !== "live") throw forbidden("LIVE_CLOSED", "Le direct n'est ouvert que pendant le match");
    }
    // Pas de mode lent, mais un plafond souple par compte.
    const lastMinute = await this.prisma.forumMessage.count({ where: { userId: user.id, createdAt: { gte: new Date(Date.now() - 60_000) } } });
    if (lastMinute >= FORUM_MESSAGES_PER_MINUTE) throw forbidden("RATE_LIMIT", "Doucement : tu écris trop vite, réessaie dans une minute");
    const { body, kind, refId, payload } = await this.prepareContent(user, thread, dto);

    let parentId: string | null = null;
    let replyToUserId: string | null = null;
    if (dto.parentId) {
      const parent = await this.prisma.forumMessage.findUnique({ where: { id: dto.parentId } });
      if (!parent || parent.threadId !== threadId || parent.hiddenAt) throw new NotFoundException("Message introuvable");
      // Profondeur du message auquel on répond (racine = 1) : à la profondeur maximale, la réponse
      // se place au même niveau que lui. Dans le fil du direct, tout est à plat : on cite simplement le message.
      let depth = 1;
      for (let cursor = isChatThreadKind(thread.kind) ? null : parent.parentId; cursor && depth < FORUM_MAX_REPLY_DEPTH; depth++) {
        cursor = (await this.prisma.forumMessage.findUnique({ where: { id: cursor }, select: { parentId: true } }))?.parentId ?? null;
      }
      parentId = depth >= FORUM_MAX_REPLY_DEPTH ? parent.parentId : parent.id;
      replyToUserId = parent.userId;
    }

    const now = new Date();
    const [created] = await this.prisma.$transaction([
      this.prisma.forumMessage.create({
        data: { id: randomUUID(), threadId, userId: user.id, parentId, body, kind, refId, payload, isSpoiler: dto.isSpoiler ?? false, createdAt: now },
        include: { user: { select: { id: true, pseudo: true, avatarEntityId: true } }, reactions: { select: { userId: true, emoji: true } } },
      }),
      this.prisma.forumThread.update({ where: { id: threadId }, data: { lastMessageAt: now } }),
      // Écrire met le fil dans la boîte « Discussion » de l'auteur et le marque lu.
      this.prisma.forumThreadRead.upsert({ where: { threadId_userId: { threadId, userId: user.id } }, create: { threadId, userId: user.id, lastReadAt: now }, update: { lastReadAt: now } }),
    ]);
    // Notifications (le worker applique réglages, heures calmes et blocages) : réponse, mentions, puis
    // abonnés de la discussion (sauf ceux déjà prévenus).
    const notified = new Set<string>([user.id]);
    const signals: ForumReplyMessage[] = [];
    if (replyToUserId && replyToUserId !== user.id) {
      signals.push({ messageId: created.id, kind: "reply", toUserId: replyToUserId });
      notified.add(replyToUserId);
    }
    for (const mentioned of await this.resolveMentions(body, user.id, notified)) {
      // Fil privé : un pseudo cité hors du fil ne reçoit rien (ni aperçu du message).
      if (isPrivate && !(await this.isThreadMember(mentioned, thread))) continue;
      signals.push({ messageId: created.id, kind: "mention", toUserId: mentioned });
      notified.add(mentioned);
    }
    signals.push({ messageId: created.id, kind: "thread", excludeUserIds: [...notified] });
    for (const signal of signals) this.cache.publish(FORUM_REPLIES_CHANNEL, signal).catch((err) => logger.warn(err, "signal du forum non publié"));
    return this.toMessageDto(created, await this.buildContext(userId, thread, [created]), []);
  }

  /** Utilisateurs cités par `@pseudo`, hors `skip` et hors ceux qui ont bloqué l'auteur. */
  private async resolveMentions(body: string, authorId: string, skip: Set<string>): Promise<string[]> {
    const keys = extractMentions(body).map(pseudoKeyOf);
    if (keys.length === 0) return [];
    const users = await this.prisma.appUser.findMany({ where: { pseudoKey: { in: keys }, forumBannedAt: null }, select: { id: true } });
    const ids = users.map((u) => u.id).filter((id) => !skip.has(id));
    if (ids.length === 0) return [];
    const blockers = new Set((await this.prisma.userBlock.findMany({ where: { blockerId: { in: ids }, blockedId: authorId }, select: { blockerId: true } })).map((b) => b.blockerId));
    return ids.filter((id) => !blockers.has(id));
  }

  /** L'auteur corrige son message dans les 5 minutes (mention « modifié », pas de nouvelle notification). */
  async editMessage(userId: string, messageId: string, rawBody: string): Promise<ForumMessageDto> {
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId }, include: { thread: true } });
    if (!message || message.hiddenAt) throw new NotFoundException("Message introuvable");
    const isPrivate = isPrivateThreadKind(message.thread.kind);
    if (isPrivate) await this.requireThreadAccess(userId, message.thread);
    const user = await this.requirePoster(userId, isPrivate);
    if (message.kind !== "text") throw badRequest("NOT_EDITABLE", "Seul un message texte se modifie");
    if (message.userId !== user.id) throw forbidden("NOT_AUTHOR", "Tu ne peux modifier que tes messages");
    if (message.thread.lockedAt) throw forbidden("THREAD_LOCKED", "Cette discussion est verrouillée");
    if (!canEditMessage(message.createdAt, new Date())) throw forbidden("EDIT_WINDOW_CLOSED", "Un message se modifie dans les 5 minutes qui suivent sa publication");
    const body = rawBody.trim();
    const problem = messageProblem(body);
    if (problem) throw badRequest(`MESSAGE_${problem.toUpperCase()}`, PROBLEM_MESSAGES[problem]);
    const updated = await this.prisma.forumMessage.update({
      where: { id: messageId },
      data: { body, editedAt: new Date() },
      include: { user: { select: { id: true, pseudo: true, avatarEntityId: true } }, reactions: { select: { userId: true, emoji: true } } },
    });
    return this.toMessageDto(updated, await this.buildContext(userId, message.thread, [updated]), []);
  }

  /** Journal de modération : une ligne par décision (voir `ModerationLog`). */
  async logModeration(moderatorId: string, action: string, ref: { targetUserId?: string; messageId?: string; threadId?: string; detail?: string }): Promise<void> {
    await this.prisma.moderationLog.create({ data: { id: randomUUID(), moderatorId, action, ...ref } });
  }

  /** L'auteur supprime son message ; un modérateur le masque (le texte reste en base pour revue). */
  async deleteMessage(userId: string, messageId: string): Promise<void> {
    const user = await this.prisma.appUser.findUniqueOrThrow({ where: { id: userId } });
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId } });
    if (!message) throw new NotFoundException("Message introuvable");
    if (message.userId === userId) {
      // Les réponses remontent d'un niveau : le fil reste lisible sans le message supprimé.
      await this.prisma.$transaction([
        this.prisma.forumMessage.updateMany({ where: { parentId: messageId }, data: { parentId: message.parentId } }),
        this.prisma.forumMessage.delete({ where: { id: messageId } }),
      ]);
      return;
    }
    if (!user.isModerator) throw forbidden("NOT_MODERATOR", "Tu ne peux pas supprimer ce message");
    await this.hideMessage(messageId, "moderator");
    await this.logModeration(userId, "hide", { messageId, targetUserId: message.userId, threadId: message.threadId, detail: forumSnippet(message.body) });
  }

  // Le masquage automatique (signalements) laisse les signalements ouverts : un modérateur les revoit
  // (rejeter rend le message, masquer le confirme). Seule une décision de modérateur les clôt.
  async hideMessage(messageId: string, reason: "moderator" | "reports"): Promise<void> {
    await this.prisma.$transaction([
      this.prisma.forumMessage.update({ where: { id: messageId }, data: { hiddenAt: new Date(), hiddenReason: reason } }),
      ...(reason === "moderator" ? [this.prisma.forumReport.updateMany({ where: { messageId, resolvedAt: null }, data: { resolvedAt: new Date() } })] : []),
    ]);
  }

  // ---- Réactions ----

  async putReaction(userId: string, messageId: string, emoji: string): Promise<void> {
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId }, select: { hiddenAt: true, thread: { select: { id: true, kind: true, groupId: true } } } });
    if (!message || message.hiddenAt) throw new NotFoundException("Message introuvable");
    const isPrivate = isPrivateThreadKind(message.thread.kind);
    if (isPrivate) await this.requireThreadAccess(userId, message.thread);
    await this.requirePoster(userId, isPrivate);
    await this.prisma.forumReaction.upsert({ where: { messageId_userId: { messageId, userId } }, create: { messageId, userId, emoji }, update: { emoji } });
  }

  // ---- Sondages ----

  async putVote(userId: string, messageId: string, option: number): Promise<void> {
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId }, include: { thread: true } });
    if (!message || message.hiddenAt || message.kind !== "poll") throw new NotFoundException("Sondage introuvable");
    const isPrivate = isPrivateThreadKind(message.thread.kind);
    if (isPrivate) await this.requireThreadAccess(userId, message.thread);
    await this.requirePoster(userId, isPrivate);
    const payload = message.payload as { options?: string[]; endsAt?: string } | null;
    if (pollClosed(payload?.endsAt, new Date())) throw forbidden("POLL_CLOSED", "Ce sondage est terminé");
    const options = payload?.options ?? [];
    if (option >= options.length) throw badRequest("POLL_OPTION", "Cette option n'existe pas");
    await this.prisma.forumPollVote.upsert({ where: { messageId_userId: { messageId, userId } }, create: { messageId, userId, option }, update: { option } });
  }

  async deleteVote(userId: string, messageId: string): Promise<void> {
    await this.prisma.forumPollVote.deleteMany({ where: { messageId, userId } });
  }

  async deleteReaction(userId: string, messageId: string): Promise<void> {
    await this.prisma.forumReaction.deleteMany({ where: { messageId, userId } });
  }

  // ---- Signalement ----

  async reportMessage(userId: string, messageId: string, dto: ReportMessageDto): Promise<void> {
    const message = await this.prisma.forumMessage.findUnique({ where: { id: messageId }, select: { userId: true, hiddenAt: true, thread: { select: { id: true, kind: true, groupId: true } } } });
    if (!message) throw new NotFoundException("Message introuvable");
    await this.requireThreadAccess(userId, message.thread);
    if (message.userId === userId) throw badRequest("REPORT_OWN", "Tu ne peux pas signaler ton propre message");
    try {
      await this.prisma.forumReport.create({ data: { id: randomUUID(), messageId, reporterId: userId, reason: dto.reason } });
    } catch (err) {
      if ((err as { code?: string }).code === "P2002") return; // déjà signalé par cette personne : idempotent
      throw err;
    }
    if (message.hiddenAt) return;
    const count = await this.prisma.forumReport.count({ where: { messageId, resolvedAt: null } });
    if (count >= FORUM_REPORT_HIDE_THRESHOLD) await this.hideMessage(messageId, "reports");
  }

  // ---- Blocages ----

  async listBlocks(userId: string): Promise<BlockedUserDto[]> {
    const blocks = await this.prisma.userBlock.findMany({ where: { blockerId: userId }, include: { blocked: { select: { id: true, pseudo: true } } }, orderBy: { createdAt: "desc" } });
    return blocks.map((b) => ({ userId: b.blocked.id, pseudo: b.blocked.pseudo ?? "Joueur" }));
  }

  async block(userId: string, targetId: string): Promise<void> {
    if (userId === targetId) throw badRequest("BLOCK_SELF", "Tu ne peux pas te bloquer toi-même");
    const target = await this.prisma.appUser.findUnique({ where: { id: targetId }, select: { id: true } });
    if (!target) throw new NotFoundException("Joueur introuvable");
    await this.prisma.userBlock.upsert({ where: { blockerId_blockedId: { blockerId: userId, blockedId: targetId } }, create: { blockerId: userId, blockedId: targetId }, update: {} });
  }

  async unblock(userId: string, targetId: string): Promise<void> {
    await this.prisma.userBlock.deleteMany({ where: { blockerId: userId, blockedId: targetId } });
  }

  // ---- Camps ----

  async listCamps(userId: string): Promise<ForumCampDto[]> {
    const camps = await this.prisma.forumCamp.findMany({ where: { userId } });
    const entities = await this.prisma.entity.findMany({ where: { id: { in: camps.map((c) => c.entityId) } }, select: { id: true, name: true, imageUrl: true } });
    const now = new Date();
    return camps.flatMap((c) => {
      const entity = entities.find((e) => e.id === c.entityId);
      return entity ? [{ game: c.game, entityId: c.entityId, name: entity.name, imageUrl: entity.imageUrl, changeWaitDays: campChangeWaitDays(c.changedAt, now) }] : [];
    });
  }

  /** Un camp par jeu, choisi parmi les équipes suivies (le suivi donne le badge), changeable tous les 7 jours. */
  async putCamp(userId: string, dto: PutCampDto): Promise<ForumCampDto[]> {
    await this.requireOpen(userId);
    if (!isKnownGame(dto.game)) throw badRequest("GAME_UNKNOWN", "Jeu inconnu");
    const team = await this.prisma.entity.findFirst({ where: { id: dto.entityId, kind: "team", participants: { some: { event: { competition: { game: dto.game } } } } }, select: { id: true } });
    if (!team) throw badRequest("TEAM_NOT_IN_GAME", "Cette équipe ne joue pas à ce jeu");
    const followed = await this.prisma.subscription.findUnique({ where: { userId_targetType_targetId: { userId, targetType: "entity", targetId: dto.entityId } }, select: { id: true } });
    if (!followed) throw badRequest("NOT_FOLLOWED", "Suis d'abord cette équipe pour en faire ton camp");

    const current = await this.prisma.forumCamp.findUnique({ where: { userId_game: { userId, game: dto.game } } });
    if (current && current.entityId !== dto.entityId) {
      const wait = campChangeWaitDays(current.changedAt, new Date());
      if (wait > 0) throw forbidden("CAMP_CHANGE_TOO_SOON", `Tu pourras changer de camp dans ${wait} jour(s)`);
    }
    if (!current || current.entityId !== dto.entityId) {
      // Le premier choix ne déclenche pas le délai (changedAt = epoch) : seuls les changements le font.
      await this.prisma.forumCamp.upsert({
        where: { userId_game: { userId, game: dto.game } },
        create: { userId, game: dto.game, entityId: dto.entityId, changedAt: new Date(0) },
        update: { entityId: dto.entityId, changedAt: new Date() },
      });
    }
    return this.listCamps(userId);
  }

  async deleteCamp(userId: string, game: string): Promise<void> {
    await this.prisma.forumCamp.deleteMany({ where: { userId, game } });
  }

  // ---- Mise en forme ----

  private async buildContext(viewerId: string | null, thread: ForumThread, rows: MessageRow[]) {
    const authorIds = [...new Set(rows.map((r) => r.userId))];
    const blocked = viewerId ? new Set((await this.prisma.userBlock.findMany({ where: { blockerId: viewerId }, select: { blockedId: true } })).map((b) => b.blockedId)) : new Set<string>();

    const camps = thread.game ? await this.prisma.forumCamp.findMany({ where: { game: thread.game, userId: { in: authorIds } } }) : [];
    // Le camp ne vaut que tant que l'équipe est suivie.
    const follows = camps.length
      ? await this.prisma.subscription.findMany({ where: { targetType: "entity", userId: { in: authorIds }, targetId: { in: camps.map((c) => c.entityId) } }, select: { userId: true, targetId: true } })
      : [];
    const activeCamps = camps.filter((c) => follows.some((f) => f.userId === c.userId && f.targetId === c.entityId));
    const entityIds = [...new Set([...activeCamps.map((c) => c.entityId), ...rows.flatMap((r) => (r.user.avatarEntityId ? [r.user.avatarEntityId] : []))])];
    const entities = await this.prisma.entity.findMany({ where: { id: { in: entityIds } }, select: { id: true, name: true, imageUrl: true } });
    return { viewerId, blocked, camps: activeCamps, entities: new Map(entities.map((e) => [e.id, e])), shares: await this.buildShares(viewerId, rows), polls: await this.buildPolls(viewerId, rows) };
  }

  // Cartes partagées : seul l'identifiant est stocké, l'appli dessine la carte avec les données du moment.
  // Un pronostic partagé reste caché jusqu'au coup d'envoi (règle des « choix des amis », décidée ici).
  private async buildShares(viewerId: string | null, rows: MessageRow[]): Promise<Map<string, ForumSharedDto>> {
    const shares = new Map<string, ForumSharedDto>();
    for (const r of rows) {
      if ((r.kind === "event" || r.kind === "competition" || r.kind === "team") && r.refId) shares.set(r.id, { kind: r.kind, refId: r.refId, pickedEntityId: null, pickedScore: null, otherScore: null, locked: false, pickemPicked: null, pickemTotal: null, pickemPoints: null });
    }
    const pickemRows = rows.filter((r) => r.kind === "pickem" && r.refId);
    if (pickemRows.length > 0) {
      const summaries = await this.pickem.shareSummaries(viewerId, pickemRows.map((r) => ({ userId: r.userId, competitionId: r.refId! })));
      for (const r of pickemRows) {
        const s = summaries.get(`${r.userId}:${r.refId}`);
        shares.set(r.id, { kind: "pickem", refId: r.refId!, pickedEntityId: s?.championEntityId ?? null, pickedScore: null, otherScore: null, locked: s?.locked ?? true, pickemPicked: s?.picked ?? null, pickemTotal: s?.total ?? null, pickemPoints: s?.points ?? null });
      }
    }
    const predictionRows = rows.filter((r) => r.kind === "prediction" && r.refId);
    if (predictionRows.length === 0) return shares;
    const eventIds = [...new Set(predictionRows.map((r) => r.refId!))];
    const events = new Map((await this.prisma.event.findMany({ where: { id: { in: eventIds } }, select: { id: true, status: true, startsAt: true } })).map((e) => [e.id, e]));
    const predictions = await this.prisma.prediction.findMany({ where: { OR: predictionRows.map((r) => ({ userId: r.userId, eventId: r.refId! })) } });
    const now = new Date();
    for (const r of predictionRows) {
      const event = events.get(r.refId!);
      const prediction = predictions.find((p) => p.userId === r.userId && p.eventId === r.refId);
      const visible = prediction !== undefined && event !== undefined && (r.userId === viewerId || canSeeFriendsPicks(event.status, event.startsAt, now));
      shares.set(r.id, {
        kind: "prediction",
        refId: r.refId!,
        pickedEntityId: visible ? prediction.pickedEntityId : null,
        pickedScore: visible ? prediction.pickedScore : null,
        otherScore: visible ? prediction.otherScore : null,
        locked: !visible,
        pickemPicked: null,
        pickemTotal: null,
        pickemPoints: null,
      });
    }
    return shares;
  }

  private async buildPolls(viewerId: string | null, rows: MessageRow[]): Promise<Map<string, ForumPollDto>> {
    const polls = new Map<string, ForumPollDto>();
    const pollRows = rows.filter((r) => r.kind === "poll");
    if (pollRows.length === 0) return polls;
    const ids = pollRows.map((r) => r.id);
    const counts = await this.prisma.forumPollVote.groupBy({ by: ["messageId", "option"], where: { messageId: { in: ids } }, _count: { _all: true } });
    const mine = viewerId ? await this.prisma.forumPollVote.findMany({ where: { messageId: { in: ids }, userId: viewerId } }) : [];
    for (const r of pollRows) {
      const payload = r.payload as { options?: string[]; endsAt?: string } | null;
      const labels = payload?.options ?? [];
      const options = labels.map((label, i) => ({ label, votes: counts.find((c) => c.messageId === r.id && c.option === i)?._count._all ?? 0 }));
      polls.set(r.id, {
        options,
        total: options.reduce((sum, o) => sum + o.votes, 0),
        myVote: mine.find((m) => m.messageId === r.id)?.option ?? null,
        endsAt: payload?.endsAt ? new Date(payload.endsAt) : null,
        closed: pollClosed(payload?.endsAt, new Date()),
      });
    }
    return polls;
  }

  private isMasked(row: MessageRow, ctx: { blocked: Set<string> }): boolean {
    return row.hiddenAt !== null || ctx.blocked.has(row.userId);
  }

  private toMessageDto(row: MessageRow, ctx: Awaited<ReturnType<ForumService["buildContext"]>>, replies: ForumMessageDto[]): ForumMessageDto {
    const masked = this.isMasked(row, ctx);
    const counts = new Map<string, number>();
    for (const r of row.reactions) counts.set(r.emoji, (counts.get(r.emoji) ?? 0) + 1);
    let author: ForumAuthorDto | null = null;
    if (!masked) {
      const camp = ctx.camps.find((c) => c.userId === row.userId);
      const campEntity = camp ? ctx.entities.get(camp.entityId) : undefined;
      author = {
        userId: row.userId,
        pseudo: row.user.pseudo ?? "Joueur",
        avatarUrl: (row.user.avatarEntityId && ctx.entities.get(row.user.avatarEntityId)?.imageUrl) || null,
        camp: campEntity ? { entityId: campEntity.id, name: campEntity.name, imageUrl: campEntity.imageUrl } : null,
      };
    }
    return {
      id: row.id,
      threadId: row.threadId,
      parentId: row.parentId,
      author,
      body: masked ? null : row.body,
      hidden: masked,
      replyTo: null,
      edited: row.editedAt !== null,
      isSpoiler: row.isSpoiler,
      kind: row.kind,
      shared: masked ? null : (ctx.shares.get(row.id) ?? null),
      poll: masked ? null : (ctx.polls.get(row.id) ?? null),
      ideaStatus: row.ideaStatus,
      pinned: row.pinnedAt !== null,
      createdAt: row.createdAt,
      reactions: masked ? [] : [...counts].map(([emoji, count]) => ({ emoji, count })),
      myReaction: ctx.viewerId ? (row.reactions.find((r) => r.userId === ctx.viewerId)?.emoji ?? null) : null,
      replies,
    };
  }
}
