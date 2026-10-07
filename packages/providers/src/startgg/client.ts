import { QuotaTracker } from "../pandascore/quota";

const URL = "https://api.start.gg/gql/alpha";
// 80 requêtes par minute permises : une toutes les 900 ms en laisse une marge (conditions d'utilisation : ne pas
// contourner les limites).
const MIN_SPACING_MS = 900;

// Client GraphQL minimal, utilisé par le worker seulement (règle 1 de CLAUDE.md). Les requêtes passent l'une après
// l'autre, espacées. `quota` ne suit rien : la limite est par minute, pas par heure, et déjà respectée ici.
export class StartGgClient {
  private last = 0;
  private chain: Promise<unknown> = Promise.resolve();

  constructor(
    private readonly token: string,
    readonly quota = new QuotaTracker(),
  ) {}

  query<T>(query: string, variables: Record<string, unknown> = {}): Promise<T> {
    const run = this.chain.then(() => this.send<T>(query, variables));
    this.chain = run.catch(() => undefined);
    return run;
  }

  private async send<T>(query: string, variables: Record<string, unknown>): Promise<T> {
    const wait = this.last + MIN_SPACING_MS - Date.now();
    if (wait > 0) await new Promise((resolve) => setTimeout(resolve, wait));
    this.last = Date.now();
    const res = await fetch(URL, {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${this.token}` },
      body: JSON.stringify({ query, variables }),
    });
    if (!res.ok) throw new Error(`start.gg → HTTP ${res.status}`);
    const json = (await res.json()) as { data?: T; errors?: { message: string }[] };
    if (json.errors?.length) throw new Error(`start.gg → ${json.errors[0].message}`);
    return json.data as T;
  }
}
