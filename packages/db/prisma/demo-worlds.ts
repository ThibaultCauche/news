import { readFileSync } from "node:fs";
import { join } from "node:path";
import { PrismaClient } from "@prisma/client";
import { computeStandings, standingsOptionsFor } from "@news/domain";

// Worlds simulés (J23) : une ligue « Worlds (démo) » de League of Legends avec une vraie phase suisse et une vraie
// phase finale (Worlds 2025, reprises de tests-pandascore/samples-lol/), pour voir la phase suisse et le classement
// global sans attendre les Worlds 2026 (play-in le 15 octobre, phase suisse le 23).
//
//   pnpm db:demo-worlds <open|partial|finished>   crée (ou remplace) la démo
//   pnpm db:demo-worlds remove               supprime tout
//
// `open` : la ronde 1 est tirée mais pas commencée (on peut faire son pronostic), le reste est inconnu.
// `partial` : rondes 1 à 3 jouées, un match de la ronde 4 en direct, le reste à venir, phase finale pas commencée.
// `finished` : tout est joué, l'équipe championne comprise.
const LEAGUE_NAME = "Worlds (démo)";
const DEMO_REGION = "demo-worlds";
const SAMPLES = join(__dirname, "../../../tests-pandascore/samples-lol");

interface RawTeam {
  id: number;
  name: string;
  acronym?: string | null;
  image_url?: string | null;
}
interface RawMatch {
  id: number;
  name: string;
  status: string;
  begin_at?: string | null;
  scheduled_at?: string | null;
  number_of_games?: number | null;
  winner_id?: number | null;
  opponents: { opponent: RawTeam }[];
  results: { team_id: number; score: number }[];
  previous_matches?: { type: "winner" | "loser"; match_id: number }[];
}

const load = <T>(file: string): T => JSON.parse(readFileSync(join(SAMPLES, file), "utf8"));
const prisma = new PrismaClient();

async function remove(): Promise<void> {
  const leagues = await prisma.competition.findMany({ where: { name: LEAGUE_NAME, parentId: null }, select: { id: true } });
  const series = await prisma.competition.findMany({ where: { parentId: { in: leagues.map((l) => l.id) } }, select: { id: true } });
  const stages = await prisma.competition.findMany({ where: { parentId: { in: series.map((s) => s.id) } }, select: { id: true } });
  const compIds = [...leagues, ...series, ...stages].map((c) => c.id);
  const eventIds = (await prisma.event.findMany({ where: { competitionId: { in: compIds } }, select: { id: true } })).map((e) => e.id);
  await prisma.notificationLog.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.prediction.deleteMany({ where: { eventId: { in: eventIds } } });
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
  await prisma.entity.deleteMany({ where: { id: { in: entityIds } } });
}

const roundOf = (name: string): number => Number(/^Round (\d+)/.exec(name)?.[1] ?? 0);

