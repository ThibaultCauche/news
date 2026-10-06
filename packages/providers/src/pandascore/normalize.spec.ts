import { readFileSync } from "node:fs";
import { join } from "node:path";
import { normalizeCompetitionsFromTournament, normalizeMatch, normalizeStructure } from "./normalize";
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
