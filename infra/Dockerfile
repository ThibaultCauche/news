# Image unique pour `api` et `worker` (docs/03 §8) : seule la commande change
# entre les deux services de infra/docker-compose.yml.
# ponytail: pas de multi-stage (node_modules complet, y compris devDependencies,
# reste dans l'image) — repasser en multi-stage si la taille devient un problème réel.
FROM node:22-slim

WORKDIR /app
RUN corepack enable
# Requis par le moteur Prisma (sinon "failed to detect the libssl/openssl version" au build et à l'exécution).
RUN apt-get update && apt-get install -y --no-install-recommends openssl && rm -rf /var/lib/apt/lists/*

COPY pnpm-workspace.yaml pnpm-lock.yaml package.json ./
COPY apps/api/package.json apps/api/package.json
COPY apps/worker/package.json apps/worker/package.json
COPY packages/domain/package.json packages/domain/package.json
COPY packages/db/package.json packages/db/package.json
COPY packages/providers/package.json packages/providers/package.json
RUN pnpm install --frozen-lockfile

COPY tsconfig.base.json ./
COPY apps/api apps/api
COPY apps/worker apps/worker
COPY packages/domain packages/domain
COPY packages/db packages/db
COPY packages/providers packages/providers
RUN pnpm -r build

ENV NODE_ENV=production
COPY infra/docker-entrypoint-api.sh /usr/local/bin/docker-entrypoint-api.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-api.sh

# La commande réelle (api ou worker) est fixée par infra/docker-compose.yml.
CMD ["node", "apps/worker/dist/main.js"]
