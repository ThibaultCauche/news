import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { PredictionSettlementService } from "./prediction-settlement.service";

// Intégration contre le vrai Postgres de dev (comme le moteur de notifications) : le barème est
// testé dans `packages/domain`, ici on vérifie le règlement une seule fois et l'absence d'effet
// sur un match sans vainqueur.
describe("PredictionSettlementService (intégration)", () => {
  const prisma = new PrismaClient();
  // Pas d'`onModuleInit` : aucune connexion Redis n'est ouverte, on appelle `settleEvent` à la main.
  const settlement = new PredictionSettlementService(new ConfigService({ REDIS_URL: "redis://localhost:6379" }), prisma);

  const slug = `test-settle-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  let teamAId: string;
  let teamBId: string;
  const userIds: string[] = [];

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test règlement" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test", status: "live" } })).id;
    teamAId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test A" } })).id;
    teamBId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test B" } })).id;
  });

  afterAll(async () => {
    await prisma.appUser.deleteMany({ where: { id: { in: userIds } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamAId, teamBId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  async function event(status: string, winner: "a" | "b" | null): Promise<string> {
    return (
      await prisma.event.create({
        data: {
          id: randomUUID(),
          competitionId,
          kind: "match",
          name: "Test A vs Test B",
          status,
          participants: {
            create: [
              { id: randomUUID(), entityId: teamAId, score: 2, isWinner: winner === null ? null : winner === "a" },
              { id: randomUUID(), entityId: teamBId, score: 1, isWinner: winner === null ? null : winner === "b" },
            ],
          },
        },
      })
    ).id;
  }

  async function predictor(eventId: string, pick: { entity: string; score?: [number, number] }): Promise<string> {
    const user = await prisma.appUser.create({ data: { id: randomUUID() } });
    userIds.push(user.id);
    await prisma.prediction.create({
      data: { id: randomUUID(), userId: user.id, eventId, pickedEntityId: pick.entity, pickedScore: pick.score?.[0] ?? null, otherScore: pick.score?.[1] ?? null },
    });
    return user.id;
  }

  const pointsOf = async (userId: string) => (await prisma.prediction.findFirstOrThrow({ where: { userId } })).points;

  it("attribue 3 points au bon vainqueur, 5 avec le score exact, 0 au mauvais", async () => {
    const eventId = await event("finished", "a");
    const winner = await predictor(eventId, { entity: teamAId });
    const exact = await predictor(eventId, { entity: teamAId, score: [2, 1] });
    const wrong = await predictor(eventId, { entity: teamBId });
    expect(await settlement.settleEvent(eventId)).toBe(3);
    expect([await pointsOf(winner), await pointsOf(exact), await pointsOf(wrong)]).toEqual([3, 5, 0]);
  });

  it("ne règle qu'une fois (idempotent)", async () => {
    const eventId = await event("finished", "a");
    const user = await predictor(eventId, { entity: teamAId });
    expect(await settlement.settleEvent(eventId)).toBe(1);
    await prisma.prediction.updateMany({ where: { userId: user }, data: { points: 99 } });
    expect(await settlement.settleEvent(eventId)).toBe(0);
    expect(await pointsOf(user)).toBe(99);
  });

  it("laisse le pronostic sans effet si le match n'est pas terminé ou n'a pas de vainqueur", async () => {
    const live = await predictor(await event("live", null), { entity: teamAId });
    const noWinner = await predictor(await event("finished", null), { entity: teamAId });
    await settlement.settleAllFinished();
    expect(await pointsOf(live)).toBeNull();
    expect(await pointsOf(noWinner)).toBeNull();
  });
});
