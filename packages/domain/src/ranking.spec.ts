import { computeCompetitionRanking, RankingMatchInput, RankingStageInput } from "./ranking";

const day = (n: number) => new Date(Date.UTC(2026, 9, n));
const match = (winner: string, loser: string, startsAt: Date): RankingMatchInput => ({
  status: "finished",
  startsAt,
  participants: [
    { entityId: winner, score: 2, isWinner: true },
    { entityId: loser, score: 0, isWinner: false },
  ],
});

describe("computeCompetitionRanking", () => {
  it("phase suisse en cours : qualifiée, éliminée et encore en course", () => {
    // A bat B, C, D ; B perd trois fois (éliminée) ; C et D sont encore en course.
    const swiss: RankingStageInput = {
      name: "Group Stage",
      format: "swiss",
      status: "live",
      startsAt: day(1),
      matches: [match("A", "B", day(1)), match("A", "C", day(2)), match("A", "D", day(3)), match("C", "B", day(4)), match("D", "B", day(5))],
    };
    const ranking = computeCompetitionRanking([swiss]);
    const byId = Object.fromEntries(ranking.map((r) => [r.entityId, r]));
    expect(ranking[0].entityId).toBe("A");
    expect(byId.A).toMatchObject({ status: "in_race", wins: 3, losses: 0, qualified: true });
    expect(byId.C.qualified).toBe(false);
    expect(byId.B).toMatchObject({ status: "eliminated", wins: 0, losses: 3, stage: "Group Stage" });
    expect(byId.C.status).toBe("in_race");
    expect(ranking.at(-1)?.entityId).toBe("B");
  });

  it("phase finale terminée : championne, finaliste, équipe restée en phase suisse", () => {
    const swiss: RankingStageInput = { name: "Group Stage", format: "swiss", status: "finished", startsAt: day(1), matches: [match("A", "B", day(1)), match("C", "D", day(1))] };
    const playoffs: RankingStageInput = {
      name: "Playoffs",
      format: "single_elim",
      status: "finished",
      startsAt: day(10),
      matches: [match("A", "C", day(10)), match("E", "F", day(10)), match("A", "E", day(12))],
    };
    const ranking = computeCompetitionRanking([playoffs, swiss]);
    expect(ranking[0]).toMatchObject({ entityId: "A", status: "champion", stage: "Playoffs", rank: 1 });
    expect(ranking[1]).toMatchObject({ entityId: "E", status: "eliminated", stage: "Playoffs" });
    expect(ranking.find((r) => r.entityId === "B")).toMatchObject({ status: "in_race", stage: "Group Stage" });
  });

  it("rien à classer sans match", () => {
    expect(computeCompetitionRanking([])).toEqual([]);
  });
});
