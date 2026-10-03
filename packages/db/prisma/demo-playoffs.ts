import { PrismaClient } from "@prisma/client";
import { computeStandings } from "@news/domain";

// Playoffs simulés (J20) : une série « Champions (démo) » sous la ligue VCT, avec un vrai
// tableau à double élimination de 8 équipes (mêmes noms de match que PandaScore). Sert à
// voir chaque état de l'arbre sans attendre de vrais matchs, sans toucher aux vraies
// compétitions (aucun match de test dans une poule).
//
//   pnpm db:demo-playoffs <tbd|empty|partial|finished>   crée (ou remplace) la démo
//   pnpm db:demo-playoffs remove                         supprime tout
//
// `DEMO_LOGO_BASE=http://localhost:8080` donne aux équipes de démo un logo servi par là (un
// émulateur sans Internet ne charge pas ceux du CDN de PandaScore) ; sans, pas de logo.
//
// `hasBracket` reste faux : le job « structure » du worker n'y touche pas. L'API met le
// bracket en cache 15-60 s : attendre un peu après un changement d'état.
const SERIES_NAME = "Champions (démo)";
const DEMO_REGION = "demo";

type Source = { team: string } | { from: string; outcome: "winner" | "loser" };
interface Spec {
  key: string;
  name: string;
  bestOf: number;
  sides: [Source, Source?];
}

const t = (team: string): Source => ({ team });
const w = (from: string): Source => ({ from, outcome: "winner" });
const l = (from: string): Source => ({ from, outcome: "loser" });

// Ordre de jeu = ordre du tableau PandaScore (samples/brackets-playoffs.json).
const SPECS: Spec[] = [
  { key: "uq1", name: "Upper Bracket Quarterfinal 1", bestOf: 3, sides: [t("G2"), t("DRX")] },
  { key: "uq2", name: "Upper Bracket Quarterfinal 2", bestOf: 3, sides: [t("PRX"), t("TL")] },
  { key: "uq3", name: "Upper Bracket Quarterfinal 3", bestOf: 3, sides: [t("FNC"), t("EDG")] },
  { key: "uq4", name: "Upper Bracket Quarterfinal 4", bestOf: 3, sides: [t("TH"), t("SEN")] },
  { key: "us1", name: "Upper Bracket Semifinal 1", bestOf: 3, sides: [w("uq1"), w("uq2")] },
  { key: "us2", name: "Upper Bracket Semifinal 2", bestOf: 3, sides: [w("uq3"), w("uq4")] },
  { key: "lr1", name: "Lower Bracket Round 1 Match 1", bestOf: 3, sides: [l("uq2"), l("uq1")] },
  { key: "lr2", name: "Lower Bracket Round 1 Match 2", bestOf: 3, sides: [l("uq4"), l("uq3")] },
  { key: "uf", name: "Upper Bracket Final", bestOf: 5, sides: [w("us2"), w("us1")] },
  { key: "lq1", name: "Lower Bracket Quarterfinal 1", bestOf: 3, sides: [l("us2"), w("lr1")] },
  { key: "lq2", name: "Lower Bracket Quarterfinal 2", bestOf: 3, sides: [l("us1"), w("lr2")] },
  { key: "ls", name: "Lower Bracket Semifinal", bestOf: 3, sides: [w("lq2"), w("lq1")] },
  { key: "lf", name: "Lower Bracket Final", bestOf: 5, sides: [l("uf"), w("ls")] },
  { key: "gf", name: "Grand Final", bestOf: 5, sides: [w("uf"), w("lf")] },
];

// Les équipes sont classées dans cet ordre : la mieux classée gagne (déterministe).
const TEAMS = ["G2", "PRX", "FNC", "TH", "TL", "SEN", "DRX", "EDG"];
const TEAM_NAMES: Record<string, string> = {
  G2: "G2 Esports",
  PRX: "Paper Rex",
  FNC: "Fnatic",
  TH: "Team Heretics",
  TL: "Team Liquid",
  SEN: "Sentinels",
  DRX: "DRX",
  EDG: "EDward Gaming",
};

