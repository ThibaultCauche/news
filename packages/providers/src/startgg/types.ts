// Réponses start.gg (GraphQL) réduites aux champs demandés : les conditions d'utilisation exigent le minimum de
// données (tags de joueur seulement, ni e-mail ni nom réel).
export interface RawEvent {
  id: number;
  name: string;
  numEntrants: number | null;
}

export interface RawTournament {
  id: number;
  name: string;
  slug: string;
  startAt: number | null;
  endAt: number | null;
  isOnline: boolean | null;
  events: RawEvent[];
}

export interface RawPhase {
  id: number;
  name: string;
  bracketType: string;
  groupCount: number | null;
  numSeeds: number | null;
  phaseOrder: number;
  state: string;
}

export interface RawSlot {
  slotIndex?: number | null;
  prereqType: string | null;
  prereqId: string | number | null;
  prereqPlacement: number | null;
  entrant?: {
    id: number;
    name: string;
    participants: { gamerTag: string; user: { id: number } | null }[];
  } | null;
  standing?: { stats: { score: { value: number | null } | null } | null } | null;
}

export interface RawGame {
  orderNum: number;
  winnerId: number | null;
  // Personnage de chaque joueur (J27) : demandé seulement pour les phases à arbre, et pas toujours saisi.
  selections?: { entrant: { id: number } | null; character: { name: string } | null }[] | null;
}

export interface RawSet {
  id: number | string;
  identifier?: string | null;
  round?: number | null;
  fullRoundText: string | null;
  state: number;
  totalGames: number | null;
  winnerId: number | null;
  startAt: number | null;
  startedAt: number | null;
  completedAt: number | null;
  phaseGroup: { id?: number; displayIdentifier?: string | null; phase: { id: number } } | null;
  slots: RawSlot[];
  games?: RawGame[] | null;
}
