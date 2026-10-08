import { favoriteCategory, pickSuggestion } from "./affinity";

describe("appli modulée (J28, #M6)", () => {
  it("la catégorie favorite est la plus suivie, sans préférence nette en cas d'égalité", () => {
    expect(favoriteCategory({})).toBeNull();
    expect(favoriteCategory({ esport: 0, sport: 0 })).toBeNull();
    expect(favoriteCategory({ esport: 5, sport: 2 })).toBe("esport");
    expect(favoriteCategory({ esport: 2, sport: 2 })).toBeNull();
    expect(favoriteCategory({ sport: 1 })).toBe("sport");
  });

  it("ne suggère rien à qui n'a encore rien suivi, ni une catégorie déjà suivie", () => {
    const candidates = [
      { category: "esport", live: true, startsAt: "2026-10-08T09:00:00Z" },
      { category: "sport", live: false, startsAt: "2026-10-09T09:00:00Z" },
    ];
    expect(pickSuggestion({}, candidates)).toBeNull();
    expect(pickSuggestion({ esport: 3 }, candidates)?.category).toBe("sport");
    expect(pickSuggestion({ esport: 3, sport: 1 }, candidates)).toBeNull();
  });

  it("préfère le direct, puis le plus proche à venir", () => {
    const pick = pickSuggestion({ politique: 1 }, [
      { category: "sport", live: false, startsAt: "2026-10-12T09:00:00Z" },
      { category: "esport", live: false, startsAt: "2026-10-09T09:00:00Z" },
    ]);
    expect(pick?.category).toBe("esport");
    const live = pickSuggestion({ politique: 1 }, [
      { category: "esport", live: false, startsAt: "2026-10-09T09:00:00Z" },
      { category: "sport", live: true, startsAt: "2026-10-12T09:00:00Z" },
    ]);
    expect(live?.category).toBe("sport");
  });
});
