import { randomUUID } from "node:crypto";
import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { Prisma, PrismaClient } from "@news/db";
import { DOMAIN_EVENTS_CHANNEL } from "@news/domain";
import Redis from "ioredis";
import request from "supertest";
import { AppModule } from "./app.module";
import { CacheKeys } from "./cache/cache-keys";

// e2e (Supertest) contre le vrai Postgres/Redis de dev (`docker compose -f
// infra/docker-compose.dev.yml up`) : données seedées directement en Prisma,
// sans rejouer une ingestion PandaScore complète (docs/04 J2).
describe("API v1 (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let redis: Redis;

  const categorySlug = `test-esport-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  let teamAId: string;
  let teamBId: string;
  let liveEventId: string;
  let upcomingEventId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1", { exclude: ["health"] });
    app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true }));
    await app.init();

    prisma = new PrismaClient();
    redis = new Redis(process.env.REDIS_URL ?? "redis://localhost:6379");

    const category = await prisma.category.create({ data: { id: randomUUID(), slug: categorySlug, name: "Test e-sport" } });
    categoryId = category.id;
    const competition = await prisma.competition.create({
      data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Champions", format: "double_elim", status: "live", importance: 3 },
    });
    competitionId = competition.id;
    const teamA = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test Alpha", shortName: "TA" } });
    const teamB = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test Bravo", shortName: "TB" } });
    teamAId = teamA.id;
    teamBId = teamB.id;

    const now = Date.now();
    const liveEvent = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test Alpha vs Test Bravo",
        status: "live",
        startsAt: new Date(now - 10 * 60 * 1000),
        bestOf: 3,
        importance: 3,
        result: { seriesScore: [{ team_id: teamAId, score: 1 }] } as Prisma.InputJsonValue,
        participants: {
          create: [
            { id: randomUUID(), entityId: teamAId, score: 1, isWinner: null },
            { id: randomUUID(), entityId: teamBId, score: 0, isWinner: null },
          ],
        },
      },
    });
    liveEventId = liveEvent.id;

    const upcomingEvent = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test Alpha vs Test Bravo (retour)",
        status: "scheduled",
        startsAt: new Date(now + 60 * 60 * 1000),
        bestOf: 3,
        importance: 1,
      },
    });
    upcomingEventId = upcomingEvent.id;

    // Le cache "home" est partagé (pas de clé par id) : on le vide pour ne pas
    // hériter d'une réponse mise en cache avant que nos données existent.
    await redis.del(CacheKeys.home());
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamAId, teamBId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    redis.disconnect();
    await app.close();
  });

  it("GET /health répond ok", async () => {
    await request(app.getHttpServer()).get("/health").expect(200, { status: "ok" });
  });

  it("GET /v1/home renvoie le match en direct, le prochain match et le grand rendez-vous", async () => {
    const res = await request(app.getHttpServer()).get("/v1/home").expect(200);
    expect(res.body.liveNow.some((e: { id: string }) => e.id === liveEventId)).toBe(true);
    expect(res.body.upcoming.some((e: { id: string }) => e.id === upcomingEventId)).toBe(true);
    expect(res.body.highlights.some((e: { id: string }) => e.id === liveEventId)).toBe(true);
  });

  it("GET /v1/agenda?from&to renvoie les événements de la fenêtre, 400 sans bornes", async () => {
    const from = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const to = new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString();
    const res = await request(app.getHttpServer()).get(`/v1/agenda?from=${from}&to=${to}`).expect(200);
    const ids = res.body.events.map((e: { id: string }) => e.id);
    expect(ids).toEqual(expect.arrayContaining([liveEventId, upcomingEventId]));

    await request(app.getHttpServer()).get("/v1/agenda").expect(400);
  });

  it("GET /v1/events/:id renvoie le score de série et 404 si absent", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).expect(200);
    expect(res.body.participants).toHaveLength(2);
    expect((res.body.result as { seriesScore: unknown[] }).seriesScore).toHaveLength(1);

    await request(app.getHttpServer()).get(`/v1/events/${randomUUID()}`).expect(404);
  });

  it("un deuxième appel identique renvoie 304 grâce à l'ETag", async () => {
    const first = await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).expect(200);
    const etag = first.headers.etag as string;
    expect(etag).toBeTruthy();
    await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).set("If-None-Match", etag).expect(304);
  });

  it("GET /v1/competitions/:id renvoie l'en-tête, la frise et des standings vides au J2", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${competitionId}`).expect(200);
    expect(res.body.name).toBe("Test Champions");
    expect(res.body.standings).toEqual([]);
  });

  it("GET /v1/competitions/:id/bracket renvoie les nœuds (avec leur round) et les liens de bracket (J5)", async () => {
    const finalEvent = await prisma.event.create({
      data: { id: randomUUID(), competitionId, kind: "match", name: "Grande finale", status: "scheduled", bestOf: 5, importance: 3 },
    });
    await prisma.eventLink.create({ data: { id: randomUUID(), fromEventId: liveEventId, toEventId: finalEvent.id, outcome: "winner", slot: 0 } });

    const res = await request(app.getHttpServer()).get(`/v1/competitions/${competitionId}/bracket`).expect(200);
    expect(res.body.format).toBe("double_elim");
    const finalNode = res.body.nodes.find((n: { eventId: string }) => n.eventId === finalEvent.id);
    const liveNode = res.body.nodes.find((n: { eventId: string }) => n.eventId === liveEventId);
    expect(finalNode.round).toBe(0); // la finale n'alimente aucun autre match : centre de l'arbre
    expect(liveNode.round).toBe(1);
    expect(res.body.links).toContainEqual({ fromEventId: liveEventId, toEventId: finalEvent.id, outcome: "winner", slot: 0 });

    await prisma.eventLink.deleteMany({ where: { toEventId: finalEvent.id } });
    await prisma.event.delete({ where: { id: finalEvent.id } });
  });

  it("un changement de score côté worker invalide le cache de l'événement", async () => {
    const before = await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).expect(200);
    expect(before.body.result.seriesScore[0].score).toBe(1);

    // Simule ce que fait le worker : écrire le nouveau score puis publier
    // l'événement métier (docs/03 §3), sans rejouer une vraie ingestion.
    await prisma.event.update({
      where: { id: liveEventId },
      data: { result: { seriesScore: [{ team_id: teamAId, score: 2 }] } as Prisma.InputJsonValue },
    });
    await redis.publish(DOMAIN_EVENTS_CHANNEL, JSON.stringify({ type: "ScoreChanged", eventId: liveEventId, competitionId }));

    await new Promise((resolve) => setTimeout(resolve, 200));

    const after = await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).expect(200);
    expect(after.body.result.seriesScore[0].score).toBe(2);
  });
});
