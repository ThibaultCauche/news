import { readFileSync } from "node:fs";
import { join } from "node:path";
import { ELECTIONS } from "@news/domain";
import { DatasetResource, ElectionsClient } from "./client";
import { decodeCsv, eachCsvRow, frNumber } from "./csv";
import { normalizeElection, normalizeMunicipalesRow, normalizeResult } from "./normalize";
import { ElectionsProvider, pickResource } from "./provider";

const file = join(__dirname, "../../../../tests-pandascore/samples-assemblee/communes-t2-extrait.csv");
const election = ELECTIONS.find((e) => e.id === "municipales-2026-t2")!;
const rows: string[][] = [];
eachCsvRow(decodeCsv(readFileSync(file)), (row) => rows.push(row));
const [header, ...communes] = rows;
const byName = (name: string) => normalizeMunicipalesRow(header, communes.find((r) => r.includes(name))!, election, "https://example.test/communes.csv")!;

describe("CSV du ministère", () => {
  it("lit les cellules entre guillemets, les guillemets doublés et les fins de ligne Windows", () => {
    const out: string[][] = [];
    eachCsvRow('"a";"b ""c"" d";"";e\r\n"x;y";"2"\r\n\r\nlast', (r) => out.push(r));
    expect(out).toEqual([["a", 'b "c" d', "", "e"], ["x;y", "2"], ["last"]]);
  });
  it("lit les nombres à la française", () => {
    expect([frNumber("27,73%"), frNumber("1 244"), frNumber(""), frNumber(undefined)]).toEqual([27.73, 1244, 0, 0]);
  });
  it("retombe sur Windows-1252 quand le fichier n'est pas de l'UTF-8", () => {
    expect(decodeCsv(Uint8Array.from([0x4d, 0xe9, 0x72, 0x69, 0x62, 0x65, 0x6c]))).toBe("Méribel");
  });
  it("garde les trois communes de l'extrait", () => {
    expect(communes).toHaveLength(3);
  });
});

describe("résultats d'une commune", () => {
  it("lit la participation, les listes et leurs sièges, du plus de voix au moins", () => {
    const jassans = byName("Jassans-Riottier");
    expect(jassans.territory).toEqual({ code: "01194", name: "Jassans-Riottier", department: "Ain" });
    expect(jassans).toMatchObject({ registered: 4387, voters: 2469, turnoutPct: 56.28, blank: 48, nulls: 15, expressed: 2406, complete: true });
    expect(jassans.lists.map((l) => [l.label, l.votes, l.seatsCouncil])).toEqual([
      ["JASSANS-RIOTTIER VILLE D'AVENIR", 1136, 22],
      ["UN NOUVEL ELAN POUR JASSANS-RIOTTIER", 825, 5],
      ["JASSANS-RIOTTIER AGIR ET RÉALISER", 445, 2],
    ]);
    expect(jassans.lists[0]).toMatchObject({ panel: 4, head: "Marie-Laure REIX", pctExpressed: 47.22, seatsCommunity: 4 });
  });

  it("ne garde que les listes présentes, les colonnes vides sont ignorées", () => {
    expect(byName("Miribel").lists).toHaveLength(4);
  });

  it("devient un événement terminé du territoire, sans participants, le soir du scrutin à 20 h", () => {
    const event = normalizeResult(byName("Miribel"));
    expect(event).toMatchObject({ externalId: "result:municipales-2026-t2:01249", competitionExternalId: "election:municipales-2026-t2", kind: "election_result", name: "Miribel", status: "finished", participants: [] });
    expect(event.startsAt!.toISOString()).toBe("2026-03-22T19:00:00.000Z");
  });

  it("un dépouillement en cours (aucun siège attribué) reste « en direct »", () => {
    const row = communes.find((r) => r.includes("Miribel"))!.map((c, i) => (/^Sièges au C[MC] /.test(header[i]) || /^Elu /.test(header[i]) ? "" : c));
    const live = normalizeMunicipalesRow(header, row, election, "x")!;
    expect(live.complete).toBe(false);
    expect(normalizeResult(live)).toMatchObject({ status: "live", endsAt: null });
  });
});

