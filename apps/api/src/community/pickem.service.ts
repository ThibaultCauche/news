import { randomUUID } from "node:crypto";
import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { groupVote, invalidPickemMatch, PICKEM_FORMATS, pickemFinalId, pickemStanding, pickemWeights, PickemMatch, scorePickemMatch } from "@news/domain";
import { ArrayMaxSize, IsArray, IsUUID, ValidateNested } from "class-validator";
import { Type } from "class-transformer";
import { PRISMA } from "../db/db.module";

export class PickemTeamDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
}

export class PickemFeederDto {
  @ApiProperty() fromEventId!: string;
  @ApiProperty({ enum: ["winner", "loser"] }) outcome!: "winner" | "loser";
}

export class PickemMatchDto {
  @ApiProperty() eventId!: string;
  @ApiProperty() name!: string;
  @ApiProperty() status!: string;
  @ApiProperty({ nullable: true, type: String }) startsAt!: string | null;
  // Points que vaut ce match : 1, 2 (demi) ou 4 (finale).
  @ApiProperty() weight!: number;
  // Équipes déjà connues (premier tour) ; les autres se déduisent des choix précédents.
  @ApiProperty({ type: [String] }) participants!: string[];
  @ApiProperty({ type: [PickemFeederDto] }) feeders!: PickemFeederDto[];
  // Vainqueur réel, une fois le match terminé.
  @ApiProperty({ nullable: true, type: String }) winnerEntityId!: string | null;
}

export class PickemChoiceDto {
  @ApiProperty() eventId!: string;
  @ApiProperty() pickedEntityId!: string;
  @ApiProperty({ nullable: true, type: Number }) points!: number | null;
  // Le choix peut-il encore se réaliser ? Nul une fois le match joué (c'est alors `points` qui parle).
  @ApiProperty({ nullable: true, type: Boolean }) alive!: boolean | null;
}

// Pick'em d'un tableau (J25) : choisir le vainqueur de chaque match avant le premier match.
export class PickemDto {
  @ApiProperty() competitionId!: string;
  @ApiProperty() competitionName!: string;
  // Le tableau existe et ses premières équipes sont connues.
  @ApiProperty() open!: boolean;
  // Le premier match a commencé : plus rien ne bouge. Décidé ici, pas dans l'appli.
  @ApiProperty() locked!: boolean;
  @ApiProperty({ nullable: true, type: String }) lockAt!: string | null;
  @ApiProperty({ type: [PickemMatchDto] }) matches!: PickemMatchDto[];
  @ApiProperty({ type: [PickemTeamDto] }) teams!: PickemTeamDto[];
  @ApiProperty({ type: [PickemChoiceDto] }) picks!: PickemChoiceDto[];
  // Points déjà marqués (matchs + bonus).
  @ApiProperty() points!: number;
  // Bonus « tableau parfait » et bonus « champion », une fois versés.
  @ApiProperty({ nullable: true, type: Number }) bonus!: number | null;
  @ApiProperty({ nullable: true, type: Number }) championBonus!: number | null;
  // Points qu'on peut encore marquer au mieux (matchs à venir dont le choix tient, plus les bonus possibles).
  @ApiProperty() maxRemaining!: number;
}

export class PickemChoiceInputDto {
  @ApiProperty() @IsUUID("all") eventId!: string;
  @ApiProperty() @IsUUID("all") pickedEntityId!: string;
}

export class PutPickemDto {
  @ApiProperty({ type: [PickemChoiceInputDto] })
  @IsArray()
  @ArrayMaxSize(200)
  @ValidateNested({ each: true })
  @Type(() => PickemChoiceInputDto)
  picks!: PickemChoiceInputDto[];
}

export class PickemMemberDto {
  @ApiProperty() userId!: string;
  @ApiProperty() pseudo!: string;
  @ApiProperty({ nullable: true, type: String }) avatarUrl!: string | null;
  // Nombre de matchs remplis (visible avant le verrouillage, sans le contenu).
  @ApiProperty() filled!: number;
  @ApiProperty() points!: number;
  @ApiProperty() isMe!: boolean;
  // Choix du membre : vide tant que le tableau n'est pas verrouillé, décidé côté serveur.
  @ApiProperty({ type: [PickemChoiceDto] }) picks!: PickemChoiceDto[];
}

