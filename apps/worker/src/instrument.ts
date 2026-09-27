import * as Sentry from "@sentry/node";

// Doit être importé avant tout le reste (docs/03 §10, J7). Pas de compte
// Sentry tant que SENTRY_DSN est vide : le SDK reste alors inactif plutôt que
// de bloquer le démarrage.
if (process.env.SENTRY_DSN) Sentry.init({ dsn: process.env.SENTRY_DSN });
