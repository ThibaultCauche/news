import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";

// e2e (Supertest) contre le vrai Postgres de dev (docs/04 J12) : progression dans les tutos.
describe("Progression dans les tutos (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.$disconnect();
    await app.close();
  });

  const server = () => app.getHttpServer();

  it("exige un compte", async () => {
    await request(server()).get("/v1/me/learn").expect(401);
    await request(server()).put("/v1/me/learn/valorant/le-jeu").send({}).expect(401);
  });

  it("enregistre un tuto lu, puis un quiz réussi qui ne se retire jamais", async () => {
    const account = await loginTestUser(app);
    expect((await request(server()).get("/v1/me/learn").set(account.auth).expect(200)).body.entries).toEqual([]);

    await request(server()).put("/v1/me/learn/valorant/le-jeu").set(account.auth).send({}).expect(200);
    let res = await request(server()).get("/v1/me/learn").set(account.auth).expect(200);
    expect(res.body.entries).toEqual([{ guide: "valorant", articleId: "le-jeu", quizPassed: false }]);

    await request(server()).put("/v1/me/learn/valorant/le-jeu").set(account.auth).send({ quizPassed: true }).expect(200);
    // Rouvrir le tuto (ou rater le quiz une 2e fois) ne retire pas la réussite.
    await request(server()).put("/v1/me/learn/valorant/le-jeu").set(account.auth).send({}).expect(200);
    await request(server()).put("/v1/me/learn/valorant/le-jeu").set(account.auth).send({ quizPassed: false }).expect(200);
    res = await request(server()).get("/v1/me/learn").set(account.auth).expect(200);
    expect(res.body.entries).toEqual([{ guide: "valorant", articleId: "le-jeu", quizPassed: true }]);
  });

  it("garde la progression de chaque compte séparée et la supprime avec le compte", async () => {
    const a = await loginTestUser(app);
    const b = await loginTestUser(app);
    await request(server()).put("/v1/me/learn/app/pronostics").set(a.auth).send({}).expect(200);
    expect((await request(server()).get("/v1/me/learn").set(b.auth).expect(200)).body.entries).toEqual([]);

    await request(server()).delete("/v1/me").set(a.auth).expect(204);
    expect(await prisma.learnProgress.count({ where: { guide: "app", articleId: "pronostics", userId: a.userId } })).toBe(0);
  });

  it("refuse un identifiant de tuto invalide", async () => {
    const account = await loginTestUser(app);
    await request(server()).put("/v1/me/learn/Valo%20rant/le-jeu").set(account.auth).send({}).expect(400);
    await request(server()).put(`/v1/me/learn/valorant/${"a".repeat(41)}`).set(account.auth).send({}).expect(400);
    await request(server()).put("/v1/me/learn/valorant/le-jeu").set(account.auth).send({ quizPassed: "oui" }).expect(400);
  });
});
