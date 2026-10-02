import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { FcmService } from "./fcm.service";
import { MorningDigestService } from "./morning-digest.service";
import { NotificationDispatchService } from "./notification-dispatch.service";

// Intégration contre le Postgres de dev (comme `prediction-reminder.service.spec.ts`), FCM simulé.
// L'heure est fixée en 2020 : aucun vrai compte de la base de dev n'est concerné.
describe("MorningDigestService (intégration)", () => {
  const prisma = new PrismaClient();
  const fcm = new FcmService(new ConfigService(process.env));
  const digest = new MorningDigestService(prisma, fcm, new NotificationDispatchService(prisma, fcm));

  const morning = new Date("2020-03-10T07:30:00Z"); // 9 h 30 à UTC+2
  const slug = `test-digest-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  const teams: string[] = [];
  const users: string[] = [];

  beforeEach(() => {
    fcm.send = jest.fn().mockResolvedValue({ tokenInvalid: false });
  });

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test résumé" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test résumé", status: "live", importance: 3 } })).id;
    for (const name of ["Test A", "Test B"]) teams.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name } })).id);
    await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test A vs Test B",
        status: "scheduled",
        importance: 3,
        startsAt: new Date("2020-03-10T16:00:00Z"), // 18 h à UTC+2
        participants: { create: teams.map((entityId) => ({ id: randomUUID(), entityId })) },
      },
    });
  });

  afterAll(async () => {
    await prisma.notificationLog.deleteMany({ where: { userId: { in: users } } });
    await prisma.device.deleteMany({ where: { userId: { in: users } } });
    await prisma.subscription.deleteMany({ where: { userId: { in: users } } });
    await prisma.userSetting.deleteMany({ where: { userId: { in: users } } });
    await prisma.appUser.deleteMany({ where: { id: { in: users } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: teams } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  async function user(opts: { digest?: boolean; offset?: number; follow?: boolean; quiet?: [number, number] } = {}): Promise<string> {
    const id = randomUUID();
    users.push(id);
    await prisma.appUser.create({
      data: {
        id,
        setting: {
          create: { id: randomUUID(), morningDigest: opts.digest ?? true, quietHoursStart: opts.quiet?.[0] ?? null, quietHoursEnd: opts.quiet?.[1] ?? null },
        },
      },
    });
    await prisma.device.create({ data: { id: randomUUID(), userId: id, installId: randomUUID(), platform: "android", pushToken: `tok-${id}`, utcOffsetMinutes: opts.offset ?? 120 } });
    if (opts.follow ?? true) await prisma.subscription.create({ data: { id: randomUUID(), userId: id, targetType: "entity", targetId: teams[0], level: "all" } });
    return id;
  }

  const sentTo = (userId: string) => (fcm.send as jest.Mock).mock.calls.filter((c) => c[0] === `tok-${userId}`);

  it("envoie une seule fois le résumé du jour, avec l'heure locale du premier match", async () => {
    const id = await user();
    await digest.run(morning);
    await digest.run(new Date(morning.getTime() + 60_000));
    const calls = sentTo(id);
    expect(calls).toHaveLength(1);
    expect(calls[0][2]).toBe("1 match de tes suivis : Test A vs Test B à 18 h.");
  });

  it("n'envoie rien hors de la fenêtre 8 h - 11 h locale", async () => {
    const id = await user();
    await digest.run(new Date("2020-03-10T12:30:00Z")); // 14 h 30 à UTC+2
    await digest.run(new Date("2020-03-10T05:30:00Z")); // 7 h 30
    expect(sentTo(id)).toHaveLength(0);
  });

  it("n'envoie rien sans match suivi, sans le réglage, ni pendant les heures calmes", async () => {
    const noMatch = await user({ follow: false });
    const off = await user({ digest: false });
    const quiet = await user({ quiet: [22, 10] });
    await digest.run(morning);
    expect(sentTo(noMatch)).toHaveLength(0);
    expect(sentTo(off)).toHaveLength(0);
    expect(sentTo(quiet)).toHaveLength(0);
  });

  it("après les heures calmes, il part dans la fenêtre", async () => {
    const id = await user({ quiet: [22, 10] });
    await digest.run(new Date("2020-03-10T08:30:00Z")); // 10 h 30 à UTC+2
    expect(sentTo(id)).toHaveLength(1);
  });
});
