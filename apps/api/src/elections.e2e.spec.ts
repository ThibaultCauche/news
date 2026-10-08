import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { ElectionResult } from "@news/domain";
import request from "supertest";
import { CacheKeys } from "./cache/cache-keys";
import { CacheService } from "./cache/cache.service";
import { createTestApp } from "./test-utils";

// Seule l'horloge est truquée : le reste (réseau, base, temporisateurs) tourne pour de vrai.
const REAL_TIMERS = ["hrtime", "nextTick", "performance", "queueMicrotask", "requestAnimationFrame", "cancelAnimationFrame", "requestIdleCallback", "cancelIdleCallback", "setImmediate", "clearImmediate", "setInterval", "clearInterval", "setTimeout", "clearTimeout"] as const;
const clockAt = (iso: string) => jest.useFakeTimers({ now: new Date(iso), doNotFake: [...REAL_TIMERS] });

// Résultats d'élections (docs/04 J29c) contre le vrai Postgres/Redis de dev. Article L52-2 : le jour du scrutin, avant 20 h
// à Paris, l'API ne renvoie aucun résultat, par aucun chemin.
describe("J29c : élections et blocage avant 20 h (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  const tag = randomUUID().slice(0, 8);
  let categoryId: string;
  let electionId: string;
  let resultId: string;
  let nationalId: string;
  const server = () => app.getHttpServer();

  // Présidentielle 2027, 1ᵉʳ tour : dimanche 18 avril, blocage levé à 20 h, heure de Paris = 18 h UTC.
  const result: ElectionResult = {
    type: "election_result",
    electionId: "presidentielle-2027-t1",
    date: "2027-04-18",
    level: "commune",
    candidates: false,
    bureaux: { counted: 9, total: 10 },
    territory: { code: `T${tag}`, name: `Ville ${tag}`, department: "Département test" },
    registered: 10_000,
    voters: 6_100,
    turnoutPct: 61,
    blank: 100,
    nulls: 50,
    expressed: 5_950,
    complete: true,
    sourceUrl: "https://static.data.gouv.fr/test.csv",
    lists: [
      { panel: 2, label: "Liste B", head: "Jeanne Dupont", votes: 3_000, pctExpressed: 50.42, elected: false, seatsCouncil: 17, seatsCommunity: 3 },
      { panel: 1, label: "Liste A", head: null, votes: 2_950, pctExpressed: 49.58, elected: false, seatsCouncil: 16, seatsCommunity: 2 },
    ],
  };

  const clearCaches = () => app.get(CacheService).del(CacheKeys.event(resultId), CacheKeys.competition(electionId), CacheKeys.politics());

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-j29c-${tag}`, name: "Test J29c" } })).id;
    const election = await prisma.competition.create({
      data: { id: randomUUID(), categoryId, kind: "election", name: `Test présidentielle ${tag}`, game: "elections", format: "live_feed", structure: { electionId: "presidentielle-2027-t1" } },
    });
    electionId = election.id;
    const event = await prisma.event.create({
      data: { id: randomUUID(), competitionId: election.id, kind: "election_result", name: result.territory.name, status: "finished", startsAt: new Date("2027-04-18T18:00:00Z"), result: result as never },
    });
    resultId = event.id;
    // La France entière : candidats, pas de sièges.
    const national: ElectionResult = {
      ...result,
      level: "national",
      candidates: true,
      bureaux: null,
      territory: { code: "FE", name: "France entière", department: "France" },
      lists: [
        { panel: 3, label: "Candidat B", head: null, votes: 9_000_000, pctExpressed: 27.9, elected: false, seatsCouncil: 0, seatsCommunity: 0 },
        { panel: 5, label: "Candidate A", head: null, votes: 8_100_000, pctExpressed: 23.1, elected: false, seatsCouncil: 0, seatsCommunity: 0 },
      ],
    };
    nationalId = (await prisma.event.create({ data: { id: randomUUID(), competitionId: election.id, kind: "election_result", name: "France entière", status: "finished", startsAt: new Date("2027-04-18T18:00:00Z"), result: national as never } })).id;
  });

  afterAll(async () => {
    jest.useRealTimers();
    await prisma.event.deleteMany({ where: { competitionId: electionId } });
    await prisma.competition.deleteMany({ where: { categoryId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  afterEach(() => jest.useRealTimers());

  it("le jour du scrutin avant 20 h, le détail d'un territoire ne contient aucun résultat, ni brut ni structuré", async () => {
    clockAt("2027-04-18T17:59:00Z");
    await clearCaches();
    const res = await request(server()).get(`/v1/events/${resultId}`).expect(200);
    expect(res.body.election).toMatchObject({ embargoed: true, liftsAt: "2027-04-18T18:00:00.000Z", result: null });
    expect(res.body.result).toEqual({});
    expect(JSON.stringify(res.body)).not.toContain("Liste B");
    expect(JSON.stringify(res.body)).not.toContain("3000");
  });

  it("la page de l'élection ne liste aucun territoire tant que le blocage court", async () => {
    clockAt("2027-04-18T09:00:00Z");
    await clearCaches();
    const res = await request(server()).get(`/v1/competitions/${electionId}`).expect(200);
    expect(res.body.election).toMatchObject({ embargoed: true, national: null, territories: [], date: "2027-04-18", type: "presidentielle", round: 1, hasResults: false });
  });

  it("à 20 h pile, les résultats sont publics : participation, listes, sièges et majorité", async () => {
    clockAt("2027-04-18T18:00:00Z");
    await clearCaches();
    const res = await request(server()).get(`/v1/events/${resultId}`).expect(200);
    expect(res.body.election).toMatchObject({ embargoed: false, name: "Présidentielle 2027 · 1ᵉʳ tour" });
    expect(res.body.election.result).toMatchObject({ territoryName: result.territory.name, turnoutPct: 61, totalSeats: 33, majoritySeats: 17, complete: true });
    expect(res.body.election.result.lists.map((l: { label: string }) => l.label)).toEqual(["Liste B", "Liste A"]);

    const page = await request(server()).get(`/v1/competitions/${electionId}`).expect(200);
    // La France entière a sa propre carte : elle ne se mêle pas à la liste des territoires.
    expect(page.body.election.territories).toEqual([expect.objectContaining({ eventId: resultId, level: "commune", leaderLabel: "Liste B", leaderPct: 50.42, turnoutPct: 61 })]);
    expect(page.body.election.national).toMatchObject({ level: "national", candidates: true, totalSeats: 0, majoritySeats: null });
    expect(page.body.election.national.lists.map((l: { label: string }) => l.label)).toEqual(["Candidat B", "Candidate A"]);
    expect(res.body.election.result.bureaux).toEqual({ counted: 9, total: 10 });
  });

  it("la veille du scrutin il n'y a rien à bloquer, et la page Politique annonce le scrutin avec l'heure de levée", async () => {
    clockAt("2027-04-17T10:00:00Z");
    await clearCaches();
    const res = await request(server()).get("/v1/politics").expect(200);
    const card = res.body.elections.find((e: { competitionId: string }) => e.competitionId === electionId);
    expect(card).toMatchObject({ date: "2027-04-18", embargoed: false, phase: "upcoming", liftsAt: "2027-04-18T18:00:00.000Z" });
  });

  it("le soir du scrutin la page Politique dit « ce soir », avec le blocage actif avant 20 h", async () => {
    clockAt("2027-04-18T12:00:00Z");
    await clearCaches();
    const res = await request(server()).get("/v1/politics").expect(200);
    expect(res.body.elections.find((e: { competitionId: string }) => e.competitionId === electionId)).toMatchObject({ phase: "tonight", embargoed: true });
  });

  it("un résultat d'élection n'a ni participants ni score de vote : rien à notifier ni à afficher en match", async () => {
    clockAt("2027-04-19T12:00:00Z");
    await clearCaches();
    const res = await request(server()).get(`/v1/events/${resultId}`).expect(200);
    expect(res.body.participants).toEqual([]);
    expect(res.body.voteOutcome).toBeNull();
  });
});
