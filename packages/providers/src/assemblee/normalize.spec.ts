import { readFileSync } from "node:fs";
import { join } from "node:path";
import { flattenActs, groupsOf, normalizeLaw, normalizeVote, parseScrutin, titleKey } from "./normalize";
import { RawDossier, RawOrgane, RawScrutin } from "./types";

const dir = join(__dirname, "../../../../tests-pandascore/samples-assemblee");
const load = (name: string) => JSON.parse(readFileSync(join(dir, name), "utf8"));
const groups = groupsOf(load("groupes.json") as RawOrgane[]);
const scrutin = load("scrutin-1308.json").scrutin as RawScrutin;
const dossier = load("dossier-promulgue.json").dossierParlementaire as RawDossier;

describe("Assemblée nationale", () => {
  it("lit un scrutin : décompte, groupes dans l'ordre alphabétique, positions recalculées", () => {
    const vote = parseScrutin(scrutin, groups)!;
    expect(vote.overall).toBe(true);
    expect(vote.result).toMatchObject({ numero: 1308, date: "2025-04-08", sort: "adopté", pour: 339, contre: 174, abst: 11, required: 257 });
    expect(vote.result.groups.map((g) => g.name)).toEqual([...vote.result.groups.map((g) => g.name)].sort((a, b) => a.localeCompare(b, "fr")));
    const rn = vote.result.groups.find((g) => g.shortName === "RN")!;
    expect(rn).toMatchObject({ name: "Rassemblement National", members: 123, pour: 122, position: "pour" });
    expect(vote.result.sourceUrl).toBe("https://www.assemblee-nationale.fr/dyn/17/scrutins/1308");
  });

  it("transforme un vote en événement terminé dont les participants sont les groupes", () => {
    const event = normalizeVote(parseScrutin(scrutin, groups)!, "law:DLR5L17N50168");
    expect(event).toMatchObject({ externalId: "vote:1308", competitionExternalId: "law:DLR5L17N50168", kind: "vote", status: "finished" });
    expect(event.participants).toHaveLength(12);
    expect(event.participants[0].entity).toMatchObject({ kind: "party_group", externalId: expect.stringMatching(/^group:PO/) });
  });

  it("met à plat l'arbre d'actes d'un dossier et lit la promulgation", () => {
    const acts = flattenActs(dossier.actesLegislatifs);
    expect(acts.find((a) => a.code === "SN1-DEPOT")?.date).toBe("2024-07-10");
    expect(acts.find((a) => a.code === "PROM-PUB")).toMatchObject({ date: "2024-12-13", conclusion: "Loi n° 2024-1177" });
  });

  it("construit la loi : étapes, type, numéro et lien Légifrance, sans texte inventé", () => {
    const law = normalizeLaw(dossier, [], new Map(), groups)!;
    expect(law.competition).toMatchObject({
      externalId: "law:DLR5L17N50168",
      parentExternalId: "league:an17",
      kind: "law",
      format: "law_process",
      game: "assemblee-nationale",
      status: "finished",
      name: "Proposition de loi organique portant réforme du financement de l'audiovisuel public",
    });
    const structure = law.competition.structure as { process: { status: string; steps: { key: string; state: string }[] }; lawType: string; lawNumber: string; legifranceUrl: string };
    expect(structure.process.status).toBe("promulgated");
    expect(structure.lawType).toBe("Proposition de loi organique");
    expect(structure.lawNumber).toBe("2024-1177");
    expect(structure.legifranceUrl).toContain("legifrance.gouv.fr");
    expect(structure.process.steps.every((s) => s.state === "done")).toBe(true);
  });

  it("n'ouvre pas un suivi pour un texte seulement déposé ni pour une résolution", () => {
    const deposited = { ...dossier, actesLegislatifs: { acteLegislatif: { codeActe: "AN1", actesLegislatifs: { acteLegislatif: { codeActe: "AN1-DEPOT", dateActe: "2025-01-01" } } } } } as unknown as RawDossier;
    expect(normalizeLaw(deposited, [], new Map(), groups)).toBeNull();
    expect(normalizeLaw({ ...dossier, procedureParlementaire: { libelle: "Résolution" } }, [], new Map(), groups)).toBeNull();
  });

  it("rapproche le titre d'un scrutin de celui du texte, accents, parenthèses et apostrophes compris", () => {
    expect(titleKey("l’ensemble de la proposition de loi relative au droit à l’aide à mourir (première lecture).")).toBe(titleKey("proposition de loi relative au droit à l'aide à mourir"));
  });
});
