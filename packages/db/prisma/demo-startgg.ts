import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PrismaClient } from "@prisma/client";
import { computeStandings, standingsOptionsFor, EventDTO } from "@news/domain";
import {
  normalizeStartGgSet,
  normalizeStartGgStructure,
  START_GG_PHASE_LINKS_QUERY,
  START_GG_PHASE_SETS_QUERY,
  StartGgClient,
  startGgSetNumbers,
} from "@news/providers";

// Major Smash Ultimate simulé (J27) : le Top 8 réel de Genesis X3 (tests-pandascore/samples-startgg/), rejoué dans une
// ligue « Majors Smash Ultimate (démo) » pour voir le tableau sans attendre un vrai major (Genesis X4 : février 2027).
//
//   pnpm db:demo-startgg <live|finished|open|top64>   crée (ou remplace) la démo
//   pnpm db:demo-startgg remove                       supprime tout
//
// `live` : les premiers sets sont joués, un set est en cours, le reste attend (joueurs inconnus, sans horaire).
// `finished` : tout est joué, le champion compris.
// `open` : rien n'a commencé, seuls les joueurs déjà connus sont inscrits (on peut faire son pick'em).
// `top64` : comme `finished`, plus le vrai Top 64 de Genesis X3 et quelques poules du premier tour, lus chez start.gg
// avec `STARTGG_TOKEN` (rien de cela n'est versionné).
const LEAGUE_NAME = "Majors Smash Ultimate (démo)";
const DEMO_REGION = "demo-startgg";
const GAME = "super-smash-bros-ultimate";
const SAMPLES = join(__dirname, "../../../tests-pandascore/samples-startgg");
const TOP64_PHASE = 2195695;
const POOLS_PHASE = 2030937;

type Raw = Parameters<typeof normalizeStartGgSet>[0];
type LinkSets = Parameters<typeof normalizeStartGgStructure>[1];
type State = "live" | "finished" | "open" | "top64";

const prisma = new PrismaClient();

async function remove(): Promise<void> {
  const leagues = await prisma.competition.findMany({ where: { name: LEAGUE_NAME, parentId: null }, select: { id: true } });
  const series = await prisma.competition.findMany({ where: { parentId: { in: leagues.map((l) => l.id) } }, select: { id: true } });
  const stages = await prisma.competition.findMany({ where: { parentId: { in: series.map((s) => s.id) } }, select: { id: true } });
  const compIds = [...leagues, ...series, ...stages].map((c) => c.id);
  const eventIds = (await prisma.event.findMany({ where: { competitionId: { in: compIds } }, select: { id: true } })).map((e) => e.id);
  await prisma.notificationLog.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.prediction.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.bracketPickBonus.deleteMany({ where: { competitionId: { in: compIds } } });
  await prisma.bracketPick.deleteMany({ where: { competitionId: { in: compIds } } });
  await prisma.forumThread.deleteMany({ where: { kind: { in: ["event", "live"] }, targetId: { in: eventIds } } });
  await prisma.eventLink.deleteMany({ where: { OR: [{ fromEventId: { in: eventIds } }, { toEventId: { in: eventIds } }] } });
  await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
  await prisma.standing.deleteMany({ where: { competitionId: { in: compIds } } });
  await prisma.competition.deleteMany({ where: { id: { in: stages.map((s) => s.id) } } });
  await prisma.competition.deleteMany({ where: { id: { in: series.map((s) => s.id) } } });
  await prisma.competition.deleteMany({ where: { id: { in: leagues.map((l) => l.id) } } });
  const entityIds = (await prisma.entity.findMany({ where: { region: DEMO_REGION }, select: { id: true } })).map((e) => e.id);
  await prisma.subscription.deleteMany({ where: { OR: [{ targetType: "entity", targetId: { in: entityIds } }, { targetType: "competition", targetId: { in: compIds } }] } });
  await prisma.notificationLog.deleteMany({ where: { entityId: { in: entityIds } } });
  await prisma.providerRef.deleteMany({ where: { provider: "demo-startgg" } });
  await prisma.entity.deleteMany({ where: { id: { in: entityIds } } });
}

// Sets d'une phase lus chez start.gg (`maxPages` : on s'arrête aux premiers groupes d'une phase de poules).
async function fetchPhaseSets(client: StartGgClient, phaseId: number, maxPages: number): Promise<Raw[]> {
  const sets: Raw[] = [];
  for (let page = 1; page <= maxPages; page++) {
    const data = await client.query<{ phase: { sets: { pageInfo: { totalPages: number }; nodes: Raw[] } } }>(START_GG_PHASE_SETS_QUERY, { id: phaseId, page });
    sets.push(...data.phase.sets.nodes);
    if (page >= data.phase.sets.pageInfo.totalPages) break;
  }
  return sets;
}

