import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { computeLawProcess, LAW_FORMAT, LawStructure, VoteResult } from "@news/domain";
import request from "supertest";
import { CacheKeys } from "./cache/cache-keys";
import { CacheService } from "./cache/cache.service";
import { createTestApp } from "./test-utils";

// Politique (docs/04 J29) contre le vrai Postgres/Redis de dev : une loi est une compétition au format `law_process`,
// un vote est un événement dont les participants sont des groupes.
describe("J29 : lois et votes de l'Assemblée (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  const tag = randomUUID().slice(0, 8);
  const today = new Date().toISOString().slice(0, 10);
  let categoryId: string;
  let lawId: string;
  let voteId: string;
  const groupIds: string[] = [];

  const result: VoteResult = {
    numero: 900000 + Math.floor(Math.random() * 99999),
    date: today,
    sort: "adopté",
    announcement: "l'Assemblée nationale a adopté",
    voteType: "scrutin public solennel",
    pour: 312,
    contre: 198,
    abst: 41,
    nonVotants: 26,
    votants: 551,
    required: 276,
    sourceUrl: "https://www.assemblee-nationale.fr/dyn/17/scrutins/1",
    groups: [
      { id: "PO1", name: `Alpha ${tag}`, shortName: "AL", members: 100, pour: 90, contre: 2, abst: 1, nonVotants: 7, position: "pour" },
      { id: "PO2", name: `Beta ${tag}`, shortName: "BE", members: 80, pour: 3, contre: 70, abst: 2, nonVotants: 5, position: "contre" },
    ],
  };

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-j29-${tag}`, name: "Test J29" } })).id;
    const league = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: `Test AN ${tag}`, game: "assemblee-nationale" } });
    const process = computeLawProcess(
      [
        { code: "AN1-DEPOT", date: "2026-05-12" },
        { code: "AN1-COM-FOND-RAPPORT", date: "2026-06-03" },
        { code: "AN1-DEBATS-DEC", date: today, conclusion: "adoptée" },
      ],
      [{ numero: result.numero, date: today, pour: 312, contre: 198, abst: 41, sort: "adopté" }],
    );
    const structure: LawStructure = {
      process,
      officialTitle: `Proposition de loi test ${tag}`,
      lawType: "Proposition de loi",
      author: { kind: "deputy", name: "Jeanne Test", group: `Alpha ${tag}`, cosigners: 3 },
      lawNumber: null,
      legifranceUrl: null,
      sourceUrl: "https://www.assemblee-nationale.fr/dyn/17/dossiers/test",
    };
    const law = await prisma.competition.create({
      data: { id: randomUUID(), categoryId, parentId: league.id, kind: "law", name: structure.officialTitle, game: "assemblee-nationale", format: LAW_FORMAT, structure: structure as never },
    });
    lawId = law.id;
    const vote = await prisma.event.create({
      data: { id: randomUUID(), competitionId: law.id, kind: "vote", name: `L'ensemble de la proposition de loi test ${tag}`, status: "finished", startsAt: new Date(), result: result as never },
    });
    voteId = vote.id;
    for (const [side, g] of result.groups.entries()) {
      const entity = await prisma.entity.create({ data: { id: randomUUID(), kind: "party_group", name: g.name, shortName: g.shortName } });
      groupIds.push(entity.id);
      await prisma.eventParticipant.create({ data: { id: randomUUID(), eventId: vote.id, entityId: entity.id, side, score: g.pour } });
    }
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId: lawId } } });
    await prisma.event.deleteMany({ where: { competitionId: lawId } });
    await prisma.entity.deleteMany({ where: { id: { in: groupIds } } });
    const competitions = await prisma.competition.findMany({ where: { categoryId }, select: { id: true } });
    await prisma.competition.updateMany({ where: { categoryId }, data: { parentId: null } });
    await prisma.competition.deleteMany({ where: { id: { in: competitions.map((c) => c.id) } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("la page d'une loi donne les étapes du colis et rattache le vote à son écran", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${lawId}`).expect(200);
    const { law } = res.body;
    expect(law).toMatchObject({ status: "in_progress", lawType: "Proposition de loi", author: { kind: "deputy", name: "Jeanne Test", cosigners: 3 } });
    expect(law.steps.map((s: { state: string }) => s.state)).toEqual(["done", "done", "done", "current", "todo", "todo", "todo"]);
    const vote = law.steps[2].vote;
    expect(vote).toMatchObject({ eventId: voteId, sort: "adopté", sentence: "Adopté : 312 pour, 198 contre, 41 abstentions" });
  });

  it("le détail d'un vote porte les groupes avec leur position, et aucun participant « duel »", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/events/${voteId}`).expect(200);
    expect(res.body.participants).toEqual([]);
    expect(res.body.voteOutcome).toMatchObject({ sort: "adopté", pour: 312 });
    expect(res.body.vote).toMatchObject({ numero: result.numero, majority: 276, lawId, lawName: `Proposition de loi test ${tag}` });
    expect(res.body.vote.groups.map((g: { name: string; position: string }) => [g.name, g.position])).toEqual([
      [`Alpha ${tag}`, "pour"],
      [`Beta ${tag}`, "contre"],
    ]);
    expect(res.body.context).toMatchObject({ stakes: null, recentForm: [], headToHead: null });
  });

  it("la page Politique liste les votes récents et les textes en cours", async () => {
    // La page se garde 60 s dans Redis, partagé avec l'API de dev.
    await app.get(CacheService).del(CacheKeys.politics());
    const res = await request(app.getHttpServer()).get("/v1/politics").expect(200);
    expect(res.body.votes.find((v: { eventId: string }) => v.eventId === voteId)).toMatchObject({ lawId, outcome: { sentence: "Adopté : 312 pour, 198 contre, 41 abstentions" } });
    const card = res.body.inProgress.find((l: { id: string }) => l.id === lawId);
    expect(card).toMatchObject({ lawType: "Proposition de loi", stepLabel: "Examiné en commission au Sénat", lastDate: today });
  });

  it("une loi n a pas de liste de matchs et ne casse pas l Accueil", async () => {
    const res = await request(app.getHttpServer()).get(`/v1/competitions/${lawId}`).expect(200);
    expect(res.body.events).toEqual([]);
    const home = await request(app.getHttpServer()).get("/v1/home").expect(200);
    expect(home.status).toBe(200);
  });
});
