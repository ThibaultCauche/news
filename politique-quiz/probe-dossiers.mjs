import fs from "fs";
const dir = "dossierParlementaire";
const codes = new Map(); const procs = new Map(); let n = 0, withProm = 0, withDecAn = 0, withVote = 0;
const arr = (x) => (x == null ? [] : Array.isArray(x) ? x : [x]);
const walk = (a, f) => arr(a).forEach((x) => { f(x); if (x.actesLegislatifs) walk(x.actesLegislatifs.acteLegislatif, f); });
const links = new Set();
for (const file of fs.readdirSync(dir).filter((f) => f.startsWith("DLR5L17"))) {
  const d = JSON.parse(fs.readFileSync(`${dir}/${file}`)).dossierParlementaire; n++;
  procs.set(d.procedureParlementaire.libelle, (procs.get(d.procedureParlementaire.libelle) || 0) + 1);
  let prom = false;
  walk(d.actesLegislatifs?.acteLegislatif, (x) => {
    const c = x.codeActe; codes.set(c, (codes.get(c) || 0) + 1);
    if (/PROM/.test(c)) prom = true;
    if (x.voteRefs) links.add(file);
  });
  if (prom) withProm++;
}
console.log({ n, withProm, withVoteRefs: links.size });
console.log([...procs].sort((a, b) => b[1] - a[1]));
console.log([...codes].filter(([c]) => !/REUNION|NOMIN|SAISIE|AUDITION/.test(c)).sort((a, b) => b[1] - a[1]).slice(0, 70).map(([c, k]) => c + ":" + k).join("  "));
