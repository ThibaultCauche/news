import { buildVoteNotificationText, computeLawProcess, groupPosition, isLawProcedure, lawTypeOf, LawAct, reachedFloor, sortGroupsNeutral, voteSentence } from "./politics";

describe("groupPosition", () => {
  it("recalcule la position depuis les voix, pas depuis l'open data", () => {
    // Scrutin 2957 : 119 députés RN ont voté pour, l'open data annonçait « abstention ».
    expect(groupPosition({ pour: 119, contre: 0, abst: 2 })).toBe("pour");
    expect(groupPosition({ pour: 0, contre: 61, abst: 3 })).toBe("contre");
    expect(groupPosition({ pour: 3, contre: 1, abst: 9 })).toBe("abstention");
  });
  it("un groupe sans voix exprimée est non-votant (motion de censure)", () => {
    expect(groupPosition({ pour: 0, contre: 0, abst: 0 })).toBe("non-votant");
  });
});

describe("voteSentence", () => {
  it("suit le gabarit fixe", () => {
    expect(voteSentence({ sort: "adopté", pour: 312, contre: 198, abst: 41 })).toBe("Adopté : 312 pour, 198 contre, 41 abstentions");
    expect(voteSentence({ sort: "rejeté", pour: 197, contre: 0, abst: 1 })).toBe("Rejeté : 197 pour, 0 contre, 1 abstention");
    expect(voteSentence({ sort: "adopté", pour: 5, contre: 2, abst: 0 })).toBe("Adopté : 5 pour, 2 contre");
  });
});

describe("buildVoteNotificationText", () => {
  it("dit le résultat sans rien cacher, même en sans spoil", () => {
    expect(buildVoteNotificationText("Revente de billets", { sort: "adopté", pour: 312, contre: 198, abst: 0 })).toEqual({
      title: "Vote à l'Assemblée",
      body: "Revente de billets — Adopté : 312 pour, 198 contre.",
    });
  });
});

describe("sortGroupsNeutral", () => {
  it("range par nom officiel, sans tenir compte des accents", () => {
    const names = sortGroupsNeutral([{ name: "Rassemblement National" }, { name: "Écologiste et Social" }, { name: "Droite Républicaine" }]).map((g) => g.name);
    expect(names).toEqual(["Droite Républicaine", "Écologiste et Social", "Rassemblement National"]);
  });
});

const act = (code: string, date: string | null = null, conclusion: string | null = null): LawAct => ({ code, date, conclusion });
const states = (acts: LawAct[]) => computeLawProcess(acts).steps.map((s) => `${s.key}:${s.state}`);

