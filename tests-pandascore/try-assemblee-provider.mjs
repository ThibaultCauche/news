// Essaie l'adaptateur compilé contre les vraies archives de l'Assemblée (`pnpm --filter @news/providers build` avant).
import { AssembleeClient, AssembleeProvider } from "../packages/providers/dist/index.js";

const provider = new AssembleeProvider(new AssembleeClient("Keryx"));
const t = Date.now();
const competitions = await provider.listCompetitions();
const events = await provider.listEvents();
console.log(`${competitions.length} compétitions, ${events.length} votes, ${Date.now() - t} ms`);
const laws = competitions.filter((c) => c.kind === "law");
const byStatus = {};
for (const l of laws) byStatus[l.structure.process.status] = (byStatus[l.structure.process.status] ?? 0) + 1;
console.log(byStatus, "avec vote rattaché:", laws.filter((l) => l.structure.process.steps.some((s) => s.vote)).length);
const show = (l) => {
  console.log("\n" + l.name, "|", l.structure.lawType, "|", JSON.stringify(l.structure.author), l.structure.lawNumber ?? "");
  for (const s of l.structure.process.steps) console.log(`  ${s.state.padEnd(7)} ${s.label} ${s.date ?? ""} ${s.detail ?? ""} ${s.vote ? `[${s.vote.pour}/${s.vote.contre}]` : ""}`);
};
show(laws.find((l) => l.structure.process.status === "promulgated" && l.structure.process.steps.some((s) => s.vote)));
show(laws.find((l) => l.structure.process.status === "rejected") ?? laws[0]);
show(laws.find((l) => l.structure.process.status === "in_progress" && l.structure.process.steps.some((s) => s.vote)));
const e = events[0];
console.log("\n", e.name, e.startsAt, e.participants.length, "groupes", JSON.stringify(e.result.groups.slice(0, 2)));
