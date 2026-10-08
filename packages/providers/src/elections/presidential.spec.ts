import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ELECTIONS, ElectionConfig } from "@news/domain";
import { countBureaux, isBureauResource } from "./bureaux";
import { DatasetResource, DatasetSummary, ElectionsClient } from "./client";
import { decodeCsv, eachCsvRow } from "./csv";
import { matchElectionDataset, normalizePresidentialRow, pickPresidentialResource } from "./presidential";
import { ElectionsProvider } from "./provider";

const dir = join(__dirname, "../../../../tests-pandascore/samples-assemblee");
const rows = (name: string) => {
  const out: string[][] = [];
  eachCsvRow(decodeCsv(readFileSync(join(dir, name))), (r) => out.push(r));
  return out;
};
// Un scrutin de 2022 sert de modèle : les fichiers de 2027 auront la même forme (à revalider sur un scrutin partiel).
const election2022: ElectionConfig = { id: "presidentielle-2022-t1", name: "Présidentielle 2022", type: "presidentielle", round: 1, date: "2022-04-10", datasetId: null, resourceMatch: null, featured: 0, search: null };

describe("présidentielle : fichiers du ministère (modèle 2022)", () => {
  it("lit la France entière : participation, saisie complète et douze candidats dans l'ordre des voix", () => {
    const [header, row] = rows("presidentielle-2022-fe-t1.txt");
    const fe = normalizePresidentialRow(header, row, election2022, "national", "https://x/fe.txt")!;
    expect(fe).toMatchObject({ level: "national", candidates: true, complete: true, registered: 48_747_876, voters: 35_923_707, turnoutPct: 73.69, blank: 543_609, nulls: 247_151, expressed: 35_132_947 });
    expect(fe.territory).toEqual({ code: "FE", name: "France entière", department: "France" });
    expect(fe.lists).toHaveLength(12);
    expect(fe.lists.slice(0, 3).map((l) => [l.label, l.votes, l.pctExpressed])).toEqual([
      ["Emmanuel MACRON", 9_783_058, 27.85],
      ["Marine LE PEN", 8_133_828, 23.15],
      ["Jean-Luc MÉLENCHON", 7_712_520, 21.95],
    ]);
    // Aucun siège, aucune tête de liste : ce sont des candidats.
    expect(fe.lists.every((l) => l.seatsCouncil === 0 && l.head === null)).toBe(true);
    // Le numéro de panneau officiel est gardé.
    expect(fe.lists.find((l) => l.label === "Nathalie ARTHAUD")!.panel).toBe(1);
  });

  it("lit un département (blocs de six colonnes, sans numéro de panneau) et son état de saisie", () => {
    const [header, ain, aisne] = rows("presidentielle-2022-dpt-t1-extrait.txt");
    const dep = normalizePresidentialRow(header, ain, election2022, "department", "x")!;
    expect(dep.territory).toEqual({ code: "01", name: "Ain", department: "Ain" });
    expect(dep).toMatchObject({ level: "department", registered: 438_109, turnoutPct: 77.74, expressed: 333_024, complete: true });
    expect(dep.lists[0]).toMatchObject({ label: "Emmanuel MACRON", votes: 92_206, pctExpressed: 27.69 });
    expect(dep.lists).toHaveLength(12);
    expect(normalizePresidentialRow(header, aisne, election2022, "department", "x")!.territory.name).toBe("Aisne");
    // Une saisie partielle reste « en cours ».
    const partial = ain.map((c, i) => (header[i] === "Etat saisie" ? "Partiel" : c));
    expect(normalizePresidentialRow(header, partial, election2022, "department", "x")!.complete).toBe(false);
  });

  it("choisit le fichier du niveau et du tour, jamais le classeur Excel", () => {
    const r = (name: string, format: string): DatasetResource => ({ title: name, url: `https://x/${name}`, format, lastModified: "2022-04-14T15:00" });
    const resources = [
      r("resultats-par-niveau-fe-t1-france-entiere.xlsx", "xlsx"),
      r("resultats-par-niveau-fe-t1-france-entiere.txt", "txt"),
      r("resultats-par-niveau-dpt-t1-france-entiere.txt", "txt"),
      r("resultats-par-niveau-dpt-t2-france-entiere.txt", "txt"),
      r("resultats-par-niveau-burvot-t1-france-entiere.txt", "txt"),
    ];
    expect(pickPresidentialResource(resources, "national", 1)?.title).toBe("resultats-par-niveau-fe-t1-france-entiere.txt");
    expect(pickPresidentialResource(resources, "department", 2)?.title).toBe("resultats-par-niveau-dpt-t2-france-entiere.txt");
    expect(pickPresidentialResource(resources, "national", 2)).toBeNull();
  });

  it("retrouve le jeu de données d'un scrutin par son titre : ministère de l'Intérieur, année, tour", () => {
    const d = (id: string, title: string, organization: string, createdAt: string): DatasetSummary => ({ id, title, organization, createdAt });
    const found = [
      d("soissons", "Elections présidentielles 2022 Résultats du 1er tour", "Ville de Soissons", "2025-06-26"),
      d("t1-def", "Election présidentielle des 10 et 24 avril 2022 - Résultats définitifs du 1er tour", "Ministère de l'intérieur", "2022-04-14"),
      d("t1-prov", "Election présidentielle des 10 et 24 avril 2022 - Résultats provisoires du 1er tour", "Ministère de l'intérieur", "2022-04-10"),
      d("t2-def", "Election présidentielle des 10 et 24 avril 2022 - Résultats définitifs du 2nd tour", "Ministère de l'intérieur", "2022-04-28"),
    ];
    // Le plus récent du ministère l'emporte (les définitifs, une fois publiés, remplacent les provisoires).
    expect(matchElectionDataset(election2022, found)?.id).toBe("t1-def");
    expect(matchElectionDataset({ ...election2022, round: 2 }, found)?.id).toBe("t2-def");
    expect(matchElectionDataset({ ...election2022, date: "2027-04-18" }, found)).toBeNull();
    expect(matchElectionDataset(election2022, [found[0]])).toBeNull();
  });

  it("la présidentielle 2027 cherche son jeu de données, sans identifiant écrit en dur", () => {
    const president = ELECTIONS.filter((e) => e.type === "presidentielle");
    expect(president.every((e) => e.datasetId === null && e.search !== null)).toBe(true);
  });
});

