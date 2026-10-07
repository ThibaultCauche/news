import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import Redis from "ioredis";
import request from "supertest";
import { CacheKeys } from "./cache/cache-keys";
import { createTestApp } from "./test-utils";

// Une compétition passée et vide n'apparaît ni dans le catalogue ni comme étape « déjà jouée » (J23).
describe("Compétitions passées et vides (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let redis: Redis;

  const slug = `test-past-${randomUUID().slice(0, 8)}`;
  const day = 24 * 3600 * 1000;
  let categoryId: string;
  let leagueId: string;
  let emptyLeagueId: string;
  let championId = "";
  const teamIds: string[] = [];
  let ids: { pastEmpty: string; pastPlayed: string; futureEmpty: string; noDates: string; onlyOld: string; tournament: string };

  const catalogLeagues = async () => {
    await redis.del(CacheKeys.catalog());
    const res = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
    return res.body.categories
      .flatMap((c: { games: { leagues: { id: string; children: { id: string }[] }[] }[] }) => c.games.flatMap((g) => g.leagues))
      .filter((l: { id: string }) => [leagueId, emptyLeagueId].includes(l.id)) as { id: string; children: { id: string }[] }[];
  };

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    redis = new Redis(process.env.REDIS_URL ?? "redis://localhost:6379");
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test passées" } })).id;
    leagueId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test Ligue ${slug}`, game: slug } })).id;
    emptyLeagueId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test Ancienne ${slug}`, game: slug } })).id;
    const serie = (name: string, parentId: string, startsAt: Date | null, endsAt: Date | null) =>
      prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId, kind: "serie", name, game: slug, startsAt, endsAt } }).then((c) => c.id);
    ids = {
      pastEmpty: await serie("Ancienne vide", leagueId, new Date(Date.now() - 90 * day), new Date(Date.now() - 80 * day)),
      pastPlayed: await serie("Récente jouée", leagueId, new Date(Date.now() - 20 * day), new Date(Date.now() - 10 * day)),
      futureEmpty: await serie("À venir vide", leagueId, new Date(Date.now() + 10 * day), new Date(Date.now() + 20 * day)),
      noDates: await serie("Sans dates", leagueId, null, null),
      onlyOld: await serie("Seule ancienne", emptyLeagueId, new Date(Date.now() - 200 * day), new Date(Date.now() - 190 * day)),
      tournament: "",
    };
    ids.tournament = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: ids.pastPlayed, kind: "tournament", name: "Playoffs", game: slug } })).id;
    const event = await prisma.event.create({
      data: { id: randomUUID(), competitionId: ids.tournament, kind: "match", name: "Match", status: "finished", startsAt: new Date(Date.now() - 11 * day), result: { seriesScore: [], games: [] } },
    });
    championId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Champion ${slug}`, shortName: "CHP" } })).id;
    const loserId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Perdant ${slug}`, shortName: "PER" } })).id;
    teamIds.push(championId, loserId);
    await prisma.eventParticipant.createMany({
      data: [
        { id: randomUUID(), eventId: event.id, entityId: championId, side: 0, score: 3, isWinner: true },
        { id: randomUUID(), eventId: event.id, entityId: loserId, side: 1, score: 0, isWinner: false },
      ],
    });
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId: ids.tournament } } });
    await prisma.event.deleteMany({ where: { competitionId: ids.tournament } });
    await prisma.entity.deleteMany({ where: { id: { in: teamIds } } });
    await prisma.competition.deleteMany({ where: { parentId: { in: [ids.pastPlayed] } } });
    await prisma.competition.deleteMany({ where: { parentId: { in: [leagueId, emptyLeagueId] } } });
    await prisma.competition.deleteMany({ where: { id: { in: [leagueId, emptyLeagueId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await redis.del(CacheKeys.catalog());
    await prisma.$disconnect();
    redis.disconnect();
    await app.close();
  });

  it("le catalogue garde les séries jouées, à venir ou sans dates, et retire la passée vide", async () => {
    const leagues = await catalogLeagues();
    const league = leagues.find((l) => l.id === leagueId)!;
    expect(league.children.map((c) => c.id).sort()).toEqual([ids.pastPlayed, ids.futureEmpty, ids.noDates].sort());
  });

  it("une série terminée porte son champion : le vainqueur de son dernier match", async () => {
    await redis.del(CacheKeys.catalog());
    const res = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
    const league = res.body.categories
      .flatMap((c: { games: { leagues: { id: string; children: { id: string; champion: { name: string } | null }[] }[] }[] }) => c.games.flatMap((g) => g.leagues))
      .find((l: { id: string }) => l.id === leagueId);
    const byId = Object.fromEntries(league.children.map((c: { id: string; champion: { name: string } | null }) => [c.id, c.champion]));
    expect(byId[ids.pastPlayed]).toMatchObject({ name: `Champion ${slug}`, shortName: "CHP" });
    expect(byId[ids.futureEmpty]).toBeNull();
  });

  it("une ligue dont toutes les séries sont passées et vides disparaît du catalogue", async () => {
    const leagues = await catalogLeagues();
    expect(leagues.map((l) => l.id)).toEqual([leagueId]);
  });

  it("la page d'une ligue indique quelles étapes ont des matchs", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${leagueId}`).expect(200);
    const has = Object.fromEntries(res.body.children.map((c: { id: string; hasEvents: boolean }) => [c.id, c.hasEvents]));
    expect(has[ids.pastPlayed]).toBe(true);
    expect(has[ids.pastEmpty]).toBe(false);
    expect(has[ids.futureEmpty]).toBe(false);
  });
});
