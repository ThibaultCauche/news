import { diffEventStatus } from "./events";

describe("diffEventStatus", () => {
  it("émet EventScheduled à la création (pas d'état précédent)", () => {
    expect(diffEventStatus(null, { status: "scheduled", resultHash: null })).toEqual(["EventScheduled"]);
  });

  it("émet EventStarted quand le statut passe à live", () => {
    const types = diffEventStatus({ status: "scheduled", resultHash: null }, { status: "live", resultHash: null });
    expect(types).toEqual(["EventStarted"]);
  });

  it("émet EventFinished quand le statut passe à finished", () => {
    const types = diffEventStatus({ status: "live", resultHash: "a" }, { status: "finished", resultHash: "a" });
    expect(types).toEqual(["EventFinished"]);
  });

  it("émet ScoreChanged si le résultat change en direct, sans changement de statut", () => {
    const types = diffEventStatus({ status: "live", resultHash: "a" }, { status: "live", resultHash: "b" });
    expect(types).toEqual(["ScoreChanged"]);
  });

  it("peut émettre EventFinished et ScoreChanged ensemble (dernier score = score final)", () => {
    const types = diffEventStatus({ status: "live", resultHash: "a" }, { status: "finished", resultHash: "b" });
    expect(types).toEqual(["EventFinished", "ScoreChanged"]);
  });

  it("n'émet rien si rien n'a changé", () => {
    expect(diffEventStatus({ status: "live", resultHash: "a" }, { status: "live", resultHash: "a" })).toEqual([]);
  });

  it("ignore un changement de résultat tant que le match n'a pas commencé", () => {
    const types = diffEventStatus({ status: "scheduled", resultHash: null }, { status: "scheduled", resultHash: "a" });
    expect(types).toEqual([]);
  });
});
