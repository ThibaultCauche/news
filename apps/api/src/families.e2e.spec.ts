import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import Redis from "ioredis";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";
import { CacheKeys } from "./cache/cache-keys";

// Familles de compétitions et sourdine (docs/04 J10), contre le vrai Postgres/Redis de dev.
describe("Familles et sourdine (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let redis: Redis;

  const slug = `test-fam-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let leagueId: string;
  let familyId: string;
  let champions2026: { serieId: string; eventId: string };
  let champions2027: { serieId: string; eventId: string };
  let token: string;

  async function createEdition(name: string, startsInHours: number) {
    const serie = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: leagueId, familyId, kind: "serie", name } });
    const tournament = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serie.id, kind: "tournament", name: `${name} Playoffs` } });
    const event = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId: tournament.id,
        kind: "match",
        name: `Match ${name}`,
        status: "scheduled",
        startsAt: new Date(Date.now() + startsInHours * 3600 * 1000),
        importance: 3,
      },
    });
    return { serieId: serie.id, eventId: event.id };
  }

  const auth = () => ({ Authorization: `Bearer ${token}` });

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    redis = new Redis(process.env.REDIS_URL ?? "redis://localhost:6379");

    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test familles" } })).id;
    leagueId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: "Test VCT", game: slug, importance: 3 } })).id;
    familyId = (await prisma.competitionFamily.create({ data: { id: randomUUID(), leagueId, name: "Champions" } })).id;
    champions2026 = await createEdition("Champions 2026", 5);
    champions2027 = await createEdition("Champions 2027", 48);
    await redis.del(CacheKeys.catalog());

    token = (await loginTestUser(app)).accessToken;
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    const serieIds = [champions2026.serieId, champions2027.serieId];
    const tournaments = await prisma.competition.findMany({ where: { parentId: { in: serieIds } }, select: { id: true } });
    const competitionIds = [...serieIds, ...tournaments.map((t) => t.id)];
    await prisma.event.deleteMany({ where: { competitionId: { in: competitionIds } } });
    await prisma.subscription.deleteMany({ where: { targetId: { in: [leagueId, familyId, ...serieIds] } } });
    await prisma.competition.deleteMany({ where: { id: { in: competitionIds } } });
    await prisma.competitionFamily.deleteMany({ where: { leagueId } });
    await prisma.competition.delete({ where: { id: leagueId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await redis.del(CacheKeys.catalog());
    await prisma.$disconnect();
    redis.disconnect();
    await app.close();
  });

  it("le catalogue expose les familles d'une ligue et la famille de chaque série", async () => {
    const res = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
    const league = res.body.categories
      .flatMap((c: { games: { leagues: { id: string }[] }[] }) => c.games.flatMap((g) => g.leagues))
      .find((l: { id: string }) => l.id === leagueId);
    expect(league.families).toEqual([{ id: familyId, name: "Champions" }]);
    expect(league.children.map((c: { familyId: string | null }) => c.familyId)).toEqual([familyId, familyId]);
  });

  it("le catalogue signale une ligue « en cours » d'après les dates de ses séries", async () => {
    const isLive = async () => {
      await redis.del(CacheKeys.catalog());
      const res = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
      const league = res.body.categories
        .flatMap((c: { games: { leagues: { id: string }[] }[] }) => c.games.flatMap((g) => g.leagues))
        .find((l: { id: string }) => l.id === leagueId);
      return league.live as boolean;
    };
    expect(await isLive()).toBe(false); // aucune série datée

    const hour = 3600 * 1000;
    await prisma.competition.update({
      where: { id: champions2026.serieId },
      data: { startsAt: new Date(Date.now() - hour), endsAt: new Date(Date.now() + 24 * hour) },
    });
    expect(await isLive()).toBe(true);

    await prisma.competition.update({
      where: { id: champions2026.serieId },
      data: { startsAt: new Date(Date.now() - 48 * hour), endsAt: new Date(Date.now() - 24 * hour) },
    });
    expect(await isLive()).toBe(false); // terminée
    await prisma.competition.update({ where: { id: champions2026.serieId }, data: { startsAt: null, endsAt: null } });
  });

  it("suivre une famille : nom et prochain match toutes éditions confondues", async () => {
    await request(app.getHttpServer()).post("/v1/subscriptions").set(auth()).send({ targetType: "competition_family", targetId: familyId }).expect(201);
    const list = await request(app.getHttpServer()).get("/v1/subscriptions").set(auth()).expect(200);
    const follow = list.body.find((f: { targetId: string }) => f.targetId === familyId);
    expect(follow.name).toBe("Champions");
    expect(follow.muted).toBe(false);
    expect(follow.currentEvent.id).toBe(champions2026.eventId); // le plus proche, édition 2026
  });

  it("la sourdine n'est acceptée que pour une compétition ou une famille", async () => {
    await request(app.getHttpServer()).post("/v1/subscriptions").set(auth()).send({ targetType: "event", targetId: champions2026.eventId, muted: true }).expect(400);
    await request(app.getHttpServer()).post("/v1/subscriptions").set(auth()).send({ targetType: "competition", targetId: champions2026.serieId, muted: true }).expect(201);
  });

  it("« tout sauf une » : la série en sourdine sort du prochain match de la famille et n'a pas de carte", async () => {
    const list = await request(app.getHttpServer()).get("/v1/subscriptions").set(auth()).expect(200);
    const family = list.body.find((f: { targetId: string }) => f.targetId === familyId);
    expect(family.currentEvent.id).toBe(champions2027.eventId); // Champions 2026 est en sourdine
    const muted = list.body.find((f: { targetId: string }) => f.targetId === champions2026.serieId);
    expect(muted.muted).toBe(true);
    expect(muted.currentEvent).toBeNull();
  });

  it("suivre la ligue : ses compétitions en sourdine restent exclues", async () => {
    await request(app.getHttpServer()).post("/v1/subscriptions").set(auth()).send({ targetType: "competition", targetId: leagueId }).expect(201);
    const list = await request(app.getHttpServer()).get("/v1/subscriptions").set(auth()).expect(200);
    const league = list.body.find((f: { targetId: string }) => f.targetId === leagueId);
    expect(league.currentEvent.id).toBe(champions2027.eventId);
  });

  it("J22 : « aujourd'hui dans tes suivis » et « Mes suivis » suivent la hiérarchie et la sourdine, le tournoi parent est exposé", async () => {
    await prisma.event.update({ where: { id: champions2027.eventId }, data: { startsAt: new Date(Date.now() + 6 * 3600 * 1000) } });
    await redis.del(CacheKeys.home());
    const ids = (events: { id: string }[]) => events.map((e) => e.id);

    const home = await request(app.getHttpServer()).get("/v1/home").set(auth()).expect(200);
    expect(ids(home.body.todayFollowed)).toContain(champions2027.eventId);
    expect(ids(home.body.todayFollowed)).not.toContain(champions2026.eventId); // série en sourdine
    const mine27 = home.body.todayFollowed.find((e: { id: string }) => e.id === champions2027.eventId);
    expect(mine27.competition.tournamentName).toBe("Champions 2027");

    const from = new Date(Date.now() - 24 * 3600 * 1000).toISOString();
    const to = new Date(Date.now() + 24 * 3600 * 1000).toISOString();
    const mine = await request(app.getHttpServer()).get(`/v1/agenda?from=${from}&to=${to}&mine=true`).set(auth()).expect(200);
    expect(ids(mine.body.events)).toContain(champions2027.eventId);
    expect(ids(mine.body.events)).not.toContain(champions2026.eventId);

    const all = await request(app.getHttpServer()).get(`/v1/agenda?from=${from}&to=${to}`).expect(200);
    expect(ids(all.body.events)).toContain(champions2026.eventId); // « Tout » ne dépend pas des suivis
    const guest = await request(app.getHttpServer()).get(`/v1/agenda?from=${from}&to=${to}&mine=true`).expect(200);
    expect(guest.body.events).toEqual([]);
  });
});
