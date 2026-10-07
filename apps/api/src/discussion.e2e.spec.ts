import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { FORUM_TERMS_VERSION } from "@news/domain";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser, TestAccount } from "./test-utils";

// e2e (Supertest) contre le vrai Postgres de dev (docs/04 J24) : fil de groupe, messages privés limités aux
// groupes en commun, boîte avec non-lus, partage de cartes, sondages, tableau des idées, recherche.
// Le forum public reste en bêta fermée (comptes sans `forum_beta`) : le privé doit fonctionner quand même.
describe("Discussion (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;

  const suffix = randomUUID().slice(0, 8);
  let categoryId: string;
  let competitionId: string;
  let teamAId: string;
  let teamBId: string;
  let eventId: string;
  const threadIds: string[] = [];

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-disc-${suffix}`, name: "Test discussion" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: `Disc ${suffix}`, status: "live", game: "valorant" } })).id;
    teamAId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Disc Alpha ${suffix}` } })).id;
    teamBId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Disc Beta ${suffix}` } })).id;
    eventId = (
      await prisma.event.create({
        data: {
          id: randomUUID(),
          competitionId,
          kind: "match",
          name: `Disc A vs Disc B ${suffix}`,
          status: "scheduled",
          startsAt: new Date(Date.now() + 3_600_000),
          participants: { create: [{ id: randomUUID(), entityId: teamAId }, { id: randomUUID(), entityId: teamBId }] },
        },
      })
    ).id;
  });

  afterAll(async () => {
    await prisma.forumThread.deleteMany({ where: { OR: [{ id: { in: threadIds } }, { targetId: eventId }, { kind: "dm", members: { none: {} } }] } });
    await deleteTestUsers(prisma);
    await prisma.forumThread.deleteMany({ where: { kind: "dm", members: { none: {} } } });
    await prisma.moderationLog.deleteMany({ where: { moderatorId: null } });
    await prisma.prediction.deleteMany({ where: { eventId } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamAId, teamBId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  const server = () => app.getHttpServer();

  /** Compte prêt à écrire (pseudo, conditions, 2 jours d'ancienneté), sans la bêta du forum sauf `beta`. */
  async function player(options: { beta?: boolean; moderator?: boolean } = {}): Promise<TestAccount & { pseudo: string }> {
    const account = await loginTestUser(app);
    const pseudo = `Disc${randomUUID().slice(0, 7)}`;
    await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo }).expect(200);
    await prisma.appUser.update({ where: { id: account.userId }, data: { forumBeta: options.beta ?? false, isModerator: options.moderator ?? false, createdAt: new Date(Date.now() - 2 * 86_400_000) } });
    await request(server()).post("/v1/forum/terms").set(account.auth).send({ version: FORUM_TERMS_VERSION }).expect(201);
    return { ...account, pseudo };
  }

  async function group(owner: TestAccount, ...members: TestAccount[]): Promise<string> {
    const created = await request(server()).post("/v1/groups").set(owner.auth).send({ name: `Copains ${suffix}` }).expect(201);
    // Membres ajoutés en base : la route « rejoindre » est limitée à 10 par minute (testée dans community.e2e).
    for (const m of members) await prisma.friendGroupMember.create({ data: { groupId: created.body.id, userId: m.userId } });
    return created.body.id as string;
  }

  // Les routes de groupe sont limitées en rafale : les tests de finition partagent un seul groupe.
  let pair: { alice: TestAccount & { pseudo: string }; bob: TestAccount & { pseudo: string }; groupId: string } | null = null;
  async function sharedPair() {
    if (!pair) {
      const alice = await player();
      const bob = await player();
      pair = { alice, bob, groupId: await group(alice, bob) };
    }
    return pair;
  }

  const groupThread = async (account: TestAccount, groupId: string) => (await request(server()).get(`/v1/forum/groups/${groupId}/thread`).set(account.auth).expect(200)).body as { id: string; title: string; kind: string };
  const openDm = (account: TestAccount, userId: string) => request(server()).post("/v1/forum/dm").set(account.auth).send({ userId });
  const post = (account: TestAccount, threadId: string, body: string, extra: Record<string, unknown> = {}) => request(server()).post(`/v1/forum/threads/${threadId}/messages`).set(account.auth).send({ body, ...extra });
  const messages = (account: TestAccount, threadId: string) => request(server()).get(`/v1/forum/threads/${threadId}/messages`).set(account.auth);

  describe("fil de groupe", () => {
    it("s'ouvre et s'écrit entre membres, même hors bêta du forum ; un non-membre n'en voit rien", async () => {
      const alice = await player();
      const bob = await player();
      const carol = await player();
      const groupId = await group(alice, bob);

      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);
      expect(thread.kind).toBe("group");
      expect(thread.title).toBe(`Copains ${suffix}`);
      expect((await groupThread(bob, groupId)).id).toBe(thread.id);

      await post(alice, thread.id, "salut le groupe").expect(201);
      const read = await messages(bob, thread.id).expect(200);
      expect(read.body.messages[0]).toMatchObject({ body: "salut le groupe", kind: "text" });
      await post(bob, thread.id, "yo", { parentId: read.body.messages[0].id }).expect(201);

      // Un non-membre : 404 partout (le fil n'existe pas pour lui).
      await request(server()).get(`/v1/forum/groups/${groupId}/thread`).set(carol.auth).expect(404);
      await messages(carol, thread.id).expect(404);
      await post(carol, thread.id, "intrus").expect(404);
      await request(server()).put(`/v1/forum/threads/${thread.id}/follow`).set(carol.auth).expect(400);
      await request(server()).get(`/v1/forum/threads/${thread.id}/messages`).expect(404);
      // Jamais dans une liste ni une résolution publique.
      const beta = await player({ beta: true });
      const listed = await request(server()).get("/v1/forum/threads").set(beta.auth).expect(200);
      expect((listed.body as { id: string }[]).some((t) => t.id === thread.id)).toBe(false);
      await request(server()).get("/v1/forum/threads").query({ kind: "group" }).set(beta.auth).expect(400);
      await request(server()).get("/v1/forum/threads/resolve").query({ kind: "group", targetId: groupId }).set(beta.auth).expect(400);
    });

    it("réactions, spoiler, signalement et blocage s'y appliquent", async () => {
      const alice = await player();
      const bob = await player();
      const groupId = await group(alice, bob);
      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);
      const sent = await post(alice, thread.id, "le score final est incroyable", { isSpoiler: true }).expect(201);
      expect(sent.body.isSpoiler).toBe(true);
      await request(server()).put(`/v1/forum/messages/${sent.body.id}/reaction`).set(bob.auth).send({ emoji: "fire" }).expect(204);
      const read = await messages(bob, thread.id).expect(200);
      expect(read.body.messages[0]).toMatchObject({ reactions: [{ emoji: "fire", count: 1 }], myReaction: "fire" });
      await request(server()).post(`/v1/forum/messages/${sent.body.id}/report`).set(bob.auth).send({ reason: "spoiler" }).expect(204);
      // Bob bloque Alice : ses messages disparaissent pour lui seul.
      await request(server()).put(`/v1/forum/blocks/${alice.userId}`).set(bob.auth).expect(204);
      expect((await messages(bob, thread.id).expect(200)).body.messages).toHaveLength(0);
      expect((await messages(alice, thread.id).expect(200)).body.messages).toHaveLength(1);
    });
  });

  describe("messages privés", () => {
    it("exigent un groupe en commun, vérifié à l'ouverture et à chaque message", async () => {
      const alice = await player();
      const bob = await player();
      const carol = await player();
      const groupId = await group(alice, bob);

      // Contacts : les membres de mes groupes, pas les inconnus.
      const contacts = await request(server()).get("/v1/forum/contacts").set(alice.auth).expect(200);
      expect((contacts.body as { userId: string }[]).map((c) => c.userId)).toEqual([bob.userId]);
      expect((await request(server()).get("/v1/forum/contacts").set(carol.auth).expect(200)).body).toEqual([]);

      // Sans groupe commun ou avec soi-même : refusé côté serveur, même message d'erreur.
      expect((await openDm(carol, alice.userId).expect(403)).body.code).toBe("DM_NOT_ALLOWED");
      expect((await openDm(alice, carol.userId).expect(403)).body.code).toBe("DM_NOT_ALLOWED");
      expect((await openDm(alice, alice.userId).expect(403)).body.code).toBe("DM_NOT_ALLOWED");
      expect((await openDm(alice, randomUUID()).expect(403)).body.code).toBe("DM_NOT_ALLOWED");
      await request(server()).post("/v1/forum/dm").send({ userId: bob.userId }).expect(401);

      const dm = (await openDm(alice, bob.userId).expect(201)).body as { id: string; kind: string; title: string };
      threadIds.push(dm.id);
      expect(dm.kind).toBe("dm");
      expect(dm.title).toBe(bob.pseudo);
      const fromBob = (await openDm(bob, alice.userId).expect(201)).body as { id: string; title: string };
      expect(fromBob.id).toBe(dm.id);
      expect(fromBob.title).toBe(alice.pseudo);

      await post(alice, dm.id, "salut Bob").expect(201);
      expect((await messages(bob, dm.id).expect(200)).body.messages[0].body).toBe("salut Bob");
      await post(bob, dm.id, "salut Alice").expect(201);

      // Une tierce personne, même membre du groupe, ne lit ni n'écrit.
      const dave = await player();
      await prisma.friendGroupMember.create({ data: { groupId, userId: dave.userId } });
      await messages(dave, dm.id).expect(404);
      await post(dave, dm.id, "coucou").expect(404);
      await messages(carol, dm.id).expect(404);

      // Plus de groupe en commun : on peut relire, plus écrire.
      await request(server()).delete(`/v1/groups/${groupId}/members/me`).set(bob.auth).expect(204);
      await messages(alice, dm.id).expect(200);
      expect((await post(alice, dm.id, "tu es là ?").expect(403)).body.code).toBe("DM_NOT_ALLOWED");
      expect((await openDm(alice, bob.userId).expect(403)).body.code).toBe("DM_NOT_ALLOWED");
    });

    it("un blocage coupe l'écriture dans les deux sens et retire le contact", async () => {
      const alice = await player();
      const bob = await player();
      await group(alice, bob);
      const dm = (await openDm(alice, bob.userId).expect(201)).body as { id: string };
      threadIds.push(dm.id);
      await post(alice, dm.id, "salut").expect(201);
      await request(server()).put(`/v1/forum/blocks/${alice.userId}`).set(bob.auth).expect(204);
      expect((await post(alice, dm.id, "tu m'ignores ?").expect(403)).body.code).toBe("DM_BLOCKED");
      expect((await post(bob, dm.id, "non").expect(403)).body.code).toBe("DM_BLOCKED");
      expect((await openDm(alice, bob.userId).expect(403)).body.code).toBe("DM_BLOCKED");
      expect((await request(server()).get("/v1/forum/contacts").set(alice.auth).expect(200)).body).toEqual([]);
      expect((await request(server()).get("/v1/forum/contacts").set(bob.auth).expect(200)).body).toEqual([]);
    });

    it("le signalement d'un message privé arrive aux modérateurs, avec une trace de lecture", async () => {
      const alice = await player();
      const bob = await player();
      const moderator = await player({ moderator: true });
      await group(alice, bob);
      const dm = (await openDm(alice, bob.userId).expect(201)).body as { id: string };
      threadIds.push(dm.id);
      const sent = await post(alice, dm.id, "message déplacé").expect(201);
      await request(server()).post(`/v1/forum/messages/${sent.body.id}/report`).set(bob.auth).send({ reason: "insult" }).expect(204);
      // La tierce personne ne peut pas signaler ce qu'elle ne voit pas.
      await request(server()).post(`/v1/forum/messages/${sent.body.id}/report`).set(moderator.auth).send({ reason: "insult" }).expect(404);

      const reports = await request(server()).get("/v1/forum/moderation/reports").set(moderator.auth).expect(200);
      expect((reports.body as { messageId: string }[]).some((r) => r.messageId === sent.body.id)).toBe(true);
      await request(server()).get("/v1/forum/moderation/reports").set(moderator.auth).expect(200);
      expect(await prisma.moderationLog.count({ where: { moderatorId: moderator.userId, action: "view_private", messageId: sent.body.id } })).toBe(1);
    });
  });

  describe("boîte Discussion", () => {
    it("liste groupes, messages privés et fils suivis avec non-lus et aperçu ; lire remet à zéro", async () => {
      const alice = await player({ beta: true });
      const bob = await player({ beta: true });
      const groupId = await group(alice, bob);
      const gThread = await groupThread(alice, groupId);
      const dm = (await openDm(alice, bob.userId).expect(201)).body as { id: string };
      threadIds.push(gThread.id, dm.id);

      await post(bob, gThread.id, "premier").expect(201);
      await post(bob, gThread.id, "second").expect(201);
      await post(bob, dm.id, "en privé").expect(201);

      const inbox = (await request(server()).get("/v1/forum/inbox").set(alice.auth).expect(200)).body as { thread: { id: string; kind: string; title: string }; unreadCount: number; preview: string | null; previewAuthor: string | null }[];
      const g = inbox.find((i) => i.thread.id === gThread.id)!;
      const d = inbox.find((i) => i.thread.id === dm.id)!;
      expect(g).toMatchObject({ unreadCount: 2, preview: "second", previewAuthor: bob.pseudo });
      expect(d).toMatchObject({ unreadCount: 1, preview: "en privé" });
      expect(d.thread.title).toBe(bob.pseudo);
      // Mes propres messages ne comptent pas comme non lus pour moi.
      expect((await request(server()).get("/v1/forum/inbox").set(bob.auth).expect(200)).body.find((i: { thread: { id: string } }) => i.thread.id === dm.id).unreadCount).toBe(0);

      await messages(alice, gThread.id).expect(200);
      const after = (await request(server()).get("/v1/forum/inbox").set(alice.auth).expect(200)).body as { thread: { id: string }; unreadCount: number }[];
      expect(after.find((i) => i.thread.id === gThread.id)?.unreadCount).toBe(0);
      expect(after.find((i) => i.thread.id === dm.id)?.unreadCount).toBe(1);

      // Fil public suivi : dans la boîte, non-lus à partir du suivi.
      const eventThread = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(alice.auth).expect(200)).body as { id: string };
      await request(server()).put(`/v1/forum/threads/${eventThread.id}/follow`).set(alice.auth).expect(204);
      await post(bob, eventThread.id, "avis sur le match").expect(201);
      const withPublic = (await request(server()).get("/v1/forum/inbox").set(alice.auth).expect(200)).body as { thread: { id: string }; unreadCount: number }[];
      expect(withPublic.find((i) => i.thread.id === eventThread.id)?.unreadCount).toBe(1);
      // Un compte sans groupe ni suivi a une boîte vide.
      const loner = await player();
      expect((await request(server()).get("/v1/forum/inbox").set(loner.auth).expect(200)).body).toEqual([]);
      await request(server()).get("/v1/forum/inbox").expect(401);
    });
  });

  describe("partage", () => {
    it("un match, une compétition : seul l'identifiant voyage ; refusé si inconnu", async () => {
      const alice = await player();
      const bob = await player();
      const groupId = await group(alice, bob);
      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);

      const sent = await post(alice, thread.id, "", { share: { kind: "event", refId: eventId } }).expect(201);
      expect(sent.body).toMatchObject({ kind: "event", body: "", shared: { kind: "event", refId: eventId, locked: false } });
      await post(alice, thread.id, "regarde cette compétition", { share: { kind: "competition", refId: competitionId } }).expect(201);
      const read = await messages(bob, thread.id).expect(200);
      expect(read.body.messages.map((m: { kind: string }) => m.kind).sort()).toEqual(["competition", "event"]);
      expect((await post(alice, thread.id, "", { share: { kind: "event", refId: randomUUID() } }).expect(404)).status).toBe(404);
      expect((await post(alice, thread.id, "", { share: { kind: "competition", refId: randomUUID() } }).expect(404)).status).toBe(404);
      await post(alice, thread.id, "", { share: { kind: "event", refId: "pas-un-uuid" } }).expect(400);
      // Pas de lien libre dans le commentaire d'un partage.
      await post(alice, thread.id, "voir https://exemple.test", { share: { kind: "event", refId: eventId } }).expect(400);
      // Ni partage et sondage ensemble.
      await post(alice, thread.id, "x", { share: { kind: "event", refId: eventId }, pollOptions: ["a", "b"] }).expect(400);
    });

    it("un pronostic reste caché jusqu'au coup d'envoi, côté serveur ; seulement en privé", async () => {
      const alice = await player();
      const bob = await player();
      const groupId = await group(alice, bob);
      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);

      expect((await post(alice, thread.id, "", { share: { kind: "prediction", refId: eventId } }).expect(400)).body.code).toBe("NO_PREDICTION");
      await request(server()).put("/v1/predictions").set(alice.auth).send({ eventId, pickedEntityId: teamAId, pickedScore: 2, otherScore: 1 }).expect(200);
      const sent = await post(alice, thread.id, "", { share: { kind: "prediction", refId: eventId } }).expect(201);
      expect(sent.body.shared).toMatchObject({ kind: "prediction", locked: false, pickedEntityId: teamAId });

      // Avant le match : Bob ne voit pas le choix, même en appelant l'API directement.
      const hidden = (await messages(bob, thread.id).expect(200)).body.messages[0];
      expect(hidden.shared).toMatchObject({ kind: "prediction", locked: true, pickedEntityId: null, pickedScore: null });
      expect(JSON.stringify(hidden)).not.toContain(teamAId);
      // Une fois le match lancé, il apparaît.
      await prisma.event.update({ where: { id: eventId }, data: { status: "live", startsAt: new Date(Date.now() - 60_000) } });
      const visible = (await messages(bob, thread.id).expect(200)).body.messages[0];
      expect(visible.shared).toMatchObject({ locked: false, pickedEntityId: teamAId, pickedScore: 2, otherScore: 1 });
      await prisma.event.update({ where: { id: eventId }, data: { status: "scheduled", startsAt: new Date(Date.now() + 3_600_000) } });

      // Dans un fil public : refusé.
      const beta = await player({ beta: true });
      const publicThread = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(beta.auth).expect(200)).body as { id: string };
      expect((await post(beta, publicThread.id, "", { share: { kind: "prediction", refId: eventId } }).expect(400)).body.code).toBe("SHARE_PRIVATE_ONLY");
    });
  });

  describe("recherche", () => {
    it("trouve équipes, compétitions et discussions publiques ; réservée au forum ouvert", async () => {
      const beta = await player({ beta: true });
      const found = (await request(server()).get("/v1/forum/search").query({ q: `Disc Alpha ${suffix}` }).set(beta.auth).expect(200)).body as { kind: string; targetId: string; threadId: string | null }[];
      expect(found.find((r) => r.kind === "entity" && r.targetId === teamAId)).toMatchObject({ threadId: null });
      const comp = (await request(server()).get("/v1/forum/search").query({ q: `Disc ${suffix}` }).set(beta.auth).expect(200)).body as { kind: string; targetId: string }[];
      expect(comp.some((r) => r.kind === "competition" && r.targetId === competitionId)).toBe(true);
      const games = (await request(server()).get("/v1/forum/search").query({ q: "valor" }).set(beta.auth).expect(200)).body as { kind: string; targetId: string }[];
      expect(games.some((r) => r.kind === "game" && r.targetId === "valorant")).toBe(true);
      // Une fois le fil créé, la recherche renvoie son identifiant.
      const thread = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "entity", targetId: teamAId }).set(beta.auth).expect(200)).body as { id: string };
      threadIds.push(thread.id);
      const again = (await request(server()).get("/v1/forum/search").query({ q: `Disc Alpha ${suffix}` }).set(beta.auth).expect(200)).body as { kind: string; threadId: string | null }[];
      expect(again.find((r) => r.kind === "entity")?.threadId).toBe(thread.id);
      // Les fils privés ne sortent jamais d'une recherche.
      expect((await request(server()).get("/v1/forum/search").query({ q: "Copains" }).set(beta.auth).expect(200)).body).toEqual([]);
      // Trop court : vide. Hors bêta : fermé.
      expect((await request(server()).get("/v1/forum/search").query({ q: "a" }).set(beta.auth).expect(200)).body).toEqual([]);
      const outsider = await player();
      expect((await request(server()).get("/v1/forum/search").query({ q: "valorant" }).set(outsider.auth).expect(403)).body.code).toBe("FORUM_CLOSED");
    });
  });

  describe("sondages", () => {
    it("lancés par un modérateur, un vote par personne, modifiable et retirable", async () => {
      const moderator = await player({ beta: true, moderator: true });
      const alice = await player({ beta: true });
      const thread = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(moderator.auth).expect(200)).body as { id: string };

      expect((await post(alice, thread.id, "Qui gagne ?", { pollOptions: ["A", "B"] }).expect(403)).body.code).toBe("NOT_MODERATOR");
      await post(moderator, thread.id, "Qui gagne ?", { pollOptions: ["A"] }).expect(400);
      await post(moderator, thread.id, "Qui gagne ?", { pollOptions: ["A", "a"] }).expect(400);
      const poll = (await post(moderator, thread.id, "Qui gagne ?", { pollOptions: ["Alpha", "Beta"] }).expect(201)).body;
      expect(poll).toMatchObject({ kind: "poll", body: "Qui gagne ?", poll: { total: 0, myVote: null, options: [{ label: "Alpha", votes: 0 }, { label: "Beta", votes: 0 }] } });

      const vote = (account: TestAccount, option: number) => request(server()).put(`/v1/forum/messages/${poll.id}/vote`).set(account.auth).send({ option });
      await vote(alice, 0).expect(204);
      await vote(moderator, 1).expect(204);
      await vote(alice, 5).expect(400);
      await vote(alice, 1).expect(204);
      const read = (await messages(alice, thread.id).expect(200)).body.messages.find((m: { id: string }) => m.id === poll.id);
      expect(read.poll).toMatchObject({ total: 2, myVote: 1, options: [{ votes: 0 }, { votes: 2 }] });
      await request(server()).delete(`/v1/forum/messages/${poll.id}/vote`).set(alice.auth).expect(204);
      const after = (await messages(alice, thread.id).expect(200)).body.messages.find((m: { id: string }) => m.id === poll.id);
      expect(after.poll).toMatchObject({ total: 1, myVote: null });
      // Un message texte n'est pas un sondage.
      const text = await post(alice, thread.id, "salut").expect(201);
      await vote(alice, 0).expect(204);
      await request(server()).put(`/v1/forum/messages/${text.body.id}/vote`).set(alice.auth).send({ option: 0 }).expect(404);
    });
  });

  describe("tableau des idées", () => {
    it("idées à plat, votées par 👍, statut posé par un modérateur, jamais dans la liste publique", async () => {
      const moderator = await player({ beta: true, moderator: true });
      const alice = await player({ beta: true });
      const bob = await player({ beta: true });
      const board = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "feature", targetId: "ideas" }).set(alice.auth).expect(200)).body as { id: string; kind: string; title: string };
      expect(board).toMatchObject({ kind: "feature", title: "Boîte à idées" });
      await request(server()).get("/v1/forum/threads/resolve").query({ kind: "feature", targetId: "autre" }).set(alice.auth).expect(400);
      const listed = (await request(server()).get("/v1/forum/threads").set(alice.auth).expect(200)).body as { id: string }[];
      expect(listed.some((t) => t.id === board.id)).toBe(false);

      const first = (await post(alice, board.id, "Un mode sombre plus sombre").expect(201)).body;
      const second = (await post(bob, board.id, "Des alertes pour les streams").expect(201)).body;
      await post(alice, board.id, "x", { parentId: first.id }).expect(400);
      await post(alice, board.id, "", { share: { kind: "event", refId: eventId } }).expect(400);
      await request(server()).put(`/v1/forum/messages/${second.id}/reaction`).set(alice.auth).send({ emoji: "up" }).expect(204);
      await request(server()).put(`/v1/forum/messages/${second.id}/reaction`).set(moderator.auth).send({ emoji: "up" }).expect(204);

      const ordered = (await messages(alice, board.id).expect(200)).body.messages as { id: string; reactions: { count: number }[]; ideaStatus: string | null }[];
      const mine = ordered.filter((m) => [first.id, second.id].includes(m.id));
      expect(mine.map((m) => m.id)).toEqual([second.id, first.id]);

      const setStatus = (account: TestAccount, id: string, status: string) => request(server()).put(`/v1/forum/moderation/messages/${id}/idea-status`).set(account.auth).send({ status });
      expect((await setStatus(alice, first.id, "planned").expect(403)).body.code).toBe("NOT_MODERATOR");
      await setStatus(moderator, first.id, "nimporte").expect(400);
      await setStatus(moderator, second.id, "done").expect(204);
      const after = (await messages(alice, board.id).expect(200)).body.messages as { id: string; ideaStatus: string | null }[];
      const ids = after.filter((m) => [first.id, second.id].includes(m.id));
      // Une idée « faite » descend sous les idées ouvertes, même plus votée.
      expect(ids.map((m) => m.id)).toEqual([first.id, second.id]);
      expect(ids[1].ideaStatus).toBe("done");
      await request(server()).delete(`/v1/forum/moderation/messages/${second.id}/idea-status`).set(moderator.auth).expect(204);
      // Le statut ne s'applique qu'à une idée.
      const eventThread = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(alice.auth).expect(200)).body as { id: string };
      const note = (await post(alice, eventThread.id, "salut").expect(201)).body;
      await setStatus(moderator, note.id, "planned").expect(404);
    });
  });
  describe("lecture en tchat, non-lus, vu, écrit…, sourdine", () => {
    it("les fils privés sont à plat (les réponses citent), avec le premier non-lu de la page", async () => {
      const alice = await player();
      const bob = await player();
      const groupId = await group(alice, bob);
      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);
      const first = (await post(alice, thread.id, "premier").expect(201)).body;
      await post(bob, thread.id, "reponse a Alice", { parentId: first.id }).expect(201);
      await post(bob, thread.id, "deuxieme de Bob").expect(201);

      // Alice n'a rien lu depuis son premier message : deux messages de Bob sont nouveaux, le plus ancien est signalé.
      const page = (await messages(alice, thread.id).expect(200)).body;
      expect(page.messages.map((m: { body: string }) => m.body)).toEqual(["deuxieme de Bob", "reponse a Alice", "premier"]);
      expect(page.messages.every((m: { replies: unknown[] }) => m.replies.length === 0)).toBe(true);
      expect(page.messages[1].replyTo).toMatchObject({ messageId: first.id, snippet: "premier" });
      expect(page.unreadCount).toBe(2);
      expect(page.firstUnreadId).toBe(page.messages[1].id);
      // Une fois lu, plus rien de nouveau.
      const again = (await messages(alice, thread.id).expect(200)).body;
      expect(again).toMatchObject({ unreadCount: 0, firstUnreadId: null });
      // Un fil public garde son arbre et n'a ni compteur ni « vu ».
      const beta = await player({ beta: true });
      const pub = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(beta.auth).expect(200)).body as { id: string };
      const root = (await post(beta, pub.id, "racine").expect(201)).body;
      await post(beta, pub.id, "fille", { parentId: root.id }).expect(201);
      const tree = (await messages(beta, pub.id).expect(200)).body;
      expect(tree.messages.find((m: { id: string }) => m.id === root.id).replies).toHaveLength(1);
      expect(tree.unreadCount ?? 0).toBe(0);
    });

    it("message privé : « Vu » quand l'autre a lu, « écrit… » quelques secondes", async () => {
      const { alice, bob } = await sharedPair();
      const dm = (await openDm(alice, bob.userId).expect(201)).body as { id: string };
      threadIds.push(dm.id);
      await post(alice, dm.id, "tu es la ?").expect(201);
      expect((await messages(alice, dm.id).expect(200)).body.seenAt).toBeNull();
      await messages(bob, dm.id).expect(200);
      const seen = (await messages(alice, dm.id).expect(200)).body;
      expect(new Date(seen.seenAt).getTime()).toBeGreaterThanOrEqual(new Date(seen.messages[0].createdAt).getTime());

      expect((await messages(alice, dm.id).expect(200)).body.typing).toBeNull();
      await request(server()).put(`/v1/forum/threads/${dm.id}/typing`).set(bob.auth).expect(204);
      expect((await messages(alice, dm.id).expect(200)).body.typing).toBe(bob.pseudo);
      // On ne se voit pas écrire soi-même, et un tiers ne peut rien signaler.
      expect((await messages(bob, dm.id).expect(200)).body.typing).toBeNull();
      const carol = await player();
      await request(server()).put(`/v1/forum/threads/${dm.id}/typing`).set(carol.auth).expect(204);
      expect((await messages(alice, dm.id).expect(200)).body.typing).toBe(bob.pseudo);
    });

    it("sourdine d'un fil privé : par personne, réservée aux membres, sans effet sur les fils publics", async () => {
      const { alice, bob, groupId } = await sharedPair();
      const carol = await player();
      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);
      expect((await messages(alice, thread.id).expect(200)).body.thread.muted).toBe(false);
      await request(server()).put(`/v1/forum/threads/${thread.id}/mute`).set(alice.auth).expect(204);
      expect((await messages(alice, thread.id).expect(200)).body.thread.muted).toBe(true);
      expect((await messages(bob, thread.id).expect(200)).body.thread.muted).toBe(false);
      const inbox = (await request(server()).get("/v1/forum/inbox").set(alice.auth).expect(200)).body as { thread: { id: string; muted: boolean } }[];
      expect(inbox.find((i) => i.thread.id === thread.id)?.thread.muted).toBe(true);
      await request(server()).delete(`/v1/forum/threads/${thread.id}/mute`).set(alice.auth).expect(204);
      expect((await messages(alice, thread.id).expect(200)).body.thread.muted).toBe(false);
      await request(server()).put(`/v1/forum/threads/${thread.id}/mute`).set(carol.auth).expect(404);
      const beta = await player({ beta: true });
      const pub = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(beta.auth).expect(200)).body as { id: string };
      await request(server()).put(`/v1/forum/threads/${pub.id}/mute`).set(beta.auth).expect(404);
    });
  });

  describe("sondage à durée et partage d'équipe", () => {
    it("un sondage terminé n'accepte plus de vote et se présente comme fermé", async () => {
      const moderator = await player({ beta: true, moderator: true });
      const alice = await player({ beta: true });
      const thread = (await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(moderator.auth).expect(200)).body as { id: string };
      await post(moderator, thread.id, "Durée ?", { pollOptions: ["A", "B"], pollHours: 5 }).expect(400);
      const poll = (await post(moderator, thread.id, "Durée ?", { pollOptions: ["A", "B"], pollHours: 24 }).expect(201)).body;
      expect(poll.poll).toMatchObject({ closed: false });
      // Le client Dart généré envoie la durée en chaîne (« "24" ») : le serveur l'accepte aussi.
      await post(moderator, thread.id, "Durée texte ?", { pollOptions: ["A", "B"], pollHours: "1" }).expect(201);
      expect(new Date(poll.poll.endsAt).getTime()).toBeGreaterThan(Date.now() + 23 * 3_600_000);
      await request(server()).put(`/v1/forum/messages/${poll.id}/vote`).set(alice.auth).send({ option: 0 }).expect(204);
      // La date de fin passe : la dernière réponse reste lisible, le vote est refusé.
      await prisma.forumMessage.update({ where: { id: poll.id }, data: { payload: { options: ["A", "B"], endsAt: new Date(Date.now() - 1000).toISOString() } } });
      const closed = (await messages(alice, thread.id).expect(200)).body.messages.find((m: { id: string }) => m.id === poll.id);
      expect(closed.poll).toMatchObject({ closed: true, total: 1, myVote: 0 });
      const res = await request(server()).put(`/v1/forum/messages/${poll.id}/vote`).set(alice.auth).send({ option: 1 }).expect(403);
      expect(res.body.code).toBe("POLL_CLOSED");
      // Sans durée : jamais fermé.
      const open = (await post(moderator, thread.id, "Sans fin ?", { pollOptions: ["A", "B"] }).expect(201)).body;
      expect(open.poll).toMatchObject({ closed: false, endsAt: null });
    });

    it("partage d'une équipe : identifiant seulement, équipe inconnue refusée", async () => {
      const { alice, groupId } = await sharedPair();
      const thread = await groupThread(alice, groupId);
      threadIds.push(thread.id);
      const sent = await post(alice, thread.id, "", { share: { kind: "team", refId: teamAId } }).expect(201);
      expect(sent.body).toMatchObject({ kind: "team", shared: { kind: "team", refId: teamAId, locked: false } });
      await post(alice, thread.id, "", { share: { kind: "team", refId: randomUUID() } }).expect(404);
      await post(alice, thread.id, "", { share: { kind: "team", refId: competitionId } }).expect(404);
    });
  });
});
