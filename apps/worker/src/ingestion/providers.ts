import { Provider } from "@news/domain";
import { QuotaTracker } from "@news/providers";

export const INGESTION_PROVIDERS = "INGESTION_PROVIDERS";

// Un fournisseur de données avec son suivi de quota (règle 5 de CLAUDE.md).
export type IngestionProvider = Provider & { quota: QuotaTracker };

// Fournisseurs actifs, par nom (`provider_ref.provider`). Un fournisseur sans clé d'API n'y figure pas.
export type IngestionProviders = Record<string, IngestionProvider>;
