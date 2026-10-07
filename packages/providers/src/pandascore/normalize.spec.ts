import { readFileSync } from "node:fs";
import { join } from "node:path";
import { computeStandings, standingsOptionsFor } from "@news/domain";
import { PandaScoreClient } from "./client";
import { normalizeCompetitionsFromTournament, normalizeMatch, normalizeStructure } from "./normalize";
import { PandaScoreProvider } from "./provider";
import { RawMatch, RawTournament } from "./types";

// Fixtures = vraies réponses PandaScore, gardées dans tests-pandascore/samples/
// (CLAUDE.md : "à réutiliser comme fixtures de tests").
const SAMPLES = join(__dirname, "../../../../tests-pandascore/samples");
const load = <T>(file: string): T => JSON.parse(readFileSync(join(SAMPLES, file), "utf8"));

describe("streams d'un match (J21)", () => {
  it("un vrai match PandaScore : seulement des chaînes Twitch de l'éditeur", () => {
    const matches = load<RawMatch[]>("brackets-du-tournoi.json");
    const streams = matches.flatMap((m) => normalizeMatch(m).streams);
    expect(streams.length).toBeGreaterThan(0);
    for (const s of streams) expect(s.url).toMatch(/^https:\/\/www\.twitch\.tv\//);
  });
});

describe("normalizeMatch", () => {
  it("normalise un match terminé : score de série, gagnant par carte, pas de score en rounds", () => {
    const [match] = load<RawMatch[]>("matchs-termin-s.json");
    const event = normalizeMatch(match);

    expect(event.provider).toBe("pandascore");
    expect(event.externalId).toBe("1682153");
    expect(event.competitionExternalId).toBe("21883");
    expect(event.status).toBe("finished");
    expect(event.bestOf).toBe(3);

    expect(event.participants).toHaveLength(2);
    const g2 = event.participants.find((p) => p.entity.externalId === "128538");
    const tyloo = event.participants.find((p) => p.entity.externalId === "133288");
    expect(g2?.score).toBe(2);
    expect(g2?.isWinner).toBe(true);
    expect(tyloo?.score).toBe(0);
    expect(tyloo?.isWinner).toBe(false);

    const result = event.result as { games: Array<{ winnerExternalId: string | null; durationSeconds: number | null }> };
    expect(result.games).toHaveLength(2);
    expect(result.games.every((g) => g.winnerExternalId === "128538")).toBe(true);
    expect(result.games[0].durationSeconds).toBe(2738);
  });

  it("normalise un match en cours : pas de gagnant tranché, cartes mélangées", () => {
    const [match] = load<RawMatch[]>("matchs-en-cours.json");
    const event = normalizeMatch(match);

    expect(event.status).toBe("live");
    expect(event.participants.every((p) => p.isWinner === null)).toBe(true);

    const result = event.result as { games: Array<{ status: string; winnerExternalId: string | null }> };
    expect(result.games[0].status).toBe("finished");
    expect(result.games[0].winnerExternalId).not.toBeNull();
    expect(result.games[2].status).toBe("not_started");
    expect(result.games[2].winnerExternalId).toBeNull();
  });

  it("normalise un match à venir : programmé, sans score", () => {
    const [match] = load<RawMatch[]>("matchs-venir.json");
    const event = normalizeMatch(match);

    expect(event.status).toBe("scheduled");
    expect(event.startsAt).toBeInstanceOf(Date);
    // PandaScore renvoie un score placeholder (0) avant le début du match, pas null.
    expect(event.participants.every((p) => p.isWinner === null)).toBe(true);
  });
});

describe("normalizeCompetitionsFromTournament", () => {
  it("dérive ligue, série et tournoi d'une seule réponse (économie de quota)", () => {
    const [tournament] = load<RawTournament[]>("tournois-en-cours.json");
    const [league, serie, t] = normalizeCompetitionsFromTournament(tournament);

    expect(league.kind).toBe("league");
    expect(league.externalId).toBe(String(tournament.league_id));
    expect(league.parentExternalId).toBeNull();

    expect(serie.kind).toBe("serie");
    expect(serie.externalId).toBe(String(tournament.serie_id));
    expect(serie.parentExternalId).toBe(String(tournament.league_id));

    expect(t.kind).toBe("tournament");
    expect(t.externalId).toBe(String(tournament.id));
    expect(t.parentExternalId).toBe(String(tournament.serie_id));
    expect(t.importance).toBe(3); // tier "s"
    expect(t.hasBracket).toBe(tournament.has_bracket ?? false);
  });
});

describe("normalizeStructure", () => {
  it("détecte une poule GSL et construit les liens gagnant/perdant", () => {
    const matches = load<RawMatch[]>("brackets-du-tournoi.json");
    const structure = normalizeStructure(matches);

    expect(structure.format).toBe("groups_gsl");
    expect(structure.links).toContainEqual({ fromExternalId: "1685231", toExternalId: "1685232", outcome: "winner", slot: 1 });
  });

  it("détecte une double élimination sur le bracket des playoffs Champions", () => {
    const matches = load<RawMatch[]>("brackets-playoffs.json");
    const structure = normalizeStructure(matches);
    expect(structure.format).toBe("double_elim");
    expect(structure.links.length).toBeGreaterThan(0);
  });
});

// Vraies réponses PandaScore League of Legends (tests-pandascore/samples-lol/) : Worlds 2025 et 2026.
const LOL_SAMPLES = join(__dirname, "../../../../tests-pandascore/samples-lol");
const loadLol = <T>(file: string): T => JSON.parse(readFileSync(join(LOL_SAMPLES, file), "utf8"));

describe("League of Legends (J23)", () => {
  it("donne le jeu du tournoi à sa ligue, sa série et son tournoi", () => {
    const [tournament] = loadLol<RawTournament[]>("tournois-tier-s.json");
    const competitions = normalizeCompetitionsFromTournament(tournament);
    expect(competitions.map((c) => c.game)).toEqual(["league-of-legends", "league-of-legends", "league-of-legends"]);
  });

  it("reconnaît la phase suisse des Worlds par les noms « Round N: … »", () => {
    const matches = loadLol<RawMatch[]>("suisse-worlds-2025-matchs.json");
    expect(normalizeStructure(matches).format).toBe("swiss");
  });

  it("phase suisse terminée : 8 qualifiées (3 victoires) et 8 éliminées (3 défaites)", () => {
    const matches = loadLol<RawMatch[]>("suisse-worlds-2025-matchs.json").map(normalizeMatch);
    const standings = computeStandings(
      matches.map((m) => ({
        status: m.status,
        participants: m.participants.map((p) => ({ entityExternalId: p.entity.externalId, score: p.score, isWinner: p.isWinner })),
      })),
      standingsOptionsFor("swiss"),
    );
    expect(standings).toHaveLength(16);
    expect(standings.filter((s) => s.qualified)).toHaveLength(8);
    expect(standings.filter((s) => s.livesLeft === 0)).toHaveLength(8);
    expect(standings.filter((s) => s.qualified && s.livesLeft === 0)).toHaveLength(0);
  });

  it("le gagnant de chaque partie est donné pour les matchs de tier S (Worlds 2025)", () => {
    const games = [...loadLol<RawMatch[]>("suisse-worlds-2025-matchs.json"), ...loadLol<RawMatch[]>("brackets-playoffs-worlds-2025.json")].flatMap((m) => m.games ?? []);
    expect(games.length).toBeGreaterThan(50);
    expect(games.every((g) => g.winner?.id != null)).toBe(true);
  });
});

describe("PandaScoreProvider, deux jeux", () => {
  const fakeClient = (calls: string[]) =>
    ({
      quota: {},
      get: async (path: string) => {
        calls.push(path);
        return [];
      },
    }) as unknown as PandaScoreClient;

  it("ne demande les matchs LoL qu'avec les tournois suivis, et rien au rythme du direct sans tournoi en cours", async () => {
    const calls: string[] = [];
    const provider = new PandaScoreProvider(fakeClient(calls));
    expect(await provider.listEvents({ onlyLive: true })).toEqual([]);
    // Valorant : un appel direct ; LoL : un appel catalogue (2 requêtes) pour connaître les tournois, aucun appel de matchs.
    expect(calls.filter((c) => c.startsWith("/valorant/matches/running"))).toHaveLength(1);
    expect(calls.filter((c) => c.includes("/lol/matches"))).toHaveLength(0);
  });

  it("filtre les tournois LoL de tier S/A", async () => {
    const calls: string[] = [];
    await new PandaScoreProvider(fakeClient(calls)).listCompetitions();
    expect(calls).toContain("/lol/tournaments/running?per_page=50&filter[tier]=s,a");
    expect(calls).toContain("/valorant/tournaments/running?per_page=50");
  });
});

describe("nom d'une série dont le nom complet n'est que l'année", () => {
  it("remet le nom de la ligue devant : « Worlds 2026 »", () => {
    const [tournament] = loadLol<RawTournament[]>("tournois-tier-s.json");
    const [, serie] = normalizeCompetitionsFromTournament(tournament);
    expect(serie.name).toBe("Worlds 2026");
  });

  it("garde un nom complet déjà lisible : « Champions 2026 »", () => {
    const [tournament] = load<RawTournament[]>("tournois-en-cours.json");
    expect(normalizeCompetitionsFromTournament(tournament)[1].name).toBe("Champions 2026");
  });
});
