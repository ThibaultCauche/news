import { randomInt, randomUUID } from "node:crypto";
import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import {
  canPredict,
  canSeeFriendsPicks,
  earnedBadges,
  generateGroupCode,
  GROUP_MAX_MEMBERS,
  normalizeGroupCode,
  pseudoChangeWaitDays,
  pseudoKeyOf,
  pseudoProblem,
} from "@news/domain";
import { PRISMA } from "../db/db.module";
import { BadgeDto, FriendsPicksDto, GroupDetailDto, GroupDto, PredictionDto, ProfileCampDto, PredictionStatsDto, ProfileDto, PublicProfileDto, PutPredictionDto, PutProfileDto } from "./community.dto";

const PSEUDO_MESSAGES = {
  length: "Le pseudo doit faire entre 3 et 20 caractères",
  characters: "Le pseudo ne peut contenir que des lettres, chiffres, « _ », « . » et « - »",
  forbidden: "Ce pseudo n'est pas autorisé",
} as const;

// Erreurs à code stable : l'appli affiche son propre texte selon `code` (docs/04 J11).
const forbidden = (code: string, message: string) => new ForbiddenException({ statusCode: 403, code, message });
const conflict = (code: string, message: string) => new ConflictException({ statusCode: 409, code, message });

// Couche communautaire (J11) : profil, pronostics, groupes d'amis. Tout exige un compte ;
// pronostics et groupes exigent en plus un pseudo (donc un e-mail vérifié).
@Injectable()
export class CommunityService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  // ---- Profil ----

  async getProfile(userId: string): Promise<ProfileDto> {
    const user = await this.prisma.appUser.findUniqueOrThrow({ where: { id: userId } });
    return {
      pseudo: user.pseudo,
      avatarUrl: await this.avatarUrlOf(user.avatarEntityId),
      emailVerified: user.emailVerified,
      pseudoChangeWaitDays: pseudoChangeWaitDays(user.pseudoChangedAt, new Date()),
      stats: await this.getStats(userId),
      badges: await this.getBadges(userId),
    };
  }

  /** Badges (J25) : déduits des pick'em et des phases suisses jouées, cosmétiques. */
  private async getBadges(userId: string): Promise<BadgeDto[]> {
    const [competitions, bonuses, swiss] = await Promise.all([
      this.prisma.bracketPick.findMany({ where: { userId }, select: { competitionId: true }, distinct: ["competitionId"] }),
      this.prisma.bracketPickBonus.findMany({ where: { userId }, select: { kind: true } }),
      this.prisma.stagePick.findMany({ where: { userId, settledAt: { not: null } }, select: { entityIds: true, points: true } }),
    ]);
    return earnedBadges({
      pickemsPlayed: competitions.length,
      perfectBrackets: bonuses.filter((b) => b.kind === "perfect").length,
      championsCalled: bonuses.filter((b) => b.kind === "champion").length,
      perfectSwiss: swiss.filter((s) => (s.entityIds as string[]).length >= 4 && s.points === (s.entityIds as string[]).length).length,
    });
  }

  async updateProfile(userId: string, dto: PutProfileDto): Promise<ProfileDto> {
    if (dto.pseudo === undefined && dto.avatarEntityId === undefined) throw new BadRequestException("Rien à modifier");
    if (dto.avatarEntityId !== undefined) {
      const team = await this.prisma.entity.findUnique({ where: { id: dto.avatarEntityId }, select: { kind: true, imageUrl: true } });
      if (!team || team.kind !== "team" || !team.imageUrl) throw new BadRequestException("Cette équipe ne peut pas servir d'avatar");
      await this.prisma.appUser.update({ where: { id: userId }, data: { avatarEntityId: dto.avatarEntityId } });
    }
    if (dto.pseudo !== undefined) return this.setPseudo(userId, dto.pseudo);
    return this.getProfile(userId);
  }

  private async setPseudo(userId: string, pseudo: string): Promise<ProfileDto> {
    const user = await this.prisma.appUser.findUniqueOrThrow({ where: { id: userId } });
    if (!user.emailVerified) throw forbidden("EMAIL_NOT_VERIFIED", "Vérifie ton e-mail avant de créer ton profil");
    const problem = pseudoProblem(pseudo);
    if (problem) throw new BadRequestException({ statusCode: 400, code: `PSEUDO_${problem.toUpperCase()}`, message: PSEUDO_MESSAGES[problem] });
    const wait = pseudoChangeWaitDays(user.pseudoChangedAt, new Date());
    if (wait > 0) throw forbidden("PSEUDO_CHANGE_TOO_SOON", `Tu pourras changer de pseudo dans ${wait} jour(s)`);
    const pseudoKey = pseudoKeyOf(pseudo);
    const taken = await this.prisma.appUser.findUnique({ where: { pseudoKey }, select: { id: true } });
    if (taken && taken.id !== userId) throw conflict("PSEUDO_TAKEN", "Ce pseudo est déjà pris");
    // Le premier pseudo ne déclenche pas le délai de 30 jours : seuls les changements le font.
    // Deux requêtes simultanées sur le même pseudo : la contrainte unique tranche (P2002 -> 409).
    try {
      await this.prisma.appUser.update({ where: { id: userId }, data: { pseudo, pseudoKey, pseudoChangedAt: user.pseudo ? new Date() : null } });
    } catch (err) {
      if ((err as { code?: string }).code === "P2002") throw conflict("PSEUDO_TAKEN", "Ce pseudo est déjà pris");
      throw err;
    }
    return this.getProfile(userId);
  }

  private async avatarUrlOf(entityId: string | null): Promise<string | null> {
    if (!entityId) return null;
    return (await this.prisma.entity.findUnique({ where: { id: entityId }, select: { imageUrl: true } }))?.imageUrl ?? null;
  }

  /** Profil d'un autre joueur : réservé à soi-même et aux membres d'un groupe en commun (404 sinon). */
  async getPublicProfile(viewerId: string, userId: string): Promise<PublicProfileDto> {
    if (viewerId !== userId) {
      const shared = await this.prisma.friendGroupMember.findFirst({ where: { userId, group: { members: { some: { userId: viewerId } } } }, select: { userId: true } });
      // Un joueur qui écrit sur le forum (J13) y est déjà public sous son pseudo : son profil s'ouvre depuis le fil.
      const postedOnForum = shared ? null : await this.prisma.forumMessage.findFirst({ where: { userId }, select: { id: true } });
      if (!shared && !postedOnForum) throw new NotFoundException("Joueur introuvable");
    }
    const user = await this.prisma.appUser.findUnique({ where: { id: userId } });
    if (!user?.pseudo) throw new NotFoundException("Joueur introuvable");
    return { userId, pseudo: user.pseudo, avatarUrl: await this.avatarUrlOf(user.avatarEntityId), stats: await this.getStats(userId), camps: await this.campsOf(userId), badges: await this.getBadges(userId) };
  }

  /** Camps du forum encore valables (équipe toujours suivie). */
  private async campsOf(userId: string): Promise<ProfileCampDto[]> {
    const camps = await this.prisma.forumCamp.findMany({ where: { userId } });
    if (camps.length === 0) return [];
    const follows = await this.prisma.subscription.findMany({ where: { userId, targetType: "entity", targetId: { in: camps.map((c) => c.entityId) } }, select: { targetId: true } });
    const entities = await this.prisma.entity.findMany({ where: { id: { in: follows.map((f) => f.targetId) } }, select: { id: true, name: true, imageUrl: true } });
    return camps.flatMap((c) => {
      const team = entities.find((e) => e.id === c.entityId);
      return team ? [{ game: c.game, name: team.name, imageUrl: team.imageUrl }] : [];
    });
  }

  private async requirePseudo(userId: string): Promise<void> {
    const user = await this.prisma.appUser.findUniqueOrThrow({ where: { id: userId }, select: { pseudo: true } });
    if (!user.pseudo) throw forbidden("PROFILE_REQUIRED", "Crée ton profil (pseudo) pour continuer");
  }

  private async getStats(userId: string): Promise<PredictionStatsDto> {
    const predictions = await this.prisma.prediction.findMany({
      where: { userId },
      select: { points: true, settledAt: true, event: { select: { startsAt: true } } },
    });
    // Le pick'em de tableau compte dans les mêmes points (J25, docs/07) ; ni série ni bons pronostics.
    const pickemPoints =
      ((await this.prisma.bracketPick.aggregate({ where: { userId }, _sum: { points: true } }))._sum.points ?? 0) +
      ((await this.prisma.bracketPickBonus.aggregate({ where: { userId }, _sum: { points: true } }))._sum.points ?? 0) +
      ((await this.prisma.stagePick.aggregate({ where: { userId }, _sum: { points: true } }))._sum.points ?? 0);
    const settled = predictions.filter((p) => p.settledAt !== null).sort((a, b) => (a.event.startsAt?.getTime() ?? 0) - (b.event.startsAt?.getTime() ?? 0));
    let current = 0;
    let best = 0;
    for (const p of settled) {
      current = (p.points ?? 0) > 0 ? current + 1 : 0;
      best = Math.max(best, current);
    }
    return {
      points: predictions.reduce((sum, p) => sum + (p.points ?? 0), 0) + pickemPoints,
      predictionsCount: predictions.length,
      settledCount: settled.length,
      correctCount: settled.filter((p) => (p.points ?? 0) > 0).length,
      currentStreak: current,
      bestStreak: best,
    };
  }

  // ---- Pronostics ----

  async listPredictions(userId: string): Promise<PredictionDto[]> {
    const rows = await this.prisma.prediction.findMany({ where: { userId }, orderBy: { createdAt: "desc" } });
    return rows.map(toPredictionDto);
  }

  async putPrediction(userId: string, dto: PutPredictionDto): Promise<PredictionDto> {
    await this.requirePseudo(userId);
    if ((dto.pickedScore === undefined) !== (dto.otherScore === undefined)) {
      throw new BadRequestException("Le score de série se donne en entier (deux valeurs) ou pas du tout");
    }
    const event = await this.prisma.event.findUnique({ where: { id: dto.eventId }, include: { participants: { select: { entityId: true } } } });
    if (!event) throw new NotFoundException("Match introuvable");
    if (!event.participants.some((p) => p.entityId === dto.pickedEntityId)) throw new BadRequestException("Cette équipe ne joue pas ce match");
    if (!canPredict(event.status, event.startsAt, new Date())) throw forbidden("PREDICTION_LOCKED", "Le match a commencé, le pronostic est verrouillé");
    const data = { pickedEntityId: dto.pickedEntityId, pickedScore: dto.pickedScore ?? null, otherScore: dto.otherScore ?? null };
    const row = await this.prisma.prediction.upsert({
      where: { userId_eventId: { userId, eventId: dto.eventId } },
      create: { id: randomUUID(), userId, eventId: dto.eventId, ...data },
      update: data,
    });
    return toPredictionDto(row);
  }

  /**
   * Choix des amis (membres d'un groupe en commun) sur un match, une fois le coup d'envoi donné.
   * Avant : liste vide, décidée ici et non dans l'appli, pour qu'on ne puisse pas copier un ami.
   */
  async friendsPicks(userId: string, eventId: string): Promise<FriendsPicksDto> {
    const event = await this.prisma.event.findUnique({ where: { id: eventId }, select: { status: true, startsAt: true } });
    if (!event) throw new NotFoundException("Match introuvable");
    if (!canSeeFriendsPicks(event.status, event.startsAt, new Date())) return { picks: [] };
    const rows = await this.prisma.prediction.findMany({
      where: { eventId, userId: { not: userId }, user: { pseudo: { not: null }, groupMemberships: { some: { group: { members: { some: { userId } } } } } } },
      include: { user: { select: { pseudo: true, avatarEntityId: true } } },
      orderBy: { createdAt: "asc" },
    });
    const avatarIds = rows.map((r) => r.user.avatarEntityId).filter((id): id is string => id !== null);
    const avatars = new Map((await this.prisma.entity.findMany({ where: { id: { in: avatarIds } }, select: { id: true, imageUrl: true } })).map((e) => [e.id, e.imageUrl]));
    return {
      picks: rows.map((r) => ({
        userId: r.userId,
        pseudo: r.user.pseudo ?? "?",
        avatarUrl: r.user.avatarEntityId ? (avatars.get(r.user.avatarEntityId) ?? null) : null,
        pickedEntityId: r.pickedEntityId,
        pickedScore: r.pickedScore,
        otherScore: r.otherScore,
      })),
    };
  }

  // ---- Groupes ----

  async createGroup(userId: string, name: string): Promise<GroupDto> {
    await this.requirePseudo(userId);
    // 31^8 codes : une collision est quasi impossible, mais la contrainte unique le garantit.
    for (let attempt = 0; attempt < 5; attempt++) {
      try {
        const group = await this.prisma.friendGroup.create({
          data: { id: randomUUID(), name: name.trim(), code: generateGroupCode(randomInt), ownerId: userId, members: { create: { userId } } },
        });
        return { id: group.id, name: group.name, code: group.code, memberCount: 1, isOwner: true };
      } catch (err) {
        if ((err as { code?: string }).code !== "P2002") throw err;
      }
    }
    throw conflict("CODE_COLLISION", "Impossible de générer un code de groupe, réessaie");
  }

  async joinGroup(userId: string, rawCode: string): Promise<GroupDto> {
    await this.requirePseudo(userId);
    const group = await this.prisma.friendGroup.findUnique({ where: { code: normalizeGroupCode(rawCode) }, include: { _count: { select: { members: true } } } });
    if (!group) throw new NotFoundException("Code de groupe inconnu");
    const already = await this.prisma.friendGroupMember.findUnique({ where: { groupId_userId: { groupId: group.id, userId } } });
    if (!already) {
      if (group._count.members >= GROUP_MAX_MEMBERS) throw conflict("GROUP_FULL", "Ce groupe est complet");
      await this.prisma.friendGroupMember.create({ data: { groupId: group.id, userId } });
    }
    const memberCount = await this.prisma.friendGroupMember.count({ where: { groupId: group.id } });
    return { id: group.id, name: group.name, code: group.code, memberCount, isOwner: group.ownerId === userId };
  }

  async listGroups(userId: string): Promise<GroupDto[]> {
    const groups = await this.prisma.friendGroup.findMany({
      where: { members: { some: { userId } } },
      include: { _count: { select: { members: true } } },
      orderBy: { createdAt: "asc" },
    });
    return groups.map((g) => ({ id: g.id, name: g.name, code: g.code, memberCount: g._count.members, isOwner: g.ownerId === userId }));
  }

  async getGroup(userId: string, groupId: string, game?: string): Promise<GroupDetailDto> {
    const group = await this.prisma.friendGroup.findFirst({
      where: { id: groupId, members: { some: { userId } } },
      include: { members: { include: { user: { select: { pseudo: true, avatarEntityId: true } } } } },
    });
    if (!group) throw new NotFoundException("Groupe introuvable");
    const predictions = await this.prisma.prediction.findMany({ where: { userId: { in: group.members.map((m) => m.userId) }, ...(game ? { event: { competition: { game } } } : {}) }, select: { userId: true, points: true } });
    // Le pick'em de tableau compte dans les mêmes points (J25, docs/07).
    const bracketPicks = await this.prisma.bracketPick.findMany({ where: { userId: { in: group.members.map((m) => m.userId) }, points: { not: null }, ...(game ? { competition: { game } } : {}) }, select: { userId: true, points: true } });
    const bracketBonuses = await this.prisma.bracketPickBonus.findMany({ where: { userId: { in: group.members.map((m) => m.userId) }, ...(game ? { competition: { game } } : {}) }, select: { userId: true, points: true } });
    const avatarEntityIds = group.members.map((m) => m.user.avatarEntityId).filter((id): id is string => id !== null);
    const avatars = new Map((await this.prisma.entity.findMany({ where: { id: { in: avatarEntityIds } }, select: { id: true, imageUrl: true } })).map((e) => [e.id, e.imageUrl]));
    const stagePicks = await this.prisma.stagePick.findMany({ where: { userId: { in: group.members.map((m) => m.userId) }, points: { not: null }, ...(game ? { competition: { game } } : {}) }, select: { userId: true, points: true } });
    const entries = group.members.map((m) => {
      const mine = [...predictions, ...bracketPicks, ...bracketBonuses, ...stagePicks].filter((p) => p.userId === m.userId);
      return {
        userId: m.userId,
        pseudo: m.user.pseudo ?? "?",
        avatarUrl: m.user.avatarEntityId ? (avatars.get(m.user.avatarEntityId) ?? null) : null,
        points: mine.reduce((sum, p) => sum + (p.points ?? 0), 0),
        correctCount: mine.filter((p) => (p.points ?? 0) > 0).length,
        isMe: m.userId === userId,
      };
    });
    entries.sort((a, b) => b.points - a.points || b.correctCount - a.correctCount || a.pseudo.localeCompare(b.pseudo));
    // Ex æquo de points et de bons pronostics : même rang (1, 1, 3).
    const ranking = entries.map((e, i) => {
      const prev = entries[i - 1];
      const tied = prev && prev.points === e.points && prev.correctCount === e.correctCount;
      return { ...e, rank: tied ? -1 : i + 1 };
    });
    ranking.forEach((r, i) => {
      if (r.rank === -1) r.rank = ranking[i - 1].rank;
    });
    return { id: group.id, name: group.name, code: group.code, memberCount: group.members.length, isOwner: group.ownerId === userId, ranking };
  }

  async leaveGroup(userId: string, groupId: string): Promise<void> {
    const group = await this.prisma.friendGroup.findFirst({ where: { id: groupId, members: { some: { userId } } } });
    if (!group) throw new NotFoundException("Groupe introuvable");
    if (group.ownerId === userId) throw conflict("OWNER_CANNOT_LEAVE", "Le créateur doit supprimer le groupe plutôt que le quitter");
    await this.prisma.friendGroupMember.delete({ where: { groupId_userId: { groupId, userId } } });
  }

  async deleteGroup(userId: string, groupId: string): Promise<void> {
    const group = await this.prisma.friendGroup.findFirst({ where: { id: groupId, members: { some: { userId } } } });
    if (!group) throw new NotFoundException("Groupe introuvable");
    if (group.ownerId !== userId) throw forbidden("NOT_GROUP_OWNER", "Seul le créateur peut supprimer le groupe");
    await this.prisma.friendGroup.delete({ where: { id: groupId } });
  }
}

function toPredictionDto(row: { eventId: string; pickedEntityId: string; pickedScore: number | null; otherScore: number | null; points: number | null }): PredictionDto {
  return { eventId: row.eventId, pickedEntityId: row.pickedEntityId, pickedScore: row.pickedScore, otherScore: row.otherScore, points: row.points };
}
