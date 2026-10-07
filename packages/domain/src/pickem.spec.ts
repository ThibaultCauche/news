import { groupVote, invalidPickemMatch, isPerfectPickem, pickemCandidates, pickemWeights, PickemMatch, scorePickemMatch } from "./pickem";

// Quarts a/b, demie c (a,b), plus un match d (a, b : perdants) pour la 3e place façon repêchage.
const matches: PickemMatch[] = [
  { id: "qa", participants: ["A", "B"], feeders: [] },
  { id: "qb", participants: ["C", "D"], feeders: [] },
  { id: "sf", participants: [], feeders: [{ fromId: "qa", outcome: "winner" }, { fromId: "qb", outcome: "winner" }] },
  { id: "lo", participants: [], feeders: [{ fromId: "qa", outcome: "loser" }, { fromId: "sf", outcome: "loser" }] },
  { id: "f", participants: [], feeders: [{ fromId: "sf", outcome: "winner" }, { fromId: "lo", outcome: "winner" }] },
];

describe("pick'em de tableau", () => {
  it("pondère par tour : finale 4, demie 2, le reste 1", () => {
    const w = pickemWeights(matches);
    expect(w.get("f")).toBe(4);
    expect(w.get("sf")).toBe(2);
    expect(w.get("lo")).toBe(2);
    expect(w.get("qa")).toBe(1);
  });

  it("déduit les équipes possibles d'un match depuis ses propres choix", () => {
    const c = pickemCandidates(matches, { qa: "A", qb: "D", sf: "A" });
    expect(c.get("sf")).toEqual(["A", "D"]);
    expect(c.get("lo")).toEqual(["B", "D"]);
    expect(c.get("f")).toEqual(["A"]);
  });

  it("refuse une équipe qui ne peut pas jouer le match", () => {
    expect(invalidPickemMatch(matches, { qa: "A", qb: "C", sf: "C" })).toBeNull();
    expect(invalidPickemMatch(matches, { qa: "A", qb: "C", sf: "B" })).toBe("sf");
    expect(invalidPickemMatch(matches, { qa: "Z" })).toBe("qa");
    expect(invalidPickemMatch(matches, { nope: "A" })).toBe("nope");
  });

  it("marque le poids si juste, rien sinon", () => {
    expect(scorePickemMatch(4, "A", "A")).toBe(4);
    expect(scorePickemMatch(4, "A", "B")).toBe(0);
  });

  it("le bonus exige tous les matchs justes", () => {
    const winners = new Map([["qa", "A"], ["qb", "C"]]);
    expect(isPerfectPickem(winners, { qa: "A", qb: "C" })).toBe(true);
    expect(isPerfectPickem(winners, { qa: "A", qb: "D" })).toBe(false);
    expect(isPerfectPickem(winners, { qa: "A" })).toBe(false);
    expect(isPerfectPickem(new Map(), {})).toBe(false);
  });

  it("le vote de groupe suit la majorité, puis le plus ancien", () => {
    expect(groupVote(["A", "B", "B"])).toBe("B");
    expect(groupVote(["A", "B"])).toBe("A");
    expect(groupVote([])).toBeNull();
  });
});

import { pickemFinalId, pickemPossible, pickemStanding } from "./pickem";
import { earnedBadges } from "./badges";
import { isStageSettled, stagePickPoints } from "./stage-pick";

describe("pick'em : en vie, champion", () => {
  it("trouve la finale", () => {
    expect(pickemFinalId(matches)).toBe("f");
  });

  it("un match joué ne laisse passer que son vainqueur", () => {
    const p = pickemPossible(matches, new Map([["qa", "A"]]));
    expect([...p.get("sf")!].sort()).toEqual(["A", "C", "D"]);
    // le perdant de la demie peut être n'importe quel finaliste possible, A compris
    expect([...p.get("lo")!].sort()).toEqual(["A", "B", "C", "D"]);
  });

  it("calcule les points encore possibles et le champion", () => {
    const picks = { qa: "A", qb: "C", sf: "A", lo: "B", f: "A" };
    // Rien de joué : 1 + 1 + 2 + 2 + 4 + bonus 5 + champion 3
    expect(pickemStanding(matches, picks, new Map()).maxRemaining).toBe(18);
    // A perd son quart : la demie choisie tombe, mais A peut encore atteindre la finale par le repêchage.
    const lost = pickemStanding(matches, picks, new Map([["qa", "B"]]));
    expect(lost.alive.get("sf")).toBe(false);
    expect(lost.alive.get("f")).toBe(true);
    // Le tableau parfait n'est plus possible : plus de bonus de 5.
    expect(lost.maxRemaining).toBe(1 + 2 + 4 + 3);
    expect(lost.alive.get("qb")).toBe(true);
  });
});

describe("pronostic de phase suisse : points", () => {
  it("un point par qualifiée devinée, et l'étape est réglée quand chacun a son sort", () => {
    expect(stagePickPoints(["a", "b", "c"], new Set(["a", "c", "z"]))).toBe(2);
    expect(isStageSettled(["a", "b"], new Set(["a"]), new Set(["b"]))).toBe(true);
    expect(isStageSettled(["a", "b"], new Set(["a"]), new Set())).toBe(false);
    expect(isStageSettled([], new Set(), new Set())).toBe(false);
  });
});

describe("badges", () => {
  it("se déduisent de l'activité", () => {
    const ids = (s: Parameters<typeof earnedBadges>[0]) => earnedBadges(s).filter((b) => b.earned).map((b) => b.id);
    expect(ids({ pickemsPlayed: 0, perfectBrackets: 0, championsCalled: 0, perfectSwiss: 0 })).toEqual([]);
    expect(ids({ pickemsPlayed: 3, perfectBrackets: 1, championsCalled: 1, perfectSwiss: 0 })).toEqual(["first_pickem", "three_pickems", "champion_called", "perfect_bracket"]);
  });
});

describe("équipes réelles connues", () => {
  it("un match dont les deux équipes sont connues ne propose qu'elles, quoi qu'on ait choisi plus haut", () => {
    const real: PickemMatch[] = [
      { id: "q1", participants: ["A", "B"], feeders: [] },
      { id: "q2", participants: ["C", "D"], feeders: [] },
      { id: "s", participants: ["A", "D"], feeders: [{ fromId: "q1", outcome: "winner" }, { fromId: "q2", outcome: "winner" }] },
    ];
    expect(pickemCandidates(real, { q1: "B", q2: "C" }).get("s")).toEqual(["A", "D"]);
  });
});
