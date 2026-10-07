import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser, TestAccount } from "./test-utils";

// Pronostic d'une phase suisse (docs/04 J23), contre le vrai Postgres/Redis de dev.
describe("Pronostic de phase suisse (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let account: TestAccount;
  let noPseudo: TestAccount;

  const tag = randomUUID().slice(0, 8);
  let categoryId: string;
  let swissId: string;
  let singleId: string;
  const teamIds: string[] = [];
  const eventIds: string[] = [];

  const url = () => `/v1/competitions/${swissId}/pick`;

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-pick-${tag}`, name: "Test pick" } })).id;
    swissId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: `Test Swiss ${tag}`, format: "swiss", game: "league-of-legends" } })).id;
    singleId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: `Test KO ${tag}`, format: "single_elim" } })).id;
    // Huit équipes, quatre matchs de première ronde dans le futur.
    for (let i = 0; i < 8; i++) teamIds.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Équipe ${i} ${tag}`, shortName: `E${i}` } })).id);
    for (let m = 0; m < 4; m++) {
      const event = await prisma.event.create({
        data: { id: randomUUID(), competitionId: swissId, kind: "match", name: `Round 1: E${2 * m} vs E${2 * m + 1}`, status: "scheduled", startsAt: new Date(Date.now() + (m + 1) * 3600_000), result: { seriesScore: [], games: [] } },
      });
      eventIds.push(event.id);
      await prisma.eventParticipant.createMany({
        data: [
          { id: randomUUID(), eventId: event.id, entityId: teamIds[2 * m], side: 0 },
          { id: randomUUID(), eventId: event.id, entityId: teamIds[2 * m + 1], side: 1 },
        ],
      });
    }
    account = await loginTestUser(app);
    await request(app.getHttpServer()).put("/v1/me/profile").set(account.auth).send({ pseudo: `Pick${tag}` }).expect(200);
    noPseudo = await loginTestUser(app);
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.stagePick.deleteMany({ where: { competitionId: swissId } });
    await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
    await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
    await prisma.entity.deleteMany({ where: { id: { in: teamIds } } });
    await prisma.competition.deleteMany({ where: { id: { in: [swissId, singleId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("exige un compte", async () => {
    await request(app.getHttpServer()).get(url()).expect(401);
  });

  it("les équipes sont proposées, on peut en choisir la moitié, et le pronostic se retrouve", async () => {
    const before = await request(app.getHttpServer()).get(url()).set(account.auth).expect(200);
    expect(before.body).toMatchObject({ open: true, locked: false, max: 4, picks: [], score: null });
    expect(before.body.teams).toHaveLength(8);

    const picks = teamIds.slice(0, 4);
    const saved = await request(app.getHttpServer()).put(url()).set(account.auth).send({ entityIds: picks }).expect(200);
    expect(saved.body.picks.sort()).toEqual([...picks].sort());
    expect(saved.body.score).toEqual({ correct: 0, wrong: 0, pending: 4 });

    const again = await request(app.getHttpServer()).get(url()).set(account.auth).expect(200);
    expect(again.body.picks).toHaveLength(4);
  });

  it("refuse trop d'équipes, une équipe étrangère et un compte sans pseudo", async () => {
    await request(app.getHttpServer()).put(url()).set(account.auth).send({ entityIds: teamIds.slice(0, 5) }).expect(400);
    await request(app.getHttpServer()).put(url()).set(account.auth).send({ entityIds: [randomUUID()] }).expect(400);
    await request(app.getHttpServer()).put(url()).set(noPseudo.auth).send({ entityIds: teamIds.slice(0, 2) }).expect(403);
  });

  it("une étape qui n'est pas une phase suisse n'a pas de pronostic", async () => {
    await request(app.getHttpServer()).get(`/v1/competitions/${singleId}/pick`).set(account.auth).expect(404);
  });

  it("une fois le premier match lancé, le pronostic est verrouillé côté serveur et le score se calcule", async () => {
    // Le premier match se termine : E0 bat E1.
    const first = await prisma.event.findFirstOrThrow({ where: { id: { in: eventIds } }, orderBy: { startsAt: "asc" } });
    await prisma.event.update({ where: { id: first.id }, data: { status: "finished" } });
    await prisma.eventParticipant.updateMany({ where: { eventId: first.id, entityId: teamIds[0] }, data: { isWinner: true, score: 1 } });
    await prisma.eventParticipant.updateMany({ where: { eventId: first.id, entityId: teamIds[1] }, data: { isWinner: false, score: 0 } });

    await request(app.getHttpServer()).put(url()).set(account.auth).send({ entityIds: teamIds.slice(4, 8) }).expect(409);
    const after = await request(app.getHttpServer()).get(url()).set(account.auth).expect(200);
    expect(after.body.locked).toBe(true);
    // Une victoire ne qualifie pas encore (3 victoires) : le pronostic reste à l'état « en cours ».
    expect(after.body.score).toEqual({ correct: 0, wrong: 0, pending: 4 });
  });
});