describe("bureaux dépouillés", () => {
  it("compte les bureaux d'une commune et ceux qui ont des votants", () => {
    const [header, ...bureaux] = rows("bureaux-t2-extrait.csv");
    expect(bureaux.length).toBeGreaterThanOrEqual(4);
    const csv = [header, ...bureaux].map((r) => r.map((c) => `"${c}"`).join(";")).join("\n");
    const ferney = countBureaux(csv).get("01160")!;
    expect(ferney.total).toBe(bureaux.filter((r) => r[header.indexOf("Code commune")] === "01160").length);
    expect(ferney.counted).toBe(ferney.total);
    // Un bureau sans votant n'est pas encore dépouillé.
    const empty = [header, bureaux[0].map((c, i) => (header[i] === "Votants" ? "0" : c))].map((r) => r.map((c) => `"${c}"`).join(";")).join("\n");
    expect(countBureaux(empty).get("01160")).toEqual({ counted: 0, total: 1 });
  });
  it("reconnaît le fichier par bureau, hors Polynésie et arrondissements", () => {
    const match = "Municipales 2026 - Résultats - Communes_";
    expect(isBureauResource("Municipales 2026 - Résultats - Bureau de vote_2026-03-23_16h15.csv", match)).toBe(true);
    expect(isBureauResource("Municipales 2026 - Résultats - BV par communes_2026-03-20.csv", match)).toBe(true);
    expect(isBureauResource("Municipales 2026 - Résultats - Communes_2026-03-20.csv", match)).toBe(false);
    expect(isBureauResource("Municipales Polynésie française 2026 - Résultats - BV par communes_2026-03-20.csv", match)).toBe(false);
  });
});

describe("ElectionsProvider : présidentielle de bout en bout (fichiers de 2022 rejoués en 2027)", () => {
  // Faux data.gouv.fr : la recherche renvoie un jeu « 2027 » dont les ressources sont les fichiers de 2022.
  class FakeClient extends ElectionsClient {
    searches = 0;
    constructor() {
      super("test");
    }
    async search(): Promise<DatasetSummary[]> {
      this.searches++;
      return [{ id: "ds-2027", title: "Election présidentielle des 18 avril et 2 mai 2027 - Résultats provisoires du 1er tour", organization: "Ministère de l'intérieur", createdAt: "2027-04-18T18:30" }];
    }
    async resources(): Promise<DatasetResource[]> {
      return [
        { title: "resultats-par-niveau-fe-t1-france-entiere.txt", url: "fe", format: "txt", lastModified: "2027-04-18T19:00" },
        { title: "resultats-par-niveau-dpt-t1-france-entiere.txt", url: "dpt", format: "txt", lastModified: "2027-04-18T19:00" },
      ];
    }
    async download(url: string): Promise<Uint8Array> {
      return readFileSync(join(dir, url === "fe" ? "presidentielle-2022-fe-t1.txt" : "presidentielle-2022-dpt-t1-extrait.txt"));
    }
  }

  it("ne cherche ni ne télécharge rien avant 20 h le jour du scrutin", async () => {
    const client = new FakeClient();
    const provider = new ElectionsProvider(client, () => new Date("2027-04-18T17:59:00Z"));
    expect((await provider.listEvents({ onlyLive: true })).filter((e) => e.competitionExternalId.includes("presidentielle"))).toEqual([]);
    expect(client.searches).toBe(0);
  });

  it("à 20 h, retrouve le jeu de données puis publie la France entière et les départements", async () => {
    const client = new FakeClient();
    const provider = new ElectionsProvider(client, () => new Date("2027-04-18T18:30:00Z"));
    const events = (await provider.listEvents({ onlyLive: true })).filter((e) => e.competitionExternalId === "election:presidentielle-2027-t1");
    expect(events.map((e) => e.externalId)).toEqual([
      "result:presidentielle-2027-t1:national-FE",
      "result:presidentielle-2027-t1:department-01",
      "result:presidentielle-2027-t1:department-02",
      "result:presidentielle-2027-t1:department-03",
    ]);
    expect(events[0]).toMatchObject({ name: "France entière", status: "finished", participants: [] });
    expect(client.searches).toBe(1);
  });
});
