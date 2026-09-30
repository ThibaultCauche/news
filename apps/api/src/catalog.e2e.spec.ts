import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";
import { CacheKeys } from "./cache/cache-keys";
import { CacheService } from "./cache/cache.service";

// e2e (Supertest) du J9 : catalogue (onglet Compétitions), jeux favoris, équipes par jeu.
describe("Catalogue, favoris de jeu, équipes par jeu (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;

  const categorySlug = `test-cat-${randomUUID().slice(0, 8)}`;
  const emptyCategorySlug = `test-empty-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let emptyCategoryId: string;
  let leagueId: string;
  let serieId: string;
  let teamId: string;
  let otherTeamId: string;
  let eventId: string;

  beforeAll(async () => {
    app = await createTestApp();

    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: categorySlug, name: "Test catégorie" } })).id;
    emptyCategoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: emptyCategorySlug, name: "Test vide" } })).id;
    leagueId = (
      await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", game: "valorant", name: "Test Ligue", imageUrl: "https://example.test/ligue.png" } })
    ).id;
    serieId = (
      await prisma.competition.create({
        data: { id: randomUUID(), categoryId, parentId: leagueId, kind: "serie", game: "valorant", name: "Test Série 2026" },
      })
    ).id;
    teamId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test Équipe Valo" } })).id;
    otherTeamId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test Équipe Sans Jeu" } })).id;
    eventId = (
      await prisma.event.create({
        data: {
          id: randomUUID(),
          competitionId: serieId,
          kind: "match",
          name: "Test match",
          status: "scheduled",
          startsAt: new Date(Date.now() + 3600_000),
          importance: 1,
          participants: { create: [{ id: randomUUID(), entityId: teamId }] },
        },
      })
    ).id;
    // Le catalogue est mis en cache 60 s : sans ça, un serveur de dev déjà lancé masquerait nos données.
    await app.get(CacheService).del(CacheKeys.catalog());
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.eventParticipant.deleteMany({ where: { eventId } });
    await prisma.event.delete({ where: { id: eventId } });
    await prisma.competition.deleteMany({ where: { id: { in: [serieId, leagueId] } } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamId, otherTeamId] } } });
    await prisma.category.deleteMany({ where: { id: { in: [categoryId, emptyCategoryId] } } });
    await app.get(CacheService).del(CacheKeys.catalog());
    await prisma.$disconnect();
    await app.close();
  });

  const createAccount = () => loginTestUser(app);

  it("regroupe le catalogue par catégorie puis jeu, et masque les catégories sans compétition", async () => {
    const res = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
    const categories = res.body.categories as Array<{ slug: string; games: Array<{ slug: string; name: string; leagues: Array<{ id: string; imageUrl: string | null; children: Array<{ id: string }> }> }> }>;
    const category = categories.find((c) => c.slug === categorySlug);
    expect(category).toBeDefined();
    const game = category!.games.find((g) => g.slug === "valorant");
    expect(game?.name).toBe("Valorant");
    const league = game!.leagues.find((l) => l.id === leagueId);
    expect(league?.imageUrl).toBe("https://example.test/ligue.png");
    expect(league?.children.map((c) => c.id)).toEqual([serieId]);
    expect(categories.find((c) => c.slug === emptyCategorySlug)).toBeUndefined();
  });

  it("met un jeu en favori sans créer d'abonnement, de façon idempotente et isolée par compte", async () => {
    const alice = await createAccount();
    const bob = await createAccount();
    const auth = (token: string) => ({ Authorization: `Bearer ${token}` });

    await request(app.getHttpServer()).put("/v1/favorites/games/valorant").set(auth(alice.accessToken)).expect(204);
    await request(app.getHttpServer()).put("/v1/favorites/games/valorant").set(auth(alice.accessToken)).expect(204);

    const aliceList = await request(app.getHttpServer()).get("/v1/favorites/games").set(auth(alice.accessToken)).expect(200);
    expect(aliceList.body).toEqual([{ game: "valorant" }]);
    const bobList = await request(app.getHttpServer()).get("/v1/favorites/games").set(auth(bob.accessToken)).expect(200);
    expect(bobList.body).toEqual([]);
    expect(await prisma.subscription.count({ where: { userId: alice.userId } })).toBe(0);

    await request(app.getHttpServer()).delete("/v1/favorites/games/valorant").set(auth(alice.accessToken)).expect(204);
    const after = await request(app.getHttpServer()).get("/v1/favorites/games").set(auth(alice.accessToken)).expect(200);
    expect(after.body).toEqual([]);
  });

  it("refuse un jeu inconnu et l'accès sans jeton, et supprime les favoris avec le compte", async () => {
    const carol = await createAccount();
    await request(app.getHttpServer()).put("/v1/favorites/games/valorant").expect(401);
    await request(app.getHttpServer()).put("/v1/favorites/games/inconnu").set("Authorization", `Bearer ${carol.accessToken}`).expect(400);

    await request(app.getHttpServer()).put("/v1/favorites/games/valorant").set("Authorization", `Bearer ${carol.accessToken}`).expect(204);
    await request(app.getHttpServer()).delete("/v1/me").set("Authorization", `Bearer ${carol.accessToken}`).expect(204);
    expect(await prisma.favoriteGame.count({ where: { userId: carol.userId } })).toBe(0);
  });

  it("liste les équipes ayant joué dans un jeu, et refuse un jeu inconnu", async () => {
    const res = await request(app.getHttpServer()).get("/v1/entities?game=valorant").expect(200);
    const ids = (res.body as Array<{ id: string }>).map((e) => e.id);
    expect(ids).toContain(teamId);
    expect(ids).not.toContain(otherTeamId);
    await request(app.getHttpServer()).get("/v1/entities?game=inconnu").expect(400);
  });
});
