import { randomUUID } from "node:crypto";
import { BadRequestException, ConflictException, ForbiddenException, Inject, Injectable, NotFoundException } from "@nestjs/common";
import { ApiProperty } from "@nestjs/swagger";
import { PrismaClient } from "@news/db";
import { computeStandings, EventStatus, maxStagePicks, scoreStagePick, standingsOptionsFor } from "@news/domain";
import { ArrayUnique, IsArray, IsUUID } from "class-validator";
import { PRISMA } from "../db/db.module";

export class StagePickTeamDto {
  @ApiProperty() entityId!: string;
  @ApiProperty() name!: string;
  @ApiProperty({ nullable: true, type: String }) shortName!: string | null;
  @ApiProperty({ nullable: true, type: String }) imageUrl!: string | null;
  // Où en est l'équipe dans l'étape : qualifiée (3 victoires), éliminée (3 défaites) ou encore en jeu.
  @ApiProperty({ enum: ["qualified", "eliminated", "playing"] }) state!: "qualified" | "eliminated" | "playing";
}

export class StagePickScoreDto {
  @ApiProperty() correct!: number;
  @ApiProperty() wrong!: number;
  @ApiProperty() pending!: number;
}

// Pronostic d'une phase suisse (J23) : quelles équipes se qualifieront, à choisir avant le premier match.
export class StagePickDto {
  @ApiProperty() competitionId!: string;
  // Les équipes de l'étape sont connues (sinon rien à choisir encore).
  @ApiProperty() open!: boolean;
  // Le premier match a commencé (ou est passé) : le pronostic ne bouge plus. Décidé ici, pas dans l'appli.
  @ApiProperty() locked!: boolean;
  @ApiProperty({ nullable: true, type: String }) lockAt!: string | null;
  // Nombre d'équipes qu'on peut choisir.
  @ApiProperty() max!: number;
  @ApiProperty({ type: [StagePickTeamDto] }) teams!: StagePickTeamDto[];
  // Le pronostic de la personne connectée (ids d'équipes).
  @ApiProperty({ type: [String] }) picks!: string[];
  @ApiProperty({ nullable: true, type: StagePickScoreDto }) score!: StagePickScoreDto | null;
  // Points versés à la fin de l'étape (un par équipe qualifiée devinée) ; nul tant que l'étape n'est pas finie.
  @ApiProperty({ nullable: true, type: Number }) points!: number | null;
}

export class PutStagePickDto {
  @ApiProperty({ type: [String] })
  @IsArray()
  @ArrayUnique()
  @IsUUID("all", { each: true })
  entityIds!: string[];
}

const forbidden = (code: string, message: string) => new ForbiddenException({ statusCode: 403, code, message });

@Injectable()
export class StagePickService {
  constructor(@Inject(PRISMA) private readonly prisma: PrismaClient) {}

  async get(userId: string, competitionId: string): Promise<StagePickDto> {
    const competition = await this.prisma.competition.findUnique({
      where: { id: competitionId },
      select: {
        format: true,
        events: {
          where: { status: { not: "cancelled" } },
          select: {
            status: true,
            startsAt: true,
            participants: { select: { entityId: true, score: true, isWinner: true, entity: { select: { name: true, shortName: true, imageUrl: true } } } },
          },
        },
      },
    });
    if (!competition || competition.format !== "swiss") throw new NotFoundException("Pas de pronostic pour cette étape");

    const teams = new Map<string, Omit<StagePickTeamDto, "state">>();
    for (const event of competition.events) {
      for (const p of event.participants) teams.set(p.entityId, { entityId: p.entityId, name: p.entity.name, shortName: p.entity.shortName, imageUrl: p.entity.imageUrl });
    }
    const standings = computeStandings(
      competition.events.map((e) => ({ status: e.status as EventStatus, participants: e.participants.map((p) => ({ entityExternalId: p.entityId, score: p.score, isWinner: p.isWinner })) })),
      standingsOptionsFor("swiss"),
    );
    const qualified = new Set(standings.filter((s) => s.qualified).map((s) => s.entityExternalId));
    const eliminated = new Set(standings.filter((s) => s.livesLeft === 0).map((s) => s.entityExternalId));

    const startTimes = competition.events.map((e) => e.startsAt?.getTime()).filter((t): t is number => t !== undefined);
    const lockAt = startTimes.length ? new Date(Math.min(...startTimes)) : null;
    const locked = competition.events.some((e) => e.status !== "scheduled") || (lockAt !== null && lockAt.getTime() <= Date.now());

    const saved = await this.prisma.stagePick.findUnique({ where: { userId_competitionId: { userId, competitionId } } });
    const picks = ((saved?.entityIds as string[] | undefined) ?? []).filter((id) => teams.has(id));
    return {
      competitionId,
      open: teams.size >= 4,
      locked,
      lockAt: lockAt?.toISOString() ?? null,
      max: maxStagePicks(teams.size),
      teams: [...teams.values()]
        .sort((a, b) => a.name.localeCompare(b.name))
        .map((t) => ({ ...t, state: qualified.has(t.entityId) ? "qualified" : eliminated.has(t.entityId) ? "eliminated" : "playing" })),
      picks,
      score: picks.length > 0 ? scoreStagePick(picks, qualified, eliminated) : null,
      points: saved?.settledAt ? (saved.points ?? 0) : null,
    };
  }

  async put(userId: string, competitionId: string, dto: PutStagePickDto): Promise<StagePickDto> {
    const user = await this.prisma.appUser.findUniqueOrThrow({ where: { id: userId }, select: { pseudo: true } });
    if (!user.pseudo) throw forbidden("PROFILE_REQUIRED", "Crée ton profil (pseudo) pour continuer");

    const current = await this.get(userId, competitionId);
    if (!current.open) throw new BadRequestException("Les équipes ne sont pas encore connues");
    if (current.locked) throw new ConflictException({ statusCode: 409, code: "PICK_LOCKED", message: "L'étape a commencé, le pronostic est verrouillé" });
    const known = new Set(current.teams.map((t) => t.entityId));
    if (dto.entityIds.some((id) => !known.has(id))) throw new BadRequestException("Une de ces équipes ne joue pas cette étape");
    if (dto.entityIds.length > current.max) throw new BadRequestException(`Au plus ${current.max} équipes`);

    await this.prisma.stagePick.upsert({
      where: { userId_competitionId: { userId, competitionId } },
      create: { id: randomUUID(), userId, competitionId, entityIds: dto.entityIds },
      update: { entityIds: dto.entityIds },
    });
    return this.get(userId, competitionId);
  }
}
