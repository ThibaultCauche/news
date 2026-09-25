// Couverture multi-jeux de PandaScore (plan gratuit).
// Usage : node test-multijeux.mjs   (même .env que test-pandascore.mjs)
// Le token n'est jamais affiché ni écrit. ~40 appels sur les 1 000/h.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = dirname(fileURLToPath(import.meta.url));
const BASE = "https://api.pandascore.co";
const OUT = join(DIR, "samples-multijeux");

const envPath = join(DIR, ".env");
if (!existsSync(envPath)) { console.error("❌ .env introuvable."); process.exit(1); }
const line = readFileSync(envPath, "utf8").split(/\r?\n/).find(l => l.startsWith("PANDASCORE_TOKEN="));
const TOKEN = line ? line.slice(17).trim().replace(/^["']|["']$/g, "") : "";
if (!TOKEN) { console.error("❌ PANDASCORE_TOKEN vide."); process.exit(1); }
const scrub = s => String(s).split(TOKEN).join("***");

let calls = 0, rate = null;
async function get(path) {
  calls++;
  try {
    const res = await fetch(BASE + path, { headers: { Authorization: `Bearer ${TOKEN}`, Accept: "application/json" } });
    for (const [k, v] of res.headers) if (/rate/i.test(k)) rate = { ...(rate || {}), [k]: v };
    const body = res.status === 200 ? await res.json() : null;
    return { status: res.status, body };
  } catch (e) { return { status: 0, body: null, err: scrub(e.message) }; }
}
// Récupère plusieurs pages d'une liste (max `pages` pages de 100).
async function getAll(path, pages = 2) {
  let all = [], status = 200;
  for (let p = 1; p <= pages; p++) {
    const r = await get(`${path}${path.includes("?") ? "&" : "?"}per_page=100&page=${p}`);
    status = r.status;
    if (r.status !== 200 || !Array.isArray(r.body)) break;
    all = all.concat(r.body);
    if (r.body.length < 100) break;
  }
  return { status, list: all };
}
const icon = s => s === 200 ? "✅" : s === 403 ? "🔒" : s === 404 ? "❓" : s === 429 ? "⏳" : `⚠️${s}`;

mkdirSync(OUT, { recursive: true });
console.log("Couverture multi-jeux PandaScore\n");

// 1. Jeux disponibles
const vg = await get("/videogames?per_page=100");
if (vg.status === 401) { console.error("Token refusé."); process.exit(1); }
const games = (vg.body || []).map(g => ({ id: g.id, name: g.name, slug: g.slug }));
writeFileSync(join(OUT, "videogames.json"), JSON.stringify(vg.body, null, 2));
console.log(`${icon(vg.status)} ${games.length} jeux listés`);

// 2. Matchs globaux (en cours, à venir, passés récents) regroupés par jeu
const running = await getAll("/matches/running", 1);
const upcoming = await getAll("/matches/upcoming?sort=begin_at", 3);
const past = await getAll("/matches/past?sort=-end_at", 3);
const runningT = await getAll("/tournaments/running", 3);
console.log(`${icon(upcoming.status)} matchs : ${running.list.length} en cours, ${upcoming.list.length} à venir, ${past.list.length} passés récents ; ${runningT.list.length} tournois en cours`);

const by = (list, key = m => m.videogame?.slug) => list.reduce((acc, x) => { const k = key(x); (acc[k] ||= []).push(x); return acc; }, {});
const runBy = by(running.list), upBy = by(upcoming.list), pastBy = by(past.list), tBy = by(runningT.list);

// 3. Par jeu : accès aux tournois + un bracket si un tournoi est en cours
const rows = [];
for (const g of games) {
  const t = await get(`/videogames/${g.id}/tournaments?sort=-begin_at&per_page=50`);
  const list = Array.isArray(t.body) ? t.body : [];
  const tiers = list.reduce((a, x) => (a[(x.tier || "?").toUpperCase()] = (a[(x.tier || "?").toUpperCase()] || 0) + 1, a), {});
  const last = list[0];
  const live = tBy[g.slug] || [];
  const pick = live.find(x => x.has_bracket && ["s", "a"].includes(x.tier)) || live.find(x => x.has_bracket);
  let bracket = "—";
  if (pick) {
    const b = await get(`/tournaments/${pick.id}/brackets`);
    bracket = b.status === 200 ? `✅ ${b.body.length} matchs (${b.body.filter(m => m.previous_matches?.length).length} liés)` : icon(b.status);
  }
  const sampleMatch = (pastBy[g.slug] || [])[0];
  const mapWinners = sampleMatch ? `${(sampleMatch.games || []).filter(x => x.winner?.id != null).length}/${(sampleMatch.games || []).length}` : "—";
  rows.push({
    jeu: g.name, slug: g.slug, acces: icon(t.status),
    dernier: last ? `${last.league?.name ?? ""} ${last.serie?.full_name ?? ""} — ${last.name} (${(last.begin_at || "").slice(0, 10)})` : "—",
    tiers: Object.entries(tiers).sort().map(([k, v]) => `${k}:${v}`).join(" ") || "—",
    enCours: (runBy[g.slug] || []).length, aVenir: (upBy[g.slug] || []).length, passes: (pastBy[g.slug] || []).length,
    tournoisEnCours: live.length, bracket, mapWinners,
  });
  console.log(`${icon(t.status)} ${g.name.padEnd(28)} à venir ${String((upBy[g.slug] || []).length).padStart(3)} · en cours ${String(live.length).padStart(2)} tournois · bracket ${bracket}`);
}

// 4. Rapport
const now = new Date().toLocaleString("fr-FR", { timeZone: "Europe/Paris" });
const md = [
  `# Couverture multi-jeux PandaScore (plan gratuit)`, ``,
  `Généré le ${now} — ${calls} appels. Échantillons dans \`samples-multijeux/\`.`, ``,
  `Les colonnes « à venir » et « passés » comptent les matchs présents dans les ${upcoming.list.length} prochains et ${past.list.length} derniers matchs tous jeux confondus : c'est une indication d'activité, pas un total.`, ``,
  `| Jeu | Slug | Accès tournois | Tournoi le plus récent | Tiers (50 derniers) | Matchs en cours | À venir | Passés | Tournois en cours | Bracket testé | Gagnants de carte renseignés |`,
  `|---|---|---|---|---|---|---|---|---|---|---|`,
  ...rows.map(r => `| ${r.jeu} | \`${r.slug}\` | ${r.acces} | ${r.dernier} | ${r.tiers} | ${r.enCours} | ${r.aVenir} | ${r.passes} | ${r.tournoisEnCours} | ${r.bracket} | ${r.mapWinners} |`),
  ``, `## Quota`, ``,
  rate ? Object.entries(rate).map(([k, v]) => `- \`${k}\` : ${v}`).join("\n") : "- aucun en-tête", ``,
].join("\n");
writeFileSync(join(DIR, "rapport-multijeux.md"), scrub(md));
console.log(`\n📄 Rapport : rapport-multijeux.md (${calls} appels)`);
