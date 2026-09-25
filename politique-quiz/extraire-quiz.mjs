// Extrait de l'open data de l'Assemblée nationale (17e législature) des scrutins
// sur des sujets marquants, pour le jeu « Qui a voté ? ».
// Usage : node extraire-quiz.mjs   (Node 18+, Windows 10+ : utilise tar.exe pour dézipper)
// Sortie : candidats.json + candidats.md. Aucune donnée personnelle, aucun token.

import { writeFileSync, mkdirSync, existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";

const DIR = dirname(fileURLToPath(import.meta.url));
const DATA = join(DIR, "data");
const R = "https://data.assemblee-nationale.fr/static/openData/repository/17";
const SOURCES = {
  scrutins: [`${R}/loi/scrutins/Scrutins.json.zip`],
  amo: [
    `${R}/amo/deputes_actifs_mandats_actifs_organes/AMO10_deputes_actifs_mandats_actifs_organes.json.zip`,
    `${R}/amo/tous_acteurs_mandats_organes_xi_legislature/AMO30_tous_acteurs_tous_mandats_tous_organes_historique.json.zip`,
  ],
};

// ---------- Thèmes (texte sans accents, en minuscules) ----------
const THEMES = {
  "Carburant & énergie": /carburant|essence|gazole|diesel|prix de l.energie|electricite|accise|ticpe|energie/,
  "Environnement & climat": /environnement|climat|pesticide|glyphosate|biodiversite|zones? a faibles? emissions|\bzfe\b|pollution|artificialisation|\beau\b/,
  "Agriculture": /agricol|agricult|eleveur|elevage|mercosur|loi duplomb/,
  "Guerre & défense": /ukraine|defense|militaire|armee|guerre|israel|gaza|palestin|otan|programmation militaire/,
  "Police & sécurité": /police|securite interieure|forces de l.ordre|gendarm|narcotrafic|delinquan|videoprotection|videosurveillance|penitentiaire|prison|terroris/,
  "Retraites": /retraite/,
  "Immigration": /immigration|etrangers|asile|titre de sejour|nationalite/,
  "Fin de vie": /fin de vie|aide a mourir|soins palliatifs/,
  "Impôts & budget": /loi de finances|financement de la securite sociale|impot|\btva\b|taxe/,
  "Censure du gouvernement": /motion de censure/,
  "Logement": /logement|loyer|locati/,
  "Santé": /hopital|medecin|sante|deserts? medicaux/,
};

const norm = s => String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const arr = x => (x == null ? [] : Array.isArray(x) ? x : [x]);
const txt = x => (x && typeof x === "object" && "#text" in x ? x["#text"] : x);

// ---------- Téléchargement + extraction ----------
async function download(urls, name) {
  const zip = join(DATA, `${name}.zip`), out = join(DATA, name);
  if (existsSync(out) && readdirSync(out).length) { console.log(`↺ ${name} déjà extrait`); return out; }
  for (const url of urls) {
    process.stdout.write(`⬇ ${name} … `);
    const res = await fetch(url).catch(e => ({ ok: false, status: e.message }));
    if (!res.ok) { console.log(`échec (${res.status})`); continue; }
    writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
    console.log(`${(statSync(zip).size / 1e6).toFixed(1)} Mo`);
    mkdirSync(out, { recursive: true });
    try { execSync(`tar -xf "${zip}" -C "${out}"`, { stdio: "ignore" }); }
    catch { execSync(`powershell -NoProfile -Command "Expand-Archive -Force '${zip}' '${out}'"`, { stdio: "ignore" }); }
    return out;
  }
  return null;
}
function* walk(dir) {
  for (const f of readdirSync(dir)) {
    const p = join(dir, f);
    if (statSync(p).isDirectory()) yield* walk(p); else if (p.endsWith(".json")) yield p;
  }
}
const readJson = p => { try { return JSON.parse(readFileSync(p, "utf8")); } catch { return null; } };

mkdirSync(DATA, { recursive: true });
const scrDir = await download(SOURCES.scrutins, "scrutins");
if (!scrDir) { console.error("❌ Impossible de télécharger les scrutins."); process.exit(1); }
const amoDir = await download(SOURCES.amo, "amo");

// ---------- Groupes et députés ----------
const groupes = {}, deputes = {}; // PO -> {nom, abrege} ; nom normalisé -> {nom, groupeRef}
if (amoDir) {
  for (const p of walk(amoDir)) {
    const j = readJson(p); if (!j) continue;
    if (j.organe && j.organe.codeType === "GP") {
      groupes[txt(j.organe.uid)] = { nom: j.organe.libelle, abrege: j.organe.libelleAbrev || j.organe.libelleAbrege || "" };
    } else if (j.acteur) {
      const id = j.acteur.etatCivil?.ident; if (!id) continue;
      const gp = arr(j.acteur.mandats?.mandat).filter(m => m.typeOrgane === "GP")
        .sort((a, b) => String(b.dateDebut).localeCompare(String(a.dateDebut)))[0];
      const nom = `${id.prenom} ${id.nom}`;
      deputes[norm(nom)] = { nom, groupeRef: gp ? txt(gp.organes?.organeRef) : null };
    }
  }
}
console.log(`👥 ${Object.keys(groupes).length} groupes, ${Object.keys(deputes).length} députés`);
const gname = ref => groupes[ref]?.nom || ref;

// Auteur d'un amendement cité dans le titre : « l'amendement n° 12 de M. Jean Dupont … »
function auteurAmendement(titre) {
  const m = titre.match(/amendement n[°o]\s*\d+\s+de (?:M\.|Mme|MM\.)\s+([A-ZÀ-Ÿa-zà-ÿ' \-]+?)(?:\s+(?:et|apr[eè]s|avant|[àa]|au|aux|sur|tendant|visant)\b|,|\()/);
  if (!m) return null;
  const d = deputes[norm(m[1].trim())];
  return { nom: m[1].trim(), groupe: d ? gname(d.groupeRef) : null };
}

// ---------- Scrutins ----------
const candidats = [];
let total = 0;
for (const p of walk(scrDir)) {
  const s = readJson(p)?.scrutin; if (!s) continue;
  total++;
  const titre = s.titre || s.objet?.libelle || "";
  const t = norm(titre);
  const themes = Object.entries(THEMES).filter(([, re]) => re.test(t)).map(([k]) => k);
  if (!themes.length) continue;
  const d = s.syntheseVote?.decompte || {};
  const votants = +s.syntheseVote?.nombreVotants || 0;
  if (votants < 50) continue; // on écarte les votes dans un hémicycle presque vide

  const grp = arr(s.ventilationVotes?.organe?.groupes?.groupe).map(g => {
    const v = g.vote || {}, dv = v.decompteVoix || {};
    const pour = +dv.pour || 0, contre = +dv.contre || 0, abstention = +dv.abstentions || 0;
    // ⚠️ positionMajoritaire de l'open data ne correspond pas toujours aux décomptes :
    // on recalcule la position à partir des voix réelles.
    const max = Math.max(pour, contre, abstention);
    const position = max === 0 ? "non-votant" : pour === max ? "pour" : contre === max ? "contre" : "abstention";
    return {
      groupe: gname(g.organeRef), abrege: groupes[g.organeRef]?.abrege || "",
      membres: +g.nombreMembresGroupe || 0, position, positionOpenData: v.positionMajoritaire,
      pour, contre, abstention, nonVotants: +dv.nonVotants || 0,
    };
  });
  const solennel = s.typeVote?.codeTypeVote === "SPS";
  const ensemble = /l.ensemble d/.test(t);
  const censure = /motion de censure/.test(t);
  const amendement = /amendement/.test(t);
  const score = (solennel ? 30 : 0) + (ensemble ? 30 : 0) + (censure ? 30 : 0) + Math.min(votants, 577) / 20 - (amendement ? 5 : 0);

  candidats.push({
    numero: +s.numero, date: s.dateScrutin, type: s.typeVote?.libelleTypeVote, themes,
    titre, resultat: s.sort?.code, votants,
    pour: +d.pour || 0, contre: +d.contre || 0, abstention: +d.abstentions || 0,
    auteurAmendement: amendement ? auteurAmendement(titre) : null,
    groupes: grp, score: Math.round(score),
    source: `https://www.assemblee-nationale.fr/dyn/17/scrutins/${s.numero}`,
  });
}

// On garde les 15 meilleurs par thème.
const garde = new Map();
for (const theme of Object.keys(THEMES)) {
  candidats.filter(c => c.themes.includes(theme)).sort((a, b) => b.score - a.score || b.date.localeCompare(a.date))
    .slice(0, 15).forEach(c => garde.set(c.numero, c));
}
const liste = [...garde.values()].sort((a, b) => b.date.localeCompare(a.date));
writeFileSync(join(DIR, "candidats.json"), JSON.stringify({ genere: new Date().toISOString(), totalScrutins: total, groupes, candidats: liste }, null, 2));

const md = [`# Candidats pour le jeu « Qui a voté ? »`, ``, `${total} scrutins lus, ${candidats.length} sur les thèmes, ${liste.length} gardés.`, ``];
for (const theme of Object.keys(THEMES)) {
  const l = liste.filter(c => c.themes.includes(theme));
  md.push(`## ${theme} (${l.length})`, ``);
  for (const c of l) {
    md.push(`- **n°${c.numero}** (${c.date}, ${c.type}) — ${c.resultat} ${c.pour}/${c.contre}/${c.abstention} — ${c.titre.slice(0, 220)}`);
    md.push(`  - Groupes : ${c.groupes.map(g => `${g.abrege || g.groupe} ${g.position}`).join(" · ")}`);
  }
  md.push(``);
}
writeFileSync(join(DIR, "candidats.md"), md.join("\n"));
console.log(`\n✅ ${total} scrutins lus → ${liste.length} candidats. Fichiers : candidats.json, candidats.md`);
