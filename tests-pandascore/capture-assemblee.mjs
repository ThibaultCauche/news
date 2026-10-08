// Régénère les fixtures réduites de l'Assemblée (J29) depuis `politique-quiz/data` (téléchargé par
// `politique-quiz/extraire-quiz.mjs` et `probe-dossiers.mjs`). Les décomptes nominatifs (un député par ligne) sont retirés.
import fs from "node:fs";
const data = "politique-quiz/data";
const out = "tests-pandascore/samples-assemblee";
const read = (p) => JSON.parse(fs.readFileSync(`${data}/${p}`, "utf8"));
const scrutin = read("scrutins/json/VTANR5L17V1308.json").scrutin;
for (const g of scrutin.ventilationVotes.organe.groupes.groupe) delete g.vote.decompteNominatif;
fs.writeFileSync(`${out}/scrutin-1308.json`, JSON.stringify({ scrutin }, null, 1));
fs.writeFileSync(`${out}/dossier-promulgue.json`, JSON.stringify(read("dossiers/json/dossierParlementaire/DLR5L17N50168.json"), null, 1));
const organes = fs.readdirSync(`${data}/amo/json/organe`).map((f) => read(`amo/json/organe/${f}`).organe).filter((o) => o.codeType === "GP" && o.legislature === "17");
fs.writeFileSync(`${out}/groupes.json`, JSON.stringify(organes.map(({ uid, codeType, libelle, libelleAbrev, legislature }) => ({ uid, codeType, libelle, libelleAbrev, legislature })), null, 1));

// Élections (J29c) : trois communes du fichier « Résultats - Communes » du 2ᵈ tour des municipales 2026
// (data.gouv.fr, jeu de données 69c17fed9f18c7781fd11a14), téléchargé dans `politique-quiz/data/communes-t2.csv`.
const lines = fs.readFileSync(`${data}/communes-t2.csv`, "utf8").split(/\r?\n/);
const wanted = ["Miribel", "Jassans-Riottier", "Ferney-Voltaire"];
fs.writeFileSync(`${out}/communes-t2-extrait.csv`, [lines[0], ...wanted.map((n) => lines.find((l) => l.includes(`;"${n}";`)))].join("\n") + "\n");

// Présidentielle 2022 (J29c) : France entière et trois départements du 1ᵉʳ tour (jeu de données du ministère
// 62581fdf02e05e365ea227a1, fichiers `resultats-par-niveau-fe-t1` et `…-dpt-t1`), laissés en Windows-1252 comme à la source ;
// et cinq bureaux du 2ᵈ tour des municipales 2026 (`Résultats - Bureau de vote`). Téléchargés dans `politique-quiz/data/`.
