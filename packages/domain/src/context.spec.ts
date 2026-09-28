import { readFileSync } from "node:fs";
import { join } from "node:path";
import { BracketMatchInput, buildEventLinks, GSL_QUALIFIED_COUNT } from "./bracket";
import { buildGroupStakes, buildMatchStakes } from "./context";

// Fixtures = vraies réponses PandaScore (CLAUDE.md), gardées dans tests-pandascore/samples/.
const SAMPLES = join(__dirname, "../../../tests-pandascore/samples");
const load = <T>(file: string): T => JSON.parse(readFileSync(join(SAMPLES, file), "utf8"));

interface RawBracketMatch {
  id: number;
  name: string;
  number_of_games: number | null;
  previous_matches?: { type: "winner" | "loser"; match_id: number }[];
}

function toMatchInput(m: RawBracketMatch): BracketMatchInput {
  return {
    externalId: String(m.id),
    name: m.name,
    previousMatches: (m.previous_matches ?? []).map((p) => ({ type: p.type, matchExternalId: String(p.match_id) })),
  };
}

describe("buildMatchStakes (playoffs Champions 2026, brackets-playoffs.json)", () => {
  const raw = load<RawBracketMatch[]>("brackets-playoffs.json");
  const matches = raw.map(toMatchInput);
  const links = buildEventLinks(matches);
  const nameByExternalId = new Map(matches.map((m) => [m.externalId, m.name]));

  function stakesFor(externalId: string): string {
    const match = matches.find((m) => m.externalId === externalId)!;
    const outgoing = links.filter((l) => l.fromExternalId === externalId);
    const winnerTarget = outgoing.find((l) => l.outcome === "winner")?.toExternalId ?? null;
    const loserTarget = outgoing.find((l) => l.outcome === "loser")?.toExternalId ?? null;
    return buildMatchStakes({
      bestOf: raw.find((m) => String(m.id) === externalId)!.number_of_games,
      winnerTargetName: winnerTarget ? (nameByExternalId.get(winnerTarget) ?? null) : null,
      loserTargetName: loserTarget ? (nameByExternalId.get(loserTarget) ?? null) : null,
    });
  }

  it("demi-finale du tableau principal : le vainqueur avance, le perdant part au repêchage", () => {
    // Upper Bracket Semifinal 1 → gagnant : Upper Bracket Final, perdant : Lower Bracket Quarterfinal 2.
    expect(stakesFor("1685240")).toBe(
      "Le vainqueur avance au [[tableau principal]]. Le perdant garde une 2e chance au [[repêchage]]. Match en [[BO3]].",
    );
  });

  it("finale du tableau principal : le vainqueur file en grande finale, le perdant garde une chance", () => {
    // Upper Bracket Final → gagnant : Grand Final, perdant : Lower Bracket Final.
    expect(stakesFor("1685242")).toBe(
      "Le vainqueur file en grande finale et assure le podium. Le perdant garde une 2e chance au [[repêchage]]. Match en [[BO3]].",
    );
  });

  it("grande finale : pas de match suivant, champion ou 2e du tournoi", () => {
    expect(stakesFor("1685249")).toBe("Le vainqueur est sacré champion. Le perdant termine 2e du tournoi. Match en [[BO5]].");
  });

  it("finale du repêchage : le perdant est éliminé", () => {
    // Lower Bracket Final → gagnant : Grand Final, pas de lien perdant (élimination).
    expect(stakesFor("1685248")).toBe("Le vainqueur file en grande finale et assure le podium. Le perdant est éliminé du tournoi. Match en [[BO5]].");
  });
});

// J8 (écran Agenda) : "Group A" et "Group B" apparaissaient identiques, sans
// indiquer où ils mènent. Une seule phrase fixe suffit (`GSL_QUALIFIED_COUNT`
// est le même pour toutes les poules d'un tournoi), pas de calcul par poule.
describe("buildGroupStakes", () => {
  it("mentionne le nombre d'équipes qualifiées d'une poule GSL", () => {
    expect(buildGroupStakes()).toBe(`Les ${GSL_QUALIFIED_COUNT} premiers de la poule se qualifient pour la suite du tournoi.`);
  });
});
