import { readFileSync } from "node:fs";
import { join } from "node:path";
import { bracketName, isMajor, normalizePhase, normalizeSet, normalizeStructure, phaseHasBracket, pickSinglesEvent, setNumbers } from "./normalize";
import { RawPhase, RawSet, RawTournament } from "./types";

// Fixtures = vraies réponses start.gg réduites au Top 8 de Genesis X3 (tests-pandascore/samples-startgg/).
const SAMPLES = join(__dirname, "../../../../tests-pandascore/samples-startgg");
const sets: RawSet[] = JSON.parse(readFileSync(join(SAMPLES, "genesis-x3-top8-sets.json"), "utf8"));
const linkSets = JSON.parse(readFileSync(join(SAMPLES, "genesis-x3-top8-links.json"), "utf8")) as { bracketType: string; sets: { nodes: Pick<RawSet, "id" | "slots">[] } };

const tournament = (over: Partial<RawTournament>): RawTournament => ({
  id: 1,
  name: "Test",
  slug: "tournament/test",
  startAt: 1_800_000_000,
  endAt: 1_800_100_000,
  isOnline: false,
  events: [{ id: 10, name: "Ultimate Singles", numEntrants: 300 }],
  ...over,
});
const rules = { minEntrants: 256, staffPick: false, allowSlugs: [] as string[] };

describe("filtre des majors", () => {
  it("garde un Singles de 256 inscrits ou plus, écarte en dessous", () => {
    expect(isMajor(tournament({}), rules)).toBe(true);
    expect(isMajor(tournament({ events: [{ id: 10, name: "Ultimate Singles", numEntrants: 161 }] }), rules)).toBe(false);
  });
  it("compte les inscrits du Singles, pas ceux des autres événements", () => {
    const events = [{ id: 1, name: "Ultimate Doubles", numEntrants: 900 }, { id: 2, name: "Super Smash Bros. Ultimate - Singles", numEntrants: 100 }];
    expect(pickSinglesEvent({ events })?.id).toBe(2);
    expect(isMajor(tournament({ events }), rules)).toBe(false);
  });
  it("accepte une sélection de start.gg ou un préfixe de slug, refuse un tournoi en ligne", () => {
    const small = tournament({ slug: "tournament/genesis-x4", events: [{ id: 10, name: "Ultimate Singles", numEntrants: 161 }] });
    expect(isMajor(small, { ...rules, staffPick: true })).toBe(true);
    expect(isMajor(small, { ...rules, allowSlugs: ["genesis"] })).toBe(true);
    expect(isMajor({ ...small, isOnline: true }, { ...rules, staffPick: true })).toBe(false);
  });
  it("écarte un tournoi sans événement Singles", () => {
    expect(isMajor(tournament({ events: [{ id: 1, name: "Crew Battle", numEntrants: 400 }] }), rules)).toBe(false);
  });
});

describe("sets du Top 8 de Genesis X3", () => {
  const grandFinal = sets.find((s) => s.fullRoundText === "Grand Final")!;
  const event = normalizeSet(grandFinal)!;

  it("donne la finale 3-2, au meilleur des 5, avec le vainqueur et les manches", () => {
    expect(event.name).toBe("Grand final: Sonix vs Zomba");
    expect(event.status).toBe("finished");
    expect(event.bestOf).toBe(5);
    expect(event.participants.map((p) => [p.entity.name, p.score, p.isWinner])).toEqual([["Sonix", 3, true], ["Zomba", 2, false]]);
    expect(event.participants[0].entity.kind).toBe("player");
    expect((event.result as { games: unknown[] }).games).toHaveLength(5);
  });

  it("rattache chaque set à sa phase, avec une identité stable de joueur", () => {
    for (const set of sets) expect(normalizeSet(set)?.competitionExternalId).toBe("phase:2195696");
    expect(event.participants[0].entity.externalId).toMatch(/^user:\d+$/);
  });

  it("ne garde pas un nombre pair de manches comme format, et ignore un score de disqualification", () => {
    expect(normalizeSet({ ...grandFinal, totalGames: 4 })!.bestOf).toBeNull();
    const dq = structuredClone(grandFinal);
    dq.slots[0].standing = { stats: { score: { value: -1 } } };
    expect(normalizeSet(dq)!.participants[0].score).toBeNull();
  });

  it("laisse un set pas encore commencé sans joueur connu ni horaire inventé", () => {
    const waiting = normalizeSet({ ...grandFinal, state: 1, winnerId: null, startedAt: null, startAt: null, completedAt: null, slots: grandFinal.slots.map((s) => ({ ...s, entrant: null, standing: null })) })!;
    expect(waiting.status).toBe("scheduled");
    expect(waiting.name).toBe("Grand final: TBD vs TBD");
    expect(waiting.participants).toEqual([]);
    expect(waiting.startsAt).toBeNull();
  });

  it("donne le personnage de chaque joueur à chaque manche, quand il est saisi", () => {
    const games = (event.result as { games: { characters: Record<string, string> }[] }).games;
    const [sonix, zomba] = event.participants.map((p) => p.entity.externalId);
    expect(games[0].characters).toEqual({ [zomba]: "R.O.B.", [sonix]: "Sonic" });
    // Personnage non saisi : rien d'inventé.
    const bare = structuredClone(grandFinal);
    bare.games![0].selections = [{ entrant: { id: grandFinal.slots[0].entrant!.id }, character: null }];
    expect((normalizeSet(bare)!.result as { games: { characters: object }[] }).games[0].characters).toEqual({});
  });

  it("signale les joueurs appelés à leur station seulement à l'état « appelé », et garde la poule", () => {
    expect((event.result as { called: boolean }).called).toBe(false);
    expect((normalizeSet({ ...grandFinal, state: 6 })!.result as { called: boolean }).called).toBe(true);
    expect(normalizeSet({ ...grandFinal, state: 6 })!.status).toBe("scheduled");
    expect((event.result as { group: string }).group).toBe("ULT1");
  });

  it("ignore un set sans phase", () => {
    expect(normalizeSet({ ...grandFinal, phaseGroup: null })).toBeNull();
  });
});

