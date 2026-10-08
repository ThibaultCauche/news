import { eachCsvRow, frNumber } from "./csv";

/** Bureaux de vote dépouillés / total, par commune. */
export type BureauxByCommune = Map<string, { counted: number; total: number }>;

// Fichier « Résultats - Bureau de vote » des municipales : une ligne par bureau. Un bureau est dépouillé quand il a des
// votants ; on suppose qu'un bureau pas encore dépouillé figure dans le fichier avec des zéros (à vérifier un soir de
// vrai dépouillement : sans cela le total serait celui des bureaux déjà publiés).
export function countBureaux(csv: string): BureauxByCommune {
  const byCommune: BureauxByCommune = new Map();
  let header: Map<string, number> | null = null;
  eachCsvRow(csv, (row) => {
    if (!header) {
      header = new Map(row.map((h, i) => [h, i]));
      return;
    }
    const code = row[header.get("Code commune") ?? -1];
    if (!code) return;
    const entry = byCommune.get(code) ?? { counted: 0, total: 0 };
    entry.total++;
    if (frNumber(row[header.get("Votants") ?? -1]) > 0) entry.counted++;
    byCommune.set(code, entry);
  });
  return byCommune;
}

/** Le fichier par bureau : « Bureau de vote » au 2ᵈ tour, « BV par communes » au 1ᵉʳ ; jamais Polynésie ni arrondissements. */
export function isBureauResource(title: string, match: string): boolean {
  const prefix = match.split(" - ")[0];
  return title.startsWith(prefix) && /Bureau de vote|BV par communes/i.test(title) && !/Polyn[ée]sie|arrondissement/i.test(title);
}
