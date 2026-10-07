import { randomUUID } from "node:crypto";
import { PrismaClient } from "@news/db";
import { IngestionService } from "./ingestion.service";

// Phrase d'enjeu des matchs à venir d'une phase suisse (J23), écrite par le worker contre le vrai Postgres de dev.
describe("phrase d'enjeu de la phase suisse (intégration)", () => {
  const prisma = new PrismaClient();
  const service = new IngestionService(prisma, {}, { publish: jest.fn() } as never);

  const tag = randomUUID().slice(0, 8);
  let categoryId: string;
  let competitionId: string;
  const teamIds: string[] = [];
  let upcomingId: string;
  const eventIds: string[] = [];

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-stakes-${tag}`, name: "Test enjeu" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Group Stage", format: "swiss" } })).id;
    for (const code of ["AAA", "BBB"]) teamIds.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Test ${code} ${tag}`, shortName: code } })).id);
    upcomingId = (
      await prisma.event.create({
        data: { id: randomUUID(), competitionId, kind: "match", name: "Round 5: AAA vs BBB", status: "scheduled", bestOf: 3, startsAt: new Date(Date.now() + 3600_000), result: { seriesScore: [], games: [] } },
      })
    ).id;
    eventIds.push(upcomingId);
    await prisma.eventParticipant.createMany({
      data: [
        { id: randomUUID(), eventId: upcomingId, entityId: teamIds[0], side: 0 },
        { id: randomUUID(), eventId: upcomingId, entityId: teamIds[1], side: 1 },
      ],
    });
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
    await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
    await prisma.entity.deleteMany({ where: { id: { in: teamIds } } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  const refresh = (records: [number, number][]) =>
    (service as unknown as { refreshSwissStakes: (id: string, s: unknown[]) => Promise<void> }).refreshSwissStakes(
      competitionId,
      records.map(([wins, losses], i) => ({ entityExternalId: teamIds[i], wins, losses })),
    );
  const stakes = async () => (await prisma.event.findUniqueOrThrow({ where: { id: upcomingId }, select: { stakes: true } })).stakes;

  it("deux équipes à 2-2 : le vainqueur est qualifié, le perdant éliminé", async () => {
    await refresh([
      [2, 2],
      [2, 2],
    ]);
    expect(await stakes()).toBe("Match décisif : le vainqueur est qualifié, le perdant éliminé. Match en [[BO3]].");
  });

  it("une équipe à 2 victoires : une de plus la qualifie ; l'autre à 2 défaites : une de plus l'élimine", async () => {
    await refresh([
      [2, 0],
      [0, 2],
    ]);
    expect(await stakes()).toBe("AAA se qualifie avec une victoire. BBB est éliminé en cas de défaite. Match en [[BO3]].");
  });

  it("sans enjeu particulier : la règle de la phase suisse", async () => {
    await refresh([
      [0, 0],
      [0, 0],
    ]);
    expect(await stakes()).toContain("phase suisse");
  });
});
