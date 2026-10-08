import { grandPrixName, isPracticeSession, notificationSubject, sessionHasWinner } from "./formula1";

describe("Formule 1 (J28)", () => {
  it("traduit les Grands Prix connus et garde le nom des autres", () => {
    expect(grandPrixName("Australian Grand Prix")).toBe("Grand Prix d'Australie");
    expect(grandPrixName("United States Grand Prix")).toBe("Grand Prix des États-Unis");
    expect(grandPrixName("Bahrain Grand Prix in Malaysia")).toBe("Bahrain Grand Prix in Malaysia");
    expect(grandPrixName("Inconnu Grand Prix")).toBe("Inconnu Grand Prix");
  });

  it("nomme une session avec son Grand Prix, et laisse un duel tel quel", () => {
    expect(notificationSubject({ kind: "session", name: "Course" }, "Australian Grand Prix")).toBe("Grand Prix d'Australie (Course)");
    expect(notificationSubject({ kind: "match", name: "G2 vs PRX" }, "Playoffs")).toBe("G2 vs PRX");
  });

  it("distingue les essais, et les sessions qui ont un vainqueur", () => {
    expect(isPracticeSession("Essais libres 2")).toBe(true);
    expect(isPracticeSession("Course")).toBe(false);
    expect(sessionHasWinner("Course")).toBe(true);
    expect(sessionHasWinner("Sprint")).toBe(true);
    expect(sessionHasWinner("Qualifications")).toBe(false);
  });
});
