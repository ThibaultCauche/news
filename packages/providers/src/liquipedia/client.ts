const BASE_URL = "https://liquipedia.net/valorant/api.php";

// Client MediaWiki minimal pour Liquipedia (docs/01 : contexte/formats, en
// enrichissement, jamais en direct). Règles techniques imposées par la licence
// (CC-BY-SA, API Terms of Use) : User-Agent avec contact, 1 requête/2s, 1 appel
// "parse" (le plus coûteux) par 30s. Un seul worker en pratique (ponytail) : un
// délai en mémoire suffit, pas besoin d'un verrou distribué entre plusieurs instances.
export class LiquipediaClient {
  private lastRequestAt = 0;
  private lastParseAt = 0;

  constructor(private readonly userAgent: string) {}

  private async wait(since: number, minDelayMs: number): Promise<void> {
    const remaining = since + minDelayMs - Date.now();
    if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining));
  }

  private async get<T>(params: Record<string, string>): Promise<T> {
    await this.wait(this.lastRequestAt, 2000);
    this.lastRequestAt = Date.now();
    const url = `${BASE_URL}?${new URLSearchParams({ ...params, format: "json" }).toString()}`;
    const res = await fetch(url, { headers: { "User-Agent": this.userAgent, Accept: "application/json" } });
    if (!res.ok) throw new Error(`Liquipedia ${params.action} → HTTP ${res.status}`);
    return (await res.json()) as T;
  }

  // Titre de la page la plus pertinente pour une recherche libre, `null` si rien.
  async searchPageTitle(query: string): Promise<string | null> {
    const data = await this.get<{ query?: { search?: { title: string }[] } }>({
      action: "query",
      list: "search",
      srsearch: query,
      srlimit: "1",
    });
    return data.query?.search?.[0]?.title ?? null;
  }

  // Wikitext de la section infobox (section 0) d'une page — champs structurés
  // (dates, lieu, dotation), pas le texte libre qui resterait en anglais (règle
  // CLAUDE.md : textes visibles en français). Limite spécifique de 30s ici.
  async fetchInfoboxWikitext(pageTitle: string): Promise<string | null> {
    await this.wait(this.lastParseAt, 30_000);
    const data = await this.get<{ parse?: { wikitext?: { "*": string } } }>({
      action: "parse",
      page: pageTitle,
      prop: "wikitext",
      section: "0",
    });
    this.lastParseAt = Date.now();
    return data.parse?.wikitext?.["*"] ?? null;
  }
}
