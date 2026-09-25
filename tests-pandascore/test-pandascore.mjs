// Test des endpoints PandaScore (plan gratuit) pour Valorant.
// Usage : node test-pandascore.mjs   (Node 18+, aucune dépendance)
// Le token est lu dans .env et n'est JAMAIS affiché ni écrit dans les fichiers produits.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = dirname(fileURLToPath(import.meta.url));
const BASE = "https://api.pandascore.co";
const SAMPLES = join(DIR, "samples");

// --- Token -------------------------------------------------------------
function loadToken() {
  const envPath = join(DIR, ".env");
  if (!existsSync(envPath)) {
    console.error("❌ Fichier .env introuvable. Copie .env.example en .env et mets ton token dedans.");
    process.exit(1);
  }
  const line = readFileSync(envPath, "utf8").split(/\r?\n/).find(l => l.startsWith("PANDASCORE_TOKEN="));
  const token = line ? line.slice("PANDASCORE_TOKEN=".length).trim().replace(/^["']|["']$/g, "") : "";
  if (!token) {
    console.error("❌ PANDASCORE_TOKEN est vide dans .env.");
    process.exit(1);
  }
  return token;
}
const TOKEN = loadToken();
const scrub = s => String(s).split(TOKEN).join("***");

// --- Appels ------------------------------------------------------------
const results = [];
let lastRate = null;

async function call(label, path, { expect = "gratuit ?", note = "" } = {}) {
  const url = BASE + path;
  const t0 = Date.now();
  let status = 0, body = null, err = null;
  try {
    const res = await fetch(url, { headers: { Authorization: `Bearer ${TOKEN}`, Accept: "application/json" } });
    status = res.status;
    for (const [k, v] of res.headers) if (/rate/i.test(k)) lastRate = { ...(lastRate || {}), [k]: v };
    const text = await res.text();
    try { body = JSON.parse(text); } catch { body = text.slice(0, 300); }
  } catch (e) { err = scrub(e.message); }
  const ms = Date.now() - t0;
  const verdict = err ? "⚠️ erreur réseau"
    : status === 200 ? "✅ inclus"
    : status === 401 ? "❌ token invalide"
    : status === 403 ? "🔒 non inclus (403)"
    : status === 404 ? "❓ introuvable (404)"
    : status === 429 ? "⏳ limite atteinte (429)"
    : `⚠️ HTTP ${status}`;
  const count = Array.isArray(body) ? body.length : body && typeof body === "object" ? 1 : 0;
  results.push({ label, path, status, verdict, ms, count, expect, note, err });
  console.log(`${verdict.padEnd(22)} ${label}  (${path}, ${ms} ms)`);
  if (status === 200 && body) {
    const file = label.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "") + ".json";
    writeFileSync(join(SAMPLES, file), JSON.stringify(body, null, 2));
  }
  return status === 200 ? body : null;
}

// --- Analyses ----------------------------------------------------------
const findings = [];
const add = (q, a) => { findings.push({ q, a }); };

function analyseMatches(label, matches) {
  if (!Array.isArray(matches) || !matches.length) { add(`${label} : contenu`, "aucun match renvoyé"); return; }
  const m = matches[0];
  const games = Array.isArray(m.games) ? m.games : [];
  const gamesWithWinner = games.filter(g => g.winner && g.winner.id != null).length;
  const hasRoundScore = games.some(g => g.results || g.teams || g.rounds);
  add(`${label} : exemple`, `« ${m.name} » — statut ${m.status}, BO${m.number_of_games ?? "?"}, tournoi « ${m.tournament?.name ?? "?"} » (${m.serie?.full_name ?? m.serie?.name ?? "?"})`);
  add(`${label} : score de la série (results)`, Array.isArray(m.results) && m.results.length ? m.results.map(r => r.score).join(" – ") : "absent");
  add(`${label} : détail par carte (games)`, `${games.length} carte(s), ${gamesWithWinner} avec un gagnant renseigné${hasRoundScore ? ", avec des champs de score par carte" : ", sans score par carte (seulement le gagnant)"}`);
  add(`${label} : liens de stream`, Array.isArray(m.streams_list) && m.streams_list.length ? `${m.streams_list.length} lien(s) (ex. ${m.streams_list[0].language} ${m.streams_list[0].raw_url ?? ""})` : "aucun");
  add(`${label} : champs disponibles`, Object.keys(m).sort().join(", "));
}

// --- Scénario ----------------------------------------------------------
mkdirSync(SAMPLES, { recursive: true });
console.log("Tests PandaScore — Valorant\n");

const leagues = await call("Ligues Valorant", "/valorant/leagues?per_page=50");
if (results[0].status === 401) { console.error("\nToken refusé : vérifie ton .env."); process.exit(1); }

await call("Séries en cours", "/valorant/series/running");
const running = await call("Tournois en cours", "/valorant/tournaments/running?per_page=50");
const tierS = await call("Tournois tier S récents", "/valorant/tournaments?filter[tier]=s&sort=-begin_at&per_page=20");

// Choix du tournoi à inspecter : un tournoi en cours de tier S/A (idéalement Champions), sinon le tier S le plus récent.
const pool = [...(running || []), ...(tierS || [])];
const pick = pool.find(t => /champions/i.test(`${t.name} ${t.league?.name} ${t.serie?.full_name}`) && ["s", "a"].includes(t.tier))
  || pool.find(t => ["s", "a"].includes(t.tier)) || pool[0];

if (pick) {
  add("Tournoi inspecté", `« ${pick.league?.name ?? ""} ${pick.serie?.full_name ?? ""} — ${pick.name} » (id ${pick.id}, tier ${pick.tier?.toUpperCase()}, type ${pick.type ?? "?"}, has_bracket=${pick.has_bracket})`);
  await call("Détail du tournoi", `/tournaments/${pick.id}`);
  const brackets = await call("Brackets du tournoi", `/tournaments/${pick.id}/brackets`, { note: "clé pour l'arbre" });
  if (Array.isArray(brackets)) {
    const withPrev = brackets.filter(m => Array.isArray(m.previous_matches) && m.previous_matches.length).length;
    const types = [...new Set(brackets.flatMap(m => (m.previous_matches || []).map(p => p.type)))];
    add("Brackets : liens entre matchs", `${brackets.length} match(s), ${withPrev} avec previous_matches (types : ${types.join(", ") || "aucun"})`);
  }
  const standings = await call("Classement du tournoi", `/tournaments/${pick.id}/standings`, { note: "clé pour les poules" });
  if (Array.isArray(standings) && standings[0]) add("Classement : champs", Object.keys(standings[0]).sort().join(", "));
  await call("Rosters du tournoi", `/tournaments/${pick.id}/rosters`);
} else {
  add("Tournoi inspecté", "aucun tournoi tier S/A trouvé — brackets et classement non testés");
}

const live = await call("Matchs en cours", "/valorant/matches/running");
if (live?.length) analyseMatches("Match en cours", live);
const upcoming = await call("Matchs à venir", "/valorant/matches/upcoming?per_page=20&sort=begin_at");
if (upcoming?.length) add("Prochain match", `« ${upcoming[0].name} » le ${upcoming[0].scheduled_at ?? upcoming[0].begin_at}`);
const past = await call("Matchs terminés", "/valorant/matches/past?per_page=20&filter[finished]=true");
if (past?.length) analyseMatches("Match terminé", past);

await call("Équipes", "/valorant/teams?per_page=5");
await call("Joueurs", "/valorant/players?per_page=5");
if (past?.[0]) await call("Stats joueurs d'un match (attendu payant)", `/valorant/matches/${past[0].id}/players/stats`, { expect: "payant" });

// --- Rapport -----------------------------------------------------------
const now = new Date().toLocaleString("fr-FR", { timeZone: "Europe/Paris" });
const md = [
  `# Rapport tests PandaScore — Valorant`,
  ``,
  `Généré le ${now}. Réponses brutes dans \`samples/\` (le token n'y figure pas).`,
  ``,
  `## Endpoints`,
  ``,
  `| Résultat | Test | Endpoint | Éléments | Temps |`,
  `|---|---|---|---|---|`,
  ...results.map(r => `| ${r.verdict} | ${r.label}${r.note ? ` _(${r.note})_` : ""} | \`${r.path}\` | ${r.count} | ${r.ms} ms |`),
  ``,
  `## Observations`,
  ``,
  ...findings.map(f => `- **${f.q}** : ${f.a}`),
  ``,
  `## Quota`,
  ``,
  lastRate ? Object.entries(lastRate).map(([k, v]) => `- \`${k}\` : ${v}`).join("\n") : "- Aucun en-tête de quota renvoyé.",
  ``,
].join("\n");

writeFileSync(join(DIR, "rapport-pandascore.md"), scrub(md));
console.log(`\n📄 Rapport écrit : rapport-pandascore.md (${results.length} appels)`);
