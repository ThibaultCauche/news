import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  BracketMatchInput,
  buildEventLinks,
  computeBracketRounds,
  computeStandings,
  detectBracketFormat,
  diffStandings,
  StandingMatchInput,
} from "./bracket";

// Fixtures = vraies réponses PandaScore (CLAUDE.md : "à réutiliser comme fixtures de
// tests"), gardées dans tests-pandascore/samples/.
const SAMPLES = join(__dirname, "../../../tests-pandascore/samples");
const load = <T>(file: string): T => JSON.parse(readFileSync(join(SAMPLES, file), "utf8"));

interface RawBracketMatch {
  id: number;
  name: string;
  status: string;
  previous_matches?: { type: "winner" | "loser"; match_id: number }[];
  opponents?: { opponent: { id: number; acronym?: string } }[];
  results?: { score: number; team_id: number }[];
}

function toMatchInput(m: RawBracketMatch): BracketMatchInput {
  return {
    externalId: String(m.id),
    name: m.name,
    previousMatches: (m.previous_matches ?? []).map((p) => ({ type: p.type, matchExternalId: String(p.match_id) })),
  };
}

function toStandingInput(m: RawBracketMatch): StandingMatchInput {
  return {
    status: m.status === "finished" ? "finished" : "scheduled",
    participants: (m.opponents ?? []).map((o) => {
      const result = m.results?.find((r) => r.team_id === o.opponent.id);
      const winnerScore = Math.max(...(m.results?.map((r) => r.score) ?? [0]));
      return {
        entityExternalId: String(o.opponent.id),
        score: result?.score ?? null,
        isWinner: m.status === "finished" && result ? result.score === winnerScore : null,
      };
    }),
  };
}

describe("detectBracketFormat", () => {
  it("détecte une poule GSL (Winners/Elimination/Decider Match)", () => {
    const matches = load<RawBracketMatch[]>("brackets-du-tournoi.json").map(toMatchInput);
    expect(detectBracketFormat(matches)).toBe("groups_gsl");
  });

  it("détecte une double élimination (Upper/Lower Bracket, playoffs Champions)", () => {
    const matches = load<RawBracketMatch[]>("brackets-playoffs.json").map(toMatchInput);
    expect(detectBracketFormat(matches)).toBe("double_elim");
  });

  it("détecte une triple élimination (Upper/Mid/Lower bracket, Kickoff « 3 vies »)", () => {
    const matches = load<RawBracketMatch[]>("brackets-kickoff-3-vies.json").map(toMatchInput);
    expect(detectBracketFormat(matches)).toBe("triple_elim");
  });
});

describe("buildEventLinks", () => {
  it("construit les liens gagnant/perdant de la poule GSL", () => {
    const matches = load<RawBracketMatch[]>("brackets-du-tournoi.json").map(toMatchInput);
    const links = buildEventLinks(matches);

    // Decider Match reçoit le perdant du Winners Match et le gagnant de l'Elimination Match.
    expect(links).toContainEqual({ fromExternalId: "1685230", toExternalId: "1685232", outcome: "loser", slot: 0 });
    expect(links).toContainEqual({ fromExternalId: "1685231", toExternalId: "1685232", outcome: "winner", slot: 1 });
    // Les 2 matchs d'ouverture n'ont pas de previous_matches : pas de lien entrant.
    expect(links.some((l) => l.toExternalId === "1682152" || l.toExternalId === "1682153")).toBe(false);
  });
});

