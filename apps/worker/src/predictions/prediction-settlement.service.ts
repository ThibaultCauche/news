import { Inject, Injectable, OnModuleDestroy, OnModuleInit } from "@nestjs/common";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import {
  computeStandings,
  createLogger,
  DomainEventMessage,
  DOMAIN_EVENTS_CHANNEL,
  EventStatus,
  isPerfectPickem,
  isStageSettled,
  PICKEM_BONUS,
  PICKEM_CHAMPION_BONUS,
  PICKEM_FORMATS,
  pickemFinalId,
  pickemWeights,
  scorePickemMatch,
  scorePrediction,
  stagePickPoints,
  standingsOptionsFor,
} from "@news/domain";
import Redis from "ioredis";
import { PRISMA } from "../db/db.module";

const logger = createLogger("worker:predictions");

// Attribue les points des pronostics quand un match se termine (J11, docs/03 §3 : nouveau
// consommateur du canal d'événements métier). Idempotent : seules les lignes `settledAt IS NULL`
// sont traitées, et un rattrapage au démarrage couvre un `EventFinished` manqué (worker arrêté).
// Un match terminé sans vainqueur (annulé, forfait sans résultat) laisse le pronostic sans effet.
@Injectable()
export class PredictionSettlementService implements OnModuleInit, OnModuleDestroy {
  private readonly subscriber: Redis;

  constructor(
    config: ConfigService,
    @Inject(PRISMA) private readonly prisma: PrismaClient,
  ) {
    this.subscriber = new Redis(config.getOrThrow<string>("REDIS_URL"), { lazyConnect: true });
  }

  async onModuleInit(): Promise<void> {
    this.subscriber.on("message", (_channel, raw) => {
      const message = JSON.parse(raw) as DomainEventMessage;
      if (message.type !== "EventFinished" || !message.eventId) return;
      this.settleEvent(message.eventId).catch((err) => logger.error(err, "échec du règlement des pronostics"));
    });
    await this.subscriber.subscribe(DOMAIN_EVENTS_CHANNEL);
    this.settleAllFinished().catch((err) => logger.error(err, "échec du rattrapage des pronostics"));
  }

  async onModuleDestroy(): Promise<void> {
    this.subscriber.disconnect();
  }

  async settleAllFinished(): Promise<void> {
    const pending = await this.prisma.prediction.findMany({
      where: { settledAt: null, event: { status: "finished" } },
      select: { eventId: true },
      distinct: ["eventId"],
    });
    for (const { eventId } of pending) await this.settleEvent(eventId);
    const pendingPicks = await this.prisma.bracketPick.findMany({
      where: { settledAt: null, event: { status: "finished" } },
      select: { eventId: true },
      distinct: ["eventId"],
    });
    for (const { eventId } of pendingPicks) await this.settleEvent(eventId);
    const pendingStages = await this.prisma.stagePick.findMany({ where: { settledAt: null }, select: { competitionId: true }, distinct: ["competitionId"] });
    for (const { competitionId } of pendingStages) await this.settleStagePicks(competitionId);
  }

