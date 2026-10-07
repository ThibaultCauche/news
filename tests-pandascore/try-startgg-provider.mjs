// Essai de l'adaptateur compilé contre la vraie API (J27). Usage : node --env-file=.env tests-pandascore/try-startgg-provider.mjs
import { StartGgClient, StartGgProvider } from "../packages/providers/dist/index.js";
const provider = new StartGgProvider(new StartGgClient(process.env.STARTGG_TOKEN));
console.time("catalogue");
const comps = await provider.listCompetitions();
console.timeEnd("catalogue");
for (const c of comps) console.log(c.kind.padEnd(10), c.externalId.padEnd(18), c.status, c.hasBracket ? "bracket" : "", c.name, c.startsAt?.toISOString().slice(0, 10) ?? "");
const s = await provider.getStructure("phase:2195696");
console.log("Top 8 Genesis X3 :", s.format, s.links.length, "liens", JSON.stringify(s.links.slice(0, 3)));
