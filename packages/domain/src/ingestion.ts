import { createHash } from "node:crypto";

// Représentation stable d'une valeur JSON (clés triées) pour que le hash ne bouge
// pas si l'ordre des champs change côté fournisseur sans changement de contenu.
function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value !== null && typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>).sort(([a], [b]) => a.localeCompare(b));
    return entries.reduce<Record<string, unknown>>((acc, [k, v]) => {
      acc[k] = canonicalize(v);
      return acc;
    }, {});
  }
  return value;
}

// Hash du contenu normalisé, utilisé pour l'upsert idempotent (règle 4 de CLAUDE.md).
export function computePayloadHash(payload: unknown): string {
  return createHash("sha256").update(JSON.stringify(canonicalize(payload))).digest("hex");
}

// Rien à écrire si le hash n'a pas changé depuis la dernière synchro.
export function shouldUpsert(existingHash: string | null | undefined, newHash: string): boolean {
  return existingHash !== newHash;
}

// Latence d'ingestion : écart entre la fin réelle d'un événement et le moment où
// le worker la détecte (point ouvert de docs/01, mesuré au J1).
export function computeIngestionLatencyMs(endAt: Date, detectedAt: Date): number {
  return detectedAt.getTime() - endAt.getTime();
}
