import { GSL_QUALIFIED_COUNT, SWISS_LOSSES_TO_ELIMINATE, SWISS_WINS_TO_QUALIFY } from "./bracket";

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

// Phase suisse (J23) : la règle est la même pour tout le tournoi, une phrase fixe pour les listes.
export function buildSwissGroupStakes(): string {
  return `[[phase suisse]] : ${SWISS_WINS_TO_QUALIFY} victoires qualifient, ${SWISS_LOSSES_TO_ELIMINATE} défaites éliminent.`;
}

export interface SwissTeamRecord {
  name: string;
  wins: number;
  losses: number;
}

// « Pourquoi ce match compte » en phase suisse : ce que chaque équipe joue avec son bilan avant le match
// (2 victoires = une de plus qualifie, 2 défaites = une de plus élimine), par gabarit.
export function buildSwissMatchStakes(teams: SwissTeamRecord[], bestOf: number | null): string {
  const sentences: string[] = [];
  const decisive = teams.filter((t) => t.wins === SWISS_WINS_TO_QUALIFY - 1 && t.losses === SWISS_LOSSES_TO_ELIMINATE - 1);
  if (teams.length === 2 && decisive.length === 2) {
    sentences.push("Match décisif : le vainqueur est qualifié, le perdant éliminé.");
  } else {
    for (const t of teams) {
      if (t.wins === SWISS_WINS_TO_QUALIFY - 1) sentences.push(`${t.name} se qualifie avec une victoire.`);
      if (t.losses === SWISS_LOSSES_TO_ELIMINATE - 1) sentences.push(`${t.name} est éliminé en cas de défaite.`);
    }
  }
  if (sentences.length === 0) sentences.push(buildSwissGroupStakes());
  if (bestOf != null) sentences.push(`Match en [[BO${bestOf}]].`);
  return sentences.join(" ");
}
