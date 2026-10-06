// Formes brutes de l'API PandaScore (plan gratuit), limitées aux champs utilisés.
// Référence : réponses réelles dans tests-pandascore/samples/.

export interface RawTeam {
  id: number;
  name: string;
  acronym?: string | null;
  image_url?: string | null;
  location?: string | null;
}

export interface RawLeague {
  id: number;
  name: string;
  image_url?: string | null;
}

export interface RawSerie {
  id: number;
  name: string;
  full_name?: string | null;
  league_id: number;
  begin_at?: string | null;
  end_at?: string | null;
}

export interface RawTournament {
  id: number;
  name: string;
  begin_at?: string | null;
  end_at?: string | null;
  tier?: string | null;
  winner_id?: number | null;
  serie_id: number;
  serie: RawSerie;
  league_id: number;
  league: RawLeague;
  teams?: RawTeam[];
  has_bracket?: boolean;
}

export interface RawGame {
  id: number;
  position: number;
  status: string;
  winner: { id: number | null; type: string } | null;
  // Durée en secondes, disponible en plan gratuit contrairement au score en
  // rounds ou au nom de la carte (docs/01-donnees-sources-valorant.md §"Ce
  // qu'on obtient vraiment").
  length?: number | null;
}

export interface RawMatchOpponent {
  type: string;
  opponent: RawTeam;
}

export interface RawMatchResult {
  team_id: number;
  score: number;
}

export interface RawStream {
  main?: boolean;
  official?: boolean;
  language?: string | null;
  raw_url?: string | null;
}

export interface RawPreviousMatch {
  type: "winner" | "loser";
  match_id: number;
}

export interface RawMatch {
  id: number;
  name: string;
  status: string;
  tournament_id: number;
  scheduled_at?: string | null;
  begin_at?: string | null;
  end_at?: string | null;
  number_of_games?: number | null;
  winner_id?: number | null;
  opponents?: RawMatchOpponent[];
  results?: RawMatchResult[];
  games?: RawGame[];
  previous_matches?: RawPreviousMatch[];
  streams_list?: RawStream[];
}
