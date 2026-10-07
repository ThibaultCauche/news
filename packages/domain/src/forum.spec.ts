import { accountOldEnough, campChangeWaitDays, canEditMessage, containsForbiddenWord, dmTargetId, extractMentions, forumSnippet, isChatThreadKind, isPrivateThreadKind, messageProblem, pollClosed, pollProblem, titleProblem } from "./forum";

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
  describe("messages privés et sondages (J24)", () => {
    it("dmTargetId est le même dans les deux sens", () => {
      expect(dmTargetId("b", "a")).toBe("a:b");
      expect(dmTargetId("a", "b")).toBe(dmTargetId("b", "a"));
    });
    it("seuls group et dm sont privés", () => {
      expect(isPrivateThreadKind("group")).toBe(true);
      expect(isPrivateThreadKind("dm")).toBe(true);
      expect(isPrivateThreadKind("free")).toBe(false);
      expect(isPrivateThreadKind("feature")).toBe(false);
    });
    it("pollClosed : sans date jamais fermé, sinon fermé à partir de la date", () => {
      const now = new Date("2026-10-08T12:00:00Z");
      expect(pollClosed(null, now)).toBe(false);
      expect(pollClosed("2026-10-08T12:00:01Z", now)).toBe(false);
      expect(pollClosed("2026-10-08T12:00:00Z", now)).toBe(true);
    });
    it("le direct, les groupes et les messages privés se lisent comme un tchat", () => {
      expect(["live", "group", "dm"].every(isChatThreadKind)).toBe(true);
      expect(["event", "free", "feature"].some(isChatThreadKind)).toBe(false);
    });
    it("pollProblem vérifie nombre, longueur, doublons, liens et mots interdits", () => {
      expect(pollProblem(["G2", "Fnatic"])).toBeNull();
      expect(pollProblem(["G2"])).toBe("count");
      expect(pollProblem(["a", "b", "c", "d", "e", "f", "g"])).toBe("count");
      expect(pollProblem(["G2", " "])).toBe("length");
      expect(pollProblem(["G2", "g2"])).toBe("duplicate");
      expect(pollProblem(["G2", "voir exemple.com"])).toBe("link");
      expect(pollProblem(["G2", "connard"])).toBe("forbidden");
    });
  });
});
