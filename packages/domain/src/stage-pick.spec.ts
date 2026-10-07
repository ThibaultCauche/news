import { maxStagePicks, scoreStagePick } from "./stage-pick";

describe("pronostic d'étape", () => {
  it("on choisit la moitié des équipes", () => {
    expect(maxStagePicks(16)).toBe(8);
    expect(maxStagePicks(15)).toBe(7);
  });

  it("compte les équipes qualifiées, éliminées et encore en course", () => {
    const score = scoreStagePick(["a", "b", "c", "d"], new Set(["a", "x"]), new Set(["b", "y"]));
    expect(score).toEqual({ correct: 1, wrong: 1, pending: 2 });
  });
});