// Matchs joués / en direct selon l'état. `tbd` = rien de connu, `empty` = quarts connus
// mais rien de joué, `partial` = 8 joués puis la finale du haut en direct, `finished` = tout.
const STATES: Record<string, { played: number; live: boolean; knownTeams: boolean }> = {
  tbd: { played: 0, live: false, knownTeams: false },
  empty: { played: 0, live: false, knownTeams: true },
  partial: { played: 8, live: true, knownTeams: true },
  finished: { played: SPECS.length, live: false, knownTeams: true },
};

const prisma = new PrismaClient();

async function remove(): Promise<void> {
  const series = await prisma.competition.findMany({ where: { name: SERIES_NAME, kind: "serie" }, select: { id: true } });
  const seriesIds = series.map((s) => s.id);
  const comps = await prisma.competition.findMany({ where: { OR: [{ id: { in: seriesIds } }, { parentId: { in: seriesIds } }] }, select: { id: true } });
  const compIds = comps.map((c) => c.id);
  const events = await prisma.event.findMany({ where: { competitionId: { in: compIds } }, select: { id: true } });
  const eventIds = events.map((e) => e.id);
  await prisma.notificationLog.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.prediction.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.forumThread.deleteMany({ where: { kind: { in: ["event", "live"] }, targetId: { in: eventIds } } });
  await prisma.eventLink.deleteMany({ where: { OR: [{ fromEventId: { in: eventIds } }, { toEventId: { in: eventIds } }] } });
  await prisma.eventParticipant.deleteMany({ where: { eventId: { in: eventIds } } });
  await prisma.event.deleteMany({ where: { id: { in: eventIds } } });
  await prisma.standing.deleteMany({ where: { competitionId: { in: compIds } } });
  await prisma.competition.deleteMany({ where: { parentId: { in: seriesIds } } });
  await prisma.competition.deleteMany({ where: { id: { in: seriesIds } } });
  // Les abonnements aux équipes de démo (suivre G2 en démo) ne doivent pas rester.
  const demoEntities = await prisma.entity.findMany({ where: { region: DEMO_REGION }, select: { id: true } });
  const entityIds = demoEntities.map((e) => e.id);
  await prisma.subscription.deleteMany({ where: { OR: [{ targetType: "entity", targetId: { in: entityIds } }, { targetType: "competition", targetId: { in: compIds } }] } });
  await prisma.notificationLog.deleteMany({ where: { entityId: { in: entityIds } } });
  await prisma.entity.deleteMany({ where: { id: { in: entityIds } } });
}

