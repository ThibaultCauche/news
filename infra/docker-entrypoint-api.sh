#!/bin/sh
set -eu

# "Les migrations de base tournent au démarrage de l'API" (docs/03 §8).
pnpm --filter @news/db exec prisma migrate deploy
exec node apps/api/dist/main.js
