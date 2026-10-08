// Essaie l'adaptateur compilé contre les vrais fichiers de data.gouv.fr (`pnpm --filter @news/providers build` avant).
import { ElectionsClient, ElectionsProvider } from "../packages/providers/dist/index.js";

const provider = new ElectionsProvider(new ElectionsClient("Keryx (essai)"));
const comps = await provider.listCompetitions();
console.log(comps.map((c) => `${c.externalId} ${c.status}`).join(" | "));
const t = Date.now();
const events = await provider.listEvents();
console.log(events.length, "résultats en", Date.now() - t, "ms");
for (const e of events.slice(0, 3)) {
  const r = e.result;
  console.log(`\n${e.competitionExternalId} · ${r.territory.name} (${r.territory.department}) · inscrits ${r.registered} · participation ${r.turnoutPct} % · ${r.complete ? "définitif" : "en cours"}`);
  for (const l of r.lists.slice(0, 4)) console.log(`  ${String(l.pctExpressed).padStart(5)} %  ${l.label}  (${l.head ?? "?"}) — ${l.votes} voix, ${l.seatsCouncil} sièges`);
}