// Un set « pas encore joué » : les joueurs qui viennent d'un set précédent sont inconnus, rien n'est commencé.
function unplayed(raw: Raw): Raw {
  return {
    ...raw,
    state: 1,
    winnerId: null,
    startedAt: null,
    startAt: null,
    completedAt: null,
    games: [],
    slots: raw.slots.map((s) => (s.prereqType === "set" ? { ...s, entrant: null, standing: null } : { ...s, standing: null })),
  };
}

async function create(state: State): Promise<void> {
  const category = await prisma.category.findUnique({ where: { slug: "esport" } });
  if (!category) throw new Error("Catégorie « esport » introuvable : lancer le worker une fois pour ingérer le catalogue.");
  const top8Raws = JSON.parse(readFileSync(join(SAMPLES, "genesis-x3-top8-sets.json"), "utf8")) as Raw[];
  const top8LinkSource = JSON.parse(readFileSync(join(SAMPLES, "genesis-x3-top8-links.json"), "utf8")) as { bracketType: string; sets: { nodes: LinkSets } };
  const realTop8 = top8Raws.map((r) => normalizeStartGgSet(r)!).sort((a, b) => (a.endsAt?.getTime() ?? 0) - (b.endsAt?.getTime() ?? 0));

  // Dates décalées : `finished` finit « il y a une heure » ; `live` met le set en cours à « il y a dix minutes » ;
  // `open` commence dans deux heures.
  const minute = 60 * 1000;
  const liveIndex = state === "live" ? realTop8.length - 4 : -1;
  const anchor = state === "live" ? realTop8[liveIndex].startsAt!.getTime() : state === "open" ? realTop8[0].startsAt!.getTime() : realTop8.at(-1)!.endsAt!.getTime();
  const shift = (state === "live" ? Date.now() - 10 * minute : state === "open" ? Date.now() + 120 * minute : Date.now() - 60 * minute) - anchor;
  const at = (d: Date | null): Date | null => (d ? new Date(d.getTime() + shift) : null);
  const serieStatus = state === "live" ? "live" : state === "open" ? "scheduled" : "finished";

  const league = await prisma.competition.create({ data: { categoryId: category.id, kind: "league", game: GAME, name: LEAGUE_NAME, importance: 3 } });
  const serie = await prisma.competition.create({
    data: {
      categoryId: category.id,
      parentId: league.id,
      kind: "serie",
      game: GAME,
      name: "Genesis X3 (démo)",
      status: serieStatus,
      startsAt: at(state === "open" ? realTop8[0].startsAt : state === "top64" ? new Date(realTop8[0].startsAt!.getTime() - 2 * 24 * 60 * minute) : realTop8[0].startsAt),
      endsAt: at(realTop8.at(-1)!.endsAt),
      importance: 3,
    },
  });

  const entityByExternal = new Map<string, string>();
  const entityOf = async (externalId: string, name: string): Promise<string> => {
    const known = entityByExternal.get(externalId);
    if (known) return known;
    const created = await prisma.entity.create({ data: { kind: "player", name, region: DEMO_REGION } });
    // Comme l'ingestion : l'API retrouve les joueurs d'une manche par leur identifiant start.gg.
    await prisma.providerRef.create({ data: { provider: "demo-startgg", objectType: "entity", objectId: created.id, externalId, lastSyncedAt: new Date(), payloadHash: "demo" } });
    entityByExternal.set(externalId, created.id);
    return created.id;
  };

  // Une phase et ses sets. `mode(index)` décide de l'état de chaque set (déjà trié par fin de set).
  async function addPhase(name: string, hasBracket: boolean, dtos: EventDTO[], mode: (index: number) => "played" | "live" | "unknown", links: ReturnType<typeof normalizeStartGgStructure>["links"]): Promise<number> {
    const stage = await prisma.competition.create({
      data: {
        categoryId: category!.id,
        parentId: serie.id,
        kind: "tournament",
        game: GAME,
        name,
        format: hasBracket ? "double_elim" : null,
        hasBracket,
        status: serieStatus,
        startsAt: serie.startsAt,
        endsAt: serie.endsAt,
        importance: 3,
      },
    });
    const eventByExternal = new Map<string, string>();
    for (const [index, dto] of dtos.entries()) {
      const m = mode(index);
      const event = await prisma.event.create({
        data: {
          competitionId: stage.id,
          kind: "match",
          name: m === "unknown" && !dto.participants.length ? dto.name.replace(/: .*$/, ": TBD vs TBD") : dto.name,
          status: m === "played" ? "finished" : m === "live" ? "live" : "scheduled",
          startsAt: m === "unknown" ? null : at(dto.startsAt),
          endsAt: m === "played" ? at(dto.endsAt) : null,
          bestOf: dto.bestOf,
          importance: 3,
          spoilerSensitive: true,
          result: m === "played" ? (dto.result as object) : { called: false, group: (dto.result as { group?: string | null }).group ?? null, seriesScore: [], games: [] },
        },
      });
      eventByExternal.set(dto.externalId, event.id);
      if (m === "unknown" && state !== "open") continue;
      for (const [side, p] of dto.participants.entries()) {
        const entityId = await entityOf(p.entity.externalId, p.entity.name);
        await prisma.eventParticipant.create({
          data: { eventId: event.id, entityId, side, score: m === "played" ? p.score : m === "live" ? (side === 0 ? 1 : 0) : null, isWinner: m === "played" ? p.isWinner : null },
        });
      }
    }
    for (const link of links) {
      const from = eventByExternal.get(link.fromExternalId);
      const to = eventByExternal.get(link.toExternalId);
      if (from && to) await prisma.eventLink.create({ data: { fromEventId: from, toEventId: to, outcome: link.outcome, slot: link.slot } });
    }
    if (hasBracket) {
      const stored = await prisma.event.findMany({ where: { competitionId: stage.id }, select: { status: true, participants: { select: { entityId: true, score: true, isWinner: true } } } });
      const standings = computeStandings(
        stored.map((e) => ({ status: e.status as "finished", participants: e.participants.map((p) => ({ entityExternalId: p.entityId, score: p.score, isWinner: p.isWinner })) })),
        standingsOptionsFor("double_elim"),
      );
      for (const s of standings) {
        await prisma.standing.create({ data: { competitionId: stage.id, entityId: s.entityExternalId, rank: s.rank, wins: s.wins, losses: s.losses, livesLeft: s.livesLeft, qualified: s.qualified } });
      }
    }
    return dtos.length;
  }

  // Top 8 : réel (live, finished, top64) ou « avant le début » (open : seuls les joueurs déjà connus).
  const top8Source = state === "open" ? top8Raws.map(unplayed) : top8Raws;
  const top8Numbers = startGgSetNumbers(top8Source);
  const top8Dtos = top8Source
    .map((raw) => normalizeStartGgSet(raw, top8Numbers.get(String(raw.id)) ?? undefined)!)
    .sort((a, b) => (a.endsAt?.getTime() ?? 0) - (b.endsAt?.getTime() ?? 0) || a.externalId.localeCompare(b.externalId));
  // `open` : tri stable sur l'ordre réel des sets, pas sur des dates effacées.
  const order = new Map(realTop8.map((d, i) => [d.externalId, i]));
  top8Dtos.sort((a, b) => (order.get(a.externalId) ?? 0) - (order.get(b.externalId) ?? 0));
  const top8Links = normalizeStartGgStructure(top8LinkSource.bracketType, top8LinkSource.sets.nodes).links;
  let total = await addPhase("Top 8", true, top8Dtos, (i) => (state === "open" ? "unknown" : state === "finished" || state === "top64" || i < liveIndex ? "played" : i === liveIndex ? "live" : "unknown"), top8Links);

  if (state === "top64") {
    if (!process.env.STARTGG_TOKEN) throw new Error("STARTGG_TOKEN absent du .env : le Top 64 et les poules sont lus chez start.gg.");
    const client = new StartGgClient(process.env.STARTGG_TOKEN);
    const top64Raws = await fetchPhaseSets(client, TOP64_PHASE, 10);
    const top64Numbers = startGgSetNumbers(top64Raws);
    const top64Dtos = top64Raws
      .map((raw) => normalizeStartGgSet(raw, top64Numbers.get(String(raw.id)) ?? undefined))
      .filter((d): d is EventDTO => d !== null)
      .sort((a, b) => (a.endsAt?.getTime() ?? 0) - (b.endsAt?.getTime() ?? 0));
    const linkNodes: LinkSets = [];
    for (let page = 1; page <= 10; page++) {
      const data = await client.query<{ phase: { sets: { pageInfo: { totalPages: number }; nodes: LinkSets } } }>(START_GG_PHASE_LINKS_QUERY, { id: TOP64_PHASE, page });
      linkNodes.push(...data.phase.sets.nodes);
      if (page >= data.phase.sets.pageInfo.totalPages) break;
    }
    total += await addPhase("Top 64", true, top64Dtos, () => "played", normalizeStartGgStructure("DOUBLE_ELIMINATION", linkNodes).links);

    const poolRaws = await fetchPhaseSets(client, POOLS_PHASE, 3);
    const poolNumbers = startGgSetNumbers(poolRaws);
    const poolDtos = poolRaws
      .map((raw) => normalizeStartGgSet(raw, poolNumbers.get(String(raw.id)) ?? undefined))
      .filter((d): d is EventDTO => d !== null)
      .sort((a, b) => (a.endsAt?.getTime() ?? 0) - (b.endsAt?.getTime() ?? 0));
    total += await addPhase("Round 1 Pools", false, poolDtos, () => "played", []);
  }
  console.log(`Démo « ${LEAGUE_NAME} » (${state}) créée : ${total} sets, ${entityByExternal.size} joueurs. Série : ${serie.id}`);
}

async function main(): Promise<void> {
  const arg = process.argv[2];
  if (arg === "remove") {
    await remove();
    console.log("Démo supprimée.");
  } else if (arg === "live" || arg === "finished" || arg === "open" || arg === "top64") {
    await remove();
    await create(arg);
  } else {
    throw new Error("Usage : pnpm db:demo-startgg <live|finished|open|top64|remove>");
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
