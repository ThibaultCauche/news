import { randomUUID } from "node:crypto";
import { ConfigService } from "@nestjs/config";
import { PrismaClient } from "@news/db";
import { FcmService } from "./fcm.service";
import { NotificationDispatchService } from "./notification-dispatch.service";

// Familles et sourdine (docs/04 J10), contre le vrai Postgres de dev comme le spec voisin :
// ligue suivie, famille suivie (« toutes les éditions ») et « tout sauf une compétition ».
describe("NotificationDispatchService : familles et sourdine (J10, intégration)", () => {
  const prisma = new PrismaClient();
  const fcm = new FcmService(new ConfigService(process.env));
  const dispatch = new NotificationDispatchService(prisma, fcm);

  const slug = `test-family-${randomUUID().slice(0, 8)}`;
  let categoryId: string;
  let leagueId: string;
  let championsFamilyId: string;
  const series: Record<string, { serieId: string; tournamentId: string }> = {};
  let teamId: string;
  const userIds: Record<string, string> = {};

  beforeEach(() => {
    fcm.send = jest.fn().mockResolvedValue({ tokenInvalid: false });
  });

  async function createSerie(key: string, name: string, familyId: string | null) {
    const serie = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: leagueId, familyId, kind: "serie", name } });
    const tournament = await prisma.competition.create({ data: { id: randomUUID(), categoryId, parentId: serie.id, kind: "tournament", name: `Playoffs ${key}` } });
    series[key] = { serieId: serie.id, tournamentId: tournament.id };
  }

  async function createUser(key: string, subs: { targetType: string; targetId: string; muted?: boolean }[]) {
    const user = await prisma.appUser.create({ data: { id: randomUUID(), setting: { create: { id: randomUUID() } } } });
    userIds[key] = user.id;
    for (const sub of subs) {
      await prisma.subscription.create({ data: { id: randomUUID(), userId: user.id, level: "all", ...sub } });
    }
  }

  beforeAll(async () => {
    categoryId = (await prisma.category.create({ data: { id: randomUUID(), slug, name: "Test familles" } })).id;
    leagueId = (await prisma.competition.create({ data: { id: randomUUID(), categoryId, kind: "league", name: "Test VCT", importance: 3 } })).id;
    championsFamilyId = (await prisma.competitionFamily.create({ data: { id: randomUUID(), leagueId, name: "Champions" } })).id;
    await createSerie("champions2026", "Champions 2026", championsFamilyId);
    await createSerie("champions2027", "Champions 2027", championsFamilyId); // édition future, même famille
    const stageFamilyId = (await prisma.competitionFamily.create({ data: { id: randomUUID(), leagueId, name: "Stage 1" } })).id;
    await createSerie("stage1", "Stage 1 2026", stageFamilyId);
    teamId = (await prisma.entity.create({ data: { id: randomUUID(), kind: "team", name: "Test G2" } })).id;

    await createUser("league", [{ targetType: "competition", targetId: leagueId }]);
    await createUser("family", [{ targetType: "competition_family", targetId: championsFamilyId }]);
    // « Tout VCT sauf Champions 2026 » : ligue suivie, cette série en sourdine.
    await createUser("leagueMuted", [
      { targetType: "competition", targetId: leagueId },
      { targetType: "competition", targetId: series.champions2026.serieId, muted: true },
    ]);
    // Même exception, mais il suit aussi l'équipe : elle reste notifiée (sourdine limitée à la compétition).
    await createUser("leagueMutedAndTeam", [
      { targetType: "competition", targetId: leagueId },
      { targetType: "competition", targetId: series.champions2026.serieId, muted: true },
      { targetType: "entity", targetId: teamId },
    ]);
    // Famille suivie avec une édition en sourdine.
    await createUser("familyMuted", [
      { targetType: "competition_family", targetId: championsFamilyId },
      { targetType: "competition", targetId: series.champions2026.serieId, muted: true },
    ]);
  });

  afterAll(async () => {
    const ids = Object.values(userIds);
    await prisma.notificationLog.deleteMany({ where: { userId: { in: ids } } });
    await prisma.subscription.deleteMany({ where: { userId: { in: ids } } });
    await prisma.userSetting.deleteMany({ where: { userId: { in: ids } } });
    await prisma.appUser.deleteMany({ where: { id: { in: ids } } });
    const competitionIds = Object.values(series).flatMap((s) => [s.tournamentId, s.serieId]);
    await prisma.eventParticipant.deleteMany({ where: { event: { competitionId: { in: competitionIds } } } });
    await prisma.event.deleteMany({ where: { competitionId: { in: competitionIds } } });
    await prisma.competition.deleteMany({ where: { id: { in: competitionIds } } });
    await prisma.competitionFamily.deleteMany({ where: { leagueId } });
    await prisma.competition.delete({ where: { id: leagueId } });
    await prisma.entity.delete({ where: { id: teamId } });
    await prisma.category.delete({ where: { id: categoryId } });
    await prisma.$disconnect();
  });

  // Match terminé dans le tournoi de la série `key`, avec l'équipe de test.
  async function finishedMatch(key: string): Promise<{ eventId: string; competitionId: string }> {
    const competitionId = series[key].tournamentId;
    const event = await prisma.event.create({
      data: {
        id: randomUUID(),
        competitionId,
        kind: "match",
        name: `Match ${key}`,
        status: "finished",
        importance: 3,
        participants: { create: [{ id: randomUUID(), entityId: teamId, isWinner: true }] },
      },
    });
    return { eventId: event.id, competitionId };
  }

  async function notifiedUsers(eventId: string): Promise<string[]> {
    const logs = await prisma.notificationLog.findMany({ where: { eventId, type: "result", userId: { in: Object.values(userIds) } } });
    const byId = new Map(Object.entries(userIds).map(([key, id]) => [id, key]));
    return logs.map((l) => byId.get(l.userId)!).sort();
  }

  it("Champions 2026 : ligue et famille notifient, la sourdine coupe la compétition mais pas l'équipe suivie", async () => {
    const { eventId, competitionId } = await finishedMatch("champions2026");
    await dispatch.handle({ type: "EventFinished", eventId, competitionId });
    expect(await notifiedUsers(eventId)).toEqual(["family", "league", "leagueMutedAndTeam"]);
  });

  it("Champions 2027 (édition future de la même famille) : la famille la couvre sans rien refaire", async () => {
    const { eventId, competitionId } = await finishedMatch("champions2027");
    await dispatch.handle({ type: "EventFinished", eventId, competitionId });
    // La sourdine ne visait que Champions 2026 : « tout sauf une » suit bien 2027.
    expect(await notifiedUsers(eventId)).toEqual(["family", "familyMuted", "league", "leagueMuted", "leagueMutedAndTeam"]);
  });

  it("une autre famille (Stage 1) : seuls la ligue suivie et l'équipe notifient, pas la famille Champions", async () => {
    const { eventId, competitionId } = await finishedMatch("stage1");
    await dispatch.handle({ type: "EventFinished", eventId, competitionId });
    expect(await notifiedUsers(eventId)).toEqual(["league", "leagueMuted", "leagueMutedAndTeam"]);
  });
});
