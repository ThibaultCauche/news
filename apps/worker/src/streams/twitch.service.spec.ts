import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { TwitchService } from "./twitch.service";

// Intégration contre le vrai Postgres de dev ; l'API Twitch est simulée.
describe("TwitchService (intégration)", () => {
  const prisma = new PrismaClient();
  const login = `test_chan_${randomUUID().slice(0, 8)}`;
  const absent = `test_none_${randomUUID().slice(0, 8)}`;
  const categorySlug = `test-twitch-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;

  const service = (env: Record<string, string>, calls: string[]) => {
    const s = new TwitchService(prisma, new ConfigService(env));
    s.fetchFn = (async (url: string | URL | Request) => {
      const u = String(url);
      calls.push(u);
      if (u.includes("oauth2/token")) return { ok: true, status: 200, json: async () => ({ access_token: "t", expires_in: 3600 }) };
      if (u.includes("/helix/users")) return { ok: true, status: 200, json: async () => ({ data: [{ login, display_name: "Test Chan", profile_image_url: "https://example.test/a.png" }] }) };
      return { ok: true, status: 200, json: async () => ({ data: [{ user_login: login }] }) };
    }) as typeof fetch;
    return s;
  };

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug: categorySlug, name: "Test twitch" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Twitch" } })).id;
    const streams = [
      { channel: login, url: `https://www.twitch.tv/${login}`, language: "fr", official: true },
      { channel: absent, url: `https://www.twitch.tv/${absent}`, language: "en", official: true },
    ];
    await prisma.event.create({ data: { id: randomUUID(), competitionId, kind: "match", name: "Test", status: "live", streams } });
  });

  afterAll(async () => {
    await prisma.streamChannel.deleteMany({ where: { login: { in: [login, absent] } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  it("sans clés : n'appelle jamais Twitch", async () => {
    const calls: string[] = [];
    await service({}, calls).run();
    expect(calls).toEqual([]);
  });

  it("enregistre le profil et l'état « en direct » des chaînes d'un match en cours", async () => {
    const calls: string[] = [];
    await service({ TWITCH_CLIENT_ID: "id", TWITCH_CLIENT_SECRET: "secret" }, calls).run();

    const row = await prisma.streamChannel.findUnique({ where: { login } });
    expect(row).toMatchObject({ displayName: "Test Chan", imageUrl: "https://example.test/a.png", live: true });
    // Une chaîne inconnue de Twitch garde une ligne vide, hors ligne.
    expect(await prisma.streamChannel.findUnique({ where: { login: absent } })).toMatchObject({ displayName: null, live: false });
  });

  it("ne redemande pas un profil récent, seulement l'état en direct", async () => {
    const calls: string[] = [];
    await service({ TWITCH_CLIENT_ID: "id", TWITCH_CLIENT_SECRET: "secret" }, calls).run();
    expect(calls.some((c) => c.includes("/helix/users"))).toBe(false);
    expect(calls.some((c) => c.includes("/helix/streams"))).toBe(true);
  });
});
