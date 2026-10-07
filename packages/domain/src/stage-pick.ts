// Pronostic d'une étape (J23) : choisir, avant son début, les équipes qui se qualifieront de la phase suisse. Règles
// pures ; le verrouillage (au premier match) et l'enregistrement sont côté API.

/** Nombre d'équipes qu'on peut choisir : la moitié des équipes de l'étape (8 qualifiées sur 16 en phase suisse). */
export function maxStagePicks(teamCount: number): number {
  return Math.floor(teamCount / 2);
}

export interface StagePickScore {
  /** Équipes choisies qui se sont qualifiées. */
  correct: number;
  /** Équipes choisies déjà éliminées. */
  wrong: number;
  /** Équipes choisies dont le sort n'est pas encore réglé. */
  pending: number;
}

/** Où en est un pronostic : chaque équipe choisie est qualifiée, éliminée ou encore en course. */
export function scoreStagePick(picks: string[], qualifiedIds: Set<string>, eliminatedIds: Set<string>): StagePickScore {
  let correct = 0;
  let wrong = 0;
  for (const id of picks) {
    if (qualifiedIds.has(id)) correct += 1;
    else if (eliminatedIds.has(id)) wrong += 1;
  }
  return { correct, wrong, pending: picks.length - correct - wrong };
}
