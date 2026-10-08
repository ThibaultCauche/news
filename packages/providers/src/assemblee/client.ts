import { QuotaTracker } from "../pandascore/quota";

const REPOSITORY = "https://data.assemblee-nationale.fr/static/openData/repository/17";

// Les trois archives de l'open data de l'Assemblée (Licence ouverte 2.0), mises à jour une fois par jour.
export const ASSEMBLEE_FILES = {
  scrutins: `${REPOSITORY}/loi/scrutins/Scrutins.json.zip`,
  dossiers: `${REPOSITORY}/loi/dossiers_legislatifs/Dossiers_Legislatifs.json.zip`,
  organes: `${REPOSITORY}/amo/deputes_actifs_mandats_actifs_organes/AMO10_deputes_actifs_mandats_actifs_organes.json.zip`,
} as const;

// Pas d'API chez l'Assemblée : on télécharge des archives. Pas de quota non plus (`quota` ne suit rien, comme
// start.gg et Jolpica) ; le rythme est réglé par le cache de l'adaptateur.
export class AssembleeClient {
  constructor(
    private readonly userAgent: string,
    readonly quota = new QuotaTracker(),
  ) {}

  async download(url: string): Promise<Uint8Array> {
    // Une archive de plusieurs dizaines de Mo : la connexion peut se couper en route, trois essais.
    let failure: unknown;
    for (let attempt = 0; attempt < 3; attempt++) {
      try {
        const res = await fetch(url, { headers: { "user-agent": this.userAgent } });
        if (!res.ok) throw new Error(`Assemblée nationale → HTTP ${res.status} (${url})`);
        return new Uint8Array(await res.arrayBuffer());
      } catch (err) {
        failure = err;
        await new Promise((resolve) => setTimeout(resolve, 2000 * (attempt + 1)));
      }
    }
    throw failure;
  }
}