  async settleEvent(eventId: string): Promise<number> {
    const event = await this.prisma.event.findUnique({ where: { id: eventId }, include: { participants: true } });
    if (!event || event.status !== "finished") return 0;
    const winner = event.participants.find((p) => p.isWinner);
    if (!winner) return 0;
    const outcome = {
      winnerEntityId: winner.entityId,
      scoreByEntity: Object.fromEntries(event.participants.map((p) => [p.entityId, p.score])),
    };
    await this.settleBracketPicks(eventId, event.competitionId, winner.entityId);
    await this.settleStagePicks(event.competitionId);
    const pending = await this.prisma.prediction.findMany({ where: { eventId, settledAt: null } });
    const now = new Date();
    for (const p of pending) {
      const points = scorePrediction({ pickedEntityId: p.pickedEntityId, pickedScore: p.pickedScore, otherScore: p.otherScore }, outcome);
      // `settledAt: null` dans le where : deux règlements simultanés ne comptent pas deux fois.
      await this.prisma.prediction.updateMany({ where: { id: p.id, settledAt: null }, data: { points, settledAt: now } });
    }
    if (pending.length > 0) logger.info({ eventId, count: pending.length }, "pronostics réglés");
    return pending.length;
  }
  // Pick'em de tableau (J25) : le poids du match si le choix est juste. Même garde `settledAt: null` que les
  // pronostics ; le bonus « tableau parfait » est versé après le dernier match, une fois par personne.
  private async settleBracketPicks(eventId: string, competitionId: string, winnerEntityId: string): Promise<void> {
    const picks = await this.prisma.bracketPick.findMany({ where: { eventId, settledAt: null } });
    if (picks.length === 0) return;
    const competition = await this.prisma.competition.findUnique({
      where: { id: competitionId },
      select: { format: true, events: { where: { status: { not: "cancelled" } }, select: { id: true, linksTo: { select: { fromEventId: true, outcome: true } } } } },
    });
    if (!competition?.format || !PICKEM_FORMATS.includes(competition.format)) return;
    const ids = new Set(competition.events.map((e) => e.id));
    const matches = competition.events.map((e) => ({
      id: e.id,
      participants: [],
      feeders: e.linksTo.filter((l) => ids.has(l.fromEventId)).map((l) => ({ fromId: l.fromEventId, outcome: l.outcome as "winner" | "loser" })),
    }));
    const weight = pickemWeights(matches).get(eventId) ?? 1;
    const now = new Date();
    for (const p of picks) {
      await this.prisma.bracketPick.updateMany({ where: { id: p.id, settledAt: null }, data: { points: scorePickemMatch(weight, p.pickedEntityId, winnerEntityId), settledAt: now } });
    }
    // Bonus champion : le choix sur la finale était le bon. Clé (personne, compétition, type) : versé une seule fois.
    if (eventId === pickemFinalId(matches)) {
      const right = picks.filter((p) => p.pickedEntityId === winnerEntityId).map((p) => ({ userId: p.userId, competitionId, kind: "champion", points: PICKEM_CHAMPION_BONUS }));
      if (right.length > 0) await this.prisma.bracketPickBonus.createMany({ data: right, skipDuplicates: true });
    }
    await this.settleBonus(competitionId);
  }

  private async settleBonus(competitionId: string): Promise<void> {
    const events = await this.prisma.event.findMany({
      where: { competitionId, status: { not: "cancelled" } },
      select: { id: true, status: true, participants: { select: { entityId: true, isWinner: true } } },
    });
    if (events.length === 0 || events.some((e) => e.status !== "finished")) return;
    const winners = new Map<string, string>();
    for (const e of events) {
      const w = e.participants.find((p) => p.isWinner);
      if (!w) return;
      winners.set(e.id, w.entityId);
    }
    const rows = await this.prisma.bracketPick.findMany({ where: { competitionId } });
    const byUser = new Map<string, Record<string, string>>();
    for (const r of rows) byUser.set(r.userId, { ...byUser.get(r.userId), [r.eventId]: r.pickedEntityId });
    const perfect = [...byUser].filter(([, picks]) => isPerfectPickem(winners, picks)).map(([userId]) => ({ userId, competitionId, kind: "perfect", points: PICKEM_BONUS }));
    // Clé primaire (userId, competitionId) : un second passage ne verse rien de plus.
    if (perfect.length > 0) await this.prisma.bracketPickBonus.createMany({ data: perfect, skipDuplicates: true });
  }

  // Pronostic de phase suisse (J25) : un point par équipe qualifiée devinée, versé une fois que chaque équipe a son sort
  // (qualifiée ou éliminée). Même garde `settledAt: null` que les autres règlements.
  private async settleStagePicks(competitionId: string): Promise<void> {
    const pending = await this.prisma.stagePick.findMany({ where: { competitionId, settledAt: null } });
    if (pending.length === 0) return;
    const competition = await this.prisma.competition.findUnique({
      where: { id: competitionId },
      select: { format: true, events: { where: { status: { not: "cancelled" } }, select: { status: true, participants: { select: { entityId: true, score: true, isWinner: true } } } } },
    });
    if (competition?.format !== "swiss") return;
    const standings = computeStandings(
      competition.events.map((e) => ({ status: e.status as EventStatus, participants: e.participants.map((p) => ({ entityExternalId: p.entityId, score: p.score, isWinner: p.isWinner })) })),
      standingsOptionsFor("swiss"),
    );
    const qualified = new Set(standings.filter((s) => s.qualified).map((s) => s.entityExternalId));
    const eliminated = new Set(standings.filter((s) => s.livesLeft === 0).map((s) => s.entityExternalId));
    const teamIds = [...new Set(competition.events.flatMap((e) => e.participants.map((p) => p.entityId)))];
    if (!isStageSettled(teamIds, qualified, eliminated)) return;
    const now = new Date();
    for (const p of pending) {
      await this.prisma.stagePick.updateMany({ where: { id: p.id, settledAt: null }, data: { points: stagePickPoints(p.entityIds as string[], qualified), settledAt: now } });
    }
    logger.info({ competitionId, count: pending.length }, "pronostics de phase suisse réglés");
  }
}
