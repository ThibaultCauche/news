// Régénère les fixtures réduites de Jolpica-F1 (tests-pandascore/samples-jolpica/) : `node tests-pandascore/capture-jolpica.mjs`.
import { writeFileSync } from "node:fs";
const B = "https://api.jolpi.ca/ergast/f1/2026";
const out = new URL("./samples-jolpica/", import.meta.url);
const get = async (path) => {
  const res = await fetch(`${B}${path}.json`);
  if (!res.ok) throw new Error(`${path} → ${res.status}`);
  await new Promise((r) => setTimeout(r, 400));
  return (await res.json()).MRData;
};
const save = (name, data) => writeFileSync(new URL(name, out), JSON.stringify(data, null, 1));

const schedule = await get("");
// Courses 1 (week-end classique), 2 (sprint) et la dernière : de quoi tester les trois cas.
const races = schedule.RaceTable.Races;
schedule.RaceTable.Races = [races[0], races[1], races[races.length - 1]];
save("schedule.json", schedule);

const take = (data, key, n) => { data.RaceTable.Races.forEach((r) => (r[key] = r[key].slice(0, n))); return data; };
save("results-1.json", take(await get("/1/results"), "Results", 4));
save("qualifying-1.json", take(await get("/1/qualifying"), "QualifyingResults", 4));
save("sprint-2.json", take(await get("/2/sprint"), "SprintResults", 3));

const drivers = await get("/driverstandings");
drivers.StandingsTable.StandingsLists[0].DriverStandings.length = 3;
save("driver-standings.json", drivers);
const teams = await get("/constructorstandings");
teams.StandingsTable.StandingsLists[0].ConstructorStandings.length = 3;
save("constructor-standings.json", teams);