export class PickemGroupDto {
  @ApiProperty() groupId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ type: [PickemMemberDto] }) members!: PickemMemberDto[];
  // Choix du groupe par match (vote majoritaire) : vide avant le verrouillage.
  @ApiProperty({ type: [PickemChoiceDto] }) groupPicks!: PickemChoiceDto[];
  // Points du groupe : le poids de chaque match où le choix du groupe était juste.
  @ApiProperty() points!: number;
  @ApiProperty() rank!: number;
}

export class PickemGroupsDto {
  @ApiProperty() locked!: boolean;
  @ApiProperty({ type: [PickemGroupDto] }) groups!: PickemGroupDto[];
}

export interface PickemShareSummary {
  picked: number;
  total: number;
  locked: boolean;
  championEntityId: string | null;
  points: number | null;
}

export class MyPickemDto {
  @ApiProperty() competitionId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) game!: string | null;
  @ApiProperty() locked!: boolean;
  @ApiProperty() picked!: number;
  @ApiProperty() total!: number;
  @ApiProperty() points!: number;
}

const forbidden = (code: string, message: string) => new ForbiddenException({ statusCode: 403, code, message });

@Injectable()
export class PickemService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  // Les matchs du tableau, dans la forme attendue par le domaine, plus de quoi les afficher.
  private async loadBracket(competitionId: string) {
    const competition = await this.prisma.competition.findUnique({
      where: { id: competitionId },
      select: {
        name: true,
        parent: { select: { name: true } },
        format: true,
        events: {
          where: { status: { not: "cancelled" } },
          orderBy: { startsAt: "asc" },
          select: {
            id: true,
            name: true,
            status: true,
            startsAt: true,
            linksTo: { select: { fromEventId: true, outcome: true } },
            participants: { select: { entityId: true, isWinner: true, entity: { select: { name: true, shortName: true, imageUrl: true } } } },
          },
        },
      },
    });
    if (!competition || !competition.format || !PICKEM_FORMATS.includes(competition.format)) throw new NotFoundException("Pas de pick'em pour cette étape");
    const ids = new Set(competition.events.map((e) => e.id));
    const matches: PickemMatch[] = competition.events.map((e) => ({
      id: e.id,
      participants: e.participants.map((p) => p.entityId),
      feeders: e.linksTo.filter((l) => ids.has(l.fromEventId)).map((l) => ({ fromId: l.fromEventId, outcome: l.outcome as "winner" | "loser" })),
    }));
    const startTimes = competition.events.map((e) => e.startsAt?.getTime()).filter((t): t is number => t !== undefined);
    const lockAt = startTimes.length ? new Date(Math.min(...startTimes)) : null;
    const locked = competition.events.some((e) => e.status !== "scheduled") || (lockAt !== null && lockAt.getTime() <= Date.now());
    return { competition, matches, lockAt, locked, weights: pickemWeights(matches) };
  }

  async get(userId: string, competitionId: string): Promise<PickemDto> {
    const { competition, matches, lockAt, locked, weights } = await this.loadBracket(competitionId);
    const teams = new Map<string, PickemTeamDto>();
    for (const e of competition.events) {
      for (const p of e.participants) teams.set(p.entityId, { entityId: p.entityId, name: p.entity.name, shortName: p.entity.shortName, imageUrl: p.entity.imageUrl });
    }
    const rows = await this.prisma.bracketPick.findMany({ where: { userId, competitionId } });
    const bonuses = await this.prisma.bracketPickBonus.findMany({ where: { userId, competitionId } });
    const winners = new Map(competition.events.flatMap((e) => { const w = e.participants.find((p) => p.isWinner); return w ? [[e.id, w.entityId] as const] : []; }));
    const standing = pickemStanding(matches, Object.fromEntries(rows.map((r) => [r.eventId, r.pickedEntityId])), winners);
    return {
      competitionId,
      competitionName: competition.parent ? `${competition.parent.name} · ${competition.name}` : competition.name,
      open: matches.length >= 3 && matches.some((m) => m.participants.length >= 2),
      locked,
      lockAt: lockAt?.toISOString() ?? null,
      matches: competition.events.map((e, i) => ({
        eventId: e.id,
        name: e.name,
        status: e.status,
        startsAt: e.startsAt?.toISOString() ?? null,
        weight: weights.get(e.id) ?? 1,
        participants: matches[i].participants,
        feeders: matches[i].feeders.map((f) => ({ fromEventId: f.fromId, outcome: f.outcome })),
        winnerEntityId: e.participants.find((p) => p.isWinner)?.entityId ?? null,
      })),
      teams: [...teams.values()],
      picks: rows.map((r) => ({ eventId: r.eventId, pickedEntityId: r.pickedEntityId, points: r.points, alive: standing.alive.get(r.eventId) ?? null })),
      points: rows.reduce((sum, r) => sum + (r.points ?? 0), 0) + bonuses.reduce((sum, b) => sum + b.points, 0),
      bonus: bonuses.find((b) => b.kind === "perfect")?.points ?? null,
      championBonus: bonuses.find((b) => b.kind === "champion")?.points ?? null,
      maxRemaining: standing.maxRemaining,
    };
  }

  async put(userId: string, competitionId: string, dto: PutPickemDto): Promise<PickemDto> {
    const user = await this.prisma.appUser.findUniqueOrThrow({ where: { id: userId }, select: { pseudo: true } });
    if (!user.pseudo) throw forbidden("PROFILE_REQUIRED", "Crée ton profil (pseudo) pour continuer");

    const { matches, locked } = await this.loadBracket(competitionId);
    if (matches.length < 3 || !matches.some((m) => m.participants.length >= 2)) throw new BadRequestException("Le tableau n'est pas encore connu");
    if (locked) throw new ConflictException({ statusCode: 409, code: "PICK_LOCKED", message: "Le tournoi a commencé, le pick'em est verrouillé" });

    const picks = Object.fromEntries(dto.picks.map((p) => [p.eventId, p.pickedEntityId]));
    if (Object.keys(picks).length !== dto.picks.length) throw new BadRequestException("Un match est choisi deux fois");
    const bad = invalidPickemMatch(matches, picks);
    if (bad) throw new BadRequestException("Cette équipe ne peut pas jouer ce match");

    // Remplacement complet : un choix retiré par l'appli (équipe qui ne joue plus ce match) disparaît.
    await this.prisma.$transaction([
      this.prisma.bracketPick.deleteMany({ where: { userId, competitionId, eventId: { notIn: dto.picks.map((p) => p.eventId) } } }),
      ...dto.picks.map((p) =>
        this.prisma.bracketPick.upsert({
          where: { userId_eventId: { userId, eventId: p.eventId } },
          create: { id: randomUUID(), userId, competitionId, eventId: p.eventId, pickedEntityId: p.pickedEntityId },
          update: { pickedEntityId: p.pickedEntityId },
        }),
      ),
    ]);
    return this.get(userId, competitionId);
  }

  // Cartes « tableau » partagées dans une discussion (J25) : le nombre de choix se voit toujours, le champion et les points
  // seulement une fois le tournoi commencé (ou pour son auteur), décidé ici comme pour les choix des amis.
  async shareSummaries(viewerId: string | null, items: { userId: string; competitionId: string }[]): Promise<Map<string, PickemShareSummary>> {
    const out = new Map<string, PickemShareSummary>();
    for (const competitionId of new Set(items.map((i) => i.competitionId))) {
      const bracket = await this.loadBracket(competitionId).catch(() => null);
      if (!bracket) continue;
      const finalId = pickemFinalId(bracket.matches);
      const owners = items.filter((i) => i.competitionId === competitionId).map((i) => i.userId);
      const picks = await this.prisma.bracketPick.findMany({ where: { competitionId, userId: { in: owners } } });
      const bonuses = await this.prisma.bracketPickBonus.findMany({ where: { competitionId, userId: { in: owners } } });
      for (const userId of new Set(owners)) {
        const mine = picks.filter((p) => p.userId === userId);
        const visible = bracket.locked || userId === viewerId;
        out.set(`${userId}:${competitionId}`, {
          picked: mine.length,
          total: bracket.matches.length,
          locked: !visible,
          championEntityId: visible ? (mine.find((p) => p.eventId === finalId)?.pickedEntityId ?? null) : null,
          points: visible ? mine.reduce((s, p) => s + (p.points ?? 0), 0) + bonuses.filter((b) => b.userId === userId).reduce((s, b) => s + b.points, 0) : null,
        });
      }
    }
    return out;
  }

  // Mes pick'em : tous les tableaux où j'ai fait au moins un choix.
  async mine(userId: string): Promise<MyPickemDto[]> {
    const rows = await this.prisma.bracketPick.findMany({ where: { userId }, select: { competitionId: true, points: true } });
    const bonuses = await this.prisma.bracketPickBonus.findMany({ where: { userId } });
    const ids = [...new Set(rows.map((r) => r.competitionId))];
    const competitions = await this.prisma.competition.findMany({
      where: { id: { in: ids } },
      select: { id: true, name: true, parent: { select: { name: true } }, game: true, events: { where: { status: { not: "cancelled" } }, select: { status: true, startsAt: true } } },
    });
    return competitions.map((c) => {
      const mine = rows.filter((r) => r.competitionId === c.id);
      const starts = c.events.map((e) => e.startsAt?.getTime()).filter((t): t is number => t !== undefined);
      return {
        competitionId: c.id,
        name: c.parent ? `${c.parent.name} · ${c.name}` : c.name,
        game: c.game,
        locked: c.events.some((e) => e.status !== "scheduled") || (starts.length > 0 && Math.min(...starts) <= Date.now()),
        picked: mine.length,
        total: c.events.length,
        points: mine.reduce((s, r) => s + (r.points ?? 0), 0) + bonuses.filter((b) => b.competitionId === c.id).reduce((s, b) => s + b.points, 0),
      };
    });
  }

  // Pick'em de mes groupes : choix des membres et vote du groupe, visibles seulement une fois le tableau verrouillé.
  async groups(userId: string, competitionId: string): Promise<PickemGroupsDto> {
    const { competition, locked, weights } = await this.loadBracket(competitionId);
    const groups = await this.prisma.friendGroup.findMany({
      where: { members: { some: { userId } } },
      orderBy: { createdAt: "asc" },
      include: { members: { orderBy: { joinedAt: "asc" }, include: { user: { select: { pseudo: true, avatarEntityId: true } } } } },
    });
    const memberIds = [...new Set(groups.flatMap((g) => g.members.map((m) => m.userId)))];
    const picks = await this.prisma.bracketPick.findMany({ where: { competitionId, userId: { in: memberIds } } });
    const bonuses = await this.prisma.bracketPickBonus.findMany({ where: { competitionId, userId: { in: memberIds } } });
    const avatarIds = groups.flatMap((g) => g.members.map((m) => m.user.avatarEntityId)).filter((id): id is string => id !== null);
    const avatars = new Map((await this.prisma.entity.findMany({ where: { id: { in: avatarIds } }, select: { id: true, imageUrl: true } })).map((e) => [e.id, e.imageUrl]));
    const winners = new Map(competition.events.flatMap((e) => (e.participants.find((p) => p.isWinner) ? [[e.id, e.participants.find((p) => p.isWinner)!.entityId] as const] : [])));

    const result: Omit<PickemGroupDto, "rank">[] = groups.map((g) => {
      const members = g.members.map((m) => {
        const mine = picks.filter((p) => p.userId === m.userId);
        return {
          userId: m.userId,
          pseudo: m.user.pseudo ?? "?",
          avatarUrl: m.user.avatarEntityId ? (avatars.get(m.user.avatarEntityId) ?? null) : null,
          filled: mine.length,
          points: mine.reduce((s, p) => s + (p.points ?? 0), 0) + bonuses.filter((b) => b.userId === m.userId).reduce((sum, b) => sum + b.points, 0),
          isMe: m.userId === userId,
          picks: locked || m.userId === userId ? mine.map((p) => ({ eventId: p.eventId, pickedEntityId: p.pickedEntityId, points: p.points, alive: null })) : [],
        };
      });
      const groupPicks: PickemChoiceDto[] = [];
      let points = 0;
      if (locked) {
        for (const e of competition.events) {
          // `members` est déjà classé du plus ancien au plus récent : l'égalité se tranche par l'ancienneté.
          const votes = g.members.flatMap((m) => picks.filter((p) => p.userId === m.userId && p.eventId === e.id).map((p) => p.pickedEntityId));
          const choice = groupVote(votes);
          if (!choice) continue;
          const winner = winners.get(e.id);
          const earned = winner ? scorePickemMatch(weights.get(e.id) ?? 1, choice, winner) : null;
          groupPicks.push({ eventId: e.id, pickedEntityId: choice, points: earned, alive: null });
          points += earned ?? 0;
        }
      }
      return { groupId: g.id, name: g.name, members, groupPicks, points };
    });
    // Classement entre mes groupes (ex æquo : même rang).
    const sorted = [...result].sort((a, b) => b.points - a.points || a.name.localeCompare(b.name));
    return { locked, groups: result.map((g) => ({ ...g, rank: sorted.findIndex((s) => s.points === g.points) + 1 })) };
  }
}
