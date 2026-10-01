import { randomUUID } from "node:crypto";
import { INestApplication } from "@nestjs/common";
import { PrismaClient } from "@news/db";
import { FORUM_TERMS_VERSION } from "@news/domain";
import request from "supertest";
import { createTestApp, deleteTestUsers, loginTestUser, TestAccount } from "./test-utils";

// e2e (Supertest) contre le vrai Postgres de dev (docs/04 J13) : accès, fils, messages, réponses,
// réactions, signalements, blocages, camps, modération, suppression du compte.
describe("Forum (e2e)", () => {
  let app: INestApplication;
  let prisma: PrismaClient;

  const suffix = randomUUID().slice(0, 8);
  let categoryId: string;
  let competitionId: string;
  let teamAId: string;
  let teamBId: string;
  let eventId: string;
  let liveEventId: string;
  const threadIds: string[] = [];

  beforeAll(async () => {
    app = await createTestApp();
    prisma = new PrismaClient();
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: `test-forum-${suffix}`, name: "Test forum" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Forum", status: "live", game: "valorant" } })).id;
    teamAId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Forum A" } })).id;
    teamBId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Forum B" } })).id;
    liveEventId = (
      await prisma.event.create({
        data: {
          id: randomUUID(),
          competitionId,
          kind: "match",
          name: "Forum Live A vs Forum Live B",
          status: "live",
          startsAt: new Date(Date.now() - 600_000),
          participants: { create: [{ id: randomUUID(), entityId: teamAId }, { id: randomUUID(), entityId: teamBId }] },
        },
      })
    ).id;
    eventId = (
      await prisma.event.create({
        data: {
          id: randomUUID(),
          competitionId,
          kind: "match",
          name: "Forum A vs Forum B",
          status: "scheduled",
          startsAt: new Date(Date.now() + 3_600_000),
          participants: { create: [{ id: randomUUID(), entityId: teamAId }, { id: randomUUID(), entityId: teamBId }] },
        },
      })
    ).id;
  });

  afterAll(async () => {
    await prisma.forumThread.deleteMany({ where: { OR: [{ id: { in: threadIds } }, { targetId: { in: [eventId, liveEventId] } }, { kind: "free", title: { contains: suffix } }] } });
    await deleteTestUsers(prisma);
    // Le journal garde les décisions d'un modérateur supprimé (ligne anonyme) : on retire celles des tests.
    await prisma.moderationLog.deleteMany({ where: { moderatorId: null } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: [teamAId, teamBId] } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
    await app.close();
  });

  const server = () => app.getHttpServer();
  const pseudo = (base: string) => `${base}${randomUUID().slice(0, 6)}`;

  /** Compte prêt à écrire : bêta, pseudo, conditions acceptées, créé il y a 2 jours. */
  async function poster(options: { moderator?: boolean; old?: boolean; terms?: boolean; betaOnly?: boolean } = {}): Promise<TestAccount & { pseudo: string }> {
    const account = await loginTestUser(app);
    const name = pseudo("Fan");
    if (!options.betaOnly) await request(server()).put("/v1/me/profile").set(account.auth).send({ pseudo: name }).expect(200);
    await prisma.appUser.update({
      where: { id: account.userId },
      data: { forumBeta: true, isModerator: options.moderator ?? false, createdAt: new Date(Date.now() - (options.old === false ? 0 : 2 * 86_400_000)) },
    });
    if (options.terms !== false && !options.betaOnly) await request(server()).post("/v1/forum/terms").set(account.auth).send({ version: FORUM_TERMS_VERSION }).expect(201);
    return { ...account, pseudo: name };
  }

  async function eventThread(account: TestAccount): Promise<string> {
    const res = await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(account.auth).expect(200);
    return (res.body as { id: string }).id;
  }

  const post = (account: TestAccount, threadId: string, body: string, parentId?: string) =>
    request(server()).post(`/v1/forum/threads/${threadId}/messages`).set(account.auth).send({ body, parentId });

  describe("accès", () => {
    it("bêta fermée : un invité et un compte hors bêta n'y accèdent pas", async () => {
      await request(server()).get("/v1/forum/threads").expect(403);
      const outsider = await loginTestUser(app);
      const res = await request(server()).get("/v1/forum/threads").set(outsider.auth).expect(403);
      expect(res.body.code).toBe("FORUM_CLOSED");
      const status = await request(server()).get("/v1/forum/status").expect(200);
      expect(status.body).toMatchObject({ enabled: false, signedIn: false, canPost: false });
    });

    it("écrire exige un pseudo, les conditions et 24 h d'ancienneté", async () => {
      const account = await poster({ betaOnly: true });
      const thread = await eventThread(account);
      expect((await post(account, thread, "salut").expect(403)).body.code).toBe("PROFILE_REQUIRED");

      const noTerms = await poster({ terms: false });
      expect((await post(noTerms, thread, "salut").expect(403)).body.code).toBe("TERMS_REQUIRED");

      const fresh = await poster({ old: false });
      expect((await post(fresh, thread, "salut").expect(403)).body.code).toBe("ACCOUNT_TOO_NEW");
      const status = await request(server()).get("/v1/forum/status").set(fresh.auth).expect(200);
      expect(status.body).toMatchObject({ enabled: true, canPost: false, blockedReason: "ACCOUNT_TOO_NEW" });
    });

    it("refuse une version périmée des conditions", async () => {
      const account = await poster({ terms: false });
      await request(server()).post("/v1/forum/terms").set(account.auth).send({ version: 999 }).expect(400);
    });
  });

  describe("fils", () => {
    it("crée le fil d'un match une seule fois, rattaché au jeu", async () => {
      const account = await poster();
      const first = await eventThread(account);
      const second = await eventThread(account);
      expect(second).toBe(first);
      const res = await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(account.auth).expect(200);
      expect(res.body).toMatchObject({ kind: "event", title: "Forum A vs Forum B", game: "valorant", locked: false });
    });

    it("résout les fils d'équipe, de compétition et de jeu ; 404 sur un identifiant inconnu", async () => {
      const account = await poster();
      const get = (kind: string, targetId: string) => request(server()).get("/v1/forum/threads/resolve").query({ kind, targetId }).set(account.auth);
      const team = await get("entity", teamAId).expect(200);
      const competition = await get("competition", competitionId).expect(200);
      const game = await get("game", "valorant").expect(200);
      threadIds.push(team.body.id, competition.body.id);
      expect(team.body).toMatchObject({ title: "Forum A", game: "valorant" });
      expect(game.body).toMatchObject({ title: "Valorant", game: "valorant" });
      await get("event", randomUUID()).expect(404);
      await get("game", "inconnu").expect(404);
      await get("free", "x").expect(400);
    });

    it("crée une discussion libre, refuse un titre avec lien, la liste ensuite", async () => {
      const account = await poster();
      await request(server()).post("/v1/forum/threads").set(account.auth).send({ title: "ab" }).expect(400);
      await request(server()).post("/v1/forum/threads").set(account.auth).send({ title: `regarde youtube.com ${suffix}` }).expect(400);
      const created = await request(server()).post("/v1/forum/threads").set(account.auth).send({ title: `Meilleur agent ${suffix}`, game: "valorant" }).expect(201);
      expect(created.body).toMatchObject({ kind: "free", game: "valorant", messageCount: 0 });
      const list = await request(server()).get("/v1/forum/threads").query({ game: "valorant", kind: "free" }).set(account.auth).expect(200);
      expect((list.body as { id: string }[]).some((t) => t.id === created.body.id)).toBe(true);
    });
  });

  describe("messages", () => {
    it("poste, liste, répond en cascade (arbre), compte les messages", async () => {
      const a = await poster();
      const b = await poster();
      const thread = await eventThread(a);
      const root = await post(a, thread, "Quelle série en perspective !").expect(201);
      const reply = await post(b, thread, "Totalement d'accord", root.body.id).expect(201);
      expect(reply.body.parentId).toBe(root.body.id);
      // Répondre à une réponse crée un niveau de plus : c'est un vrai arbre, pas une liste à plat.
      const nested = await post(a, thread, "Merci", reply.body.id).expect(201);
      expect(nested.body.parentId).toBe(reply.body.id);

      const page = await request(server()).get(`/v1/forum/threads/${thread}/messages`).set(b.auth).expect(200);
      type Node = { id: string; author: { pseudo: string }; replies: Node[] };
      const found = (page.body.messages as Node[]).find((m) => m.id === root.body.id);
      expect(found?.author.pseudo).toBe(a.pseudo);
      expect(found?.replies.map((r) => r.id)).toEqual([reply.body.id]);
      expect(found?.replies[0].replies.map((r) => r.id)).toEqual([nested.body.id]);
      const threadInfo = await request(server()).get("/v1/forum/threads/resolve").query({ kind: "event", targetId: eventId }).set(a.auth).expect(200);
      expect(threadInfo.body.messageCount).toBeGreaterThanOrEqual(3);
    });

    it("limite la profondeur : à 6 niveaux, la réponse se place au même niveau", async () => {
      const a = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Profondeur ${suffix}` }).expect(201);
      let parentId: string | undefined;
      const ids: string[] = [];
      for (let level = 1; level <= 7; level++) {
        const res = await post(a, created.body.id, `niveau ${level}`, parentId).expect(201);
        ids.push(res.body.id);
        parentId = res.body.id;
      }
      // Le 7e message répond au 6e mais est rangé comme frère du 6e (enfant du 5e).
      const seventh = await prisma.forumMessage.findUniqueOrThrow({ where: { id: ids[6] } });
      expect(seventh.parentId).toBe(ids[4]);
    });

    it("supprimer un message du milieu fait remonter ses réponses d'un niveau", async () => {
      const a = await poster();
      const b = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Remontée ${suffix}` }).expect(201);
      const root = await post(a, created.body.id, "racine").expect(201);
      const middle = await post(b, created.body.id, "milieu", root.body.id).expect(201);
      const leaf = await post(a, created.body.id, "feuille", middle.body.id).expect(201);
      await request(server()).delete(`/v1/forum/messages/${middle.body.id}`).set(b.auth).expect(204);
      expect((await prisma.forumMessage.findUniqueOrThrow({ where: { id: leaf.body.id } })).parentId).toBe(root.body.id);
    });

    it("refuse vide, lien et mot interdit", async () => {
      const a = await poster();
      const thread = await eventThread(a);
      expect((await post(a, thread, "   ").expect(400)).body.code).toBe("MESSAGE_EMPTY");
      expect((await post(a, thread, "va sur https://exemple.test").expect(400)).body.code).toBe("MESSAGE_LINK");
      expect((await post(a, thread, "quel connard").expect(400)).body.code).toBe("MESSAGE_FORBIDDEN");
      expect((await post(a, thread, "x".repeat(600)).expect(400)).body.code).toBeDefined();
    });

    it("pagine par curseur, du plus récent au plus ancien", async () => {
      const a = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Pagination ${suffix}` }).expect(201);
      for (const n of [1, 2, 3]) await post(a, created.body.id, `message ${n}`).expect(201);
      const first = await request(server()).get(`/v1/forum/threads/${created.body.id}/messages`).query({ limit: 2 }).set(a.auth).expect(200);
      expect((first.body.messages as { body: string }[]).map((m) => m.body)).toEqual(["message 3", "message 2"]);
      expect(first.body.nextBefore).toBeTruthy();
      const second = await request(server()).get(`/v1/forum/threads/${created.body.id}/messages`).query({ limit: 2, before: first.body.nextBefore }).set(a.auth).expect(200);
      expect((second.body.messages as { body: string }[]).map((m) => m.body)).toEqual(["message 1"]);
      expect(second.body.nextBefore).toBeNull();
    });

    it("l'auteur supprime son message ; un autre joueur ne le peut pas", async () => {
      const a = await poster();
      const b = await poster();
      const thread = await eventThread(a);
      const message = await post(a, thread, "à supprimer").expect(201);
      expect((await request(server()).delete(`/v1/forum/messages/${message.body.id}`).set(b.auth).expect(403)).body.code).toBe("NOT_MODERATOR");
      await request(server()).delete(`/v1/forum/messages/${message.body.id}`).set(a.auth).expect(204);
      expect(await prisma.forumMessage.findUnique({ where: { id: message.body.id } })).toBeNull();
    });
  });

  describe("réactions", () => {
    it("une réaction par personne, remplaçable et retirable", async () => {
      const a = await poster();
      const b = await poster();
      const thread = await eventThread(a);
      const message = await post(a, thread, "belle action").expect(201);
      await request(server()).put(`/v1/forum/messages/${message.body.id}/reaction`).set(a.auth).send({ emoji: "fire" }).expect(204);
      await request(server()).put(`/v1/forum/messages/${message.body.id}/reaction`).set(b.auth).send({ emoji: "up" }).expect(204);
      await request(server()).put(`/v1/forum/messages/${message.body.id}/reaction`).set(b.auth).send({ emoji: "laugh" }).expect(204);
      await request(server()).put(`/v1/forum/messages/${message.body.id}/reaction`).set(b.auth).send({ emoji: "pas-une-reaction" }).expect(400);

      const read = async () => {
        const page = await request(server()).get(`/v1/forum/threads/${thread}/messages`).set(b.auth).expect(200);
        return (page.body.messages as { id: string; reactions: { emoji: string; count: number }[]; myReaction: string | null }[]).find((m) => m.id === message.body.id)!;
      };
      let found = await read();
      expect(found.myReaction).toBe("laugh");
      expect(found.reactions.sort((x, y) => x.emoji.localeCompare(y.emoji))).toEqual([{ emoji: "fire", count: 1 }, { emoji: "laugh", count: 1 }]);
      await request(server()).delete(`/v1/forum/messages/${message.body.id}/reaction`).set(b.auth).expect(204);
      found = await read();
      expect(found.myReaction).toBeNull();
    });
  });

  describe("signalements et modération", () => {
    it("masque un message après 3 signalements distincts, sans doublon possible", async () => {
      const author = await poster();
      const thread = await eventThread(author);
      const message = await post(author, thread, "message douteux").expect(201);
      const report = (who: TestAccount) => request(server()).post(`/v1/forum/messages/${message.body.id}/report`).set(who.auth).send({ reason: "insult" });

      await report(author).expect(400); // pas son propre message
      const [r1, r2, r3] = [await poster(), await poster(), await poster()];
      await report(r1).expect(204);
      await report(r1).expect(204); // idempotent
      await report(r2).expect(204);
      expect((await prisma.forumMessage.findUniqueOrThrow({ where: { id: message.body.id } })).hiddenAt).toBeNull();
      await report(r3).expect(204);
      expect((await prisma.forumMessage.findUniqueOrThrow({ where: { id: message.body.id } })).hiddenReason).toBe("reports");

      // Masqué sans réponse : il disparaît de la liste.
      const page = await request(server()).get(`/v1/forum/threads/${thread}/messages`).set(r1.auth).expect(200);
      expect((page.body.messages as { id: string }[]).some((m) => m.id === message.body.id)).toBe(false);
    });

    it("file de signalements réservée aux modérateurs ; rejeter rend le message", async () => {
      const author = await poster();
      const thread = await eventThread(author);
      const message = await post(author, thread, "rien de grave").expect(201);
      for (const who of [await poster(), await poster(), await poster()]) {
        await request(server()).post(`/v1/forum/messages/${message.body.id}/report`).set(who.auth).send({ reason: "spam" }).expect(204);
      }
      const normal = await poster();
      await request(server()).get("/v1/forum/moderation/reports").set(normal.auth).expect(403);

      const mod = await poster({ moderator: true });
      const queue = await request(server()).get("/v1/forum/moderation/reports").set(mod.auth).expect(200);
      const entry = (queue.body as { messageId: string; reportCount: number; hidden: boolean }[]).find((r) => r.messageId === message.body.id);
      expect(entry).toMatchObject({ reportCount: 3, hidden: true });

      await request(server()).post(`/v1/forum/moderation/messages/${message.body.id}/dismiss`).set(mod.auth).expect(204);
      const restored = await prisma.forumMessage.findUniqueOrThrow({ where: { id: message.body.id } });
      expect(restored.hiddenAt).toBeNull();
      const after = await request(server()).get("/v1/forum/moderation/reports").set(mod.auth).expect(200);
      expect((after.body as { messageId: string }[]).some((r) => r.messageId === message.body.id)).toBe(false);
    });

    it("un modérateur retire un message, exclut un joueur, verrouille un fil", async () => {
      const author = await poster();
      const mod = await poster({ moderator: true });
      const thread = await request(server()).post("/v1/forum/threads").set(author.auth).send({ title: `Modération ${suffix}` }).expect(201);
      const message = await post(author, thread.body.id, "à retirer").expect(201);

      await request(server()).delete(`/v1/forum/messages/${message.body.id}`).set(mod.auth).expect(204);
      const hidden = await prisma.forumMessage.findUniqueOrThrow({ where: { id: message.body.id } });
      expect(hidden.hiddenReason).toBe("moderator");

      await request(server()).put(`/v1/forum/moderation/users/${author.userId}/ban`).set(mod.auth).expect(204);
      expect((await post(author, thread.body.id, "encore moi").expect(403)).body.code).toBe("BANNED");
      await request(server()).delete(`/v1/forum/moderation/users/${author.userId}/ban`).set(mod.auth).expect(204);
      await post(author, thread.body.id, "de retour").expect(201);

      await request(server()).put(`/v1/forum/moderation/threads/${thread.body.id}/lock`).set(mod.auth).expect(204);
      expect((await post(author, thread.body.id, "verrouillé ?").expect(403)).body.code).toBe("THREAD_LOCKED");
      await request(server()).put(`/v1/forum/moderation/users/${mod.userId}/ban`).set(mod.auth).expect(403); // pas un modérateur sur un autre modérateur
    });
  });

  describe("blocages", () => {
    it("les messages d'un joueur bloqué disparaissent pour celui qui bloque seulement", async () => {
      const a = await poster();
      const b = await poster();
      const other = await poster();
      const thread = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Blocage ${suffix}` }).expect(201);
      await post(b, thread.body.id, "message de b").expect(201);

      const bodies = async (who: TestAccount) => {
        const page = await request(server()).get(`/v1/forum/threads/${thread.body.id}/messages`).set(who.auth).expect(200);
        return (page.body.messages as { body: string | null }[]).map((m) => m.body);
      };
      expect(await bodies(a)).toEqual(["message de b"]);
      await request(server()).put(`/v1/forum/blocks/${b.userId}`).set(a.auth).expect(204);
      await request(server()).put(`/v1/forum/blocks/${a.userId}`).set(a.auth).expect(400);
      expect(await bodies(a)).toEqual([]);
      expect(await bodies(other)).toEqual(["message de b"]);
      const blocks = await request(server()).get("/v1/forum/blocks").set(a.auth).expect(200);
      expect(blocks.body).toEqual([{ userId: b.userId, pseudo: b.pseudo }]);
      await request(server()).delete(`/v1/forum/blocks/${b.userId}`).set(a.auth).expect(204);
      expect(await bodies(a)).toEqual(["message de b"]);
    });
  });

  describe("camps", () => {
    it("exige de suivre l'équipe ; badge visible ; changement limité à une fois par 7 jours", async () => {
      const a = await poster();
      const reader = await poster();
      const thread = await eventThread(a);
      await request(server()).put("/v1/forum/camps").set(a.auth).send({ game: "valorant", entityId: teamAId }).expect(400);

      for (const teamId of [teamAId, teamBId]) await request(server()).post("/v1/subscriptions").set(a.auth).send({ targetType: "entity", targetId: teamId }).expect(201);
      const camps = await request(server()).put("/v1/forum/camps").set(a.auth).send({ game: "valorant", entityId: teamAId }).expect(200);
      expect(camps.body).toEqual([expect.objectContaining({ game: "valorant", entityId: teamAId, changeWaitDays: 0 })]);

      await post(a, thread, "allez A").expect(201);
      const page = await request(server()).get(`/v1/forum/threads/${thread}/messages`).set(reader.auth).expect(200);
      const mine = (page.body.messages as { body: string; author: { camp: { name: string } | null } }[]).find((m) => m.body === "allez A");
      expect(mine?.author.camp?.name).toBe("Forum A");

      await request(server()).put("/v1/forum/camps").set(a.auth).send({ game: "valorant", entityId: teamBId }).expect(200);
      const tooSoon = await request(server()).put("/v1/forum/camps").set(a.auth).send({ game: "valorant", entityId: teamAId }).expect(403);
      expect(tooSoon.body.code).toBe("CAMP_CHANGE_TOO_SOON");

      // Ne plus suivre l'équipe retire le badge.
      await request(server()).delete("/v1/subscriptions").set(a.auth).send({ targetType: "entity", targetId: teamBId }).expect(204);
      const after = await request(server()).get(`/v1/forum/threads/${thread}/messages`).set(reader.auth).expect(200);
      expect((after.body.messages as { body: string; author: { camp: unknown } }[]).find((m) => m.body === "allez A")?.author.camp).toBeNull();
    });
  });

  describe("modifier, spoiler, plafond", () => {
    it("modifie son message dans les 5 minutes, pas ceux des autres, pas après le délai", async () => {
      const a = await poster();
      const b = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Édition ${suffix}` }).expect(201);
      const message = await post(a, created.body.id, "avec une faute").expect(201);
      expect(message.body.edited).toBe(false);
      const edited = await request(server()).patch(`/v1/forum/messages/${message.body.id}`).set(a.auth).send({ body: "sans faute" }).expect(200);
      expect(edited.body).toMatchObject({ body: "sans faute", edited: true });
      expect((await request(server()).patch(`/v1/forum/messages/${message.body.id}`).set(b.auth).send({ body: "piraté" }).expect(403)).body.code).toBe("NOT_AUTHOR");
      expect((await request(server()).patch(`/v1/forum/messages/${message.body.id}`).set(a.auth).send({ body: "va sur www.truc" }).expect(400)).body.code).toBe("MESSAGE_LINK");
      await prisma.forumMessage.update({ where: { id: message.body.id }, data: { createdAt: new Date(Date.now() - 6 * 60_000) } });
      expect((await request(server()).patch(`/v1/forum/messages/${message.body.id}`).set(a.auth).send({ body: "trop tard" }).expect(403)).body.code).toBe("EDIT_WINDOW_CLOSED");
    });

    it("annonce un spoiler par message", async () => {
      const a = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Spoiler ${suffix}` }).expect(201);
      const res = await request(server()).post(`/v1/forum/threads/${created.body.id}/messages`).set(a.auth).send({ body: "2-0 pour eux", isSpoiler: true }).expect(201);
      expect(res.body.isSpoiler).toBe(true);
      expect((await post(a, created.body.id, "pas un spoiler").expect(201)).body.isSpoiler).toBe(false);
    });

    it("plafonne à 10 messages par minute et par compte", async () => {
      const a = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Plafond ${suffix}` }).expect(201);
      for (let i = 1; i <= 10; i++) await post(a, created.body.id, `message ${i}`).expect(201);
      expect((await post(a, created.body.id, "le onzième").expect(403)).body.code).toBe("RATE_LIMIT");
    });
  });

  describe("fil du direct", () => {
    it("est distinct de la discussion du match et n'accepte de messages que pendant le match", async () => {
      const a = await poster();
      const get = (id: string, kind: string) => request(server()).get("/v1/forum/threads/resolve").query({ kind, targetId: id }).set(a.auth).expect(200);
      const debate = await get(liveEventId, "event");
      const live = await get(liveEventId, "live");
      expect(live.body.id).not.toBe(debate.body.id);
      expect(live.body).toMatchObject({ kind: "live", readOnly: false, title: "Direct · Forum Live A vs Forum Live B" });
      await post(a, live.body.id, "allez !").expect(201);

      await prisma.event.update({ where: { id: liveEventId }, data: { status: "finished" } });
      const closed = await get(liveEventId, "live");
      expect(closed.body.readOnly).toBe(true);
      expect((await post(a, live.body.id, "trop tard").expect(403)).body.code).toBe("LIVE_CLOSED");
      await post(a, debate.body.id, "après-match : quel match").expect(201); // la discussion d'après-match reste ouverte
      await prisma.event.update({ where: { id: liveEventId }, data: { status: "live" } });
    });
  });

  describe("fil du direct : tchat à plat", () => {
    it("liste les messages à plat, les réponses citent le message d'origine sans imbrication", async () => {
      const a = await poster();
      const b = await poster();
      const live = await request(server()).get("/v1/forum/threads/resolve").query({ kind: "live", targetId: liveEventId }).set(a.auth).expect(200);
      const first = await post(a, live.body.id, "quel début de match").expect(201);
      const reply = await post(b, live.body.id, "grave, quel round", first.body.id).expect(201);
      const reReply = await post(a, live.body.id, "merci", reply.body.id).expect(201);
      // Aucune imbrication : chaque réponse garde simplement son message cité.
      expect((await prisma.forumMessage.findUniqueOrThrow({ where: { id: reReply.body.id } })).parentId).toBe(reply.body.id);

      const page = await request(server()).get(`/v1/forum/threads/${live.body.id}/messages`).set(b.auth).expect(200);
      type Row = { id: string; body: string; replies: unknown[]; replyTo: { pseudo: string; snippet: string } | null };
      const rows = page.body.messages as Row[];
      const mine = rows.filter((m) => [first.body.id, reply.body.id, reReply.body.id].includes(m.id));
      expect(mine.map((m) => m.body)).toEqual(["merci", "grave, quel round", "quel début de match"]); // plus récent d'abord
      expect(mine.every((m) => m.replies.length === 0)).toBe(true);
      expect(mine[0].replyTo).toMatchObject({ pseudo: b.pseudo, snippet: "grave, quel round" });
      expect(mine[2].replyTo).toBeNull();
    });
  });

  describe("suivre une discussion, tris, épingles, journal", () => {
    it("suit et ne suit plus une discussion ; le créateur suit la sienne", async () => {
      const a = await poster();
      const b = await poster();
      const created = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Suivi ${suffix}` }).expect(201);
      expect(created.body.following).toBe(true);
      const threadFor = async (who: TestAccount) => (await request(server()).get(`/v1/forum/threads/${created.body.id}/messages`).set(who.auth).expect(200)).body.thread;
      expect((await threadFor(b)).following).toBe(false);
      await request(server()).put(`/v1/forum/threads/${created.body.id}/follow`).set(b.auth).expect(204);
      expect((await threadFor(b)).following).toBe(true);
      await request(server()).delete(`/v1/forum/threads/${created.body.id}/follow`).set(b.auth).expect(204);
      expect((await threadFor(b)).following).toBe(false);
    });

    it("trie les discussions par activité récente et par popularité", async () => {
      const a = await poster();
      const quiet = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Calme ${suffix}`, game: "valorant" }).expect(201);
      const busy = await request(server()).post("/v1/forum/threads").set(a.auth).send({ title: `Animée ${suffix}`, game: "valorant" }).expect(201);
      const first = await post(a, quiet.body.id, "un seul message").expect(201);
      await prisma.forumMessage.update({ where: { id: first.body.id }, data: { createdAt: new Date(Date.now() - 2 * 86_400_000) } });
      for (const n of [1, 2, 3]) await post(a, busy.body.id, `échange ${n}`).expect(201);
      const ids = async (sort: string) => ((await request(server()).get("/v1/forum/threads").query({ game: "valorant", kind: "free", sort }).set(a.auth).expect(200)).body as { id: string }[]).map((t) => t.id);
      const active = await ids("active");
      expect(active.indexOf(busy.body.id)).toBeLessThan(active.indexOf(quiet.body.id));
      const popular = await ids("popular");
      expect(popular.indexOf(busy.body.id)).toBeLessThan(popular.indexOf(quiet.body.id));
      await request(server()).get("/v1/forum/threads").query({ sort: "n-importe-quoi" }).set(a.auth).expect(400);
    });

    it("épingle (deux au plus, racines seulement), en tête de page, et tient un journal", async () => {
      const author = await poster();
      const mod = await poster({ moderator: true });
      const created = await request(server()).post("/v1/forum/threads").set(author.auth).send({ title: `Épingles ${suffix}` }).expect(201);
      const m1 = await post(author, created.body.id, "règle 1").expect(201);
      const m2 = await post(author, created.body.id, "règle 2").expect(201);
      const m3 = await post(author, created.body.id, "règle 3").expect(201);
      const reply = await post(author, created.body.id, "réponse", m1.body.id).expect(201);
      const pin = (id: string, who: TestAccount) => request(server()).put(`/v1/forum/moderation/messages/${id}/pin`).set(who.auth);

      await pin(m1.body.id, author).expect(403);
      await pin(reply.body.id, mod).expect(400);
      await pin(m1.body.id, mod).expect(204);
      await pin(m2.body.id, mod).expect(204);
      expect((await pin(m3.body.id, mod).expect(403)).body.code).toBe("PIN_LIMIT");

      const page = await request(server()).get(`/v1/forum/threads/${created.body.id}/messages`).set(author.auth).expect(200);
      const bodies = (page.body.messages as { body: string; pinned: boolean }[]).map((m) => `${m.pinned ? "*" : ""}${m.body}`);
      expect(bodies).toEqual(["*règle 1", "*règle 2", "règle 3"]);
      await request(server()).delete(`/v1/forum/moderation/messages/${m1.body.id}/pin`).set(mod.auth).expect(204);

      await request(server()).get("/v1/forum/moderation/log").set(author.auth).expect(403);
      const log = await request(server()).get("/v1/forum/moderation/log").set(mod.auth).expect(200);
      const mine = (log.body as { moderatorPseudo: string; action: string; detail: string | null }[]).filter((l) => l.moderatorPseudo === mod.pseudo);
      expect(mine.map((l) => l.action)).toEqual(expect.arrayContaining(["pin", "unpin"]));
      expect(mine.find((l) => l.action === "pin")?.detail).toMatch(/règle/);
    });
  });

  describe("profil depuis le forum", () => {
    it("s'ouvre pour qui a écrit sur le forum, avec son camp ; 404 sinon", async () => {
      const writer = await poster();
      const reader = await poster();
      const silent = await poster();
      const thread = await eventThread(writer);
      await request(server()).get(`/v1/users/${writer.userId}/profile`).set(reader.auth).expect(404);
      await post(writer, thread, "bonjour").expect(201);
      const res = await request(server()).get(`/v1/users/${writer.userId}/profile`).set(reader.auth).expect(200);
      expect(res.body).toMatchObject({ userId: writer.userId, pseudo: writer.pseudo, camps: [] });
      await request(server()).get(`/v1/users/${silent.userId}/profile`).set(reader.auth).expect(404);
    });
  });

  describe("compte supprimé (RGPD)", () => {
    it("emporte ses messages ; les réponses des autres restent", async () => {
      const a = await poster();
      const b = await poster();
      const thread = await eventThread(a);
      const root = await post(a, thread, "message racine").expect(201);
      const reply = await post(b, thread, "réponse de b", root.body.id).expect(201);
      await request(server()).delete("/v1/me").set(a.auth).expect(204);
      expect(await prisma.forumMessage.findUnique({ where: { id: root.body.id } })).toBeNull();
      const kept = await prisma.forumMessage.findUniqueOrThrow({ where: { id: reply.body.id } });
      expect(kept.parentId).toBeNull();
    });
  });
});
