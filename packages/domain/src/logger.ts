import pino from "pino";

// Logger structuré partagé (règle "Logs structurés (pino)" de docs/04 J1).
export function createLogger(name: string) {
  return pino({ name, level: process.env.LOG_LEVEL ?? "info" });
}
