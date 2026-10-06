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
  // `shortName` n'était jamais interrogé par sa valeur avant `by-short-name`
  // (J6) : un run précédent laissé en plan par un crash (nettoyage `afterAll`
  // jamais exécuté) peut laisser une entité "TA"/"TB" orpheline en base et
  // fausser `findFirst`. Un suffixe aléatoire, comme `categorySlug`, l'évite.
  const shortNameSuffix = randomUUID().slice(0, 4).toUpperCase();
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
      data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Champions", game: "valorant", format: "double_elim", status: "live", importance: 3 },
    });
    competitionId = competition.id;
    const teamA = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test Alpha", shortName: `TA${shortNameSuffix}` } });
    const teamB = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test Bravo", shortName: `TB${shortNameSuffix}` } });
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
            { id: randomUUID(), entityId: teamAId, side: 0, score: 1, isWinner: null },
            { id: randomUUID(), entityId: teamBId, side: 1, score: 0, isWinner: null },
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
    await prisma.providerRef.deleteMany({ where: { objectType: "entity", objectId: { in: [teamAId, teamBId] } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamAId, teamBId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    redis.disconnect();
    await app.close();
  });

  it("GET /v1/app/version donne les versions de l'appli (J21)", async () => {
    const res = await request(app.getHttpServer()).get("/v1/app/version").expect(200);
    expect(res.body.latest).toMatch(/^\d+\.\d+\.\d+/);
    expect(res.body.minSupported).toMatch(/^\d+\.\d+\.\d+/);
  });

  it("GET /health répond ok", async () => {
    await request(app.getHttpServer()).get("/health").expect(200, { status: "ok" });
  });

  it("GET /v1/home renvoie le match en direct et le prochain match, sans grande finale hors phase finale", async () => {
    const res = await request(app.getHttpServer()).get("/v1/home").expect(200);
    expect(res.body.liveNow.some((e: { id: string }) => e.id === liveEventId)).toBe(true);
    expect(res.body.upcoming.some((e: { id: string }) => e.id === upcomingEventId)).toBe(true);
    // Aucun lien de bracket : un match d'une compétition importante n'est plus un « grand rendez-vous » (J10).
    expect(res.body.grandFinals.some((f: { event: { id: string } }) => f.event.id === liveEventId)).toBe(false);
  });

  it("GET /v1/home : la grande finale (sans lien « winner » sortant, alimentée par un autre match) porte sa phrase d'enjeu — J10", async () => {
    const finalEvent = await prisma.event.create({
      data: { id: randomUUID(), competitionId, kind: "match", name: "Grand Final: TBD vs TBD", status: "scheduled", startsAt: new Date(Date.now() + 2 * 24 * 3600 * 1000), bestOf: 5, importance: 3 },
    });
    // La finale du tableau bas alimente la grande finale : elle a un lien « winner », donc n'en est pas une.
    await prisma.eventLink.create({ data: { id: randomUUID(), fromEventId: upcomingEventId, toEventId: finalEvent.id, outcome: "winner", slot: 0 } });
    await redis.del(CacheKeys.home());

    const res = await request(app.getHttpServer()).get("/v1/home").expect(200);
    const ids = res.body.grandFinals.map((f: { event: { id: string } }) => f.event.id);
    expect(ids).toContain(finalEvent.id);
    expect(ids).not.toContain(upcomingEventId);
    const final = res.body.grandFinals.find((f: { event: { id: string } }) => f.event.id === finalEvent.id);
    expect(final.stakes).toContain("sacré champion");
    expect(final.tournamentName).toBe("Test Champions"); // pas de parent : repli sur le nom de la compétition

    // Au-delà de 7 jours, la finale n'est plus proposée sur l'Accueil.
    await prisma.event.update({ where: { id: finalEvent.id }, data: { startsAt: new Date(Date.now() + 10 * 24 * 3600 * 1000) } });
    await redis.del(CacheKeys.home());
    const later = await request(app.getHttpServer()).get("/v1/home").expect(200);
    expect(later.body.grandFinals.map((f: { event: { id: string } }) => f.event.id)).not.toContain(finalEvent.id);

    await prisma.eventLink.deleteMany({ where: { toEventId: finalEvent.id } });
    await prisma.event.delete({ where: { id: finalEvent.id } });
    await redis.del(CacheKeys.home());
  });

  it("les équipes gardent leur côté (gauche/droite) quel que soit l'ordre des lignes en base — J10", async () => {
    const event = await prisma.event.create({
      data: { id: randomUUID(), competitionId, kind: "match", name: "Ordre stable", status: "scheduled", startsAt: new Date(Date.now() + 2 * 3600 * 1000), importance: 1 },
    });
    // Lignes insérées dans l'ordre inverse du côté : la droite d'abord.
    await prisma.eventParticipant.create({ data: { id: randomUUID(), eventId: event.id, entityId: teamBId, side: 1 } });
    await prisma.eventParticipant.create({ data: { id: randomUUID(), eventId: event.id, entityId: teamAId, side: 0 } });
    // Une mise à jour déplace la ligne en base : c'était la cause des équipes qui changeaient de place.
    await prisma.eventParticipant.updateMany({ where: { eventId: event.id, entityId: teamAId }, data: { score: 0 } });
    await redis.del(CacheKeys.event(event.id));

    const detail = await request(app.getHttpServer()).get(`/v1/events/${event.id}`).expect(200);
    expect(detail.body.participants.map((p: { entityId: string }) => p.entityId)).toEqual([teamAId, teamBId]);

    await prisma.eventParticipant.deleteMany({ where: { eventId: event.id } });
    await prisma.event.delete({ where: { id: event.id } });
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

  it("GET /v1/events/:id donne les chaînes de diffusion avec leur profil Twitch, et le lien « Autres streamers » (J21)", async () => {
    const login = `test_chan_${randomUUID().slice(0, 8)}`;
    const event = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test streams",
        status: "scheduled",
        result: {},
        streams: [{ channel: login, url: `https://www.twitch.tv/${login}`, language: "fr", official: true }],
      },
    });
    await prisma.streamChannel.create({ data: { login, displayName: "Test FR", imageUrl: "https://example.test/fr.png", live: true, liveCheckedAt: new Date() } });
    try {
      const res = await request(app.getHttpServer()).get(`/v1/events/${event.id}`).expect(200);
      expect(res.body.streams).toEqual([{ channel: login, url: `https://www.twitch.tv/${login}`, language: "fr", displayName: "Test FR", imageUrl: "https://example.test/fr.png", live: true }]);
      expect(res.body.moreStreamersUrl).toContain("twitch.tv/directory/category/valorant");
    } finally {
      await prisma.streamChannel.delete({ where: { login } });
    }
  });

  it("GET /v1/events/:id résout le gagnant de chaque carte depuis provider_ref (règle 6)", async () => {
    const externalTeamAId = `pandascore-team-a-${randomUUID().slice(0, 8)}`;
    await prisma.providerRef.create({
      data: {
        id: randomUUID(),
        objectType: "entity",
        objectId: teamAId,
        provider: "pandascore",
        externalId: externalTeamAId,
        lastSyncedAt: new Date(),
        payloadHash: "test",
      },
    });
    const mapsEvent = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test Alpha vs Test Bravo (cartes)",
        status: "finished",
        bestOf: 3,
        importance: 1,
        result: {
          games: [
            { position: 1, status: "finished", winnerExternalId: externalTeamAId, durationSeconds: 2201 },
            { position: 2, status: "not_started", winnerExternalId: null, durationSeconds: null },
          ],
        } as Prisma.InputJsonValue,
        participants: {
          create: [
            { id: randomUUID(), entityId: teamAId, side: 0, score: 1, isWinner: null },
            { id: randomUUID(), entityId: teamBId, side: 1, score: 0, isWinner: null },
          ],
        },
      },
    });

    const res = await request(app.getHttpServer()).get(`/v1/events/${mapsEvent.id}`).expect(200);
    expect(res.body.maps).toEqual([
      { position: 1, winnerEntityId: teamAId, durationSeconds: 2201 },
      { position: 2, winnerEntityId: null, durationSeconds: null },
    ]);

    await prisma.eventParticipant.deleteMany({ where: { eventId: mapsEvent.id } });
    await prisma.event.delete({ where: { id: mapsEvent.id } });
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

  it("GET /v1/events/:id renvoie un contexte (enjeu, forme récente, face-à-face) — J6", async () => {
    // Un match déjà terminé (Alpha bat Bravo) pour nourrir forme récente/face-à-face.
    const finishedEvent = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test Alpha vs Test Bravo (aller)",
        status: "finished",
        startsAt: new Date(Date.now() - 24 * 60 * 60 * 1000),
        bestOf: 3,
        importance: 1,
        participants: {
          create: [
            { id: randomUUID(), entityId: teamAId, side: 0, score: 2, isWinner: true },
            { id: randomUUID(), entityId: teamBId, side: 1, score: 0, isWinner: false },
          ],
        },
      },
    });

    // `GET /v1/events/:id` a déjà été appelé par des tests précédents : sans purge,
    // la réponse mise en cache (TTL 20s) ne verrait pas `finishedEvent`.
    await redis.del(CacheKeys.event(liveEventId));
    const withoutLink = await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).expect(200);
    expect(withoutLink.body.context.stakes).toBeNull(); // pas de lien de bracket : pas de phrase d'enjeu
    const formA = withoutLink.body.context.recentForm.find((f: { entityId: string }) => f.entityId === teamAId);
    const formB = withoutLink.body.context.recentForm.find((f: { entityId: string }) => f.entityId === teamBId);
    expect(formA.results).toEqual(["V"]);
    expect(formB.results).toEqual(["D"]);
    expect(withoutLink.body.context.headToHead).toEqual({ entityAId: teamAId, entityAWins: 1, entityBId: teamBId, entityBWins: 0 });

    // Un lien de bracket sortant : la phrase d'enjeu doit apparaître (contenu exact testé
    // dans packages/domain/context.spec.ts sur de vraies données de bracket).
    const finalEvent = await prisma.event.create({
      data: { id: randomUUID(), competitionId, kind: "match", name: "Grand Final: TBD vs TBD", status: "scheduled", bestOf: 5, importance: 3 },
    });
    await prisma.eventLink.create({ data: { id: randomUUID(), fromEventId: liveEventId, toEventId: finalEvent.id, outcome: "winner", slot: 0 } });

    await redis.del(CacheKeys.event(liveEventId));
    const withLink = await request(app.getHttpServer()).get(`/v1/events/${liveEventId}`).expect(200);
    expect(withLink.body.context.stakes).toContain("grande finale");

    await prisma.eventLink.deleteMany({ where: { toEventId: finalEvent.id } });
    await prisma.event.delete({ where: { id: finalEvent.id } });
    await prisma.eventParticipant.deleteMany({ where: { eventId: finishedEvent.id } });
    await prisma.event.delete({ where: { id: finishedEvent.id } });
  });

  it("GET /v1/events/:id : pas de phrase d'enjeu pour une poule GSL (lien « loser » seul, pas une grande finale)", async () => {
    const gslCategory = await prisma.category.create({ data: { id: randomUUID(), slug: `${categorySlug}-gsl`, name: "Test GSL" } });
    const gslCompetition = await prisma.competition.create({
      data: { id: randomUUID(), categoryId: gslCategory.id, kind: "tournament", name: "Test Groupe C", format: "groups_gsl", status: "live", importance: 1 },
    });
    const winnersMatch = await prisma.event.create({
      data: { id: randomUUID(), competitionId: gslCompetition.id, kind: "match", name: "Winners Match: TA vs TB", status: "scheduled", bestOf: 3, importance: 1 },
    });
    const deciderMatch = await prisma.event.create({
      data: { id: randomUUID(), competitionId: gslCompetition.id, kind: "match", name: "Decider Match: TBD vs TBD", status: "scheduled", bestOf: 3, importance: 1 },
    });
    // Le vainqueur du "Winners Match" qualifie directement (pas de lien "winner" sortant :
    // ce n'est pas pour autant une grande finale) ; seul le perdant a un lien, vers le "Decider Match".
    await prisma.eventLink.create({ data: { id: randomUUID(), fromEventId: winnersMatch.id, toEventId: deciderMatch.id, outcome: "loser", slot: 0 } });

    const res = await request(app.getHttpServer()).get(`/v1/events/${winnersMatch.id}`).expect(200);
    expect(res.body.context.stakes).toBeNull();

    await prisma.eventLink.deleteMany({ where: { toEventId: deciderMatch.id } });
    await prisma.event.deleteMany({ where: { competitionId: gslCompetition.id } });
    await prisma.competition.delete({ where: { id: gslCompetition.id } });
    await prisma.category.delete({ where: { id: gslCategory.id } });
  });

  it("GET /v1/entities/:id renvoie le bilan, la série de victoires et le prochain/dernier match — J6", async () => {
    const finishedEvent = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test Alpha vs Test Bravo (aller)",
        status: "finished",
        startsAt: new Date(Date.now() - 24 * 60 * 60 * 1000),
        bestOf: 3,
        importance: 1,
        participants: {
          create: [
            { id: randomUUID(), entityId: teamAId, side: 0, score: 2, isWinner: true },
            { id: randomUUID(), entityId: teamBId, side: 1, score: 0, isWinner: false },
          ],
        },
      },
    });

    const res = await request(app.getHttpServer()).get(`/v1/entities/${teamAId}`).expect(200);
    expect(res.body.wins).toBe(1);
    expect(res.body.losses).toBe(0);
    expect(res.body.winStreak).toBe(1);
    expect(res.body.lastEvent.id).toBe(finishedEvent.id);
    expect(res.body.nextEvent.id).toBe(liveEventId); // le match en direct est le plus proche à venir/en cours

    await request(app.getHttpServer()).get(`/v1/entities/${randomUUID()}`).expect(404);

    const byShortName = await request(app.getHttpServer()).get(`/v1/entities/by-short-name/TA${shortNameSuffix}`).expect(200);
    expect(byShortName.body.id).toBe(teamAId);
    await request(app.getHttpServer()).get("/v1/entities/by-short-name/inconnu").expect(404);

    await prisma.eventParticipant.deleteMany({ where: { eventId: finishedEvent.id } });
    await prisma.event.delete({ where: { id: finishedEvent.id } });
  });

  it("GET /v1/glossary/:term renvoie la définition, insensible à la casse, 404 si absent — J6", async () => {
    await prisma.contextSnippet.create({
      data: { targetType: "glossary", targetId: "test-terme", kind: "definition", text: "Un terme de test.", generatedBy: "editorial" },
    });

    const res = await request(app.getHttpServer()).get("/v1/glossary/Test-Terme").expect(200);
    expect(res.body).toEqual({ term: "test-terme", text: "Un terme de test." });

    await request(app.getHttpServer()).get("/v1/glossary/inconnu").expect(404);

    await prisma.contextSnippet.deleteMany({ where: { targetType: "glossary", targetId: "test-terme" } });
  });

  it("GET /v1/competitions/:id renvoie le contexte Liquipedia s'il existe, `null` sinon — J6", async () => {
    const withoutContext = await request(app.getHttpServer()).get(`/v1/competitions/${competitionId}`).expect(200);
    expect(withoutContext.body.context).toBeNull();

    await prisma.contextSnippet.create({
      data: {
        targetType: "competition",
        targetId: competitionId,
        kind: "liquipedia_intro",
        text: "Compétition organisée par Riot Games, à Shanghai.",
        source: "Liquipedia",
        license: "CC-BY-SA",
        generatedBy: "liquipedia",
      },
    });
    await redis.del(CacheKeys.competition(competitionId));

    const withContext = await request(app.getHttpServer()).get(`/v1/competitions/${competitionId}`).expect(200);
    expect(withContext.body.context).toEqual({
      text: "Compétition organisée par Riot Games, à Shanghai.",
      source: "Liquipedia",
      license: "CC-BY-SA",
    });

    await prisma.contextSnippet.deleteMany({ where: { targetType: "competition", targetId: competitionId } });
  });
});
