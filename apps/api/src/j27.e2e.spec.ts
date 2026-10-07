import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";

// Smash Ultimate (docs/04 J27) contre le vrai Postgres/Redis de dev : les joueurs d'un jeu en 1 contre 1 sont listés
// seulement s'ils ont atteint une phase à arbre (les poules en comptent des centaines).
describe("J27 : joueurs de Smash Ultimate (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  const tag = randomUUID().slice(0, 8);
  const game = "super-smash-bros-ultimate";
  let categoryId: string;
  const playerIds: string[] = [];
  const eventIds: string[] = [];

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-j27-${tag}`, name: "Test J27" } })).id;
    const league = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test Majors ${tag}`, game } });
    const serie = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: league.id, kind: "serie", name: `Test Major ${tag}`, game } });
    const top8 = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serie.id, kind: "tournament", name: "Top 8", game, hasBracket: true, format: "double_elim" } });
    const pools = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serie.id, kind: "tournament", name: "Round 1 Pools", game, hasBracket: false } });

    async function player(name: string, competitionId: string) {
      const entity = await prisma.entity.create({ data: { id: randomUUID(), kind: "player", name: `${name} ${tag}` } });
      const event = await prisma.event.create({
        data: { id: randomUUID(), competitionId, kind: "match", name: "Upper bracket final", status: "scheduled", result: { seriesScore: [], games: [] } },
      });
      await prisma.eventParticipant.create({ data: { id: randomUUID(), eventId: event.id, entityId: entity.id, side: 0 } });
      playerIds.push(entity.id);
      eventIds.push(event.id);
      return entity.id;
    }
    await player("Finaliste", top8.id);
    await player("Poule", pools.id);
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
    await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
    await prisma.entity.deleteMany({ where: { id: { in: playerIds } } });
    const competitions = await prisma.competition.findMany({ where: { categoryId }, select: { id: true } });
    await prisma.competition.updateMany({ where: { categoryId }, data: { parentId: null } });
    await prisma.competition.deleteMany({ where: { id: { in: competitions.map((c) => c.id) } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("liste les joueurs qui ont atteint une phase à arbre, pas ceux qui n'ont joué que les poules", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/entities?game=${game}`).expect(200);
    const names: string[] = res.body.map((e: { name: string }) => e.name);
    expect(names).toContain(`Finaliste ${tag}`);
    expect(names).not.toContain(`Poule ${tag}`);
  });

  it("un jeu de joueurs apparaît dans le catalogue", async () => {
    const res = await request(app.getHttpServer()).get("/v1/catalog").expect(200);
    const games: { slug: string; name: string }[] = res.body.categories.flatMap((c: { games: { slug: string; name: string }[] }) => c.games);
    expect(games.find((g) => g.slug === game)?.name).toBe("Super Smash Bros. Ultimate");
  });
});

// Fiche d'un joueur, poule, personnages par manche et pick'em d'un Top 8 (J27).
describe("J27 : fiche du joueur, poule et manches (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  const tag = randomUUID().slice(0, 8);
  const game = "super-smash-bros-ultimate";
  let categoryId: string;
  let serieId: string;
  let poolsId: string;
  let top8Id: string;
  let top64Id: string;
  const ids = { a: "", b: "", c: "", d: "" };
  const eventIds: string[] = [];
  let gfId: string;

  async function player(key: keyof typeof ids, name: string) {
    ids[key] = (await prisma.entity.create({ data: { id: randomUUID(), kind: "player", name: `${name} ${tag}` } })).id;
    await prisma.providerRef.create({ data: { id: randomUUID(), provider: "startgg", objectType: "entity", objectId: ids[key], externalId: `user:${tag}-${key}`, lastSyncedAt: new Date(), payloadHash: "t" } });
  }

  async function set(competitionId: string, name: string, p1: keyof typeof ids, p2: keyof typeof ids, winner: keyof typeof ids | null, result: object = { seriesScore: [], games: [] }) {
    const event = await prisma.event.create({
      data: { id: randomUUID(), competitionId, kind: "match", name, status: winner ? "finished" : "scheduled", startsAt: new Date("2026-10-01T10:00:00Z"), result },
    });
    for (const [side, key] of [p1, p2].entries()) {
      await prisma.eventParticipant.create({ data: { id: randomUUID(), eventId: event.id, entityId: ids[key], side, score: winner ? (key === winner ? 3 : 1) : null, isWinner: winner ? key === winner : null } });
    }
    eventIds.push(event.id);
    return event.id;
  }

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-j27b-${tag}`, name: "Test J27b" } })).id;
    const league = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test Majors B ${tag}`, game } });
    serieId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: league.id, kind: "serie", name: `Test Genesis ${tag}`, game } })).id;
    poolsId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serieId, kind: "tournament", name: "Round 1 Pools", game, hasBracket: false } })).id;
    top8Id = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serieId, kind: "tournament", name: "Top 8", game, hasBracket: true, format: "double_elim" } })).id;
    top64Id = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serieId, kind: "tournament", name: "Top 64", game, hasBracket: true, format: "double_elim" } })).id;
    for (const [key, name] of [["a", "Sonix"], ["b", "Zomba"], ["c", "Hurt"], ["d", "Monte"]] as const) await player(key, name);

    // Poule E1 : a-c, a-d ; poule E2 : b-c (a n'y est pas).
    await set(poolsId, "Winners Round 1: A vs C", "a", "c", "a", { called: false, group: "E1", seriesScore: [], games: [] });
    await set(poolsId, "Winners Round 1: A vs D", "a", "d", "a", { called: false, group: "E1", seriesScore: [], games: [] });
    await set(poolsId, "Winners Round 1: B vs C", "b", "c", "b", { called: false, group: "E2", seriesScore: [], games: [] });
    // a bat b deux fois et perd une fois : adversaire fréquent (3 rencontres).
    await set(top8Id, "Upper bracket semifinal 1: A vs B", "a", "b", "a");
    await set(top8Id, "Lower bracket final: B vs A", "b", "a", "b");
    gfId = await set(
      top8Id,
      "Grand final: A vs B",
      "a",
      "b",
      "a",
      {
        called: false,
        group: "ULT1",
        seriesScore: [],
        games: [
          { position: 1, winnerExternalId: `user:${tag}-a`, characters: { [`user:${tag}-a`]: "Sonic", [`user:${tag}-b`]: "R.O.B." } },
          { position: 2, winnerExternalId: `user:${tag}-b`, characters: { [`user:${tag}-a`]: "Sonic" } },
        ],
      },
    );
    // Un Top 64 trop grand pour un pick'em : 33 sets.
    for (let i = 0; i < 33; i++) await set(top64Id, `Upper bracket round 1 match ${i + 1}: A vs B`, "a", "b", null);
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
    await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
    await prisma.providerRef.deleteMany({ where: { objectId: { in: Object.values(ids) } } });
    await prisma.entity.deleteMany({ where: { id: { in: Object.values(ids) } } });
    const competitions = await prisma.competition.findMany({ where: { categoryId }, select: { id: true } });
    await prisma.competition.updateMany({ where: { categoryId }, data: { parentId: null } });
    await prisma.competition.deleteMany({ where: { id: { in: competitions.map((c) => c.id) } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("la fiche d'un joueur donne son bilan par tournoi et ses adversaires fréquents (deux rencontres au moins)", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/entities/${ids.a}`).expect(200);
    expect(res.body.kind).toBe("player");
    expect(res.body.tournaments).toEqual([{ competitionId: serieId, name: `Test Genesis ${tag}`, wins: 4, losses: 1 }]);
    expect(res.body.rivals).toEqual([{ entityId: ids.b, name: `Zomba ${tag}`, wins: 2, losses: 1 }]);
  });

  it("la poule d'un joueur : les sets de son groupe, pas ceux des autres groupes", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/entities/${ids.a}/pool`).expect(200);
    expect(res.body.group).toBe("E1");
    expect(res.body.phaseName).toBe("Round 1 Pools");
    expect(res.body.tournamentId).toBe(serieId);
    expect(res.body.events.map((e: { name: string }) => e.name).sort()).toEqual(["Winners Round 1: A vs C", "Winners Round 1: A vs D"]);
    // Un autre joueur du même groupe voit la même poule.
    const none = await request(app.getHttpServer()).get(`/v1/entities/${ids.d}/pool`).expect(200);
    expect(none.body.events.length).toBe(2);
  });

  it("les manches donnent leur vainqueur et le personnage de chaque joueur, jamais un identifiant start.gg", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/events/${gfId}`).expect(200);
    expect(res.body.maps[0]).toMatchObject({ position: 1, winnerEntityId: ids.a });
    expect(res.body.maps[0].characters).toEqual(expect.arrayContaining([{ entityId: ids.a, character: "Sonic" }, { entityId: ids.b, character: "R.O.B." }]));
    expect(res.body.maps[1]).toMatchObject({ position: 2, winnerEntityId: ids.b });
    expect(res.body.maps[1].characters).toEqual([{ entityId: ids.a, character: "Sonic" }]);
    expect(JSON.stringify(res.body.maps)).not.toContain("user:");
  });

  it("pick'em : un Top 8 y a droit, un Top 64 de plus de 32 sets non", async () => {
    const token = (await loginTestUser(app)).accessToken;
    await request(app.getHttpServer()).get(`/v1/competitions/${top8Id}/pickem`).set("Authorization", `Bearer ${token}`).expect(200);
    await request(app.getHttpServer()).get(`/v1/competitions/${top64Id}/pickem`).set("Authorization", `Bearer ${token}`).expect(404);
    await deleteTestUsers(prisma);
  });
});
