import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";

// League of Legends (docs/04 J23) contre le vrai Postgres/Redis de dev : classement global, structure suivie
// dans deux jeux, phrases d'enjeu de la phase suisse.
describe("J23 : classement global et structures (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let token: string;

  const tag = randomUUID().slice(0, 8);
  let categoryId: string;
  let serieId: string;
  let swissId: string;
  let playoffsId: string;
  let valorantTeamId: string;
  let lolTeamId: string;
  let organizationId: string;
  const teamIds: Record<string, string> = {};
  const eventIds: string[] = [];

  async function team(code: string) {
    const entity = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Test ${code} ${tag}`, shortName: code } });
    teamIds[code] = entity.id;
    return entity.id;
  }

  async function match(competitionId: string, winner: string, loser: string, startsAt: Date, name = "Match") {
    const event = await prisma.event.create({
      data: { id: randomUUID(), competitionId, kind: "match", name, status: "finished", startsAt, bestOf: 3, result: { seriesScore: [], games: [] } },
    });
    await prisma.eventParticipant.createMany({
      data: [
        { id: randomUUID(), eventId: event.id, entityId: teamIds[winner], side: 0, score: 2, isWinner: true },
        { id: randomUUID(), eventId: event.id, entityId: teamIds[loser], side: 1, score: 0, isWinner: false },
      ],
    });
    eventIds.push(event.id);
    return event.id;
  }

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-j23-${tag}`, name: "Test J23" } })).id;
    const league = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test Worlds ${tag}`, game: "league-of-legends" } });
    serieId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: league.id, kind: "serie", name: `Test Worlds 2026 ${tag}` } })).id;
    swissId = (
      await prisma.competition.create({
        data: { id: randomUUID(), categoryId, parentId: serieId, kind: "tournament", game: "league-of-legends", name: "Group Stage", format: "swiss", status: "finished", startsAt: new Date("2026-10-01") },
      })
    ).id;
    playoffsId = (
      await prisma.competition.create({
        data: { id: randomUUID(), categoryId, parentId: serieId, kind: "tournament", game: "league-of-legends", name: "Playoffs", format: "single_elim", status: "finished", startsAt: new Date("2026-10-20") },
      })
    ).id;
    for (const code of ["AAA", "BBB", "CCC", "DDD"]) await team(code);
    // Phase suisse : AAA gagne trois fois (qualifiée) ; DDD perd trois fois (éliminée).
    await match(swissId, "AAA", "DDD", new Date("2026-10-01T10:00:00Z"), "Round 1: AAA vs DDD");
    await match(swissId, "AAA", "BBB", new Date("2026-10-02T10:00:00Z"), "Round 2: AAA vs BBB");
    await match(swissId, "AAA", "CCC", new Date("2026-10-03T10:00:00Z"), "Round 3: AAA vs CCC");
    await match(swissId, "BBB", "DDD", new Date("2026-10-02T12:00:00Z"));
    await match(swissId, "CCC", "DDD", new Date("2026-10-03T12:00:00Z"));
    // Phase finale : AAA championne contre BBB.
    await match(playoffsId, "AAA", "BBB", new Date("2026-10-20T10:00:00Z"), "Final");

    // Une structure avec une équipe par jeu.
    const orgKey = `test-org-${tag}`;
    organizationId = (await prisma.organization.create({ data: { id: randomUUID(), key: orgKey, name: `Test Org ${tag}` } })).id;
    const valorant = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test VCT ${tag}`, game: "valorant" } });
    valorantTeamId = await team("VAL");
    lolTeamId = await team("LOL");
    await prisma.entity.updateMany({ where: { id: { in: [valorantTeamId, lolTeamId] } }, data: { organizationId } });
    const valEvent = await prisma.event.create({ data: { id: randomUUID(), competitionId: valorant.id, kind: "match", name: "Val", status: "scheduled", startsAt: new Date(Date.now() + 3600_000) } });
    const lolEvent = await prisma.event.create({ data: { id: randomUUID(), competitionId: swissId, kind: "match", name: "Lol", status: "scheduled", startsAt: new Date(Date.now() + 7200_000) } });
    await prisma.eventParticipant.createMany({
      data: [
        { id: randomUUID(), eventId: valEvent.id, entityId: valorantTeamId, side: 0 },
        { id: randomUUID(), eventId: lolEvent.id, entityId: lolTeamId, side: 0 },
      ],
    });
    eventIds.push(valEvent.id, lolEvent.id);
    token = (await loginTestUser(app)).accessToken;
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    const ids = Object.values(teamIds);
    await prisma.subscription.deleteMany({ where: { targetId: { in: [...ids, organizationId] } } });
    await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
    await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
    await prisma.entity.deleteMany({ where: { id: { in: ids } } });
    await prisma.organization.deleteMany({ where: { id: organizationId } });
    const competitions = await prisma.competition.findMany({ where: { categoryId }, select: { id: true } });
    await prisma.competition.updateMany({ where: { categoryId }, data: { parentId: null } });
    await prisma.event.deleteMany({ where: { competitionId: { in: competitions.map((c) => c.id) } } });
    await prisma.competition.deleteMany({ where: { categoryId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("classement global d'une série : championne, finaliste, éliminée en phase suisse", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${serieId}/ranking`).expect(200);
    expect(res.body.finished).toBe(true);
    const byShort = Object.fromEntries(res.body.entries.map((e: { shortName: string }) => [e.shortName, e]));
    expect(res.body.entries[0].shortName).toBe("AAA");
    expect(byShort.AAA).toMatchObject({ status: "champion", stage: "Playoffs", rank: 1 });
    expect(byShort.BBB).toMatchObject({ status: "eliminated", stage: "Playoffs" });
    expect(byShort.DDD).toMatchObject({ status: "eliminated", stage: "Group Stage", stageFormat: "swiss", wins: 0, losses: 3 });
  });

  it("une compétition inconnue renvoie 404", async () => {
    await request(app.getHttpServer()).get(`/v1/competitions/${randomUUID()}/ranking`).expect(404);
  });

  it("la fiche d'une équipe annonce sa structure quand elle a des équipes dans deux jeux", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/entities/${lolTeamId}`).expect(200);
    expect(res.body.game).toBe("league-of-legends");
    expect(res.body.organization).toMatchObject({ id: organizationId, teamCount: 2, games: ["league-of-legends", "valorant"] });
  });

  it("suivre toute la structure abonne à ses équipes des deux jeux, et s'arrête d'un coup", async () => {
    const auth = { Authorization: `Bearer ${token}` };
    await request(app.getHttpServer()).post("/v1/subscriptions").set(auth).send({ targetType: "organization", targetId: organizationId }).expect(201);
    const followed = async () =>
      (await request(app.getHttpServer()).get("/v1/subscriptions").set(auth).expect(200)).body as { targetType: string; targetId: string; name: string }[];
    let subs = await followed();
    expect(subs.filter((s) => s.targetType === "entity").map((s) => s.targetId).sort()).toEqual([valorantTeamId, lolTeamId].sort());
    expect(subs.find((s) => s.targetType === "organization")?.name).toBe(`Test Org ${tag}`);

    await request(app.getHttpServer()).delete("/v1/subscriptions").set(auth).send({ targetType: "organization", targetId: organizationId }).expect(204);
    subs = await followed();
    expect(subs).toEqual([]);
  });

  it("suivre une structure sans équipe est refusé", async () => {
    const auth = { Authorization: `Bearer ${token}` };
    const empty = await prisma.organization.create({ data: { id: randomUUID(), key: `test-empty-${tag}`, name: "Vide" } });
    await request(app.getHttpServer()).post("/v1/subscriptions").set(auth).send({ targetType: "organization", targetId: empty.id }).expect(404);
    await prisma.subscription.deleteMany({ where: { targetId: empty.id } });
    await prisma.organization.delete({ where: { id: empty.id } });
  });

  it("l'écran d'un match de phase suisse explique l'enjeu selon le bilan", async () => {
    const lolEvent = await prisma.event.findFirst({ where: { name: "Lol", competitionId: swissId } });
    const res = await request(app.getHttpServer()).get(`/v1/events/${lolEvent!.id}`).expect(200);
    expect(res.body.context.stakes).toContain("phase suisse");
  });
});
