// Badges (J25, docs/07) : cosmétiques, déduits de l'activité, sans effet sur les points ni les classements.

export interface BadgeStats {
  /** Tableaux de pick'em remplis (au moins un choix). */
  pickemsPlayed: number;
  /** Tableaux parfaits (bonus versé). */
  perfectBrackets: number;
  /** Champions trouvés (bonus champion versé). */
  championsCalled: number;
  /** Pronostics de phase suisse parfaits (toutes les équipes choisies qualifiées, au moins quatre). */
  perfectSwiss: number;
}

export interface BadgeDefinition {
  id: string;
  label: string;
  description: string;
  earned: (stats: BadgeStats) => boolean;
}

export const BADGES: BadgeDefinition[] = [
  { id: "first_pickem", label: "Premier tableau", description: "Remplir un pick'em de tableau.", earned: (s) => s.pickemsPlayed >= 1 },
  { id: "three_pickems", label: "Habitué", description: "Remplir trois pick'em de tableau.", earned: (s) => s.pickemsPlayed >= 3 },
  { id: "champion_called", label: "Bon œil", description: "Trouver le champion d'un tournoi.", earned: (s) => s.championsCalled >= 1 },
  { id: "perfect_bracket", label: "Sans faute", description: "Un tableau parfait, du premier au dernier match.", earned: (s) => s.perfectBrackets >= 1 },
  { id: "perfect_swiss", label: "Voyant", description: "Toutes les équipes choisies en phase suisse se sont qualifiées.", earned: (s) => s.perfectSwiss >= 1 },
];

export function earnedBadges(stats: BadgeStats): { id: string; label: string; description: string; earned: boolean }[] {
  return BADGES.map((b) => ({ id: b.id, label: b.label, description: b.description, earned: b.earned(stats) }));
}
