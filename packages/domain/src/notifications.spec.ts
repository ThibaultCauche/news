import { buildNotificationText, isQuietHour, localHourFromOffsetMinutes, shouldNotify } from "./notifications";

describe("shouldNotify", () => {
  it("ne notifie jamais si l'option est désactivée", () => {
    expect(shouldNotify({ notifyEnabled: false, subscriptionLevel: "all", eventImportance: 5 })).toBe(false);
  });

  it("notifie de chaque événement pour un abonnement 'tout' (ex. G2)", () => {
    expect(shouldNotify({ notifyEnabled: true, subscriptionLevel: "all", eventImportance: 0 })).toBe(true);
  });

  it("un abonnement 'grands moments' (ex. catégorie Valorant) filtre par importance", () => {
    expect(shouldNotify({ notifyEnabled: true, subscriptionLevel: "key_moments", eventImportance: 0 })).toBe(false);
    expect(shouldNotify({ notifyEnabled: true, subscriptionLevel: "key_moments", eventImportance: 2 })).toBe(true);
  });
});

describe("isQuietHour", () => {
  it("aucune heure calme si les bornes sont absentes ou égales", () => {
    expect(isQuietHour(23, null, 7)).toBe(false);
    expect(isQuietHour(23, 22, 22)).toBe(false);
  });

  it("plage simple (dans la même journée)", () => {
    expect(isQuietHour(10, 9, 12)).toBe(true);
    expect(isQuietHour(8, 9, 12)).toBe(false);
  });

  it("plage qui traverse minuit (ex. 22h -> 7h)", () => {
    expect(isQuietHour(23, 22, 7)).toBe(true);
    expect(isQuietHour(3, 22, 7)).toBe(true);
    expect(isQuietHour(12, 22, 7)).toBe(false);
  });
});

describe("localHourFromOffsetMinutes", () => {
  it("calcule l'heure locale à partir d'un décalage UTC en minutes", () => {
    const date = new Date("2026-01-15T23:30:00Z");
    expect(localHourFromOffsetMinutes(date, 60)).toBe(0); // UTC+1 : 23h30 -> 0h30
    expect(localHourFromOffsetMinutes(date, 0)).toBe(23);
  });

  it("gère un décalage négatif qui repasse par la veille", () => {
    const date = new Date("2026-01-15T01:00:00Z");
    expect(localHourFromOffsetMinutes(date, -120)).toBe(23); // UTC-2
  });
});

describe("buildNotificationText", () => {
  it("ne contient jamais le score ou le gagnant en sans-spoil", () => {
    const text = buildNotificationText("result", "G2 vs PRX", true, "G2");
    expect(text.body).not.toContain("G2 a gagné");
  });

  it("annonce le gagnant quand le sans-spoil est désactivé", () => {
    const text = buildNotificationText("result", "G2 vs PRX", false, "G2");
    expect(text.body).toContain("G2 a gagné");
  });

  it("rappel et début ne dépendent pas du sans-spoil", () => {
    expect(buildNotificationText("reminder", "G2 vs PRX", true, null).body).toContain("15 minutes");
    expect(buildNotificationText("start", "G2 vs PRX", false, null).body).toContain("commence");
  });

  it("qualification et élimination portent le nom de l'entité, pas d'un match (J5)", () => {
    expect(buildNotificationText("qualification", "G2 Esports", true, null).body).toContain("G2 Esports");
    expect(buildNotificationText("elimination", "TYLOO", true, null).body).toContain("TYLOO");
  });
});
