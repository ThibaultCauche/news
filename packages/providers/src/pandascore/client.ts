import { QuotaTracker } from "./quota";

const BASE_URL = "https://api.pandascore.co";

// Client HTTP minimal : un fetch authentifié, le quota lu à chaque appel.
// L'appli ne parle jamais aux fournisseurs (règle 1 de CLAUDE.md) — seul ce
// client, utilisé par le worker, le fait.
export class PandaScoreClient {
  constructor(
    private readonly token: string,
    readonly quota = new QuotaTracker(),
  ) {}

  async get<T>(path: string): Promise<T> {
    const res = await fetch(`${BASE_URL}${path}`, {
      headers: { Authorization: `Bearer ${this.token}`, Accept: "application/json" },
    });
    this.quota.recordHeaders(res.headers);
    if (!res.ok) {
      throw new Error(`PandaScore ${path} → HTTP ${res.status}`);
    }
    return (await res.json()) as T;
  }
}
