import { buildMorningDigestText, buildNotificationText, defaultSubscriptionNotifications, isTypeEnabled, isQuietHour, localDayBounds, localHourFromOffsetMinutes, shouldNotify } from "./notifications";

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

describe("isTypeEnabled", () => {
  const all = { notifyMatchReminder: true, notifyMatchStart: true, notifyMatchResult: true, notifyQualification: true, notifyPredictionReminders: true };
  it("tout passe sans réglages", () => {
    expect(isTypeEnabled("result", null)).toBe(true);
  });
  it("chaque type suit son réglage", () => {
    expect(isTypeEnabled("start", { ...all, notifyMatchStart: false })).toBe(false);
    expect(isTypeEnabled("result", { ...all, notifyMatchStart: false })).toBe(true);
    expect(isTypeEnabled("elimination", { ...all, notifyQualification: false })).toBe(false);
  });
  it("le rappel T-15 dit que le pronostic manque", () => {
    expect(buildNotificationText("reminder", "G2 vs PRX", true, null, true).body).toContain("pas encore pronostiqué");
    expect(buildNotificationText("reminder", "G2 vs PRX", true, null).body).not.toContain("pronostiqué");
  });
});

describe("defaultSubscriptionNotifications", () => {
  it("équipe : début et résultat ; compétition : résultat seul ; match : tout", () => {
    expect(defaultSubscriptionNotifications("entity")).toEqual({ notifyReminder: false, notifyStart: true, notifyResult: true });
    expect(defaultSubscriptionNotifications("competition")).toEqual({ notifyReminder: false, notifyStart: false, notifyResult: true });
    expect(defaultSubscriptionNotifications("competition_family").notifyStart).toBe(false);
    expect(defaultSubscriptionNotifications("event")).toEqual({ notifyReminder: true, notifyStart: true, notifyResult: true });
  });
});

describe("résumé du matin", () => {
  const at = (iso: string) => new Date(iso);

  it("jour local d'un appareil en UTC+2 : de 22 h UTC la veille à 22 h UTC", () => {
    const { start, end } = localDayBounds(at("2026-10-03T07:30:00Z"), 120);
    expect(start.toISOString()).toBe("2026-10-02T22:00:00.000Z");
    expect(end.toISOString()).toBe("2026-10-03T22:00:00.000Z");
  });

  it("un seul match : heure locale, minutes seulement si non nulles", () => {
    expect(buildMorningDigestText([{ name: "G2 vs TL", startsAt: at("2026-10-03T16:00:00Z") }], 120).body).toBe("1 match de tes suivis : G2 vs TL à 18 h.");
    expect(buildMorningDigestText([{ name: "G2 vs TL", startsAt: at("2026-10-03T16:30:00Z") }], 120).body).toContain("à 18 h 30.");
  });

  it("plusieurs matchs : le nombre et le premier", () => {
    const body = buildMorningDigestText(
      [
        { name: "A vs B", startsAt: at("2026-10-03T09:00:00Z") },
        { name: "C vs D", startsAt: at("2026-10-03T12:00:00Z") },
      ],
      -300,
    ).body;
    expect(body).toBe("2 matchs de tes suivis, le premier à 4 h : A vs B.");
  });
});

describe("textes de qualification (J23)", () => {
  it("nomme la compétition quand on la connaît", () => {
    expect(buildNotificationText("qualification", "G2", false, null, false, "Worlds 2026").body).toBe("G2 est qualifiée pour la suite de Worlds 2026.");
    expect(buildNotificationText("elimination", "G2", false, null, false, "Worlds 2026").body).toBe("G2 est éliminée de Worlds 2026.");
  });

  it("garde le texte d'avant sans compétition", () => {
    expect(buildNotificationText("qualification", "G2", false, null).body).toBe("G2 est qualifiée pour la suite.");
  });

  it("annonce une équipe de plus dans une structure suivie", () => {
    expect(buildNotificationText("called", "Grand final: Sonix vs Zomba", false, null)).toEqual({ title: "Appelés à leur station", body: "Grand final: Sonix vs Zomba : les joueurs sont appelés, ça va commencer." });
    expect(isTypeEnabled("called", { notifyMatchReminder: false, notifyMatchStart: true, notifyMatchResult: false, notifyQualification: false, notifyPredictionReminders: false })).toBe(true);
    expect(buildNotificationText("organization_joined", "Team Liquid", false, null, false, "League of Legends").body).toBe(
      "Team Liquid joue aussi en League of Legends : tu la suis déjà.",
    );
  });
});
