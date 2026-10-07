import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { PredictionSettlementService } from "./prediction-settlement.service";

// Règlement du pick'em de tableau (J25), contre le vrai Postgres de dev : deux demies + une finale.
describe("Pick'em : règlement (intégration)", () => {
  const prisma = new PrismaClient();
  const settlement = new PredictionSettlementService(new ConfigService({ REDIS_URL: "redis://localhost:6379" }), prisma);

  const slug = `test-pickem-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  const teams: string[] = [];
  const userIds: string[] = [];
  let semi1: string;
  let semi2: string;
  let final: string;

  const finish = async (eventId: string, winner: string) => {
    await prisma.event.update({ where: { id: eventId }, data: { status: "finished" } });
    await prisma.eventParticipant.updateMany({ where: { eventId, entityId: winner }, data: { isWinner: true } });
  };
  const bracket = async (picks: [string, string, string]) => {
    const user = await prisma.appUser.create({ data: { id: randomUUID() } });
    userIds.push(user.id);
    for (const [eventId, pickedEntityId] of [[semi1, picks[0]], [semi2, picks[1]], [final, picks[2]]]) {
      await prisma.bracketPick.create({ data: { id: randomUUID(), userId: user.id, competitionId, eventId, pickedEntityId } });
    }
    return user.id;
  };
  const total = async (userId: string) => {
    const rows = await prisma.bracketPick.findMany({ where: { userId } });
    const bonuses = await prisma.bracketPickBonus.findMany({ where: { userId, competitionId } });
    return { points: rows.map((r) => r.points), bonus: bonuses.find((b) => b.kind === "perfect")?.points ?? null, champion: bonuses.find((b) => b.kind === "champion")?.points ?? null };
  };

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test pickem" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test", format: "single_elim" } })).id;
    for (let i = 0; i < 4; i++) teams.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Test ${i}` } })).id);
    const mk = async (pair: string[]) => {
      const e = await prisma.event.create({ data: { id: randomUUID(), competitionId, kind: "match", name: "Test", status: "live" } });
      await prisma.eventParticipant.createMany({ data: pair.map((entityId, side) => ({ id: randomUUID(), eventId: e.id, entityId, side })) });
      return e.id;
    };
    semi1 = await mk([teams[0], teams[1]]);
    semi2 = await mk([teams[2], teams[3]]);
    final = await mk([teams[0], teams[2]]);
    await prisma.eventLink.createMany({
      data: [
        { id: randomUUID(), fromEventId: semi1, toEventId: final, outcome: "winner", slot: 0 },
        { id: randomUUID(), fromEventId: semi2, toEventId: final, outcome: "winner", slot: 1 },
      ],
    });
  });

  afterAll(async () => {
    await prisma.appUser.deleteMany({ where: { id: { in: userIds } } });
    await prisma.eventLink.deleteMany({ where: { fromEventId: { in: [semi1, semi2] } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: teams } } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  it("2 points par demie, 4 pour la finale, bonus de 5 (parfait) et 3 (champion), une seule fois", async () => {
    const perfect = await bracket([teams[0], teams[2], teams[0]]);
    const partial = await bracket([teams[0], teams[3], teams[0]]);

    await finish(semi1, teams[0]);
    await settlement.settleEvent(semi1);
    // Un second règlement du même match ne change rien.
    await settlement.settleEvent(semi1);
    expect((await total(perfect)).points.filter((p) => p !== null)).toEqual([2]);

    await finish(semi2, teams[2]);
    await settlement.settleEvent(semi2);
    // Le tableau n'est pas terminé : pas de bonus.
    expect((await total(perfect)).bonus).toBeNull();

    await finish(final, teams[0]);
    await settlement.settleEvent(final);
    await settlement.settleAllFinished();

    const a = await total(perfect);
    expect(a.points.reduce((s, p) => (s ?? 0) + (p ?? 0), 0)).toBe(8);
    expect(a.bonus).toBe(5);
    expect(a.champion).toBe(3);
    const b = await total(partial);
    expect(b.points.reduce((s, p) => (s ?? 0) + (p ?? 0), 0)).toBe(6);
    expect(b.bonus).toBeNull();
    // La finale (équipe 0) était la bonne : le bonus champion est versé même sans tableau parfait.
    expect(b.champion).toBe(3);
  });
});

// Phase suisse (J25) : un point par équipe qualifiée devinée, versé quand chaque équipe a son sort.
describe("Pronostic de phase suisse : règlement (intégration)", () => {
  const prisma = new PrismaClient();
  const settlement = new PredictionSettlementService(new ConfigService({ REDIS_URL: "redis://localhost:6379" }), prisma);
  const slug = `test-swiss-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  let a: string;
  let b: string;
  let userId: string;
  const eventIds: string[] = [];

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test suisse" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test", format: "swiss" } })).id;
    a = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test A" } })).id;
    b = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test B" } })).id;
    userId = (await prisma.appUser.create({ data: { id: randomUUID() } })).id;
    await prisma.stagePick.create({ data: { id: randomUUID(), userId, competitionId, entityIds: [a] } });
  });

  afterAll(async () => {
    await prisma.appUser.delete({ where: { id: userId } });
    await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [a, b] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  async function played(): Promise<string> {
    const e = await prisma.event.create({ data: { id: randomUUID(), competitionId, kind: "match", name: "Round 1: A vs B", status: "finished" } });
    eventIds.push(e.id);
    await prisma.eventParticipant.createMany({
      data: [
        { id: randomUUID(), eventId: e.id, entityId: a, side: 0, score: 2, isWinner: true },
        { id: randomUUID(), eventId: e.id, entityId: b, side: 1, score: 0, isWinner: false },
      ],
    });
    return e.id;
  }

  it("ne verse rien tant que le sort de chaque équipe n'est pas réglé, puis un point par qualifiée devinée, une seule fois", async () => {
    await settlement.settleEvent(await played());
    expect((await prisma.stagePick.findFirstOrThrow({ where: { userId } })).settledAt).toBeNull();
    await settlement.settleEvent(await played());
    await settlement.settleEvent(await played());
    const done = await prisma.stagePick.findFirstOrThrow({ where: { userId } });
    expect(done.points).toBe(1);
    expect(done.settledAt).not.toBeNull();
    await settlement.settleAllFinished();
    expect((await prisma.stagePick.findFirstOrThrow({ where: { userId } })).points).toBe(1);
  });
});
