// Passage complet des sets d'un major terminé, pour mesurer le coût réel (J27).
import { StartGgClient, StartGgProvider } from "../packages/providers/dist/index.js";
const client = new StartGgClient(process.env.STARTGG_TOKEN);
let n = 0; const q = client.query.bind(client); client.query = (...a) => (n++, q(...a));
const provider = new StartGgProvider(client);
provider.tracked = [{ tournament: { id: 1, name: "Genesis X3", slug: "x", startAt: 1, endAt: 2 }, eventId: 1424385, phases: [] }];
console.time("sets");
const events = await provider.fetchSets(1424385);
console.timeEnd("sets");
const by = {}; for (const e of events) by[e.competitionExternalId] = (by[e.competitionExternalId] ?? 0) + 1;
console.log("requêtes", n, "sets", events.length, by);
console.log(JSON.stringify(events.find((e) => e.name === "Grand Final"), (k, v) => (k === "raw" ? undefined : v)).slice(0, 900));
