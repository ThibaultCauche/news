import { GSL_QUALIFIED_COUNT } from "./bracket";

// "Pourquoi ce match compte" (docs/03 §7) : une phrase calculée par des règles à
// partir des noms des matchs cible du bracket (`event_link`), jamais écrite à la
// main pour un match précis — déterministe, gratuit et toujours juste. Les mots
// repérés `[[terme]]` deviennent des liens vers la feuille glossaire (écran 04)
// côté appli.
export interface BracketStakesInput {
  bestOf: number | null;
  // Nom du match où va le vainqueur, `null` si ce match est déjà la dernière étape
  // (pas de lien "winner" sortant).
  winnerTargetName: string | null;
  // Nom du match où va le perdant, `null` si le perdant est éliminé du tournoi
  // (pas de lien "loser" sortant).
  loserTargetName: string | null;
}

// Même heuristique de mots-clés que `detectBracketFormat` (vérifiée sur de vrais
// brackets PandaScore) : on classe le match cible par ce que dit son nom, pas par
// une position codée en dur.
function branchLabel(targetMatchName: string): "grande finale" | "[[repêchage]]" | "tableau du milieu" | "[[tableau principal]]" {
  const name = targetMatchName.toLowerCase();
  if (name.includes("grand final")) return "grande finale";
  if (name.includes("lower bracket")) return "[[repêchage]]";
  if (name.includes("mid bracket")) return "tableau du milieu";
  return "[[tableau principal]]";
}

export function buildMatchStakes(input: BracketStakesInput): string {
  const sentences: string[] = [];

  if (input.winnerTargetName == null) {
    sentences.push("Le vainqueur est sacré champion.");
    sentences.push(
      input.loserTargetName == null ? "Le perdant termine 2e du tournoi." : `Le perdant repart au ${branchLabel(input.loserTargetName)}.`,
    );
  } else {
    const winnerBranch = branchLabel(input.winnerTargetName);
    sentences.push(
      winnerBranch === "grande finale"
        ? `Le vainqueur file en ${winnerBranch} et assure le podium.`
        : `Le vainqueur avance au ${winnerBranch}.`,
    );
    sentences.push(
      input.loserTargetName == null
        ? "Le perdant est éliminé du tournoi."
        : `Le perdant garde une 2e chance au ${branchLabel(input.loserTargetName)}.`,
    );
  }

  if (input.bestOf != null) sentences.push(`Match en [[BO${input.bestOf}]].`);

  return sentences.join(" ");
}

// Phrase d'enjeu d'une poule GSL (docs/04 J8, écran Agenda) : contrairement à
// `buildMatchStakes` (par match, formats à élimination), la règle de
// qualification est la même pour toutes les poules d'un même tournoi
// (`GSL_QUALIFIED_COUNT`) — une phrase fixe suffit, pas de calcul par poule.
// Avant ça, "Group A" et "Group B" apparaissaient identiques dans l'agenda,
// sans indiquer qu'ils mènent tous deux à la suite du tournoi.
export function buildGroupStakes(): string {
  return `Les ${GSL_QUALIFIED_COUNT} premiers de la poule se qualifient pour la suite du tournoi.`;
}
