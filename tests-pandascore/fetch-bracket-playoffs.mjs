// Récupère le bracket + classement d'un tournoi précis (playoffs, double élim)
// pour compléter le fixture GSL déjà présent dans samples/.
// Usage : node fetch-bracket-playoffs.mjs
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const DIR = dirname(fileURLToPath(import.meta.url));
const BASE = "https://api.pandascore.co";
const SAMPLES = join(DIR, "samples");

const envPath = join(DIR, ".env");
if (!existsSync(envPath)) { console.error("❌ .env introuvable"); process.exit(1); }
const line = readFileSync(envPath, "utf8").split(/\r?\n/).find(l => l.startsWith("PANDASCORE_TOKEN="));
const TOKEN = line ? line.slice("PANDASCORE_TOKEN=".length).trim().replace(/^["']|["']$/g, "") : "";
if (!TOKEN) { console.error("❌ PANDASCORE_TOKEN vide"); process.exit(1); }

async function get(path) {
  const res = await fetch(BASE + path, { headers: { Authorization: `Bearer ${TOKEN}`, Accept: "application/json" } });
  const text = await res.text();
  let body; try { body = JSON.parse(text); } catch { body = text.slice(0, 300); }
  console.log(res.status, path, Array.isArray(body) ? `${body.length} élément(s)` : "");
  if (res.status !== 200) return null;
  return body;
}

const tierS = await get("/valorant/tournaments?filter[tier]=s&sort=-begin_at&per_page=50");
const running = await get("/valorant/tournaments/running?per_page=50");
const pool = [...(tierS || []), ...(running || [])];

// On cherche un tournoi "Playoffs" de Champions avec has_bracket=true et plus de matchs qu'un simple groupe.
const candidates = pool.filter(t => /champions/i.test(`${t.name} ${t.serie?.full_name ?? ""}`) && t.has_bracket);
console.log("Candidats trouvés :", candidates.map(t => `${t.id} — ${t.name} (${t.serie?.full_name})`));

const pick = candidates.find(t => /playoff/i.test(t.name)) || candidates[0];
if (!pick) { console.error("❌ Aucun tournoi playoffs trouvé"); process.exit(1); }
console.log("Choisi :", pick.id, pick.name);

const brackets = await get(`/tournaments/${pick.id}/brackets`);
const standings = await get(`/tournaments/${pick.id}/standings`);

if (brackets) writeFileSync(join(SAMPLES, "brackets-playoffs.json"), JSON.stringify(brackets, null, 2));
if (standings) writeFileSync(join(SAMPLES, "classement-playoffs.json"), JSON.stringify(standings, null, 2));
console.log(`\nBrackets : ${brackets?.length ?? 0} match(s) avec previous_matches : ${brackets?.filter(m => m.previous_matches?.length).length ?? 0}`);