describe("élection", () => {
  it("l'élection à venir est annoncée avec l'heure de levée du blocage", () => {
    const president = ELECTIONS.find((e) => e.id === "presidentielle-2027-t1")!;
    const dto = normalizeElection(president, new Date("2026-10-08T10:00:00Z"));
    expect(dto).toMatchObject({ kind: "election", format: "live_feed", status: "scheduled", name: "Présidentielle 2027 · 1ᵉʳ tour", importance: 3 });
    expect((dto.structure as { liftsAt: string }).liftsAt).toBe("2027-04-18T18:00:00.000Z");
  });
});

describe("pickResource", () => {
  const r = (title: string, lastModified: string): DatasetResource => ({ title, url: `https://x/${title}`, format: "csv", lastModified });
  it("prend la ressource communes la plus récente, hors Polynésie et arrondissements", () => {
    const list = [
      r("Municipales 2026 - Résultats - Communes_2026-03-23_10h00.csv", "2026-03-23T10:00"),
      r("Municipales 2026 - Résultats - Communes_2026-03-23_16h14.csv", "2026-03-23T16:14"),
      r("Municipales Polynésie française 2026 - Résultats - Communes_2026-03-23.csv", "2026-03-23T18:00"),
      r("Conseils d'arrondissement Paris Lyon Marseille 2026 - Résultats - Communes", "2026-03-23T18:30"),
    ];
    expect(pickResource(list, "Municipales 2026 - Résultats - Communes_")?.title).toBe("Municipales 2026 - Résultats - Communes_2026-03-23_16h14.csv");
    expect(pickResource([], "x")).toBeNull();
  });
});

describe("ElectionsProvider : blocage avant 20 h (article L52-2)", () => {
  class FakeClient extends ElectionsClient {
    downloads = 0;
    constructor() {
      super("test");
    }
    async resources(): Promise<DatasetResource[]> {
      return [{ title: "Municipales 2026 - Résultats - Communes_x.csv", url: "https://x/c.csv", format: "csv", lastModified: "2026-03-22T21:00" }];
    }
    async download(): Promise<Uint8Array> {
      this.downloads++;
      return readFileSync(file);
    }
  }

  it("ne télécharge rien le jour du scrutin avant 20 h", async () => {
    const client = new FakeClient();
    const provider = new ElectionsProvider(client, () => new Date("2026-03-22T18:59:00Z"));
    expect(await provider.listEvents({ onlyLive: true })).toEqual([]);
    expect(client.downloads).toBe(0);
    // Le passage complet lit seulement le 1ᵉʳ tour, déjà public depuis une semaine : jamais le 2ᵈ tour du soir même.
    const all = await provider.listEvents();
    expect(all.some((e) => e.competitionExternalId === "election:municipales-2026-t2")).toBe(false);
    expect(client.downloads).toBe(1);
  });

  it("lit les résultats à partir de 20 h, les relit chaque minute le soir même, et garde les plus peuplées", async () => {
    const client = new FakeClient();
    let now = new Date("2026-03-22T19:00:00Z");
    const provider = new ElectionsProvider(client, () => now);
    const first = await provider.listEvents({ onlyLive: true });
    expect(first.map((e) => e.name).sort()).toEqual(["Ferney-Voltaire", "Jassans-Riottier", "Miribel"]);
    now = new Date("2026-03-22T19:00:30Z");
    await provider.listEvents({ onlyLive: true });
    expect(client.downloads).toBe(1);
    now = new Date("2026-03-22T19:01:30Z");
    await provider.listEvents({ onlyLive: true });
    expect(client.downloads).toBe(2);
  });

  it("le job rapide ne fait rien les autres jours", async () => {
    const client = new FakeClient();
    const provider = new ElectionsProvider(client, () => new Date("2026-04-02T10:00:00Z"));
    expect(await provider.listEvents({ onlyLive: true })).toEqual([]);
    expect(client.downloads).toBe(0);
    expect((await provider.listEvents()).length).toBeGreaterThan(0);
  });
});
