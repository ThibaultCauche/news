import { randomUUID } from "node:crypto";
import { INestApplication, ValidationPipe } from "@nestjs/common";
import { Test } from "@nestjs/testing";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { AppModule } from "./app.module";

// e2e (Supertest) contre le vrai Postgres de dev, comme `app.e2e.spec.ts` (docs/04 J4) :
// compte anonyme, abonnements, appareil, réglages, suppression RGPD, jusqu'à la
// notification (dédup + sans spoil testés côté domaine dans `packages/domain`).
describe("Comptes, abonnements, notifications (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;

  const categorySlug = `test-auth-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  let teamG2Id: string;
  let eventId: string;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("v1", { exclude: ["health"] });
    app.useGlobalPipes(new ValidationPipe({ transform: true, whitelist: true }));
    await app.init();

    prisma = new PrismaClient();
    const category = await prisma.category.create({ data: { id: randomUUID(), slug: categorySlug, name: "Test auth" } });
    categoryId = category.id;
    const competition = await prisma.competition.create({
      data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Champions", status: "live", importance: 3 },
    });
    competitionId = competition.id;
    const teamG2 = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test G2", imageUrl: "https://example.test/g2.png" } });
    teamG2Id = teamG2.id;
    await prisma.standing.create({ data: { id: randomUUID(), competitionId, entityId: teamG2Id, qualified: true } });
    const event = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test G2 vs Test PRX",
        status: "scheduled",
        startsAt: new Date(Date.now() + 60 * 60 * 1000),
        importance: 3,
        participants: { create: [{ id: randomUUID(), entityId: teamG2Id }] },
      },
    });
    eventId = event.id;
  });

  afterAll(async () => {
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.standing.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.delete({ where: { id: teamG2Id } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  async function createAnonymousAccount() {
    const res = await request(app.getHttpServer()).post("/v1/auth/anonymous").expect(201);
    return res.body as { userId: string; accessToken: string; refreshToken: string };
  }

  it("crée un compte anonyme avec des réglages par défaut (sans spoil désactivé)", async () => {
    const { accessToken } = await createAnonymousAccount();
    const res = await request(app.getHttpServer()).get("/v1/me/settings").set("Authorization", `Bearer ${accessToken}`).expect(200);
    expect(res.body).toEqual({ spoilerFree: false, morningDigest: false, quietHoursStart: null, quietHoursEnd: null });
  });

  it("refuse l'accès sans jeton et avec un jeton invalide", async () => {
    await request(app.getHttpServer()).get("/v1/me/settings").expect(401);
    await request(app.getHttpServer()).get("/v1/me/settings").set("Authorization", "Bearer invalide").expect(401);
  });

  it("rafraîchit un jeton d'accès à partir du jeton de rafraîchissement", async () => {
    const { refreshToken } = await createAnonymousAccount();
    const res = await request(app.getHttpServer()).post("/v1/auth/refresh").send({ refreshToken }).expect(201);
    expect(res.body.accessToken).toBeTruthy();
    await request(app.getHttpServer()).post("/v1/auth/refresh").send({ refreshToken: "invalide" }).expect(401);
  });

  it("Suivre G2 (POST /v1/subscriptions) fonctionne de bout en bout jusqu'à l'écran Suivis", async () => {
    const { accessToken } = await createAnonymousAccount();
    const auth = { Authorization: `Bearer ${accessToken}` };

    await request(app.getHttpServer())
      .post("/v1/subscriptions")
      .set(auth)
      .send({ targetType: "entity", targetId: teamG2Id })
      .expect(201)
      .expect((res) => {
        expect(res.body.level).toBe("all");
        expect(res.body.notifyStart).toBe(true);
      });

    const list = await request(app.getHttpServer()).get("/v1/subscriptions").set(auth).expect(200);
    expect(list.body).toHaveLength(1);
    expect(list.body[0].name).toBe("Test G2");
    expect(list.body[0].currentEvent.id).toBe(eventId);
    // Logo et statut de compétition sur l'écran Suivis (docs/04 J8).
    expect(list.body[0].imageUrl).toBe("https://example.test/g2.png");
    expect(list.body[0].status).toBe("qualified");

    const home = await request(app.getHttpServer()).get("/v1/home").set(auth).expect(200);
    expect(home.body.follows).toHaveLength(1);
    expect(home.body.nowForYou.id).toBe(eventId);

    // Se désabonner est idempotent (règle 4 de CLAUDE.md) : la 2ᵉ fois ne fait rien.
    await request(app.getHttpServer()).delete("/v1/subscriptions").set(auth).send({ targetType: "entity", targetId: teamG2Id }).expect(204);
    await request(app.getHttpServer()).delete("/v1/subscriptions").set(auth).send({ targetType: "entity", targetId: teamG2Id }).expect(204);
    const afterUnfollow = await request(app.getHttpServer()).get("/v1/subscriptions").set(auth).expect(200);
    expect(afterUnfollow.body).toEqual([]);
  });

  it("enregistre un appareil (PUT /v1/devices/me), idempotent sur le même installId", async () => {
    const { accessToken } = await createAnonymousAccount();
    const auth = { Authorization: `Bearer ${accessToken}` };
    const installId = randomUUID();

    await request(app.getHttpServer())
      .put("/v1/devices/me")
      .set(auth)
      .send({ installId, platform: "android", pushToken: "token-1", utcOffsetMinutes: 60 })
      .expect(200)
      .expect((res) => expect(res.body.pushToken).toBe("token-1"));

    // Réinstallation : même installId, nouveau jeton push — pas de doublon (docs/04 J4).
    const res = await request(app.getHttpServer())
      .put("/v1/devices/me")
      .set(auth)
      .send({ installId, platform: "android", pushToken: "token-2" })
      .expect(200);
    expect(res.body.pushToken).toBe("token-2");
    expect(await prisma.device.count({ where: { installId } })).toBe(1);
  });

  it("modifie les réglages (PATCH /v1/me/settings)", async () => {
    const { accessToken } = await createAnonymousAccount();
    const auth = { Authorization: `Bearer ${accessToken}` };

    const res = await request(app.getHttpServer())
      .patch("/v1/me/settings")
      .set(auth)
      .send({ spoilerFree: false, quietHoursStart: 22, quietHoursEnd: 7 })
      .expect(200);
    expect(res.body).toEqual({ spoilerFree: false, morningDigest: false, quietHoursStart: 22, quietHoursEnd: 7 });
  });

  it("supprime le compte (DELETE /v1/me) : le jeton n'autorise plus rien ensuite", async () => {
    const { accessToken } = await createAnonymousAccount();
    const auth = { Authorization: `Bearer ${accessToken}` };

    await request(app.getHttpServer()).delete("/v1/me").set(auth).expect(204);
    await request(app.getHttpServer()).get("/v1/me/settings").set(auth).expect(401);
  });
});