describe("computeLawProcess", () => {
  it("un texte déposé n'a que sa première étape de faite", () => {
    const process = computeLawProcess([act("AN1"), act("AN1-DEPOT", "2025-05-12")]);
    expect(process.status).toBe("in_progress");
    expect(process.steps.map((s) => s.state)).toEqual(["done", "current", "todo", "todo", "todo", "todo", "todo"]);
    expect(process.steps[0].label).toBe("Déposé à l'Assemblée");
  });

  it("un texte né au Sénat donne la main au Sénat d'abord", () => {
    const process = computeLawProcess([act("SN1-DEPOT", "2024-07-10"), act("SN1-COM-FOND-RAPPORT", "2024-10-16"), act("SN1-DEBATS-DEC", "2024-10-23", "adoptée")]);
    expect(process.firstChamber).toBe("SN");
    expect(process.steps[0].label).toBe("Déposé au Sénat");
    expect(process.steps[2]).toMatchObject({ label: "Voté par les sénateurs", state: "done", date: "2024-10-23", detail: "Adopté" });
    expect(process.steps[3]).toMatchObject({ label: "Examiné en commission à l'Assemblée", state: "current" });
  });

  it("la loi promulguée est faite de bout en bout, accord implicite compris", () => {
    const process = computeLawProcess([
      act("SN1-DEPOT", "2024-07-10"),
      act("SN1-DEBATS-DEC", "2024-10-23", "adoptée"),
      act("AN1-COM-FOND-RAPPORT", "2024-11-13"),
      act("AN1-DEBATS-DEC", "2024-11-20", "adoptée sans modification"),
      act("PROM-PUB", "2024-12-13", "Loi n° 2024-1177"),
    ]);
    expect(process.status).toBe("promulgated");
    expect(process.steps.every((s) => s.state === "done")).toBe(true);
    expect(process.steps.find((s) => s.key === "agreement")).toMatchObject({ date: "2024-11-20", detail: "Texte adopté sans modification" });
    expect(process.steps.at(-1)).toMatchObject({ key: "promulgation", detail: "Loi n° 2024-1177" });
    expect(process.steps.some((s) => s.key === "council")).toBe(false);
  });

  it("le Conseil constitutionnel n'apparaît que s'il a été saisi", () => {
    const acts = [act("AN1-DEPOT", "2025-01-01"), act("AN1-DEBATS-DEC", "2025-02-01", "adoptée"), act("SN1-DEBATS-DEC", "2025-03-01", "adoptée"), act("CMP-DEC", "2025-04-01", "Accord"), act("CC"), act("CC-CONCLUSION", "2025-05-01", "Partiellement conforme")];
    const process = computeLawProcess(acts);
    expect(process.steps.find((s) => s.key === "council")).toMatchObject({ state: "done", detail: "Partiellement conforme" });
    expect(process.steps.at(-1)).toMatchObject({ key: "promulgation", state: "current" });
  });

  it("un désaccord en commission mixte laisse l'accord « en ce moment »", () => {
    const process = computeLawProcess([act("AN1-DEBATS-DEC", "2025-02-01", "adoptée"), act("SN1-DEBATS-DEC", "2025-03-01", "modifiée"), act("CMP-DEC", "2025-04-01", "Désaccord")]);
    expect(process.steps.find((s) => s.key === "agreement")).toMatchObject({ state: "current", detail: "Désaccord en commission mixte, nouvelle lecture" });
  });

  it("un rejet clôt le texte : les étapes suivantes sont sautées", () => {
    const process = computeLawProcess([act("AN1-DEPOT", "2025-01-01"), act("AN1-DEBATS-DEC", "2025-02-01", "rejetée")]);
    expect(process.status).toBe("rejected");
    expect(states([act("AN1-DEPOT", "2025-01-01"), act("AN1-DEBATS-DEC", "2025-02-01", "rejetée")])).toEqual([
      "deposit:done",
      "committee1:done",
      "vote1:done",
      "committee2:skipped",
      "vote2:skipped",
      "agreement:skipped",
      "promulgation:skipped",
    ]);
  });

  it("une première chambre qui rejette n'arrête pas un texte que l'autre chambre examine", () => {
    const process = computeLawProcess([act("AN1-DEBATS-DEC", "2025-02-01", "rejetée"), act("SN1-DEBATS-DEC", "2025-03-01", "adoptée")]);
    expect(process.status).toBe("in_progress");
  });

  it("rattache le vote sur l'ensemble de l'Assemblée à l'étape de vote, dans les 14 jours avant la décision", () => {
    const votes = [
      { numero: 100, date: "2025-06-10", pour: 1, contre: 1, abst: 0, sort: "rejeté" as const },
      { numero: 1308, date: "2025-06-18", pour: 312, contre: 198, abst: 41, sort: "adopté" as const },
    ];
    const process = computeLawProcess([act("AN1-DEPOT", "2025-05-12"), act("AN1-DEBATS-DEC", "2025-06-18", "adoptée")], votes);
    expect(process.steps[2].vote?.numero).toBe(1308);
    expect(process.steps[2].detail).toBeNull();
  });
});

describe("textes de loi", () => {
  it("garde les textes de loi, écarte résolutions et rapports", () => {
    expect(isLawProcedure("Proposition de loi ordinaire")).toBe(true);
    expect(isLawProcedure("Projet ou proposition de loi organique")).toBe(true);
    expect(isLawProcedure("Projet de loi de finances de l'année")).toBe(true);
    expect(isLawProcedure("Projet de ratification des traités et conventions")).toBe(true);
    expect(isLawProcedure("Résolution")).toBe(false);
    expect(isLawProcedure("Rapport d'information sans mission")).toBe(false);
    expect(isLawProcedure("Engagement de la responsabilité gouvernementale")).toBe(false);
  });
  it("donne le type du texte depuis son titre officiel", () => {
    expect(lawTypeOf("Proposition de loi organique portant réforme du financement de l'audiovisuel public", "Projet ou proposition de loi organique")).toBe("Proposition de loi organique");
    expect(lawTypeOf("Projet de loi de finances pour 2026", "Projet de loi de finances de l'année")).toBe("Projet de loi de finances");
    expect(lawTypeOf("Autorisant l'approbation de l'accord", "Projet de ratification des traités et conventions")).toBe("Projet de loi de ratification");
  });
  it("un texte entre dans le suivi dès qu'il a été débattu en séance", () => {
    expect(reachedFloor([act("AN1-DEPOT"), act("AN1-COM-FOND-RAPPORT")])).toBe(false);
    expect(reachedFloor([act("AN1-DEBATS-SEANCE", "2025-01-01")])).toBe(true);
    expect(reachedFloor([act("PROM-PUB")])).toBe(true);
  });
});
