import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser } from "./test-utils";

// e2e (Supertest) contre le vrai Postgres de dev (docs/04 J11) : pseudo, pronostics, groupes,
// suppression RGPD. Le règlement des points est testé côté worker.
describe("Profil, pronostics, groupes (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;

  const suffix = randomUUID().slice(0, 8);
  let categoryId: string;
  let competitionId: string;
  let teamAId: string;
  let teamBId: string;
  let futureEventId: string;
  let startedEventId: string;

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-community-${suffix}`, name: "Test communauté" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Comm", status: "live" } })).id;
    teamAId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test A", imageUrl: "https://example.test/a.png" } })).id;
    teamBId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test B" } })).id;
    const makeEvent = async (status: string, startsAt: Date) =>
      (
        await prisma.event.create({
          data: {
            id: randomUUID(),
            competitionId,
            kind: "match",
            name: `Test A vs Test B ${status}`,
            status,
            startsAt,
            participants: { create: [{ id: randomUUID(), entityId: teamAId }, { id: randomUUID(), entityId: teamBId }] },
          },
        })
      ).id;
    futureEventId = await makeEvent("scheduled", new Date(Date.now() + 3_600_000));
    startedEventId = await makeEvent("live", new Date(Date.now() - 600_000));
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.prediction.deleteMany({ where: { event: { competitionId } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamAId, teamBId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  const server = () => app.getHttpServer();
  const uniquePseudo = (base: string) => `${base}${randomUUID().slice(0, 6)}`;

  async function accountWithPseudo(base = "Joueur") {
    const account = await loginTestUser(app);
    const pseudo = uniquePseudo(base);
    await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo }).expect(200);
    return { ...account, pseudo };
  }

  describe("pseudo", () => {
    it("exige un e-mail vérifié", async () => {
      const account = await loginTestUser(app, { verified: false });
      const res = await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: uniquePseudo("Theo") }).expect(403);
      expect(res.body.code).toBe("EMAIL_NOT_VERIFIED");
    });

    it("refuse un pseudo trop court, avec caractères spéciaux ou interdit", async () => {
      const account = await loginTestUser(app);
      await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: "ab" }).expect(400);
      await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: "a b c d" }).expect(400);
      await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: "Xx_Nazi_xX" }).expect(400);
    });

    it("est unique sans tenir compte de la casse ni des accents", async () => {
      const first = await loginTestUser(app);
      const base = `Théo${randomUUID().slice(0, 6)}`;
      await request(server()).put("/v1/me/profile").set(first.auth).send({ pseudo: base }).expect(200);
      const second = await loginTestUser(app);
      const res = await request(server()).put("/v1/me/profile").set(second.auth).send({ pseudo: base.replace("é", "e").toUpperCase() }).expect(409);
      expect(res.body.code).toBe("PSEUDO_TAKEN");
    });

    it("se change au plus une fois tous les 30 jours (le premier pseudo ne compte pas)", async () => {
      const account = await accountWithPseudo();
      const profile = await request(server()).get("/v1/me/profile").set(account.auth).expect(200);
      expect(profile.body.pseudoChangeWaitDays).toBe(0);
      await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: uniquePseudo("Autre") }).expect(200);
      const res = await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: uniquePseudo("Encore") }).expect(403);
      expect(res.body.code).toBe("PSEUDO_CHANGE_TOO_SOON");
    });
  });

  it("l'avatar est le logo d'une équipe, sans changer de pseudo", async () => {
    const account = await accountWithPseudo();
    const res = await request(server()).put("/v1/me/profile").set(account.auth).send({ avatarEntityId: teamAId }).expect(200);
    expect(res.body).toMatchObject({ avatarUrl: "https://example.test/a.png", pseudo: account.pseudo });
    // Une équipe sans logo ou un identifiant inconnu ne peut pas servir d'avatar.
    await request(server()).put("/v1/me/profile").set(account.auth).send({ avatarEntityId: teamBId }).expect(400);
    await request(server()).put("/v1/me/profile").set(account.auth).send({ avatarEntityId: randomUUID() }).expect(400);
    await request(server()).put("/v1/me/profile").set(account.auth).send({}).expect(400);
  });

  it("le profil d'un autre joueur n'est visible que par les membres d'un groupe commun", async () => {
    const owner = await accountWithPseudo("Chef");
    const friend = await accountWithPseudo("Ami");
    const stranger = await accountWithPseudo("Autre");
    const group = await request(server()).post("/v1/groups").set(owner.auth).send({ name: "Profils" }).expect(201);
    await request(server()).post("/v1/groups/join").set(friend.auth).send({ code: group.body.code }).expect(201);

    const res = await request(server()).get(`/v1/users/${friend.userId}/profile`).set(owner.auth).expect(200);
    expect(res.body).toMatchObject({ userId: friend.userId, pseudo: friend.pseudo });
    expect(res.body.stats).toBeDefined();
    await request(server()).get(`/v1/users/${friend.userId}/profile`).set(stranger.auth).expect(404);
    await request(server()).get(`/v1/users/${stranger.userId}/profile`).set(owner.auth).expect(404);
    await request(server()).get(`/v1/users/${owner.userId}/profile`).set(owner.auth).expect(200);
  });

  describe("pronostics", () => {
    it("exige un pseudo", async () => {
      const account = await loginTestUser(app);
      const res = await request(server()).put("/v1/predictions").set(account.auth).send({ eventId: futureEventId, pickedEntityId: teamAId }).expect(403);
      expect(res.body.code).toBe("PROFILE_REQUIRED");
    });

    it("se pose puis se modifie jusqu'au début du match, et se lit dans la liste", async () => {
      const account = await accountWithPseudo();
      await request(server()).put("/v1/predictions").set(account.auth).send({ eventId: futureEventId, pickedEntityId: teamAId }).expect(200);
      const res = await request(server())
        .put("/v1/predictions")
        .set(account.auth)
        .send({ eventId: futureEventId, pickedEntityId: teamBId, pickedScore: 2, otherScore: 1 })
        .expect(200);
      expect(res.body).toMatchObject({ pickedEntityId: teamBId, pickedScore: 2, otherScore: 1, points: null });
      const list = await request(server()).get("/v1/predictions").set(account.auth).expect(200);
      expect(list.body).toHaveLength(1);
      expect(await prisma.prediction.count({ where: { userId: account.userId } })).toBe(1);
    });

    it("est refusé une fois le match commencé, pour une équipe étrangère au match ou avec un score incomplet", async () => {
      const account = await accountWithPseudo();
      const locked = await request(server()).put("/v1/predictions").set(account.auth).send({ eventId: startedEventId, pickedEntityId: teamAId }).expect(403);
      expect(locked.body.code).toBe("PREDICTION_LOCKED");
      await request(server()).put("/v1/predictions").set(account.auth).send({ eventId: futureEventId, pickedEntityId: randomUUID() }).expect(400);
      await request(server()).put("/v1/predictions").set(account.auth).send({ eventId: futureEventId, pickedEntityId: teamAId, pickedScore: 2 }).expect(400);
    });
  });

  describe("groupes", () => {
    it("se crée, se rejoint par code (insensible à la casse), et classe les membres", async () => {
      const owner = await accountWithPseudo("Chef");
      const friend = await accountWithPseudo("Ami");
      const created = await request(server()).post("/v1/groups").set(owner.auth).send({ name: "Les copains" }).expect(201);
      expect(created.body.code).toMatch(/^[2-9A-HJKMNP-Z]{8}$/);

      const joined = await request(server()).post("/v1/groups/join").set(friend.auth).send({ code: created.body.code.toLowerCase() }).expect(201);
      expect(joined.body).toMatchObject({ id: created.body.id, memberCount: 2, isOwner: false });
      // Rejoindre deux fois ne crée pas de doublon.
      await request(server()).post("/v1/groups/join").set(friend.auth).send({ code: created.body.code }).expect(201);

      // Classement : points posés directement en base (le règlement est dans le worker).
      await prisma.prediction.create({ data: { id: randomUUID(), userId: friend.userId, eventId: futureEventId, pickedEntityId: teamAId, points: 5, settledAt: new Date() } });
      const detail = await request(server()).get(`/v1/groups/${created.body.id}`).set(owner.auth).expect(200);
      expect(detail.body.ranking.map((r: { pseudo: string; rank: number; points: number }) => [r.pseudo, r.rank, r.points])).toEqual([
        [friend.pseudo, 1, 5],
        [owner.pseudo, 2, 0],
      ]);
      expect(detail.body.ranking[1].isMe).toBe(true);

      const mine = await request(server()).get("/v1/groups").set(friend.auth).expect(200);
      expect(mine.body).toHaveLength(1);
    });

    it("refuse un code inconnu, un groupe complet, et cache le groupe aux non-membres", async () => {
      const owner = await accountWithPseudo("Chef");
      const stranger = await accountWithPseudo("Autre");
      await request(server()).post("/v1/groups/join").set(stranger.auth).send({ code: "AAAAAAAA" }).expect(404);

      const created = await request(server()).post("/v1/groups").set(owner.auth).send({ name: "Complet" }).expect(201);
      await request(server()).get(`/v1/groups/${created.body.id}`).set(stranger.auth).expect(404);

      const others = await Promise.all(Array.from({ length: 19 }, (_, i) => prisma.appUser.create({ data: { id: randomUUID(), pseudo: `bot${i}`, pseudoKey: `bot${i}-${suffix}` } })));
      await prisma.friendGroupMember.createMany({ data: others.map((u) => ({ groupId: created.body.id, userId: u.id })) });
      const res = await request(server()).post("/v1/groups/join").set(stranger.auth).send({ code: created.body.code }).expect(409);
      expect(res.body.code).toBe("GROUP_FULL");
      await prisma.appUser.deleteMany({ where: { id: { in: others.map((u) => u.id) } } });
    });

    it("se quitte, sauf pour le créateur, qui le supprime", async () => {
      const owner = await accountWithPseudo("Chef");
      const friend = await accountWithPseudo("Ami");
      const created = await request(server()).post("/v1/groups").set(owner.auth).send({ name: "Temporaire" }).expect(201);
      await request(server()).post("/v1/groups/join").set(friend.auth).send({ code: created.body.code }).expect(201);

      await request(server()).delete(`/v1/groups/${created.body.id}/members/me`).set(owner.auth).expect(409);
      await request(server()).delete(`/v1/groups/${created.body.id}`).set(friend.auth).expect(403);
      await request(server()).delete(`/v1/groups/${created.body.id}/members/me`).set(friend.auth).expect(204);
      await request(server()).delete(`/v1/groups/${created.body.id}`).set(owner.auth).expect(204);
      await request(server()).get(`/v1/groups/${created.body.id}`).set(owner.auth).expect(404);
    });
  });

  describe("amis et classement (J14)", () => {
    it("les choix des amis restent cachés avant le coup d'envoi, puis se montrent aux membres d'un groupe commun seulement", async () => {
      const me = await accountWithPseudo("Moi");
      const friend = await accountWithPseudo("Ami");
      const stranger = await accountWithPseudo("Inconnu");
      const group = await request(server()).post("/v1/groups").set(me.auth).send({ name: "Amis J14" }).expect(201);
      await request(server()).post("/v1/groups/join").set(friend.auth).send({ code: group.body.code }).expect(201);
      for (const [eventId, a] of [[futureEventId, friend], [startedEventId, friend], [startedEventId, stranger]] as const) {
        await prisma.prediction.create({ data: { id: randomUUID(), userId: a.userId, eventId, pickedEntityId: teamAId } });
      }

      const before = await request(server()).get(`/v1/events/${futureEventId}/friends-picks`).set(me.auth).expect(200);
      expect(before.body.picks).toEqual([]);

      const after = await request(server()).get(`/v1/events/${startedEventId}/friends-picks`).set(me.auth).expect(200);
      expect(after.body.picks.map((p: { pseudo: string; pickedEntityId: string }) => [p.pseudo, p.pickedEntityId])).toEqual([[friend.pseudo, teamAId]]);
      expect(after.body.picks[0]).not.toHaveProperty("points");

      await request(server()).get(`/v1/events/${randomUUID()}/friends-picks`).set(me.auth).expect(404);
      await request(server()).get(`/v1/events/${startedEventId}/friends-picks`).expect(401);
    });

    it("le classement d'un groupe se filtre par jeu", async () => {
      const owner = await accountWithPseudo("Chef");
      const group = await request(server()).post("/v1/groups").set(owner.auth).send({ name: "Filtre jeu" }).expect(201);
      const game = `test-game-${suffix}`;
      const otherCompetition = await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test autre jeu", status: "live", game } });
      const otherEvent = await prisma.event.create({
        data: { id: randomUUID(), competitionId: otherCompetition.id, kind: "match", name: "Test autre", status: "finished", participants: { create: [{ id: randomUUID(), entityId: teamAId }] } },
      });
      await prisma.prediction.create({ data: { id: randomUUID(), userId: owner.userId, eventId: otherEvent.id, pickedEntityId: teamAId, points: 3, settledAt: new Date() } });
      await prisma.prediction.create({ data: { id: randomUUID(), userId: owner.userId, eventId: futureEventId, pickedEntityId: teamAId, points: 5, settledAt: new Date() } });

      const all = await request(server()).get(`/v1/groups/${group.body.id}`).set(owner.auth).expect(200);
      expect(all.body.ranking[0].points).toBe(8);
      const filtered = await request(server()).get(`/v1/groups/${group.body.id}`).query({ game }).set(owner.auth).expect(200);
      expect(filtered.body.ranking[0]).toMatchObject({ points: 3, correctCount: 1 });

      await prisma.prediction.deleteMany({ where: { eventId: otherEvent.id } });
      await prisma.eventParticipant.deleteMany({ where: { eventId: otherEvent.id } });
      await prisma.event.delete({ where: { id: otherEvent.id } });
      await prisma.competition.delete({ where: { id: otherCompetition.id } });
    });
  });

  it("la suppression du créateur transmet son groupe au membre le plus ancien, et le supprime s'il est seul", async () => {
    const owner = await accountWithPseudo("Chef");
    const heir = await accountWithPseudo("Heritier");
    const group = await request(server()).post("/v1/groups").set(owner.auth).send({ name: "Transmis" }).expect(201);
    await request(server()).post("/v1/groups/join").set(heir.auth).send({ code: group.body.code }).expect(201);
    const alone = await request(server()).post("/v1/groups").set(heir.auth).send({ name: "Seul" }).expect(201);

    await request(server()).delete("/v1/me").set(owner.auth).expect(204);
    const after = await request(server()).get(`/v1/groups/${group.body.id}`).set(heir.auth).expect(200);
    expect(after.body.isOwner).toBe(true);
    expect(after.body.ranking.map((r: { pseudo: string }) => r.pseudo)).toEqual([heir.pseudo]);

    await request(server()).delete("/v1/me").set(heir.auth).expect(204);
    expect(await prisma.friendGroup.count({ where: { id: { in: [group.body.id, alone.body.id] } } })).toBe(0);
  });

  it("la suppression du compte (RGPD) emporte pronostics et appartenances, et libère le pseudo", async () => {
    const account = await accountWithPseudo();
    await request(server()).put("/v1/predictions").set(account.auth).send({ eventId: futureEventId, pickedEntityId: teamAId }).expect(200);
    const group = await request(server()).post("/v1/groups").set(account.auth).send({ name: "À supprimer" }).expect(201);

    await request(server()).delete("/v1/me").set(account.auth).expect(204);
    expect(await prisma.prediction.count({ where: { userId: account.userId } })).toBe(0);
    expect(await prisma.friendGroup.count({ where: { id: group.body.id } })).toBe(0);
    expect(await prisma.appUser.count({ where: { pseudoKey: account.pseudo.toLowerCase() } })).toBe(0);
  });
});
