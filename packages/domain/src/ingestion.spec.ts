import { computeIngestionLatencyMs, computePayloadHash, shouldUpsert } from "./ingestion";

describe("computePayloadHash", () => {
  it("est stable si l'ordre des clés change mais pas le contenu", () => {
    const a = computePayloadHash({ id: 1, name: "NS vs NRG" });
    const b = computePayloadHash({ name: "NS vs NRG", id: 1 });
    expect(a).toBe(b);
  });

  it("change si le contenu change", () => {
    const a = computePayloadHash({ id: 1, status: "running" });
    const b = computePayloadHash({ id: 1, status: "finished" });
    expect(a).not.toBe(b);
  });
});

describe("shouldUpsert", () => {
  it("n'écrit rien si le hash est identique (règle 4 de CLAUDE.md)", () => {
    const hash = computePayloadHash({ id: 1 });
    expect(shouldUpsert(hash, hash)).toBe(false);
  });

  it("écrit si le hash a changé", () => {
    expect(shouldUpsert("abc", "def")).toBe(true);
  });

  it("écrit à la première synchro (aucun hash existant)", () => {
    expect(shouldUpsert(null, "def")).toBe(true);
  });
});

describe("computeIngestionLatencyMs", () => {
  it("mesure l'écart entre la fin réelle et la détection", () => {
    const endAt = new Date("2026-09-25T09:55:30Z");
    const detectedAt = new Date("2026-09-25T09:56:12Z");
    expect(computeIngestionLatencyMs(endAt, detectedAt)).toBe(42_000);
  });
});
