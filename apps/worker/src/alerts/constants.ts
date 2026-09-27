export const ALERTS_QUEUE_NAME = "alerts";

// Seuils de supervision (docs/03 §10, docs/04 J7).
export const ALERTS_CHECK_INTERVAL_MS = 5 * 60 * 1000;
export const INGESTION_STALE_THRESHOLD_MS = 15 * 60 * 1000;
export const QUOTA_ALERT_THRESHOLD = 0.8;
export const PUSH_FAILURE_ALERT_THRESHOLD = 0.05;
