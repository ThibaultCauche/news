import { accountOldEnough, campChangeWaitDays, canEditMessage, containsForbiddenWord, extractMentions, forumSnippet, messageProblem, titleProblem } from "./forum";

describe("forum", () => {
  describe("messageProblem", () => {
    it("accepte un message normal", () => {
      expect(messageProblem("Quelle série ! Le 3e round était fou")).toBeNull();
    });
    it("refuse vide, trop long, lien, mot interdit", () => {
      expect(messageProblem("   ")).toBe("empty");
      expect(messageProblem("a".repeat(501))).toBe("length");
      expect(messageProblem("regarde https://exemple.test")).toBe("link");
      expect(messageProblem("va sur www.truc")).toBe("link");
      expect(messageProblem("clique exemple.com")).toBe("link");
      expect(messageProblem("T'es un Connard")).toBe("forbidden");
    });
    it("ne bloque pas un mot qui en contient un autre", () => {
      expect(containsForbiddenWord("ordinateur compute")).toBe(false);
      expect(containsForbiddenWord("ENCULÉ")).toBe(true);
    });
    it("ne prend pas un score ou une ponctuation pour un lien", () => {
      expect(messageProblem("2.1 pour eux, non ?")).toBeNull();
      expect(messageProblem("fin.Ok")).toBeNull();
    });
  });

  it("titleProblem", () => {
    expect(titleProblem("ab")).toBe("length");
    expect(titleProblem("Meilleure équipe de la saison ?")).toBeNull();
    expect(titleProblem("vu sur youtube.com")).toBe("link");
  });

  it("accountOldEnough : 24 h", () => {
    const now = new Date("2026-10-02T12:00:00Z");
    expect(accountOldEnough(new Date("2026-10-01T11:00:00Z"), now)).toBe(true);
    expect(accountOldEnough(new Date("2026-10-01T13:00:00Z"), now)).toBe(false);
  });

  it("campChangeWaitDays : 7 jours", () => {
    const now = new Date("2026-10-08T00:00:00Z");
    expect(campChangeWaitDays(null, now)).toBe(0);
    expect(campChangeWaitDays(new Date("2026-10-05T00:00:00Z"), now)).toBe(4);
    expect(campChangeWaitDays(new Date("2026-10-01T00:00:00Z"), now)).toBe(0);
  });

  it("forumSnippet tronque", () => {
    expect(forumSnippet("a  b\nc")).toBe("a b c");
    expect(forumSnippet("x".repeat(200)).length).toBe(90);
  });

  it("canEditMessage : 5 minutes", () => {
    const created = new Date("2026-10-02T12:00:00Z");
    expect(canEditMessage(created, new Date("2026-10-02T12:04:59Z"))).toBe(true);
    expect(canEditMessage(created, new Date("2026-10-02T12:05:01Z"))).toBe(false);
  });

  it("extractMentions : @pseudo sans doublon, pas dans un mot ni un e-mail", () => {
    expect(extractMentions("@Theo_92 et @Lea.k, bien vu @Theo_92 !")).toEqual(["Theo_92", "Lea.k"]);
    expect(extractMentions("ecris a moi@exemple.test")).toEqual([]);
    expect(extractMentions("@ab trop court")).toEqual([]);
    expect(extractMentions("@aaa @bbb @ccc @ddd @eee @fff")).toHaveLength(5);
  });
});
