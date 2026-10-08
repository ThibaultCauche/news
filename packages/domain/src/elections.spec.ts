import { electionEmbargo, ELECTIONS, isComplete, isElectionDay, majoritySeats, parisTime } from "./elections";

describe("parisTime", () => {
  it("tient compte de l'heure d'hiver et d'été", () => {
    // 22 mars 2026 : heure d'hiver (UTC+1) ; 18 avril 2027 : heure d'été (UTC+2).
    expect(parisTime("2026-03-22", 20).toISOString()).toBe("2026-03-22T19:00:00.000Z");
    expect(parisTime("2027-04-18", 20).toISOString()).toBe("2027-04-18T18:00:00.000Z");
  });
  it("gère le jour du changement d'heure (29 mars 2026, 2 h → 3 h)", () => {
    expect(parisTime("2026-03-29", 0).toISOString()).toBe("2026-03-28T23:00:00.000Z");
    expect(parisTime("2026-03-29", 20).toISOString()).toBe("2026-03-29T18:00:00.000Z");
  });
});

describe("electionEmbargo (article L52-2)", () => {
  const date = "2027-04-18";
  it("bloque tout le jour du scrutin jusqu'à 20 h, heure de Paris", () => {
    expect(electionEmbargo(date, new Date("2027-04-18T05:00:00Z")).embargoed).toBe(true);
    expect(electionEmbargo(date, new Date("2027-04-18T17:59:59Z")).embargoed).toBe(true);
  });
  it("se lève pile à 20 h", () => {
    expect(electionEmbargo(date, new Date("2027-04-18T18:00:00Z")).embargoed).toBe(false);
    expect(electionEmbargo(date, new Date("2027-04-18T22:00:00Z")).liftsAt.toISOString()).toBe("2027-04-18T18:00:00.000Z");
  });
  it("la veille, rien à bloquer : le résultat n'existe pas encore, l'appli montre le compte à rebours", () => {
    expect(electionEmbargo(date, new Date("2027-04-17T12:00:00Z")).embargoed).toBe(false);
  });
  it("le lendemain, tout est public", () => {
    expect(electionEmbargo(date, new Date("2027-04-19T08:00:00Z")).embargoed).toBe(false);
  });
});

describe("isElectionDay", () => {
  it("couvre la journée de Paris, pas celle d'UTC", () => {
    expect(isElectionDay("2027-04-18", new Date("2027-04-17T22:30:00Z"))).toBe(true);
    expect(isElectionDay("2027-04-18", new Date("2027-04-18T22:30:00Z"))).toBe(false);
  });
});

describe("élections", () => {
  it("la présidentielle 2027 est annoncée aux bonnes dates, sans jeu de données avant sa publication", () => {
    const first = ELECTIONS.find((e) => e.id === "presidentielle-2027-t1")!;
    const second = ELECTIONS.find((e) => e.id === "presidentielle-2027-t2")!;
    expect([first.date, second.date]).toEqual(["2027-04-18", "2027-05-02"]);
    expect(first.datasetId).toBeNull();
  });
  it("majorité absolue d'un conseil et résultat définitif", () => {
    expect(majoritySeats(53)).toBe(27);
    expect(majoritySeats(33)).toBe(17);
    expect(isComplete([{ seatsCouncil: 0, elected: false }])).toBe(false);
    expect(isComplete([{ seatsCouncil: 28, elected: false }])).toBe(true);
  });
});