describe("computeBracketRounds", () => {
  it("place la Grand Final au round 0 et les quarts au round le plus élevé (playoffs)", () => {
    const matches = load<RawBracketMatch[]>("brackets-playoffs.json").map(toMatchInput);
    const rounds = computeBracketRounds(matches);

    const finalMatch = matches.find((m) => m.name.startsWith("Grand Final"))!;
    expect(rounds[finalMatch.externalId]).toBe(0);

    // Le tableau haut (upper bracket) atteint la finale en moins de tours que le
    // tableau bas (lower bracket, qui rejoue les perdants) : les quarts du tableau
    // haut ne sont donc pas forcément le round le plus profond de l'arbre entier.
    const upperQuarterFinals = matches.filter((m) => m.name.includes("Upper Bracket Quarterfinal"));
    expect(upperQuarterFinals.length).toBe(4);
    const upperRounds = new Set(upperQuarterFinals.map((m) => rounds[m.externalId]));
    expect(upperRounds.size).toBe(1); // les 4 quarts sont au même round
    expect([...upperRounds][0]).toBeGreaterThan(0);

    const lowerRoundOne = matches.filter((m) => m.name.includes("Lower Bracket Round 1"));
    expect(lowerRoundOne.length).toBe(2);
    for (const m of lowerRoundOne) {
      expect(rounds[m.externalId]).toBe(Math.max(...Object.values(rounds)));
    }
  });

  it("place le Decider Match au round 0 dans une poule GSL à 5 matchs", () => {
    const matches = load<RawBracketMatch[]>("brackets-du-tournoi.json").map(toMatchInput);
    const rounds = computeBracketRounds(matches);
    const decider = matches.find((m) => m.name.startsWith("Decider Match"))!;
    expect(rounds[decider.externalId]).toBe(0);
  });
});

describe("computeStandings", () => {
  it("recalcule victoires/défaites/écart de cartes d'une poule GSL à partir des matchs joués", () => {
    const matches = load<RawBracketMatch[]>("brackets-du-tournoi.json").map(toStandingInput);
    const standings = computeStandings(matches, { maxLives: 2, qualifiedCount: 2 });

    const g2 = standings.find((s) => s.entityExternalId === "128538")!; // G2, a battu TYLOO 2-0
    const tyloo = standings.find((s) => s.entityExternalId === "133288")!;
    const pr = standings.find((s) => s.entityExternalId === "128917")!; // PR, a battu TL 2-1
    const tl = standings.find((s) => s.entityExternalId === "128541")!;

    expect(g2).toMatchObject({ wins: 1, losses: 0, mapDiff: 2, livesLeft: 2, qualified: true });
    expect(pr).toMatchObject({ wins: 1, losses: 0, mapDiff: 1, livesLeft: 2, qualified: true });
    expect(tl).toMatchObject({ wins: 0, losses: 1, mapDiff: -1, livesLeft: 1, qualified: false });
    expect(tyloo).toMatchObject({ wins: 0, losses: 1, mapDiff: -2, livesLeft: 1, qualified: false });

    // Classement trié par victoires puis écart de cartes : G2 > PR > TL > TYLOO.
    expect(standings.map((s) => s.entityExternalId)).toEqual(["128538", "128917", "128541", "133288"]);
  });

  it("ignore les matchs non terminés (TBD, à venir)", () => {
    const matches = load<RawBracketMatch[]>("brackets-playoffs.json").map(toStandingInput);
    const standings = computeStandings(matches, { maxLives: 2 });
    expect(standings).toEqual([]);
  });
});

describe("diffStandings", () => {
  it("détecte une nouvelle qualification (docs/03 §6, notification 'qualification')", () => {
    const before = [{ entityId: "g2", qualified: false, livesLeft: 2 }];
    const after = [{ entityId: "g2", qualified: true, livesLeft: 2 }];
    expect(diffStandings(before, after)).toEqual({ qualifiedEntityIds: ["g2"], eliminatedEntityIds: [] });
  });

  it("détecte une élimination (0 vie restante)", () => {
    const before = [{ entityId: "tyloo", qualified: false, livesLeft: 1 }];
    const after = [{ entityId: "tyloo", qualified: false, livesLeft: 0 }];
    expect(diffStandings(before, after)).toEqual({ qualifiedEntityIds: [], eliminatedEntityIds: ["tyloo"] });
  });

  it("ne redéclenche pas si l'état était déjà qualifié/éliminé (pas de spam à chaque recalcul)", () => {
    const state = [{ entityId: "g2", qualified: true, livesLeft: 0 }];
    expect(diffStandings(state, state)).toEqual({ qualifiedEntityIds: [], eliminatedEntityIds: [] });
  });

  it("une nouvelle entité (pas dans l'ancien classement) qui arrive déjà qualifiée compte comme un changement", () => {
    const after = [{ entityId: "g2", qualified: true, livesLeft: 2 }];
    expect(diffStandings([], after)).toEqual({ qualifiedEntityIds: ["g2"], eliminatedEntityIds: [] });
  });
});