describe("noms de rondes", () => {
  it("reprend le vocabulaire de PandaScore, que l'appli sait lire", () => {
    expect(bracketName("Winners Semi-Final", 2)).toBe("Upper bracket semifinal 2");
    expect(bracketName("Winners Final")).toBe("Upper bracket final");
    expect(bracketName("Losers Quarter-Final", 1)).toBe("Lower bracket quarterfinal 1");
    expect(bracketName("Losers Round 1", 2)).toBe("Lower bracket round 1 match 2");
    expect(bracketName("Losers Final")).toBe("Lower bracket final");
    expect(bracketName("Grand Final")).toBe("Grand final");
    expect(bracketName("Grand Final Reset")).toBe("Grand final reset");
    expect(bracketName("Pools A")).toBe("Pools A");
  });
  it("numérote les sets d'une même ronde dans l'ordre des identifiants", () => {
    const numbers = setNumbers(sets);
    const by = (identifier: string) => numbers.get(String(sets.find((s) => s.identifier === identifier)!.id));
    expect([by("A"), by("B")]).toEqual([1, 2]);
    expect([by("H"), by("I")]).toEqual([1, 2]);
    expect(by("C")).toBeNull();
    expect(normalizeSet(sets.find((s) => s.identifier === "B")!, by("B") ?? undefined)!.name).toMatch(/^Upper bracket semifinal 2: .+ vs .+$/);
  });
});

describe("structure du bracket", () => {
  const structure = normalizeStructure(linkSets.bracketType, linkSets.sets.nodes);
  it("construit les liens gagnant/perdant à partir des sets précédents", () => {
    expect(structure.format).toBe("double_elim");
    expect(structure.links.length).toBeGreaterThan(8);
    expect(structure.links.every((l) => l.slot === 0 || l.slot === 1)).toBe(true);
    // La finale des perdants (Losers Final) reçoit le perdant de la finale des gagnants.
    expect(structure.links.some((l) => l.outcome === "loser")).toBe(true);
    expect(structure.links).toContainEqual({ fromExternalId: "99355747", toExternalId: "99355748", outcome: "winner", slot: 0 });
  });
});

describe("phases", () => {
  const phase = (over: Partial<RawPhase>): RawPhase => ({ id: 1, name: "Top 8", bracketType: "DOUBLE_ELIMINATION", groupCount: 1, numSeeds: 8, phaseOrder: 4, state: "COMPLETED", ...over });
  it("n'affiche un arbre que pour un groupe en élimination", () => {
    expect(phaseHasBracket(phase({}))).toBe(true);
    expect(phaseHasBracket(phase({ groupCount: 32 }))).toBe(false);
    expect(phaseHasBracket(phase({ bracketType: "ROUND_ROBIN" }))).toBe(false);
  });
  it("reprend l'état de la phase et les dates du tournoi", () => {
    const c = normalizePhase(tournament({}), phase({ state: "ACTIVE" }));
    expect(c.status).toBe("live");
    expect(c.parentExternalId).toBe("tournament:1");
    expect(c.game).toBe("super-smash-bros-ultimate");
  });
});
