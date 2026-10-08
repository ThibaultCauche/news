import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { quizDay } from "@news/domain";
import request from "supertest";
import { CacheService } from "./cache/cache.service";
import { createTestApp, deleteTestUsers, loginTestUser, TestAccount } from "./test-utils";

type Question = { id: string; eventId: string; groupName: string; choices: string[]; myChoice: string | null; myCorrect: boolean | null };

// Quiz « Qui a voté ? » (docs/04 J29b) contre le vrai Postgres/Redis de dev et les votes ingérés de l'Assemblée : le
// serveur tire les cinq questions du jour, corrige, et ne dévoile la bonne réponse qu'avec la correction.
// ponytail: en CI la base est vide (aucun vote ingéré), ces tests ne tournent qu'en local ; ajouter des votes de test pour la CI.
const it = process.env.CI ? globalThis.it.skip : globalThis.it;

describe("J29b : quiz « Qui a voté ? » (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let me: TestAccount;
  const server = () => app.getHttpServer();

  const today = async () => (await request(server()).get("/v1/politics/quiz").expect(200)).body;
  // La bonne réponse d'une question, lue dans le détail du vote (position du groupe) comme le ferait un tricheur.
  const rightAnswer = async (q: Question) => {
    const vote = (await request(server()).get(`/v1/events/${q.eventId}`).expect(200)).body.vote;
    return vote.groups.find((g: { name: string }) => g.name === q.groupName).position as string;
  };

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    await app.get(CacheService).del(`cache:v1:quiz:${quizDay(new Date())}`);
    me = await loginTestUser(app);
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.$disconnect();
    await app.close();
  });

  it("donne cinq questions sans jamais dévoiler la réponse", async () => {
    const quiz = await today();
    expect(quiz).toMatchObject({ signedIn: false, answered: 0, streak: 0 });
    expect(quiz.questions).toHaveLength(5);
    expect(new Set(quiz.questions.map((q: Question) => q.groupName)).size).toBe(5);
    for (const q of quiz.questions as Question[]) {
      expect(q.choices).toEqual(["pour", "contre", "abstention"]);
      expect(q.myChoice).toBeNull();
      expect(Object.keys(q)).not.toContain("answer");
    }
  });

  it("deux visiteurs ont les mêmes questions le même jour", async () => {
    const [a, b] = [await today(), await today()];
    expect(a.questions.map((q: Question) => q.id)).toEqual(b.questions.map((q: Question) => q.id));
  });

  it("sans compte, la réponse est corrigée avec sa source mais pas gardée", async () => {
    const [q] = (await today()).questions as Question[];
    const right = await rightAnswer(q);
    const ok = await request(server()).post("/v1/politics/quiz/answer").send({ questionId: q.id, choice: right }).expect(200);
    expect(ok.body).toMatchObject({ correct: true, answer: right, recorded: false, eventId: q.eventId });
    expect(ok.body.sourceUrl).toMatch(/^https:\/\/www\.assemblee-nationale\.fr\/dyn\/17\/scrutins\/\d+$/);
    expect(ok.body.group.name).toBe(q.groupName);
    const wrong = ["pour", "contre", "abstention"].find((c) => c !== right)!;
    const ko = await request(server()).post("/v1/politics/quiz/answer").send({ questionId: q.id, choice: wrong }).expect(200);
    expect(ko.body).toMatchObject({ correct: false, answer: right });
  });

  it("avec un compte, on ne répond qu'une fois : rejouer renvoie la première réponse, la série démarre", async () => {
    const [q] = (await today()).questions as Question[];
    const right = await rightAnswer(q);
    const wrong = ["pour", "contre", "abstention"].find((c) => c !== right)!;
    const first = await request(server()).post("/v1/politics/quiz/answer").set(me.auth).send({ questionId: q.id, choice: wrong }).expect(200);
    expect(first.body).toMatchObject({ correct: false, recorded: true, choice: wrong });
    const retry = await request(server()).post("/v1/politics/quiz/answer").set(me.auth).send({ questionId: q.id, choice: right }).expect(200);
    expect(retry.body).toMatchObject({ correct: false, choice: wrong });

    const quiz = (await request(server()).get("/v1/politics/quiz").set(me.auth).expect(200)).body;
    expect(quiz).toMatchObject({ signedIn: true, answered: 1, correct: 0, streak: 1, bestStreak: 1 });
    expect(quiz.questions[0]).toMatchObject({ myChoice: wrong, myCorrect: false });
  });

  it("refuse une question hors du programme du jour et un choix inconnu", async () => {
    const [q] = (await today()).questions as Question[];
    await request(server()).post("/v1/politics/quiz/answer").send({ questionId: "nimporte:quoi", choice: "pour" }).expect(400);
    await request(server()).post("/v1/politics/quiz/answer").send({ questionId: q.id, choice: "peut-etre" }).expect(400);
    await request(server()).post("/v1/politics/quiz/answer").send({ choice: "pour" }).expect(400);
  });
});
