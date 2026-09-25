import { QuotaTracker } from "./quota";

function headersWith(limit: string, used: string, remaining: string): Headers {
  return new Headers({
    "x-rate-limit-limit": limit,
    "x-rate-limit-used": used,
    "x-rate-limit-remaining": remaining,
  });
}

describe("QuotaTracker", () => {
  it("calcule le ratio d'utilisation à partir des en-têtes", () => {
    const tracker = new QuotaTracker();
    tracker.recordHeaders(headersWith("1000", "400", "600"));
    expect(tracker.getUsageRatio()).toBeCloseTo(0.4);
    expect(tracker.shouldThrottle()).toBe(false);
  });

  it("ralentit au-delà de 70% du quota (règle 5 de CLAUDE.md)", () => {
    const tracker = new QuotaTracker();
    tracker.recordHeaders(headersWith("1000", "750", "250"));
    expect(tracker.shouldThrottle()).toBe(true);
  });

  it("ne ralentit pas avant d'avoir reçu un en-tête", () => {
    const tracker = new QuotaTracker();
    expect(tracker.shouldThrottle()).toBe(false);
  });

  it("déduit le quota de used+remaining quand x-rate-limit-limit est absent (cas réel PandaScore)", () => {
    const tracker = new QuotaTracker();
    tracker.recordHeaders(new Headers({ "x-rate-limit-remaining": "985", "x-rate-limit-used": "15" }));
    expect(tracker.getUsageRatio()).toBeCloseTo(0.015);
  });
});
