import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { FcmService } from "./fcm.service";
import { NotificationDispatchService } from "./notification-dispatch.service";
import { PredictionReminderService } from "./prediction-reminder.service";

// Intégration contre le Postgres de dev (comme `notification-dispatch.service.spec.ts`), FCM simulé.
describe("PredictionReminderService (intégration)", () => {
  const prisma = new PrismaClient();
  const fcm = new FcmService(new ConfigService(process.env));
  const reminder = new PredictionReminderService(prisma, fcm, new NotificationDispatchService(prisma, fcm));

  const slug = `test-remind-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  const teams: string[] = [];
  const users: string[] = [];

  beforeEach(() => {
    fcm.send = jest.fn().mockResolvedValue({ tokenInvalid: false });
  });

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test rappel" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test rappel", status: "live", importance: 3 } })).id;
    for (const name of ["Test A", "Test B"]) teams.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name } })).id);
  });

  afterAll(async () => {
    await prisma.notificationLog.deleteMany({ where: { userId: { in: users } } });
    await prisma.prediction.deleteMany({ where: { userId: { in: users } } });
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

  async function eventIn(minutes: number): Promise<string> {
    const event = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: "Test A vs Test B",
        status: "scheduled",
        importance: 3,
        startsAt: new Date(Date.now() + minutes * 60_000 - 20_000),
        participants: { create: teams.map((entityId) => ({ id: randomUUID(), entityId })) },
      },
    });
    return event.id;
  }

  async function follower(opts: { pseudo?: string | null; remind?: boolean } = {}): Promise<string> {
    const id = randomUUID();
    users.push(id);
    const pseudo = opts.pseudo === undefined ? `t${id.slice(0, 8)}` : opts.pseudo;
    await prisma.appUser.create({
      data: { id, pseudo, pseudoKey: pseudo, setting: { create: { id: randomUUID(), notifyPredictionReminders: opts.remind ?? true } } },
    });
    await prisma.device.create({ data: { id: randomUUID(), userId: id, installId: randomUUID(), platform: "android", pushToken: `tok-${id}` } });
    await prisma.subscription.create({ data: { id: randomUUID(), userId: id, targetType: "entity", targetId: teams[0], level: "all" } });
    return id;
  }

  const logsOf = (userId: string, eventId: string) => prisma.notificationLog.count({ where: { userId, eventId, type: "prediction_reminder" } });

  it("rappelle une seule fois, 30 minutes avant, l'abonné sans pronostic", async () => {
    const eventId = await eventIn(30);
    const userId = await follower();
    await reminder.run();
    await reminder.run();
    expect(await logsOf(userId, eventId)).toBe(1);
    expect(fcm.send).toHaveBeenCalledTimes(1);
  });

  it("ne rappelle pas hors de la fenêtre de 30 minutes", async () => {
    const eventId = await eventIn(60);
    const userId = await follower();
    await reminder.run();
    expect(await logsOf(userId, eventId)).toBe(0);
  });

  it("ne rappelle pas qui a déjà pronostiqué, a coupé le rappel ou n'a pas de pseudo", async () => {
    const eventId = await eventIn(30);
    const done = await follower();
    await prisma.prediction.create({ data: { id: randomUUID(), userId: done, eventId, pickedEntityId: teams[0] } });
    const off = await follower({ remind: false });
    const noPseudo = await follower({ pseudo: null });
    await reminder.run();
    expect(await logsOf(done, eventId)).toBe(0);
    expect(await logsOf(off, eventId)).toBe(0);
    expect(await logsOf(noPseudo, eventId)).toBe(0);
  });
});
