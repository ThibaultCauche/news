// CSV du ministère de l'Intérieur (data.gouv.fr) : séparateur « ; », guillemets doublés, fin de ligne \n ou \r\n.
// Écrit à la main plutôt qu'avec une bibliothèque : une seule forme de fichier à lire, et des fichiers de plus de 30 Mo
// qu'on parcourt ligne à ligne sans tout garder en mémoire.

export function eachCsvRow(text: string, onRow: (cells: string[]) => void): void {
  let cells: string[] = [];
  let cell = "";
  let quoted = false;
  const n = text.length;
  for (let i = 0; i < n; i++) {
    const c = text[i];
    if (quoted) {
      if (c === '"') {
        if (text[i + 1] === '"') {
          cell += '"';
          i++;
        } else quoted = false;
      } else cell += c;
    } else if (c === '"') quoted = true;
    else if (c === ";") {
      cells.push(cell);
      cell = "";
    } else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      cells.push(cell);
      cell = "";
      if (cells.length > 1 || cells[0] !== "") onRow(cells);
      cells = [];
    } else cell += c;
  }
  if (cell !== "" || cells.length > 0) {
    cells.push(cell);
    onRow(cells);
  }
}

/** Texte d'un fichier : UTF-8, ou Windows-1252 quand le fichier n'est pas de l'UTF-8 valide. */
export function decodeCsv(bytes: Uint8Array): string {
  const utf8 = new TextDecoder("utf-8").decode(bytes);
  return utf8.includes("�") ? new TextDecoder("windows-1252").decode(bytes) : utf8.replace(/^﻿/, "");
}

/** « 27,73% » → 27.73 ; « 1 244 » → 1244 ; vide → 0. */
export function frNumber(cell: string | undefined): number {
  if (!cell) return 0;
  const n = Number(cell.replace(/[%\s ]/g, "").replace(",", "."));
  return Number.isFinite(n) ? n : 0;
}
