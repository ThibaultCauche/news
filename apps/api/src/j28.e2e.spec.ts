import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";

// Formule 1 (docs/04 J28) contre le vrai Postgres/Redis de dev : une session est un classement de pilotes, pas un duel ;
// les listes n'en montrent que le podium, le détail porte l'arrivée complète.
describe("J28 : sessions de Formule 1 (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  const tag = randomUUID().slice(0, 8);
  const game = "formula-1";
  let categoryId: string;
  let seasonId: string;
  let gpId: string;
  let sessionId: string;
  const driverIds: string[] = [];
  const teamId = randomUUID();
  const startsAt = new Date(Date.now() + 36 * 3600_000);

  const rows = [
    { position: 1, positionText: "1", code: "AAA", number: "1", constructor: "Alpha", grid: 2, laps: 58, time: "1:30:00.000", status: "Finished", points: 25 },
    { position: 2, positionText: "2", code: "BBB", number: "2", constructor: "Alpha", grid: 1, laps: 58, time: "+1.2", status: "Finished", points: 18 },
    { position: 3, positionText: "3", code: "CCC", number: "3", constructor: "Beta", grid: 3, laps: 58, time: "+3.4", status: "Finished", points: 15 },
    { position: 4, positionText: "R", code: "DDD", number: "4", constructor: "Beta", grid: 4, laps: 20, time: null, status: "Engine", points: 0 },
  ];

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-j28-${tag}`, name: "Test J28" } })).id;
    const league = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test F1 ${tag}`, game } });
    const season = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: league.id, kind: "serie", name: `Test saison ${tag}`, game } });
    seasonId = season.id;
    const gp = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: season.id, kind: "tournament", name: `Test GP ${tag}`, game, location: "Circuit Test, Ville Test" } });
    gpId = gp.id;
    const session = await prisma.event.create({
      data: { id: randomUUID(), competitionId: gp.id, kind: "session", name: "Course", status: "finished", startsAt, result: { type: "classification", session: "race", rows } },
    });
    sessionId = session.id;
    for (const [side, row] of rows.entries()) {
      const driver = await prisma.entity.create({ data: { id: randomUUID(), kind: "driver", name: `Pilote ${row.code} ${tag}`, shortName: row.code } });
      driverIds.push(driver.id);
      await prisma.eventParticipant.create({ data: { id: randomUUID(), eventId: session.id, entityId: driver.id, side, score: row.position, isWinner: row.position === 1 } });
      await prisma.standing.create({ data: { id: randomUUID(), competitionId: season.id, entityId: driver.id, rank: row.position, points: row.points, wins: row.position === 1 ? 1 : 0 } });
    }
    await prisma.entity.create({ data: { id: teamId, kind: "constructor", name: `Alpha ${tag}` } });
    await prisma.standing.create({ data: { id: randomUUID(), competitionId: season.id, entityId: teamId, rank: 1, points: 43, wins: 1 } });
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.standing.deleteMany({ where: { competitionId: seasonId } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId: gpId } } });
    await prisma.event.deleteMany({ where: { competitionId: gpId } });
    await prisma.entity.deleteMany({ where: { id: { in: [...driverIds, teamId] } } });
    const competitions = await prisma.competition.findMany({ where: { categoryId }, select: { id: true } });
    await prisma.competition.updateMany({ where: { categoryId }, data: { parentId: null } });
    await prisma.competition.deleteMany({ where: { id: { in: competitions.map((c) => c.id) } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("le détail d'une session porte le classement complet, abandon compris", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/events/${sessionId}`).expect(200);
    expect(res.body.classification).toHaveLength(4);
    expect(res.body.classification[0]).toMatchObject({ position: 1, name: `Pilote AAA ${tag}`, code: "AAA", constructorName: "Alpha", points: 25, grid: 2, time: "1:30:00.000" });
    expect(res.body.classification[3]).toMatchObject({ position: 4, positionText: "R", status: "Engine", time: null });
    expect(res.body.classification[0].entityId).toBe(driverIds[0]);
    // Le résumé du même événement ne garde que le podium.
    expect(res.body.participants).toHaveLength(3);
  });

  it("la page d'un Grand Prix liste ses sessions avec leur podium", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${gpId}`).expect(200);
    expect(res.body.events.map((e: { name: string }) => e.name)).toEqual(["Course"]);
    expect(res.body.events[0].participants).toHaveLength(3);
    expect(res.body.location).toBe("Circuit Test, Ville Test");
  });

  it("la fiche d'un pilote donne sa place au championnat, celle d'une écurie aussi", async () => {
    const driver = await request(app.getHttpServer()).get(`/v1/entities/${driverIds[1]}`).expect(200);
    expect(driver.body.game).toBe(game);
    expect(driver.body.championships).toEqual([expect.objectContaining({ competitionId: seasonId, rank: 2, points: 18, wins: 0 })]);
    const team = await request(app.getHttpServer()).get(`/v1/entities/${teamId}`).expect(200);
    expect(team.body.kind).toBe("constructor");
    expect(team.body.championships[0]).toMatchObject({ rank: 1, points: 43, wins: 1 });
  });

  it("un duel n'a pas de classement", async () => {
    const duel = await prisma.event.create({ data: { id: randomUUID(), competitionId: gpId, kind: "match", name: "Duel", status: "scheduled", result: { seriesScore: [], games: [] } } });
    const res = await request(app.getHttpServer()).get(`/v1/events/${duel.id}`).expect(200);
    expect(res.body.classification).toEqual([]);
  });

  it("l'agenda de la catégorie ne montre que le podium d'une session", async () => {
    const from = new Date(startsAt.getTime() - 3600_000).toISOString();
    const to = new Date(startsAt.getTime() + 3600_000).toISOString();
    const res = await request(app.getHttpServer()).get(`/v1/agenda?from=${from}&to=${to}&category=test-j28-${tag}`).expect(200);
    const session = res.body.events.find((e: { id: string }) => e.id === sessionId);
    expect(session?.participants).toHaveLength(3);
  });

  it("le championnat donne pilotes et écurie avec leurs points", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${seasonId}`).expect(200);
    const drivers = res.body.standings.filter((s: { entityKind: string }) => s.entityKind === "driver");
    expect(drivers.map((s: { points: number }) => s.points)).toEqual([25, 18, 15, 0]);
    expect(res.body.standings.find((s: { entityKind: string }) => s.entityKind === "constructor")).toMatchObject({ entityName: `Alpha ${tag}`, points: 43 });
    expect(res.body.game).toBe(game);
  });

  it("l'Accueil se module selon les suivis : catégorie favorite, et suggestion d'une catégorie encore inconnue", async () => {
    const newcomer = await loginTestUser(app);
    const empty = await request(app.getHttpServer()).get("/v1/home").set(newcomer.auth).expect(200);
    // Rien de suivi : on ne sait pas ce qui plaît, donc ni préférence ni suggestion.
    expect(empty.body.favoriteCategory).toBeNull();
    expect(empty.body.suggestion).toBeNull();

    const fan = await loginTestUser(app);
    await request(app.getHttpServer()).post("/v1/subscriptions").set(fan.auth).send({ targetType: "competition", targetId: seasonId }).expect(201);
    const home = await request(app.getHttpServer()).get("/v1/home").set(fan.auth).expect(200);
    expect(home.body.favoriteCategory).toBe(`test-j28-${tag}`);
    // Une suggestion, s'il y en a une, vient d'une autre catégorie que celle déjà suivie.
    if (home.body.suggestion) expect(home.body.suggestion.category).not.toBe(home.body.favoriteCategory);

    const anonymous = await request(app.getHttpServer()).get("/v1/home").expect(200);
    expect(anonymous.body.favoriteCategory).toBeNull();
  });

  it("liste les pilotes de la F1 et le jeu apparaît au catalogue", async () => {
    const list = await request(app.getHttpServer()).get(`/v1/entities?game=${game}`).expect(200);
    const names: string[] = list.body.map((e: { name: string }) => e.name);
    expect(names).toContain(`Pilote AAA ${tag}`);
    expect(names).not.toContain(`Alpha ${tag}`);
    const catalog = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
    const games = catalog.body.categories.flatMap((c: { games: { slug: string; name: string }[] }) => c.games);
    expect(games.find((g: { slug: string }) => g.slug === game)?.name).toBe("Formule 1");
  });
});
