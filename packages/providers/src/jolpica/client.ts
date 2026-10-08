import { QuotaTracker } from "../pandascore/quota";

const BASE = "https://api.jolpi.ca/ergast/f1";
// Jolpica limite à 4 requêtes par seconde en rafale et 200 par heure sans clé : une requête toutes les 500 ms, et
// l'adaptateur ne relit que les week-ends récents. `quota` ne suit rien, comme celui de start.gg.
const MIN_SPACING_MS = 500;

// Client minimal de Jolpica-F1, utilisé par le worker seulement (règle 1 de CLAUDE.md). Les requêtes passent l'une
// après l'autre.
export class JolpicaClient {
  private last = 0;
  private chain: Promise<unknown> = Promise.resolve();

  constructor(
    private readonly userAgent: string,
    readonly quota = new QuotaTracker(),
  ) {}

  get<T>(path: string): Promise<T> {
    const run = this.chain.then(() => this.send<T>(path));
    this.chain = run.catch(() => undefined);
    return run;
  }

  private async send<T>(path: string): Promise<T> {
    const wait = this.last + MIN_SPACING_MS - Date.now();
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    this.last = Date.now();
    // Trop de requêtes (429) : on attend le délai demandé, puis on réessaie, trois fois au plus.
    let res = await fetch(`${BASE}${path}.json?limit=100`, { headers: { "user-agent": this.userAgent } });
    for (let attempt = 0; res.status === 429 && attempt < 3; attempt++) {
      const retryAfter = Number(res.headers.get("retry-after"));
      await new Promise((resolve) => setTimeout(resolve, (retryAfter > 0 ? retryAfter : 10) * 1000));
      res = await fetch(`${BASE}${path}.json?limit=100`, { headers: { "user-agent": this.userAgent } });
    }
    if (!res.ok) throw new Error(`Jolpica → HTTP ${res.status} (${path})`);
    return ((await res.json()) as { MRData: T }).MRData;
  }
}
