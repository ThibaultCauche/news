import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { FcmService } from "./fcm.service";
import { NotificationDispatchService } from "./notification-dispatch.service";

// Intégration (contre le vrai Postgres de dev, comme les e2e de apps/api) : seule
// la déduplication et le déclenchement passent par la base, `packages/domain`
// couvre déjà les règles pures (sans spoil, heures calmes, importance — docs/04 J4).
// `FcmService.send` est simulé plutôt qu'appelé pour de vrai : un vrai envoi
// dépendrait du réseau et des identifiants Firebase, hors de portée d'un test.
describe("NotificationDispatchService (intégration)", () => {
  const prisma = new PrismaClient();
  const fcm = new FcmService(new ConfigService(process.env));
  const dispatch = new NotificationDispatchService(prisma, fcm);

  const categorySlug = `test-notif-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  let entityId: string;
  let userId: string;

  beforeEach(() => {
    fcm.send = jest.fn().mockResolvedValue({ tokenInvalid: false });
  });

  beforeAll(async () => {
    const category = await prisma.category.create({ data: { id: randomUUID(), slug: categorySlug, name: "Test notif" } });
    categoryId = category.id;
    const competition = await prisma.competition.create({
      data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test Champions", status: "live", importance: 3 },
    });
    competitionId = competition.id;
    const entity = await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test G2" } });
    entityId = entity.id;

    const user = await prisma.appUser.create({ data: { id: randomUUID(), setting: { create: { id: randomUUID(), spoilerFree: true } } } });
    userId = user.id;
    await prisma.subscription.create({ data: { id: randomUUID(), userId, targetType: "entity", targetId: entityId, level: "all" } });
  });

  afterAll(async () => {
    await prisma.notificationLog.deleteMany({ where: { userId } });
    await prisma.device.deleteMany({ where: { userId } });
    await prisma.subscription.deleteMany({ where: { userId } });
    await prisma.userSetting.deleteMany({ where: { userId } });
    await prisma.appUser.delete({ where: { id: userId } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.delete({ where: { id: entityId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  async function createFinishedEvent(name: string): Promise<string> {
    const event = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name,
        status: "finished",
        importance: 3,
        participants: { create: [{ id: randomUUID(), entityId, isWinner: true }] },
      },
    });
    return event.id;
  }

  it("n'envoie jamais deux fois la même notification (user, event, type)", async () => {
    await prisma.device.create({ data: { id: randomUUID(), userId, installId: randomUUID(), platform: "android", pushToken: "token-1" } });
    const eventId = await createFinishedEvent("Test G2 vs Test PRX");

    await dispatch.handle({ type: "EventFinished", eventId, competitionId });
    await dispatch.handle({ type: "EventFinished", eventId, competitionId });

    const logs = await prisma.notificationLog.findMany({ where: { userId, eventId, type: "result" } });
    expect(logs).toHaveLength(1);
    expect(fcm.send).toHaveBeenCalledTimes(1);
  });

  it("le réglage global d'un type (J14) coupe ce type seulement", async () => {
    const quiet = await prisma.appUser.create({ data: { id: randomUUID(), setting: { create: { id: randomUUID(), notifyMatchResult: false } } } });
    try {
      await prisma.device.create({ data: { id: randomUUID(), userId: quiet.id, installId: randomUUID(), platform: "android", pushToken: "token-quiet" } });
      await prisma.subscription.create({ data: { id: randomUUID(), userId: quiet.id, targetType: "entity", targetId: entityId, level: "all" } });
      const eventId = await createFinishedEvent("Test G2 vs Test PRX (réglage)");

      await dispatch.handle({ type: "EventFinished", eventId, competitionId });
      expect(await prisma.notificationLog.count({ where: { userId: quiet.id, eventId } })).toBe(0);

      await dispatch.handle({ type: "EventStarted", eventId, competitionId });
      expect(await prisma.notificationLog.count({ where: { userId: quiet.id, eventId, type: "start" } })).toBe(1);
    } finally {
      await prisma.notificationLog.deleteMany({ where: { userId: quiet.id } });
      await prisma.device.deleteMany({ where: { userId: quiet.id } });
      await prisma.subscription.deleteMany({ where: { userId: quiet.id } });
      await prisma.userSetting.deleteMany({ where: { userId: quiet.id } });
      await prisma.appUser.delete({ where: { id: quiet.id } });
    }
  });

  it("ignore les types d'événements sans notification associée au J4", async () => {
    const eventId = await createFinishedEvent("Test G2 vs Test PRX (2)");
    const before = await prisma.notificationLog.count({ where: { userId } });
    await dispatch.handle({ type: "ScoreChanged", eventId, competitionId });
    expect(await prisma.notificationLog.count({ where: { userId } })).toBe(before);
  });

  it("qualification/élimination (J5) : notifie l'abonné direct à l'équipe, jamais deux fois", async () => {
    await prisma.device.create({ data: { id: randomUUID(), userId, installId: randomUUID(), platform: "android", pushToken: "token-quali" } });

    await dispatch.handle({ type: "EntityQualified", entityId, competitionId });
    await dispatch.handle({ type: "EntityQualified", entityId, competitionId });

    const logs = await prisma.notificationLog.findMany({ where: { userId, entityId, type: "qualification" } });
    expect(logs).toHaveLength(1);
    expect(logs[0].eventId).toBeNull();
  });

  it("supprime l'appareil quand FCM signale un jeton invalide (désinstallation/réinstallation, docs/04 J4)", async () => {
    const device = await prisma.device.create({
      data: { id: randomUUID(), userId, installId: randomUUID(), platform: "android", pushToken: "dead-token" },
    });
    fcm.send = jest.fn().mockResolvedValue({ tokenInvalid: true });
    const eventId = await createFinishedEvent("Test G2 vs Test PRX (3)");

    await dispatch.handle({ type: "EventFinished", eventId, competitionId });

    expect(await prisma.device.findUnique({ where: { id: device.id } })).toBeNull();
  });
});
