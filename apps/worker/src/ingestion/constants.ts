export const QUEUE_NAME = "ingestion";

// Rythmes de collecte (docs/03 §3) : catalogue lent, calendrier modéré,
// matchs en direct rapides — un seul appel PandaScore pour ces derniers.
export const JOB_INTERVALS_MS: Record<"catalogue" | "calendar" | "live", number> = {
  catalogue: 6 * 60 * 60 * 1000,
  calendar: 10 * 60 * 1000,
  live: 30 * 1000,
};
