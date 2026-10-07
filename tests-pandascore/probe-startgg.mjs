// Sondage start.gg (J27) : tournois Smash Ultimate récents, taille, coût en requêtes.
// Usage : node --env-file=.env tests-pandascore/probe-startgg.mjs [jours]
// Le token n'est jamais affiché.
const token = process.env.STARTGG_TOKEN;
if (!token) throw new Error("STARTGG_TOKEN absent du .env");
const days = Number(process.argv[2] ?? 60);
let requests = 0;

async function gql(query, variables = {}) {
  requests++;
  const res = await fetch("https://api.start.gg/gql/alpha", {
    method: "POST",
    headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
    body: JSON.stringify({ query, variables }),
  });
  const json = await res.json();
  if (json.errors) throw new Error(`HTTP ${res.status} ${JSON.stringify(json.errors).slice(0, 400)}`);
  return json.data;
}

const after = Math.floor(Date.now() / 1000) - days * 86400;
const before = Math.floor(Date.now() / 1000) + 86400;
const list = `query($page:Int,$after:Timestamp,$before:Timestamp){tournaments(query:{perPage:40,page:$page,sortBy:"startAt desc",filter:{videogameIds:[1386],afterDate:$after,beforeDate:$before}}){pageInfo{totalPages total} nodes{id name slug startAt endAt numAttendees countryCode isOnline events(filter:{videogameId:[1386]}){id name numEntrants state type}}}}`;
const all = [];
for (let page = 1; page <= 12; page++) {
  const d = await gql(list, { page, after, before });
  all.push(...d.tournaments.nodes);
  if (page >= d.tournaments.pageInfo.totalPages) break;
}
console.log(`tournois Smash Ultimate sur ${days} jours : ${all.length}, requêtes ${requests}`);
const top = all.filter((t) => !t.isOnline).sort((a, b) => (b.numAttendees ?? 0) - (a.numAttendees ?? 0)).slice(0, 15);
for (const t of top) {
  const singles = t.events.filter((e) => /singles/i.test(e.name)).sort((a, b) => b.numEntrants - a.numEntrants)[0];
  console.log(`${t.numAttendees}\t${new Date(t.startAt * 1000).toISOString().slice(0, 10)}\t${t.slug}\t${t.name}\t| ${singles ? `${singles.name} (${singles.numEntrants}, état ${singles.state}, id ${singles.id})` : "pas de singles"}`);
}
const dist = [64, 128, 256, 512].map((n) => `>=${n}: ${all.filter((t) => (t.numAttendees ?? 0) >= n).length}`);
console.log("répartition", dist.join("  "));
