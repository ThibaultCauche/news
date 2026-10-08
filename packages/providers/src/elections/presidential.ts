import { ElectionConfig, ElectionList, ElectionResult, TerritoryLevel } from "@news/domain";
import { DatasetResource, DatasetSummary } from "./client";
import { frNumber } from "./csv";

// Présidentielle : fichiers « resultats-par-niveau-<niveau>-t<tour>-france-entiere » du ministère de l'Intérieur (format
// des fichiers de 2022, seul exemple réel disponible ; à revalider sur un scrutin partiel avant avril 2027). Un fichier par
// niveau (`fe` = France entière, `reg`, `dpt`, `subcom`, `burvot`), une ligne par territoire, les candidats à la suite en
// blocs de colonnes qui se répètent : N°Panneau;Sexe;Nom;Prénom;Voix;% Voix/Ins;% Voix/Exp (sans le numéro de panneau dans
// le fichier des départements).

const norm = (s: string) =>
  s
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "")
    .toLowerCase();

const LEVEL_TOKEN: Record<Exclude<TerritoryLevel, "commune">, string> = { national: "fe", department: "dpt" };

/** La ressource d'un niveau et d'un tour : texte ou CSV, jamais le classeur Excel du même contenu. */
export function pickPresidentialResource(resources: DatasetResource[], level: Exclude<TerritoryLevel, "commune">, round: number): DatasetResource | null {
  const token = `-${LEVEL_TOKEN[level]}-t${round}-`;
  return (
    resources
      .filter((r) => norm(r.url + " " + r.title).includes(token) && /^(txt|csv)$/i.test(r.format))
      .sort((a, b) => (b.lastModified ?? "").localeCompare(a.lastModified ?? ""))[0] ?? null
  );
}

/**
 * Le jeu de données d'un scrutin parmi ceux que renvoie la recherche : titre du ministère de l'Intérieur qui nomme l'élection,
 * l'année et le tour. Les résultats provisoires (publiés le soir même) passent avant les définitifs tant que ceux-ci
 * n'existent pas : le plus récent l'emporte.
 */
export function matchElectionDataset(election: Pick<ElectionConfig, "type" | "round" | "date">, datasets: DatasetSummary[]): DatasetSummary | null {
  const kind = election.type === "presidentielle" ? "presidentielle" : "municipales";
  const year = election.date.slice(0, 4);
  const round = election.round === 1 ? /\b(1er|premier|1e)\s+tour\b/ : /\b(2nd|second|2e|2eme|2d)\s+tour\b/;
  return (
    datasets
      .filter((d) => /minist[eè]re de l.int[eé]rieur/i.test(d.organization ?? ""))
      .filter((d) => {
        const title = norm(d.title);
        return title.includes(kind) && title.includes(year) && round.test(title);
      })
      .sort((a, b) => b.createdAt.localeCompare(a.createdAt))[0] ?? null
  );
}

// Le fichier d'un niveau : `Code du niveau` (France entière) ou `Code du département` ; les colonnes de chiffres portent leur
// nom, les candidats se lisent par position.
export function normalizePresidentialRow(
  header: string[],
  row: string[],
  election: ElectionConfig,
  level: Exclude<TerritoryLevel, "commune">,
  sourceUrl: string,
): ElectionResult | null {
  const at = new Map(header.map((h, i) => [h, i]));
  const cell = (name: string) => row[at.get(name) ?? -1] ?? "";
  const code = level === "national" ? cell("Code du niveau") : cell("Code du département");
  if (!code) return null;
  const name = level === "national" ? cell("Libellé du niveau") : cell("Libellé du département");

  // Début des blocs de candidats, et leur largeur (de la première colonne du bloc à sa répétition).
  const start = header.findIndex((h) => h === "N°Panneau" || h === "Sexe");
  if (start < 0) return null;
  const first = header[start];
  const repeat = header.findIndex((h, i) => i > start && h === first);
  const size = repeat > 0 ? repeat - start : header.length - start;
  const block = header.slice(start, start + size);
  const col = (field: string) => block.indexOf(field);
  const [iPanel, iName, iFirst, iVotes, iPct] = [col("N°Panneau"), col("Nom"), col("Prénom"), col("Voix"), col("% Voix/Exp")];
  if (iName < 0 || iVotes < 0) return null;

  const lists: ElectionList[] = [];
  for (let offset = start; offset + size <= row.length; offset += size) {
    const nom = row[offset + iName];
    if (!nom) continue;
    lists.push({
      panel: iPanel >= 0 ? Number(row[offset + iPanel]) : lists.length + 1,
      label: [row[offset + iFirst], nom].filter(Boolean).join(" "),
      head: null,
      votes: frNumber(row[offset + iVotes]),
      pctExpressed: frNumber(row[offset + iPct]),
      elected: false,
      seatsCouncil: 0,
      seatsCommunity: 0,
    });
  }
  lists.sort((a, b) => b.votes - a.votes || a.panel - b.panel);
  return {
    type: "election_result",
    electionId: election.id,
    date: election.date,
    level,
    candidates: true,
    territory: { code, name, department: level === "national" ? "France" : name },
    registered: frNumber(cell("Inscrits")),
    voters: frNumber(cell("Votants")),
    turnoutPct: frNumber(cell("% Vot/Ins")),
    blank: frNumber(cell("Blancs")),
    nulls: frNumber(cell("Nuls")),
    expressed: frNumber(cell("Exprimés")),
    lists,
    // « Etat saisie » : « Complet » quand tous les bureaux du territoire sont saisis.
    complete: /^complet$/i.test(cell("Etat saisie")),
    bureaux: null,
    sourceUrl,
  };
}
