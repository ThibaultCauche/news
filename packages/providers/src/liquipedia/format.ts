// Extraction minimale du modèle "Infobox league" : une valeur par ligne
// "|clé=valeur" (pas un parseur wikitexte complet, ponytail — suffisant pour les
// champs structurés dont on a besoin).
export function parseInfoboxFields(wikitext: string): Record<string, string> {
  const fields: Record<string, string> = {};
  for (const line of wikitext.split("\n")) {
    const match = /^\|\s*([a-zA-Z0-9_]+)\s*=\s*(.*)$/.exec(line);
    if (match) fields[match[1]] = match[2].trim();
  }
  return fields;
}

const FRENCH_MONTHS = [
  "janvier",
  "février",
  "mars",
  "avril",
  "mai",
  "juin",
  "juillet",
  "août",
  "septembre",
  "octobre",
  "novembre",
  "décembre",
];

function formatFrenchDate(iso: string): string | null {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!match) return null;
  const [, year, month, day] = match;
  return `${Number(day)} ${FRENCH_MONTHS[Number(month) - 1]} ${year}`;
}

// Phrase de contexte pour l'en-tête d'une compétition (docs/01/§7) : gabarit rempli
// avec des champs structurés (dates, lieu, dotation), jamais le texte libre de la
// page (qui resterait en anglais — règle CLAUDE.md : textes visibles en français).
// `null` si les champs qu'on sait lire manquent tous (page atypique).
export function buildCompetitionIntro(fields: Record<string, string>): string | null {
  const sentences: string[] = [];

  // `country` n'est pas repris : nom de pays en anglais côté Liquipedia (ex.
  // "China"), pas de table de traduction pour un simple complément de lieu — la
  // ville seule (`city`) suffit et reste toujours un nom propre.
  if (fields.organizer) {
    sentences.push(fields.city ? `Compétition organisée par ${fields.organizer}, à ${fields.city}.` : `Compétition organisée par ${fields.organizer}.`);
  }

  const start = fields.sdate ? formatFrenchDate(fields.sdate) : null;
  const end = fields.edate ? formatFrenchDate(fields.edate) : null;
  if (start && end) sentences.push(`Du ${start} au ${end}.`);

  const facts: string[] = [];
  if (fields.team_number) facts.push(`${fields.team_number} équipes`);
  if (fields.prizepoolusd) facts.push(`${fields.prizepoolusd} $ de dotation`);
  if (facts.length > 0) sentences.push(`${facts.join(", ")}.`);

  return sentences.length > 0 ? sentences.join(" ") : null;
}