async function create(stateName: string): Promise<void> {
  const state = STATES[stateName];
  const league = await prisma.competition.findFirst({ where: { name: "VCT", kind: "league", parentId: null } });
  if (!league) throw new Error("Ligue VCT introuvable : lancer le worker une fois pour ingérer le catalogue.");

  const now = Date.now();
  const hour = 3600 * 1000;
  const series = await prisma.competition.create({
    data: { categoryId: league.categoryId, parentId: league.id, kind: "serie", game: "valorant", name: SERIES_NAME, status: "live", startsAt: new Date(now - 7 * 24 * hour), endsAt: new Date(now + 3 * 24 * hour) },
  });
  const playoffs = await prisma.competition.create({
    data: { categoryId: league.categoryId, parentId: series.id, kind: "tournament", game: "valorant", name: "Playoffs", format: "double_elim", status: "live", startsAt: new Date(now - 24 * hour), endsAt: new Date(now + 3 * 24 * hour), hasBracket: false },
  });

  const entityIds: Record<string, string> = {};
  for (const code of TEAMS) {
    entityIds[code] = (await prisma.entity.create({ data: { kind: "team", name: TEAM_NAMES[code], shortName: code, region: DEMO_REGION, imageUrl: process.env.DEMO_LOGO_BASE ? `${process.env.DEMO_LOGO_BASE}/${code}.png` : null } })).id;
  }

  // Résolution dans l'ordre de jeu : chaque match connaît ses deux équipes (ou aucune).
  const resolved: Record<string, { teams: (string | null)[]; winner: string | null; loser: string | null; scores: number[] }> = {};
  const eventIds: Record<string, string> = {};
  let finishedCount = 0;
  const finishedMatches: { status: "finished"; participants: { entityExternalId: string; score: number | null; isWinner: boolean | null }[] }[] = [];

  for (const [index, spec] of SPECS.entries()) {
    const teams = spec.sides.map((s) => {
      if (!s) return null;
      if ("team" in s) return state.knownTeams ? s.team : null;
      const source = resolved[s.from];
      return source ? (s.outcome === "winner" ? source.winner : source.loser) : null;
    });
    const isPlayed = index < state.played;
    const isLive = state.live && index === state.played;
    let winner: string | null = null;
    let loser: string | null = null;
    let scores = [0, 0];
    if (isPlayed && teams[0] && teams[1]) {
      const [a, b] = teams as string[];
      winner = TEAMS.indexOf(a) < TEAMS.indexOf(b) ? a : b;
      loser = winner === a ? b : a;
      const winTo = Math.ceil(spec.bestOf / 2);
      const loserScore = finishedCount % 2 === 0 ? 0 : winTo - 1;
      scores = winner === a ? [winTo, loserScore] : [loserScore, winTo];
      finishedCount++;
    } else if (isLive && teams[0] && teams[1]) {
      scores = [1, 0];
    }
    resolved[spec.key] = { teams, winner, loser, scores };

    const startsAt = isPlayed ? new Date(now - (state.played - index + 1) * 2 * hour) : isLive ? new Date(now - hour) : new Date(now + (index - state.played + 1) * 3 * hour + 18 * hour);
    const event = await prisma.event.create({
      data: {
        competitionId: playoffs.id,
        kind: "match",
        name: `${spec.name}: ${teams[0] ? TEAM_NAMES[teams[0]] : "TBD"} vs ${teams[1] ? TEAM_NAMES[teams[1]] : "TBD"}`,
        status: isPlayed ? "finished" : isLive ? "live" : "scheduled",
        startsAt,
        endsAt: isPlayed ? new Date(startsAt.getTime() + 2 * hour) : null,
        bestOf: spec.bestOf,
        importance: spec.key === "gf" ? 3 : 1,
        result: { seriesScore: [], games: [] },
      },
    });
    eventIds[spec.key] = event.id;
    const parts = teams.map((team, side) => (team ? { team, side } : null)).filter((p): p is { team: string; side: number } => p !== null);
    for (const p of parts) {
      await prisma.eventParticipant.create({
        data: { eventId: event.id, entityId: entityIds[p.team], side: p.side, score: isPlayed || isLive ? scores[p.side] : null, isWinner: isPlayed ? p.team === winner : null },
      });
    }
    if (isPlayed && winner) {
      finishedMatches.push({
        status: "finished",
        participants: parts.map((p) => ({ entityExternalId: entityIds[p.team], score: scores[p.side], isWinner: p.team === winner })),
      });
    }
  }

  for (const spec of SPECS) {
    for (const [slot, s] of spec.sides.entries()) {
      if (!s || "team" in s) continue;
      await prisma.eventLink.create({ data: { fromEventId: eventIds[s.from], toEventId: eventIds[spec.key], outcome: s.outcome, slot } });
    }
  }

  for (const s of computeStandings(finishedMatches, { maxLives: 2 })) {
    await prisma.standing.create({
      data: { competitionId: playoffs.id, entityId: s.entityExternalId, rank: s.rank, wins: s.wins, losses: s.losses, livesLeft: s.livesLeft },
    });
  }
  console.log(`Démo « ${SERIES_NAME} » créée (${stateName}). Série ${series.id}, tournoi ${playoffs.id}.`);
}

async function main(): Promise<void> {
  const arg = process.argv[2];
  if (arg !== "remove" && !(arg in STATES)) {
    console.error("Usage : pnpm db:demo-playoffs <tbd|empty|partial|finished|remove>");
    process.exit(1);
  }
  await remove();
  if (arg === "remove") console.log("Démo supprimée.");
  else await create(arg);
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(() => prisma.$disconnect());
