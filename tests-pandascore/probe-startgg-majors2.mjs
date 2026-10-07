// Les plus gros tournois « featured » de l'année (J27).
const gql = async (query, variables) => {
  const r = await fetch("https://api.start.gg/gql/alpha", { method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${process.env.STARTGG_TOKEN}` }, body: JSON.stringify({ query, variables }) });
  const j = await r.json();
  if (j.errors) throw new Error(JSON.stringify(j.errors).slice(0, 300));
  return j.data.tournaments;
};
const q = `query($after:Timestamp,$before:Timestamp,$page:Int){tournaments(query:{perPage:40,page:$page,sortBy:"startAt desc",filter:{videogameIds:[1386],isFeatured:true,afterDate:$after,beforeDate:$before}}){pageInfo{totalPages} nodes{id name slug startAt endAt numAttendees isOnline events(filter:{videogameId:[1386]}){id name numEntrants state}}}}`;
const now = Math.floor(Date.now() / 1000);
const all = [];
for (let page = 1; page <= 10; page++) {
  const t = await gql(q, { after: now - 400 * 86400, before: now + 120 * 86400, page });
  all.push(...t.nodes);
  if (page >= t.pageInfo.totalPages) break;
}
console.log("featured :", all.length);
for (const n of all.sort((a, b) => (b.numAttendees ?? 0) - (a.numAttendees ?? 0)).slice(0, 16)) {
  const e = n.events.sort((a, b) => b.numEntrants - a.numEntrants)[0];
  console.log(`${n.numAttendees}\t${new Date(n.startAt * 1000).toISOString().slice(0, 10)}\t${n.slug.replace("tournament/", "")}\t${n.name}\t| ${e?.name} ${e?.numEntrants} ${e?.state} id=${e?.id}`);
}
