// Essai de l'adaptateur compilé contre la vraie API (J28). Usage : node tests-pandascore/try-jolpica-provider.mjs
import { JolpicaClient, JolpicaProvider } from "../packages/providers/dist/index.js";
const provider = new JolpicaProvider(new JolpicaClient("Keryx (essai)"));
console.time("catalogue");
const comps = await provider.listCompetitions();
console.timeEnd("catalogue");
console.log(comps.length, "compétitions", comps.slice(0, 3).map((c) => `${c.kind} ${c.externalId} ${c.status}`));
console.time("événements");
const events = await provider.listEvents();
console.timeEnd("événements");
const byStatus = {};
for (const e of events) byStatus[e.status] = (byStatus[e.status] ?? 0) + 1;
console.log(events.length, "sessions", byStatus);
const race = events.find((e) => e.kind === "session" && e.name === "Course" && e.participants.length);
console.log(race.competitionExternalId, race.participants.length, "classés, vainqueur", race.participants[0].entity.name);
const standings = await provider.listStandings();
console.log(standings.length, "lignes de classement", standings.filter((s) => s.entity.kind === "driver").slice(0, 3).map((s) => `${s.rank}. ${s.entity.name} ${s.points}`));
