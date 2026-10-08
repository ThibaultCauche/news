// Formule 1 (J28) : noms et règles qui servent à l'API comme au worker. L'appli en tient un miroir pour l'affichage
// (`apps/mobile/lib/features/formula1/f1_model.dart`, `grandPrixName`) : à garder d'accord.

// Jolpica donne « Australian Grand Prix » ; les textes envoyés aux gens disent « Grand Prix d'Australie ».
const GRAND_PRIX_PLACES: Record<string, string> = {
  Australian: "d'Australie",
  Chinese: "de Chine",
  Japanese: "du Japon",
  Bahrain: "de Bahreïn",
  "Saudi Arabian": "d'Arabie saoudite",
  Miami: "de Miami",
  "Emilia Romagna": "d'Émilie-Romagne",
  Monaco: "de Monaco",
  Canadian: "du Canada",
  Barcelona: "de Barcelone",
  Spanish: "d'Espagne",
  Austrian: "d'Autriche",
  British: "de Grande-Bretagne",
  Hungarian: "de Hongrie",
  Belgian: "de Belgique",
  Dutch: "des Pays-Bas",
  Italian: "d'Italie",
  Azerbaijan: "d'Azerbaïdjan",
  Singapore: "de Singapour",
  "United States": "des États-Unis",
  "Mexico City": "de Mexico",
  Mexican: "du Mexique",
  Brazilian: "du Brésil",
  "São Paulo": "de São Paulo",
  "Las Vegas": "de Las Vegas",
  Qatar: "du Qatar",
  "Abu Dhabi": "d'Abou Dhabi",
};

export function grandPrixName(name: string): string {
  const place = /^(.+) Grand Prix$/.exec(name)?.[1];
  const french = place ? GRAND_PRIX_PLACES[place] : undefined;
  return french ? `Grand Prix ${french}` : name;
}

/** Les essais libres n'ont ni classement ni enjeu : pas de notification pour qui suit seulement la saison ou le Grand Prix. */
export function isPracticeSession(sessionName: string): boolean {
  return sessionName.startsWith("Essais");
}

/** Qui a gagné : seulement une course ou un sprint. Le premier des qualifications a la pole, pas la victoire. */
export function sessionHasWinner(sessionName: string): boolean {
  return sessionName === "Course" || sessionName === "Sprint";
}

/** Nom d'une session dans une notification : « Grand Prix d'Australie (Course) » ; le nom du match pour le reste. */
export function notificationSubject(event: { kind: string; name: string }, competitionName: string): string {
  return event.kind === "session" ? `${grandPrixName(competitionName)} (${event.name})` : event.name;
}
