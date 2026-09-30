import { generateGroupCode, GROUP_CODE_LENGTH, pseudoChangeWaitDays, pseudoKeyOf, pseudoProblem, scorePrediction } from "./community";

const outcome = { winnerEntityId: "g2", scoreByEntity: { g2: 2, prx: 1 } };

describe("scorePrediction", () => {
  it("3 points pour le bon vainqueur sans score", () => {
    expect(scorePrediction({ pickedEntityId: "g2", pickedScore: null, otherScore: null }, outcome)).toBe(3);
  });
  it("+2 si le score de série est exact", () => {
    expect(scorePrediction({ pickedEntityId: "g2", pickedScore: 2, otherScore: 1 }, outcome)).toBe(5);
  });
  it("score faux mais bon vainqueur : 3", () => {
    expect(scorePrediction({ pickedEntityId: "g2", pickedScore: 2, otherScore: 0 }, outcome)).toBe(3);
  });
  it("mauvais vainqueur : 0, même avec un score juste vu de l'autre côté", () => {
    expect(scorePrediction({ pickedEntityId: "prx", pickedScore: 2, otherScore: 1 }, outcome)).toBe(0);
  });
});

describe("pseudo", () => {
  it("clé insensible à la casse et aux accents", () => {
    expect(pseudoKeyOf("Théo_92")).toBe(pseudoKeyOf("theo_92"));
  });
  it("refuse trop court, caractères spéciaux, mots interdits", () => {
    expect(pseudoProblem("ab")).toBe("length");
    expect(pseudoProblem("a b c")).toBe("characters");
    expect(pseudoProblem("Xx_Nazi_xX")).toBe("forbidden");
    expect(pseudoProblem("Théo_92")).toBeNull();
  });
  it("délai de changement de 30 jours", () => {
    const now = new Date("2026-10-31T00:00:00Z");
    expect(pseudoChangeWaitDays(null, now)).toBe(0);
    expect(pseudoChangeWaitDays(new Date("2026-10-21T00:00:00Z"), now)).toBe(20);
    expect(pseudoChangeWaitDays(new Date("2026-09-01T00:00:00Z"), now)).toBe(0);
  });
});

describe("generateGroupCode", () => {
  it("8 caractères sans ambiguïté", () => {
    const code = generateGroupCode((max) => Math.floor(Math.random() * max));
    expect(code).toHaveLength(GROUP_CODE_LENGTH);
    expect(code).toMatch(/^[2-9A-HJKMNP-Z]+$/);
  });
});
