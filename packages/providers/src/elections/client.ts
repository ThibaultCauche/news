import { QuotaTracker } from "../pandascore/quota";

const API = "https://www.data.gouv.fr/api/1";

export interface DatasetSummary {
  id: string;
  title: string;
  organization: string | null;
  createdAt: string;
}

export interface DatasetResource {
  title: string;
  url: string;
  format: string;
  lastModified: string | null;
}

// Les résultats des élections sont des fichiers CSV du ministère de l'Intérieur publiés sur data.gouv.fr (Licence
// ouverte 2.0) : le worker lit la fiche du jeu de données, choisit la ressource, la télécharge. Pas de quota.
export class ElectionsClient {
  constructor(
    private readonly userAgent: string,
    readonly quota = new QuotaTracker(),
  ) {}

  private async fetchOk(url: string): Promise<Response> {
    let failure: unknown;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const res = await fetch(url, { headers: { "user-agent": this.userAgent } });
        if (!res.ok) throw new Error(`data.gouv.fr → HTTP ${res.status} (${url})`);
        return res;
      } catch (err) {
        failure = err;
        await new Promise((resolve) => setTimeout(resolve, 2000 * (attempt + 1)));
      }
    }
    throw failure;
  }

  /** Recherche de jeux de données par mots (le jeu d'un scrutin à venir n'a pas d'identifiant connu). */
  async search(query: string): Promise<DatasetSummary[]> {
    const url = `${API}/datasets/?q=${encodeURIComponent(query)}&page_size=20&sort=-created`;
    const body = (await (await this.fetchOk(url)).json()) as { data: { id: string; title: string; created_at: string; organization: { name: string } | null }[] };
    return body.data.map((d) => ({ id: d.id, title: d.title, organization: d.organization?.name ?? null, createdAt: d.created_at }));
  }

  async resources(datasetId: string): Promise<DatasetResource[]> {
    const dataset = (await (await this.fetchOk(`${API}/datasets/${datasetId}/`)).json()) as { resources: { title: string; url: string; format: string; last_modified: string | null }[] };
    return dataset.resources.map((r) => ({ title: r.title, url: r.url, format: r.format, lastModified: r.last_modified }));
  }

  async download(url: string): Promise<Uint8Array> {
    return new Uint8Array(await (await this.fetchOk(url)).arrayBuffer());
  }
}
