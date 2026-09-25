// Suit le quota PandaScore (1000 req/h partagées, règle 5 de CLAUDE.md) à partir
// des en-têtes de réponse, pour ralentir les jobs non prioritaires au-delà de 70 %.
export interface QuotaSnapshot {
  limit: number | null;
  remaining: number | null;
  used: number | null;
}

export class QuotaTracker {
  private snapshot: QuotaSnapshot = { limit: null, remaining: null, used: null };

  recordHeaders(headers: Headers): void {
    const limitHeader = headers.get("x-rate-limit-limit");
    const remaining = headers.get("x-rate-limit-remaining");
    const used = headers.get("x-rate-limit-used");
    const remainingNum = remaining != null ? Number(remaining) : this.snapshot.remaining;
    const usedNum = used != null ? Number(used) : this.snapshot.used;
    // PandaScore ne renvoie pas x-rate-limit-limit (vérifié le 2026-09-25, voir
    // tests-pandascore/rapport-pandascore.md) : on le déduit de used + remaining.
    const limit =
      limitHeader != null ? Number(limitHeader) : remainingNum != null && usedNum != null ? remainingNum + usedNum : this.snapshot.limit;
    this.snapshot = { limit, remaining: remainingNum, used: usedNum };
  }

  getSnapshot(): QuotaSnapshot {
    return this.snapshot;
  }

  // Ratio d'utilisation dans [0, 1], ou null si aucune donnée reçue encore.
  getUsageRatio(): number | null {
    const { limit, used } = this.snapshot;
    if (limit == null || used == null || limit <= 0) return null;
    return used / limit;
  }

  shouldThrottle(threshold = 0.7): boolean {
    const ratio = this.getUsageRatio();
    return ratio != null && ratio >= threshold;
  }
}
