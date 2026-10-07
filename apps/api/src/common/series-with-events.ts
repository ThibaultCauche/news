import { PrismaClient } from "@news/db";

/**
 * Parmi ces séries, celles qui ont au moins un match en base (directement ou dans l'un de leurs tournois).
 * Sert à ne pas montrer une compétition passée dont la page serait vide : on n'ingère que les matchs récents
 * (une semaine après la fin), donc les séries plus anciennes n'ont plus rien à afficher.
 */
export async function seriesWithEvents(prisma: PrismaClient, serieIds: string[]): Promise<Set<string>> {
  if (serieIds.length === 0) return new Set();
  const rows = await prisma.event.findMany({
    where: { competition: { OR: [{ id: { in: serieIds } }, { parentId: { in: serieIds } }] } },
    distinct: ["competitionId"],
    select: { competition: { select: { id: true, parentId: true } } },
  });
  const wanted = new Set(serieIds);
  const result = new Set<string>();
  for (const { competition } of rows) {
    if (wanted.has(competition.id)) result.add(competition.id);
    else if (competition.parentId && wanted.has(competition.parentId)) result.add(competition.parentId);
  }
  return result;
}

/** Une compétition « passée et vide » : terminée, sans aucun match à montrer. */
export function isPastAndEmpty(competition: { endsAt: Date | null }, hasEvents: boolean, now: Date): boolean {
  return competition.endsAt !== null && competition.endsAt < now && !hasEvents;
}

export interface Champion {
  name: string;
  shortName: string | null;
  imageUrl: string | null;
}

/**
 * Le champion de chaque série terminée : le vainqueur du dernier match de sa dernière étape (la finale d'une phase
 * finale). `null` si on ne l'a pas (série pas jouée jusqu'au bout chez nous). Une seule requête pour toutes les séries.
 */
export async function championsOf(prisma: PrismaClient, serieIds: string[]): Promise<Map<string, Champion>> {
  if (serieIds.length === 0) return new Map();
  const events = await prisma.event.findMany({
    where: { status: "finished", competition: { parentId: { in: serieIds } } },
    select: {
      startsAt: true,
      competition: { select: { parentId: true, startsAt: true } },
      participants: { where: { isWinner: true }, select: { entity: { select: { name: true, shortName: true, imageUrl: true } } } },
    },
  });
  const last = new Map<string, { stageStart: number; matchStart: number; champion: Champion | null }>();
  for (const e of events) {
    const serieId = e.competition.parentId!;
    const stageStart = e.competition.startsAt?.getTime() ?? 0;
    const matchStart = e.startsAt?.getTime() ?? 0;
    const known = last.get(serieId);
    if (known && (stageStart < known.stageStart || (stageStart === known.stageStart && matchStart <= known.matchStart))) continue;
    last.set(serieId, { stageStart, matchStart, champion: e.participants[0]?.entity ?? null });
  }
  return new Map([...last].flatMap(([id, v]) => (v.champion ? [[id, v.champion] as const] : [])));
}