async function create(state: "open" | "partial" | "finished"): Promise<void> {
  const category = await prisma.category.findUnique({ where: { slug: "esport" } });
  if (!category) throw new Error("Catégorie « esport » introuvable : lancer le worker une fois pour ingérer le catalogue.");
  const swissMatches = load<RawMatch[]>("suisse-worlds-2025-matchs.json").sort((a, b) => (a.begin_at ?? "").localeCompare(b.begin_at ?? ""));
  const playoffMatches = load<RawMatch[]>("brackets-playoffs-worlds-2025.json").sort((a, b) => (a.begin_at ?? "").localeCompare(b.begin_at ?? ""));

  // Les dates des vrais matchs sont décalées pour que le dernier match de la phase finale tombe « il y a une heure ».
  const hour = 3600 * 1000;
  const lastReal = Math.max(...[...swissMatches, ...playoffMatches].map((m) => Date.parse(m.begin_at ?? m.scheduled_at ?? "")).filter(Number.isFinite));
  const partial = state !== "finished";
  // En `partial`, la ronde 3 se termine « il y a une heure » : on cale les dates sur le début de la ronde 4.
  const round4Start = Date.parse(swissMatches.find((m) => roundOf(m.name) === 4)?.begin_at ?? "");
  const round1Start = Date.parse(swissMatches.find((m) => roundOf(m.name) === 1)?.begin_at ?? "");
  // `open` : la première ronde commence dans deux heures.
  const shift = state === "open" ? Date.now() + 2 * hour - round1Start : partial ? Date.now() - hour - round4Start : Date.now() - hour - lastReal;
  const at = (iso?: string | null): Date | null => (iso ? new Date(Date.parse(iso) + shift) : null);

  const league = await prisma.competition.create({ data: { categoryId: category.id, kind: "league", game: "league-of-legends", name: LEAGUE_NAME, importance: 3 } });
  const serie = await prisma.competition.create({
    data: { categoryId: category.id, parentId: league.id, kind: "serie", game: "league-of-legends", name: "Worlds démo 2025", status: partial ? "live" : "finished", startsAt: at(swissMatches[0].begin_at), endsAt: at(playoffMatches.at(-1)?.begin_at ?? null) },
  });
  const swiss = await prisma.competition.create({
    data: { categoryId: category.id, parentId: serie.id, kind: "tournament", game: "league-of-legends", name: "Group Stage", format: "swiss", status: partial ? "live" : "finished", startsAt: at(swissMatches[0].begin_at), endsAt: at(swissMatches.at(-1)?.begin_at ?? null), importance: 3 },
  });
  const playoffs = await prisma.competition.create({
    data: { categoryId: category.id, parentId: serie.id, kind: "tournament", game: "league-of-legends", name: "Playoffs", format: "single_elim", status: partial ? "scheduled" : "finished", startsAt: at(playoffMatches[0].begin_at), endsAt: at(playoffMatches.at(-1)?.begin_at ?? null), importance: 3 },
  });

  const entityByExternal = new Map<number, string>();
  const entityOf = async (team: RawTeam): Promise<string> => {
    const known = entityByExternal.get(team.id);
    if (known) return known;
    const created = await prisma.entity.create({ data: { kind: "team", name: team.name, shortName: team.acronym ?? null, imageUrl: team.image_url ?? null, region: DEMO_REGION } });
    entityByExternal.set(team.id, created.id);
    return created.id;
  };

  const eventByExternal = new Map<number, string>();
  let liveGiven = false;

  async function addMatch(m: RawMatch, competitionId: string, mode: "played" | "live" | "scheduled" | "unknown"): Promise<void> {
    const status = mode === "played" ? "finished" : mode === "live" ? "live" : "scheduled";
    const event = await prisma.event.create({
      data: {
        competitionId,
        kind: "match",
        name: mode === "unknown" ? m.name.replace(/: .*$/, ": TBD vs TBD") : m.name,
        status,
        startsAt: at(m.begin_at ?? m.scheduled_at),
        bestOf: m.number_of_games ?? null,
        importance: 3,
        spoilerSensitive: true,
        result: { seriesScore: mode === "played" ? m.results : [], games: [] },
      },
    });
    eventByExternal.set(m.id, event.id);
    if (mode === "unknown") return;
    for (const [side, o] of m.opponents.entries()) {
      const entityId = await entityOf(o.opponent);
      const score = mode === "played" ? (m.results.find((r) => r.team_id === o.opponent.id)?.score ?? 0) : 0;
      const isWinner = mode === "played" ? m.winner_id === o.opponent.id : null;
      await prisma.eventParticipant.create({ data: { eventId: event.id, entityId, side, score, isWinner } });
    }
  }

  for (const m of swissMatches) {
    const round = roundOf(m.name);
    const mode =
      state === "open"
        ? round === 1
          ? "scheduled"
          : "unknown"
        : !partial || round <= 3
          ? "played"
          : round === 4
            ? liveGiven
              ? "scheduled"
              : ((liveGiven = true), "live")
            : "unknown";
    await addMatch(m, swiss.id, mode);
  }
  for (const m of playoffMatches) await addMatch(m, playoffs.id, partial ? "unknown" : "played");

  // Liens de la phase finale (le vainqueur de A va en B), comme `event_link` d'un vrai tableau.
  for (const m of playoffMatches) {
    for (const [slot, prev] of (m.previous_matches ?? []).entries()) {
      const from = eventByExternal.get(prev.match_id);
      const to = eventByExternal.get(m.id);
      if (from && to) await prisma.eventLink.create({ data: { fromEventId: from, toEventId: to, outcome: prev.type, slot } });
    }
  }

  // Classements d'étape, comme le worker les calcule.
  for (const stage of [swiss, playoffs]) {
    const events = await prisma.event.findMany({ where: { competitionId: stage.id }, select: { status: true, participants: { select: { entityId: true, score: true, isWinner: true } } } });
    const standings = computeStandings(
      events.map((e) => ({ status: e.status as "finished", participants: e.participants.map((p) => ({ entityExternalId: p.entityId, score: p.score, isWinner: p.isWinner })) })),
      standingsOptionsFor(stage.format as "swiss" | "single_elim"),
    );
    for (const s of standings) {
      await prisma.standing.create({ data: { competitionId: stage.id, entityId: s.entityExternalId, rank: s.rank, wins: s.wins, losses: s.losses, livesLeft: s.livesLeft, qualified: s.qualified } });
    }
  }
  console.log(`Démo « ${LEAGUE_NAME} » (${state}) créée : ${swissMatches.length} matchs suisses, ${playoffMatches.length} de phase finale. Série : ${serie.id}`);
}

async function main(): Promise<void> {
  const arg = process.argv[2];
  if (arg === "remove") {
    await remove();
    console.log("Démo supprimée.");
  } else if (arg === "open" || arg === "partial" || arg === "finished") {
    await remove();
    await create(arg);
  } else {
    throw new Error("Usage : pnpm db:demo-worlds <open|partial|finished|remove>");
  }
}

main()
  .catch((err) => {
    console.error(err);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
