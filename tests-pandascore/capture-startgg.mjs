// Fixtures réduites (J27) : le Top 8 de Genesis X3 uniquement (10 sets, tags de joueur), pas le tournoi entier.
import { writeFileSync } from "node:fs";
import { StartGgClient } from "../packages/providers/dist/startgg/client.js";
import { EVENT_SETS_QUERY, PHASE_CHARACTERS_QUERY, PHASE_LINKS_QUERY } from "../packages/providers/dist/startgg/queries.js";
const client = new StartGgClient(process.env.STARTGG_TOKEN);
const PHASE = 2195696;
const sets = [];
for (let page = 1; ; page++) {
  const d = await client.query(EVENT_SETS_QUERY, { id: 1424385, page, updatedAfter: null });
  sets.push(...d.event.sets.nodes.filter((s) => s.phaseGroup?.phase?.id === PHASE));
  if (page >= d.event.sets.pageInfo.totalPages) break;
}
// Personnages par manche (phase à arbre), comme le fait l'adaptateur.
const chars = await client.query(PHASE_CHARACTERS_QUERY, { id: PHASE, page: 1, updatedAfter: null });
for (const node of chars.phase.sets.nodes) {
  const set = sets.find((s) => String(s.id) === String(node.id));
  if (set && node.games) set.games = node.games;
}
const links = await client.query(PHASE_LINKS_QUERY, { id: PHASE, page: 1 });
writeFileSync("tests-pandascore/samples-startgg/genesis-x3-top8-sets.json", JSON.stringify(sets, null, 1));
writeFileSync("tests-pandascore/samples-startgg/genesis-x3-top8-links.json", JSON.stringify(links.phase, null, 1));
console.log(sets.length, "sets", links.phase.sets.nodes.length, "liens");
