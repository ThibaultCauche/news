import { parseQuizQuestionId, pickQuizQuestions, quizDay, quizQuestionId, quizStreak, QuizVote } from "./quiz";

const groups = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L"];
const positions = ["pour", "contre", "abstention", "pour", "contre", "pour"] as const;
const votes: QuizVote[] = Array.from({ length: 40 }, (_, v) => ({
  eventId: `v${String(v).padStart(2, "0")}`,
  groups: groups.map((id, g) => ({ id, position: id === "L" && v % 3 === 0 ? ("non-votant" as const) : positions[(v + g) % positions.length] })),
}));
const day = (offset: number) => new Date(Date.UTC(2026, 9, 1 + offset)).toISOString().slice(0, 10);

describe("pickQuizQuestions", () => {
  it("donne les mêmes questions à tout le monde le même jour", () => {
    expect(pickQuizQuestions(votes, groups, "2026-10-09")).toEqual(pickQuizQuestions(votes, groups, "2026-10-09"));
    expect(pickQuizQuestions(votes, groups, "2026-10-09")).not.toEqual(pickQuizQuestions(votes, groups, "2026-10-10"));
  });

  it("interroge cinq groupes différents, sans répéter un vote", () => {
    const picks = pickQuizQuestions(votes, groups, "2026-10-09");
    expect(picks).toHaveLength(5);
    expect(new Set(picks.map((p) => p.groupId)).size).toBe(5);
    expect(new Set(picks.map((p) => p.eventId)).size).toBe(5);
  });

  it("fait tourner les groupes : sur douze jours de cinq questions, chacun est interrogé 5 fois", () => {
    const count = new Map<string, number>();
    for (let d = 0; d < 12; d++) {
      for (const p of pickQuizQuestions(votes, groups, day(d))) count.set(p.groupId, (count.get(p.groupId) ?? 0) + 1);
    }
    expect([...count.values()].every((c) => c === 5)).toBe(true);
    expect(count.size).toBe(12);
  });

  it("répartit les bonnes réponses : ni toutes « pour », ni abstention exclue", () => {
    const tally = { pour: 0, contre: 0, abstention: 0 };
    for (let d = 0; d < 30; d++) {
      for (const p of pickQuizQuestions(votes, groups, day(d))) {
        const position = votes.find((v) => v.eventId === p.eventId)!.groups.find((g) => g.id === p.groupId)!.position;
        if (position !== "non-votant") tally[position]++;
      }
    }
    expect(tally.contre).toBeGreaterThan(20);
    expect(tally.abstention).toBeGreaterThan(10);
    expect(tally.pour).toBeGreaterThan(20);
  });

  it("n'interroge jamais un groupe qui n'a pas voté", () => {
    for (let d = 0; d < 24; d++) {
      for (const p of pickQuizQuestions(votes, groups, day(d))) {
        expect(votes.find((v) => v.eventId === p.eventId)!.groups.find((g) => g.id === p.groupId)!.position).not.toBe("non-votant");
      }
    }
  });

  it("ne plante pas sans votes ni groupes", () => {
    expect(pickQuizQuestions([], groups, "2026-10-09")).toEqual([]);
    expect(pickQuizQuestions(votes, [], "2026-10-09")).toEqual([]);
  });
});

describe("quizStreak", () => {
  it("compte les jours d'affilée jusqu'à aujourd'hui, ou hier si on n'a pas encore joué", () => {
    expect(quizStreak(["2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"], "2026-10-09")).toEqual({ current: 4, best: 4 });
    expect(quizStreak(["2026-10-07", "2026-10-08"], "2026-10-09")).toEqual({ current: 2, best: 2 });
    expect(quizStreak(["2026-10-01", "2026-10-02", "2026-10-03", "2026-10-07"], "2026-10-09")).toEqual({ current: 0, best: 3 });
    expect(quizStreak([], "2026-10-09")).toEqual({ current: 0, best: 0 });
  });
});

describe("identifiants et jour", () => {
  it("un identifiant de question se lit dans les deux sens", () => {
    expect(parseQuizQuestionId(quizQuestionId("evt-1", "PO845401"))).toEqual({ eventId: "evt-1", groupId: "PO845401" });
    expect(parseQuizQuestionId("sans-separateur")).toBeNull();
    expect(parseQuizQuestionId("a:b:c")).toBeNull();
  });
  it("le jour change à minuit, heure de Paris", () => {
    expect(quizDay(new Date("2026-10-08T21:59:00Z"))).toBe("2026-10-08");
    expect(quizDay(new Date("2026-10-08T22:01:00Z"))).toBe("2026-10-09");
  });
});
