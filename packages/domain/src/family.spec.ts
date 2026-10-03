import { competitionSpecificity, familyNameOf, isMajorEvent, nearestCompetitionRule } from "./family";

describe("familyNameOf", () => {
  it("retire l'année finale", () => {
    expect(familyNameOf("Champions 2026")).toBe("Champions");
    expect(familyNameOf("Champions 2025")).toBe("Champions");
    expect(familyNameOf("Americas Stage 2 2026")).toBe("Americas Stage 2");
    expect(familyNameOf("EMEA Kickoff 2026")).toBe("EMEA Kickoff");
  });

  it("regroupe tous les Masters, quelle que soit la ville", () => {
    expect(familyNameOf("Masters Santiago 2026")).toBe("Masters");
    expect(familyNameOf("Masters London 2026")).toBe("Masters");
    expect(familyNameOf("Masters Toronto 2027")).toBe("Masters");
  });

  it("garde un nom sans année tel quel et ne confond pas « Masters » seul", () => {
    expect(familyNameOf("Champions")).toBe("Champions");
    expect(familyNameOf("Masters")).toBe("Masters");
  });

  it("pas de famille pour une série réduite à son année", () => {
    expect(familyNameOf("2025")).toBeNull();
    expect(familyNameOf("2026")).toBeNull();
  });
});

describe("nearestCompetitionRule", () => {
  // Chaîne d'un match : 0 = tournoi (Playoffs), 1 = série (Champions 2026), 2 = ligue (VCT).
  const league = { name: "ligue", specificity: competitionSpecificity("competition", 2), muted: false };
  const family = { name: "famille", specificity: competitionSpecificity("family", 1), muted: false };
  const serie = { name: "série", specificity: competitionSpecificity("competition", 1), muted: false };
  const mutedSerie = { ...serie, muted: true };

  it("aucune règle : rien", () => {
    expect(nearestCompetitionRule([])).toBeNull();
  });

  it("la famille passe avant la ligue, la série avant la famille", () => {
    expect(nearestCompetitionRule([league, family])?.name).toBe("famille");
    expect(nearestCompetitionRule([league, family, serie])?.name).toBe("série");
  });

  it("« tout sauf une » : une série en sourdine l'emporte sur la ligue suivie", () => {
    const nearest = nearestCompetitionRule([league, mutedSerie]);
    expect(nearest?.muted).toBe(true);
  });

  it("la sourdine d'une autre série n'a pas d'effet sur celle-ci (elle n'est pas dans la chaîne)", () => {
    expect(nearestCompetitionRule([league])?.muted).toBe(false);
  });
});

describe("isMajorEvent", () => {
  it("reconnaît les grands rendez-vous mondiaux", () => {
    expect(isMajorEvent("VCT", "Champions 2026")).toBe(true);
    expect(isMajorEvent("VCT", "Masters London 2026")).toBe(true);
    expect(isMajorEvent("Esports World Cup", "2026")).toBe(true);
    expect(isMajorEvent("LoL Esports", "Worlds 2026")).toBe(true);
  });

  it("écarte les étapes régionales, les qualifications et les petites ligues", () => {
    expect(isMajorEvent("VCT", "Americas Stage 2 2026")).toBe(false);
    expect(isMajorEvent("VCT", "EMEA Kickoff 2026")).toBe(false);
    expect(isMajorEvent("Monsters Reloaded", "Closed Qualifier 2026")).toBe(false);
    expect(isMajorEvent("Esports World Cup", "Americas Qualifier 2026")).toBe(false);
  });
});
