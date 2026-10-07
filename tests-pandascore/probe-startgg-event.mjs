// Structure d'un événement start.gg : phases, groupes, sets (J27). Usage : node --env-file=.env ... <eventId>
const id = Number(process.argv[2] ?? 1424385);
let n = 0;
const gql = async (query, variables) => {
  n++;
  const r = await fetch("https://api.start.gg/gql/alpha", { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${process.env.STARTGG_TOKEN}` }, body: JSON.stringify({ query, variables }) });
  const j = await r.json();
  if (j.errors) throw new Error(JSON.stringify(j.errors).slice(0, 300));
  return j.data;
};
const head = await gql(`query($id:ID){event(id:$id){id name numEntrants state type startAt tournament{name} phases{id name bracketType numSeeds groupCount state phaseOrder} phaseGroups{id displayIdentifier bracketType phase{id name}}}}`, { id });
const e = head.event;
console.log(e.tournament.name, "-", e.name, e.numEntrants, e.state, "phases:");
for (const p of e.phases) console.log(`  #${p.phaseOrder} ${p.id} ${p.name} ${p.bracketType} seeds=${p.numSeeds} groups=${p.groupCount} ${p.state}`);
const biggest = e.phases.sort((a, b) => b.numSeeds - a.numSeeds);
// Une phase finale : prendre celle qui s'appelle top 8 / bracket, sinon la dernière.
const last = e.phases.find((p) => /top 8/i.test(p.name)) ?? e.phases.at(-1);
console.log("phase finale :", last.id, last.name);
const sets = await gql(`query($id:ID,$page:Int){phase(id:$id){phaseGroups(query:{perPage:5}){nodes{id displayIdentifier bracketType numRounds sets(page:$page,perPage:12,sortType:STANDARD){pageInfo{total} nodes{id identifier fullRoundText round state totalGames winnerId displayScore startedAt completedAt wPlacement lPlacement setGamesType slots{id prereqType prereqId entrant{id name participants{gamerTag prefix user{slug}}} standing{placement stats{score{value}}}}}}}}}}`, { id: last.id, page: 1 });
for (const g of sets.phase.phaseGroups.nodes) {
  console.log(`groupe ${g.id} ${g.displayIdentifier} ${g.bracketType} rondes=${g.numRounds} sets=${g.sets.pageInfo.total}`);
  for (const s of g.sets.nodes.slice(0, 4)) console.log("  ", s.fullRoundText, s.state, s.displayScore, "| prereq:", s.slots.map((x) => `${x.prereqType}:${x.prereqId}`).join(" "), "| manches:", s.games?.map((x) => x.selections?.length).join(","));
}
console.log("requêtes:", n);
console.log(JSON.stringify(sets.phase.phaseGroups.nodes[0].sets.nodes[0], null, 1).slice(0, 1800));
