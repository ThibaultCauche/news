import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  normalizeConstructorStandings,
  normalizeDriverStandings,
  normalizeGrandPrix,
  normalizeRace,
  normalizeSeason,
  parseSessionRef,
  sessionsOf,
} from "./normalize";
import { RawRace } from "./types";

const dir = join(__dirname, "../../../../tests-pandascore/samples-jolpica");
const load = (name: string) => JSON.parse(readFileSync(join(dir, name), "utf8")).RaceTable ?? JSON.parse(readFileSync(join(dir, name), "utf8"));
const schedule: RawRace[] = load("schedule.json").Races;
const [australia, china] = schedule;
const standings = (name: string) => JSON.parse(readFileSync(join(dir, name), "utf8")).StandingsTable.StandingsLists[0];

describe("Jolpica-F1", () => {
  it("liste les sessions du week-end dans l'ordre, sprint compris", () => {
    expect(sessionsOf(australia).map((s) => s.kind)).toEqual(["fp1", "fp2", "fp3", "qualifying", "race"]);
    expect(sessionsOf(china).map((s) => s.kind)).toEqual(["fp1", "sprint_qualifying", "sprint", "qualifying", "race"]);
  });

  it("construit la saison et le Grand Prix", () => {
    const now = new Date("2026-12-31T12:00:00Z");
    expect(normalizeSeason("2026", schedule, now)).toMatchObject({ externalId: "season:2026", parentExternalId: "league:f1", name: "Formule 1 2026", game: "formula-1", status: "finished" });
    expect(normalizeGrandPrix(australia, now)).toMatchObject({ externalId: "race:2026-1", parentExternalId: "season:2026", name: "Australian Grand Prix", status: "finished" });
    expect(normalizeGrandPrix(australia, new Date("2026-01-01")).status).toBe("scheduled");
  });

  it("classe la course : premier gagnant, position en score, tableau d'arrivée dans result", () => {
    const results = load("results-1.json").Races[0].Results;
    const race = normalizeRace(australia, { results }, new Date("2026-10-08")).find((e) => e.externalId === "2026-1-race")!;
    expect(race).toMatchObject({ kind: "session", name: "Course", status: "finished", competitionExternalId: "race:2026-1" });
    expect(race.participants.map((p) => [p.entity.shortName, p.score, p.isWinner])).toEqual([
      ["RUS", 1, true],
      ["ANT", 2, false],
      ["LEC", 3, false],
      ["HAM", 4, false],
    ]);
    expect(race.participants[0].entity).toMatchObject({ externalId: "driver:russell", kind: "driver", name: "George Russell" });
    expect((race.result as { rows: { points: number; constructor: string }[] }).rows[0]).toMatchObject({ points: 25, constructor: "Mercedes" });
  });

  it("garde une session sans classement : à venir, en cours puis terminée selon l'horloge", () => {
    const status = (now: string) => normalizeRace(australia, {}, new Date(now)).find((e) => e.externalId === "2026-1-race")!.status;
    expect(status("2026-03-01T00:00:00Z")).toBe("scheduled");
    expect(status("2026-03-08T05:00:00Z")).toBe("live");
    expect(status("2026-03-09T00:00:00Z")).toBe("finished");
    expect(normalizeRace(australia, {}, new Date("2026-03-01")).every((e) => e.participants.length === 0)).toBe(true);
  });

  it("lit le sprint et les qualifications", () => {
    const sprint = load("sprint-2.json").Races[0].SprintResults;
    const qualifying = load("qualifying-1.json").Races[0].QualifyingResults;
    expect(normalizeRace(china, { sprint }, new Date("2026-10-08")).find((e) => e.externalId === "2026-2-sprint")!.participants).toHaveLength(3);
    const q = normalizeRace(australia, { qualifying }, new Date("2026-10-08")).find((e) => e.externalId === "2026-1-qualifying")!;
    expect(q.participants[0].score).toBe(1);
    expect((q.result as { rows: { q3: string | null }[] }).rows[0].q3).toBeTruthy();
  });

  it("reprend les classements pilotes et constructeurs tels que la source les donne", () => {
    const drivers = normalizeDriverStandings("2026", standings("driver-standings.json").DriverStandings);
    expect(drivers[0]).toMatchObject({ competitionExternalId: "season:2026", rank: 1, entity: { kind: "driver", externalId: "driver:antonelli" } });
    expect(drivers[0].points).toBeGreaterThan(drivers[1].points);
    const teams = normalizeConstructorStandings("2026", standings("constructor-standings.json").ConstructorStandings);
    expect(teams[0]).toMatchObject({ rank: 1, entity: { kind: "constructor", externalId: "constructor:mercedes", name: "Mercedes" } });
  });

  it("retrouve week-end et session depuis un identifiant", () => {
    expect(parseSessionRef("2026-2-sprint_qualifying")).toEqual({ season: "2026", round: "2", kind: "sprint_qualifying" });
  });
});
