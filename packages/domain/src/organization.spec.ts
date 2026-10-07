import { organizationKey } from "./organization";

describe("organizationKey", () => {
  it("rapproche une structure d'un jeu à l'autre", () => {
    expect(organizationKey("Team Liquid")).toBe(organizationKey("Liquid"));
    expect(organizationKey("Gen.G Esports")).toBe(organizationKey("Gen.G"));
    expect(organizationKey("G2 Esports")).toBe("g2");
    expect(organizationKey("KOI")).toBe("koi");
  });

  it("ne confond pas une équipe académie avec la principale", () => {
    expect(organizationKey("Karmine Corp Blue")).not.toBe(organizationKey("Karmine Corp"));
  });

  it("refuse un nom trop court ou vide de sens", () => {
    expect(organizationKey("Team")).toBeNull();
    expect(organizationKey("X")).toBeNull();
  });
});
