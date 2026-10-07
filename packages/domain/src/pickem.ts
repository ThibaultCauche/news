// Pick'em de tableau (J25, docs/07) : on choisit le vainqueur de chaque match avant le premier match.
// Points croissants par tour (final 4, demi 2, reste 1) + un bonus fixe si tout le tableau est juste.

export const PICKEM_BONUS = 5;
export const PICKEM_FORMATS = ["single_elim", "double_elim", "triple_elim"];
// Au-delà, le tableau n'est plus lisible à pronostiquer (J27 : un « Top 64 » de Smash compte 126 sets, son « Top 8 » 14).
export const PICKEM_MAX_MATCHES = 32;

export interface PickemMatch {
  id: string;
  // Participants connus à l'ingestion (premier tour : les deux ; plus loin : aucun ou un).
  participants: string[];
  // Matchs dont le vainqueur / le perdant arrive ici.
  feeders: { fromId: string; outcome: "winner" | "loser" }[];
}

// Poids d'un match = sa distance à la finale en suivant les liens « vainqueur ».
export function pickemWeights(matches: PickemMatch[]): Map<string, number> {
  const next = new Map<string, string>();
  for (const m of matches) for (const f of m.feeders) if (f.outcome === "winner") next.set(f.fromId, m.id);
  const weights = new Map<string, number>();
  for (const m of matches) {
    let depth = 0;
    let at = m.id;
    // `depth` borne la remontée si les liens bouclaient.
    while (next.has(at) && depth <= matches.length) {
      at = next.get(at)!;
      depth++;
    }
    weights.set(m.id, depth === 0 ? 4 : depth === 1 ? 2 : 1);
  }
  return weights;
}

// Équipes qu'on peut choisir pour chaque match, d'après ses propres choix des tours précédents.
export function pickemCandidates(matches: PickemMatch[], picks: Record<string, string>): Map<string, string[]> {
  const byId = new Map(matches.map((m) => [m.id, m]));
  const memo = new Map<string, string[]>();
  const visiting = new Set<string>();
  const resolve = (id: string): string[] => {
    const known = memo.get(id);
    if (known) return known;
    const match = byId.get(id);
    if (!match || visiting.has(id)) return [];
    visiting.add(id);
    const out = [...match.participants];
    // Deux équipes réelles connues : ce sont elles, quoi qu'on ait choisi plus haut.
    if (out.length >= 2) {
      visiting.delete(id);
      memo.set(id, out);
      return out;
    }
    for (const f of match.feeders) {
      const from = resolve(f.fromId);
      const winner = picks[f.fromId];
      if (!winner || !from.includes(winner)) continue;
      const team = f.outcome === "winner" ? winner : from.find((t) => t !== winner);
      if (team && !out.includes(team)) out.push(team);
    }
    visiting.delete(id);
    memo.set(id, out);
    return out;
  };
  for (const m of matches) resolve(m.id);
  return memo;
}

// Premier match choisi qui n'a pas de sens (équipe qui ne peut pas y jouer) ; null si tout va bien.
export function invalidPickemMatch(matches: PickemMatch[], picks: Record<string, string>): string | null {
  const candidates = pickemCandidates(matches, picks);
  const known = new Set(matches.map((m) => m.id));
  for (const [id, team] of Object.entries(picks)) {
    if (!known.has(id) || !candidates.get(id)?.includes(team)) return id;
  }
  return null;
}

export function scorePickemMatch(weight: number, pickedEntityId: string, winnerEntityId: string): number {
  return pickedEntityId === winnerEntityId ? weight : 0;
}

// Bonus « tableau parfait » : tous les matchs choisis, tous justes.
export function isPerfectPickem(winners: Map<string, string>, picks: Record<string, string>): boolean {
  if (winners.size === 0) return false;
  for (const [id, winner] of winners) if (picks[id] !== winner) return false;
  return true;
}

// Choix du groupe pour un match : vote majoritaire ; à égalité, le choix du membre le plus ancien.
// `votes` est classé du membre le plus ancien au plus récent.
export function groupVote(votes: string[]): string | null {
  if (votes.length === 0) return null;
  const counts = new Map<string, number>();
  for (const v of votes) counts.set(v, (counts.get(v) ?? 0) + 1);
  const top = Math.max(...counts.values());
  return votes.find((v) => counts.get(v) === top) ?? null;
}

// Bonus « champion » : le vainqueur de la finale était le bon.
export const PICKEM_CHAMPION_BONUS = 3;

// La finale : le match dont le vainqueur ne va plus nulle part (poids 4). Null si le tableau n'en a pas une seule.
export function pickemFinalId(matches: PickemMatch[]): string | null {
  const finals = [...pickemWeights(matches)].filter(([, w]) => w === 4).map(([id]) => id);
  return finals.length === 1 ? finals[0] : null;
}

// Équipes qui peuvent encore jouer chaque match d'après les vrais résultats : un match terminé ne laisse passer que
// son vainqueur (ou son perdant), un match pas encore joué laisse passer toutes les équipes de ses prédécesseurs.
export function pickemPossible(matches: PickemMatch[], winners: Map<string, string>): Map<string, Set<string>> {
  const byId = new Map(matches.map((m) => [m.id, m]));
  const memo = new Map<string, Set<string>>();
  const visiting = new Set<string>();
  const resolve = (id: string): Set<string> => {
    const known = memo.get(id);
    if (known) return known;
    const match = byId.get(id);
    if (!match || visiting.has(id)) return new Set();
    visiting.add(id);
    const out = new Set(match.participants);
    for (const f of match.feeders) {
      const from = resolve(f.fromId);
      const winner = winners.get(f.fromId);
      if (winner) {
        if (f.outcome === "winner") out.add(winner);
        else for (const t of from) if (t !== winner) out.add(t);
      } else {
        for (const t of from) out.add(t);
      }
    }
    visiting.delete(id);
    memo.set(id, out);
    return out;
  };
  for (const m of matches) resolve(m.id);
  return memo;
}

export interface PickemStanding {
  // Points qu'on peut encore marquer au mieux (matchs à venir dont le choix tient toujours, plus les bonus).
  maxRemaining: number;
  // Par match non joué : le choix peut-il encore se réaliser ?
  alive: Map<string, boolean>;
}

// « Je suis en vie » : un tableau parfait reste possible tant que tous les matchs joués sont justes et que tous les
// choix à venir peuvent encore se réaliser ; le bonus champion tant que le choix de la finale tient.
export function pickemStanding(matches: PickemMatch[], picks: Record<string, string>, winners: Map<string, string>): PickemStanding {
  const weights = pickemWeights(matches);
  const possible = pickemPossible(matches, winners);
  const finalId = pickemFinalId(matches);
  const alive = new Map<string, boolean>();
  let maxRemaining = 0;
  let perfect = matches.length > 0;
  for (const m of matches) {
    const pick = picks[m.id];
    const winner = winners.get(m.id);
    if (winner) {
      if (pick !== winner) perfect = false;
      continue;
    }
    const ok = pick !== undefined && (possible.get(m.id)?.has(pick) ?? false);
    alive.set(m.id, ok);
    if (ok) maxRemaining += weights.get(m.id) ?? 1;
    else perfect = false;
  }
  if (perfect) maxRemaining += PICKEM_BONUS;
  if (finalId && !winners.has(finalId) && alive.get(finalId)) maxRemaining += PICKEM_CHAMPION_BONUS;
  return { maxRemaining, alive };
}
