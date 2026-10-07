import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser, TestAccount } from "./test-utils";

// Pick'em de tableau (docs/04 J25), contre le vrai Postgres/Redis de dev : deux demies + une finale.
describe("Pick'em de tableau (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;
  let me: TestAccount;
  let friend: TestAccount;
  let noPseudo: TestAccount;
  let groupId: string;

  const tag = randomUUID().slice(0, 8);
  let categoryId: string;
  let competitionId: string;
  let swissId: string;
  const teams: string[] = [];
  let semi1: string;
  let semi2: string;
  let final: string;

  const url = () => `/v1/competitions/${competitionId}/pickem`;
  const server = () => app.getHttpServer();
  const put = (account: TestAccount, picks: { eventId: string; pickedEntityId: string }[]) => request(server()).put(url()).set(account.auth).send({ picks });

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-pickem-${tag}`, name: "Test pickem" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: `Test KO ${tag}`, format: "single_elim" } })).id;
    swissId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: `Test Swiss ${tag}`, format: "swiss" } })).id;
    for (let i = 0; i < 4; i++) teams.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Équipe ${i} ${tag}` } })).id);
    const mk = async (name: string, hours: number, pair: string[]) => {
      const event = await prisma.event.create({
        data: { id: randomUUID(), competitionId, kind: "match", name, status: "scheduled", startsAt: new Date(Date.now() + hours * 3600_000), result: { seriesScore: [], games: [] } },
      });
      await prisma.eventParticipant.createMany({ data: pair.map((entityId, side) => ({ id: randomUUID(), eventId: event.id, entityId, side })) });
      return event.id;
    };
    semi1 = await mk("Upper Semifinal 1", 1, [teams[0], teams[1]]);
    semi2 = await mk("Upper Semifinal 2", 2, [teams[2], teams[3]]);
    final = await mk("Grand Final", 5, []);
    await prisma.eventLink.createMany({
      data: [
        { id: randomUUID(), fromEventId: semi1, toEventId: final, outcome: "winner", slot: 0 },
        { id: randomUUID(), fromEventId: semi2, toEventId: final, outcome: "winner", slot: 1 },
      ],
    });
    me = await loginTestUser(app);
    friend = await loginTestUser(app);
    noPseudo = await loginTestUser(app);
    await request(server()).put("/v1/me/profile").set(me.auth).send({ pseudo: `PickA${tag}` }).expect(200);
    await request(server()).put("/v1/me/profile").set(friend.auth).send({ pseudo: `PickB${tag}` }).expect(200);
    const group = await request(server()).post("/v1/groups").set(me.auth).send({ name: `Groupe ${tag}` }).expect(201);
    groupId = group.body.id;
    // Membre ajouté en base : la route `groups/join` est limitée à 10 par minute.
    const friendId = (await prisma.appUser.findFirstOrThrow({ where: { pseudo: `PickB${tag}` } })).id;
    await prisma.friendGroupMember.create({ data: { groupId, userId: friendId } });
  });

  afterAll(async () => {
    await deleteTestUsers(prisma);
    await prisma.friendGroup.deleteMany({ where: { id: groupId } });
    await prisma.eventLink.deleteMany({ where: { fromEventId: { in: [semi1, semi2] } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: teams } } });
    await prisma.competition.deleteMany({ where: { id: { in: [competitionId, swissId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  it("exige un compte et refuse une étape sans tableau", async () => {
    await request(server()).get(url()).expect(401);
    await request(server()).get(`/v1/competitions/${swissId}/pickem`).set(me.auth).expect(404);
  });

  it("propose le tableau avec ses poids, et on peut le remplir jusqu'à la finale", async () => {
    const before = await request(server()).get(url()).set(me.auth).expect(200);
    expect(before.body).toMatchObject({ open: true, locked: false, picks: [], points: 0 });
    const weights = Object.fromEntries(before.body.matches.map((m: { eventId: string; weight: number }) => [m.eventId, m.weight]));
    expect(weights).toEqual({ [semi1]: 2, [semi2]: 2, [final]: 4 });

    const saved = await put(me, [
      { eventId: semi1, pickedEntityId: teams[0] },
      { eventId: semi2, pickedEntityId: teams[3] },
      { eventId: final, pickedEntityId: teams[3] },
    ]).expect(200);
    expect(saved.body.picks).toHaveLength(3);
    // Rien de joué : 2 + 2 + 4, plus le tableau parfait (5) et le champion (3) encore possibles.
    expect(saved.body.maxRemaining).toBe(16);
    expect(saved.body.picks.every((p: { alive: boolean }) => p.alive)).toBe(true);
  });

  it("refuse une équipe qui ne peut pas jouer le match, un compte sans pseudo, et accepte un tableau complet à nouveau", async () => {
    await put(me, [{ eventId: semi1, pickedEntityId: teams[2] }]).expect(400);
    // La finale ne peut opposer que des équipes choisies plus haut.
    await put(me, [{ eventId: final, pickedEntityId: teams[0] }]).expect(400);
    await put(noPseudo, [{ eventId: semi1, pickedEntityId: teams[0] }]).expect(403);
    const trimmed = await put(me, [
      { eventId: semi1, pickedEntityId: teams[0] },
      { eventId: semi2, pickedEntityId: teams[3] },
      { eventId: final, pickedEntityId: teams[3] },
    ]).expect(200);
    expect(trimmed.body.picks).toHaveLength(3);
  });

  it("les choix des amis et le vote du groupe restent invisibles avant le verrouillage, même par l'API", async () => {
    await put(friend, [{ eventId: semi1, pickedEntityId: teams[1] }]).expect(200);
    const before = await request(server()).get(`${url()}/groups`).set(me.auth).expect(200);
    expect(before.body.locked).toBe(false);
    const group = before.body.groups.find((g: { groupId: string }) => g.groupId === groupId);
    expect(group.groupPicks).toEqual([]);
    const other = group.members.find((m: { isMe: boolean }) => !m.isMe);
    expect(other).toMatchObject({ filled: 1, picks: [] });
    // Les miens restent visibles pour moi.
    expect(group.members.find((m: { isMe: boolean }) => m.isMe).picks).toHaveLength(3);
  });

  it("un tableau partagé dans le groupe montre le nombre de choix, mais ni champion ni points avant le début", async () => {
    for (const account of [me, friend]) {
      const id = (await prisma.appUser.findFirstOrThrow({ where: { pseudo: account === me ? `PickA${tag}` : `PickB${tag}` } })).id;
      await prisma.appUser.update({ where: { id }, data: { createdAt: new Date(Date.now() - 2 * 86_400_000) } });
      await request(server()).post("/v1/forum/terms").set(account.auth).send({ version: 1 }).expect(201);
    }
    const thread = (await request(server()).get(`/v1/forum/groups/${groupId}/thread`).set(me.auth).expect(200)).body;
    // L'ami n'a rien à partager sur ce tableau tant qu'il n'a pas choisi : il a choisi un match, c'est donc permis.
    await request(server()).post(`/v1/forum/threads/${thread.id}/messages`).set(me.auth).send({ body: "", share: { kind: "pickem", refId: competitionId } }).expect(201);
    const read = await request(server()).get(`/v1/forum/threads/${thread.id}/messages`).set(friend.auth).expect(200);
    const card = read.body.messages.find((m: { kind: string }) => m.kind === "pickem").shared;
    expect(card).toMatchObject({ kind: "pickem", locked: true, pickemPicked: 3, pickemTotal: 3, pickedEntityId: null, pickemPoints: null });
    // Un non-membre ne voit même pas le fil du groupe.
    await request(server()).post(`/v1/forum/threads/${thread.id}/messages`).set(noPseudo.auth).send({ body: "", share: { kind: "pickem", refId: competitionId } }).expect(404);
  });

  it("le profil porte le badge « Premier tableau »", async () => {
    const profile = await request(server()).get("/v1/me/profile").set(me.auth).expect(200);
    expect(profile.body.badges.find((b: { id: string }) => b.id === "first_pickem").earned).toBe(true);
    expect(profile.body.badges.find((b: { id: string }) => b.id === "perfect_bracket").earned).toBe(false);
  });

  it("une fois le premier match lancé, tout est verrouillé côté serveur et le groupe vote", async () => {
    await prisma.event.update({ where: { id: semi1 }, data: { status: "live" } });
    await put(me, [{ eventId: semi1, pickedEntityId: teams[1] }]).expect(409);
    const locked = await request(server()).get(url()).set(me.auth).expect(200);
    expect(locked.body.locked).toBe(true);

    const groups = await request(server()).get(`${url()}/groups`).set(me.auth).expect(200);
    const group = groups.body.groups.find((g: { groupId: string }) => g.groupId === groupId);
    // Demie 1 : moi (le plus ancien) choisis l'équipe 0, mon ami l'équipe 1 : égalité, le plus ancien l'emporte.
    expect(group.groupPicks.find((p: { eventId: string }) => p.eventId === semi1).pickedEntityId).toBe(teams[0]);
    expect(group.members.find((m: { isMe: boolean }) => !m.isMe).picks).toHaveLength(1);
    // Le tableau partagé révèle maintenant le champion choisi.
    const thread = (await request(server()).get(`/v1/forum/groups/${groupId}/thread`).set(me.auth).expect(200)).body;
    const read = await request(server()).get(`/v1/forum/threads/${thread.id}/messages`).set(friend.auth).expect(200);
    const card = read.body.messages.find((m: { kind: string }) => m.kind === "pickem").shared;
    expect(card).toMatchObject({ locked: false, pickedEntityId: teams[3], pickemPoints: 0 });
  });

  it("les points du pick'em, des bonus et de la phase suisse comptent dans les points du profil", async () => {
    const meId = (await prisma.appUser.findFirstOrThrow({ where: { pseudo: `PickA${tag}` } })).id;
    const before = (await request(server()).get("/v1/me/profile").set(me.auth).expect(200)).body.stats.points;
    await prisma.bracketPick.updateMany({ where: { userId: meId, eventId: semi2 }, data: { points: 2, settledAt: new Date() } });
    await prisma.bracketPickBonus.create({ data: { userId: meId, competitionId, kind: "champion", points: 3 } });
    const after = (await request(server()).get("/v1/me/profile").set(me.auth).expect(200)).body.stats.points;
    expect(after - before).toBe(5);
  });

  it("liste mes pick'em", async () => {
    const mine = await request(server()).get("/v1/me/pickems").set(me.auth).expect(200);
    expect(mine.body).toEqual([expect.objectContaining({ competitionId, locked: true, picked: 3, total: 3, points: 5 })]);
  });
});
