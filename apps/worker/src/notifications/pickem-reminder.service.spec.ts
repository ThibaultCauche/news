import { randomUUID } from "node:crypto";
import { PrismaClient } from "@news/db";
import { FcmService } from "./fcm.service";
import { PickemReminderService } from "./pickem-reminder.service";

// Rappel de pick'em (J25), contre le vrai Postgres de dev : un tournoi à tableau dont le premier match commence dans
// 2 h ; le FCM est remplacé par un espion.
describe("PickemReminderService (intégration)", () => {
  const prisma = new PrismaClient();
  const send = jest.fn().mockResolvedValue({ tokenInvalid: false });
  const reminder = new PickemReminderService(prisma, { send } as unknown as FcmService);

  const slug = `test-pickrem-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let competitionId: string;
  const teams: string[] = [];
  const events: string[] = [];
  const users: string[] = [];

  async function follower(opts: { full: boolean; pseudo?: string | null }): Promise<string> {
    const user = await prisma.appUser.create({ data: { id: randomUUID(), pseudo: opts.pseudo === undefined ? `R${randomUUID().slice(0, 8)}` : opts.pseudo } });
    users.push(user.id);
    await prisma.userSetting.create({ data: { userId: user.id } });
    await prisma.device.create({ data: { id: randomUUID(), userId: user.id, installId: `inst-${user.id}`, platform: "android", pushToken: `tok-${user.id}` } });
    await prisma.subscription.create({ data: { id: randomUUID(), userId: user.id, targetType: "competition", targetId: competitionId } });
    if (opts.full) {
      for (const eventId of events) await prisma.bracketPick.create({ data: { id: randomUUID(), userId: user.id, competitionId, eventId, pickedEntityId: teams[0] } });
    }
    return user.id;
  }
  const logged = (userId: string) => prisma.notificationLog.count({ where: { userId, type: "pickem_reminder" } });

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test rappel" } })).id;
    competitionId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "tournament", name: "Test", format: "single_elim" } })).id;
    for (let i = 0; i < 4; i++) teams.push((await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: `Test ${i}` } })).id);
    const startsAt = new Date(Date.now() + 119.5 * 60_000);
    for (const [i, pair] of [[0, [teams[0], teams[1]]], [1, [teams[2], teams[3]]], [2, []]] as const) {
      const e = await prisma.event.create({ data: { id: randomUUID(), competitionId, kind: "match", name: "Test", status: "scheduled", startsAt: new Date(startsAt.getTime() + i * 3_600_000) } });
      events.push(e.id);
      await prisma.eventParticipant.createMany({ data: pair.map((entityId, side) => ({ id: randomUUID(), eventId: e.id, entityId, side })) });
    }
  });

  afterAll(async () => {
    await prisma.appUser.deleteMany({ where: { id: { in: users } } });
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId } } });
    await prisma.event.deleteMany({ where: { competitionId } });
    await prisma.subscription.deleteMany({ where: { targetId: competitionId } });
    await prisma.competition.delete({ where: { id: competitionId } });
    await prisma.entity.deleteMany({ where: { id: { in: teams } } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  it("prévient ceux qui suivent et n'ont pas tout rempli, une seule fois, et personne d'autre", async () => {
    const empty = await follower({ full: false });
    const full = await follower({ full: true });
    const noPseudo = await follower({ full: false, pseudo: null });
    await reminder.run();
    await reminder.run();
    expect(await logged(empty)).toBe(1);
    expect(await logged(full)).toBe(0);
    expect(await logged(noPseudo)).toBe(0);
    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][3]).toMatchObject({ competitionId, kind: "pickem" });
  });
});
