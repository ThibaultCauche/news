# News — guide pour Claude Code

Appli **mobile (Flutter) + backend (NestJS)** pour suivre les événements qui comptent pour soi — e-sport d'abord (Valorant), puis sport, politique, streams… — et **comprendre où on en est en 3 secondes**. Cible : le **néophyte curieux**, pas l'initié. Projet **open source, gratuit, non commercial**.

## À lire avant de coder

| Fichier | Quand le lire |
|---|---|
| `docs/04-jalons.md` | **Toujours** : jalon en cours, périmètre, critères d'acceptation |
| `docs/03-architecture-backend.md` | Référence technique, **fait foi** (modèle de données, ingestion, API, notifs, hébergement) |
| `docs/02-design-maquettes-mobiles.md` | Tout travail d'UI : écrans, tokens de couleur, règles de mouvement |
| `docs/01-donnees-sources-valorant.md` | Adaptateur PandaScore / Liquipedia, limites du plan gratuit |
| `docs/01b-donnees-elargissement-esport-sport.md` | Autres jeux e-sport, sport |
| `docs/01c-donnees-politique.md` | Open data Assemblée / Sénat / Légifrance / élections |
| `docs/00-vision-feuille-de-route.md` | Vision, principes produit, **journal des décisions** |

Ne lis que ce dont la tâche a besoin.

## État actuel

- **Jalon en cours : J3** (J2 fait le 2026-09-25). Mettre à jour cette ligne à chaque fin de jalon.
- **J1 fait** : monorepo pnpm (`apps/api`, `apps/worker`, `packages/domain`, `packages/db`, `packages/providers`), schéma Prisma, adaptateur PandaScore (ligues → séries → tournois → matchs), jobs BullMQ (catalogue/calendrier/live), upsert idempotent, quota et latence loggés. Vérifié en conditions réelles sur Champions 2026. **Brackets et classements (`event_link`/`standing`) pas encore alimentés, reportés au J5.**
- **J2 fait** : API `/v1` (`home`, `agenda`, `events/:id`, `competitions/:id`) + `/health`, cache Redis (15-60s) avec invalidation par Pub/Sub depuis le worker (`EventScheduled`/`EventStarted`/`EventFinished`/`ScoreChanged`), `ETag`/`304`, validation des entrées (`class-validator`), rate limiting (`@nestjs/throttler`), spec OpenAPI générée et client Dart généré dans `packages/api_client_dart` (gitignoré, régénéré par `pnpm generate:client`). Vérifié en conditions réelles sur Champions 2026 (7 tests e2e Supertest). **`event_moment`/`context_snippet` pas encore créées** (moments du direct, « pourquoi ce match compte ») : reportées après le J1, viendront au J6.
- Déjà présent dans le dépôt :
  - `tests-pandascore/` : scripts de test de l'API PandaScore et **réponses réelles** dans `samples/` et `samples-multijeux/`. Réutilisées comme **fixtures de tests** de l'adaptateur PandaScore.
  - `politique-quiz/` : extraction de l'open data de l'Assemblée (scrutins, députés) pour le prototype du jeu « Qui a voté ? ». `data/` est ignoré par Git (≈ 250 Mo, retéléchargeable).

## Stack

- **Backend** : NestJS (TypeScript strict), monorepo **pnpm**, deux points d'entrée `api` et `worker`.
- **Données** : PostgreSQL 16 + Redis 7, **Prisma** (tranché au J1), **BullMQ** pour les jobs.
- **API** : REST `/v1` pensée par écran, spec **OpenAPI** générée par NestJS → **client Dart généré**.
- **Mobile** : Flutter, Riverpod, cache local **drift**, `CustomPainter` pour l'arbre radial, `firebase_messaging`.
- **Push** : Firebase Cloud Messaging (APNs pour iOS).
- **Hébergement** : Docker Compose sur un NAS, exposé par Cloudflare Tunnel. GitHub Actions → GHCR.
- **Web (plus tard)** : Next.js.

## Structure cible

```
apps/api            NestJS — contrôleurs /v1, auth, cache, OpenAPI
apps/worker         NestJS — jobs BullMQ, ingestion, moteur de notifications
apps/mobile         Flutter (emplacement proposé, à confirmer au J3)
packages/domain     types et règles métier partagés (statuts, formats, calculs de bracket)
packages/db         schéma Prisma, migrations, client
packages/providers  un adaptateur par fournisseur (pandascore, liquipedia, …)
infra/              docker-compose.yml, cloudflared, scripts de sauvegarde
docs/               documentation du projet (source de vérité)
tests-pandascore/   prototypes et échantillons JSON réels
politique-quiz/     prototype open data Assemblée
```

## Règles non négociables

1. **L'appli ne parle jamais aux fournisseurs de données**, seulement à notre API.
2. **Secrets** dans `.env` (jamais commités, jamais affichés dans un log ou une réponse). Maintenir `.env.example` à jour.
3. **Modèle générique** `competition` / `event` / `entity` (+ `event_participant`, `event_link`, `standing`, `provider_ref`…). **Aucune table propre à un jeu ou à un sport.** Les vues se choisissent via `competition.format` + `structure`.
4. **Ingestion idempotente** : upsert via `provider_ref` + `payload_hash`. Si rien n'a changé, on n'écrit rien et on n'émet aucun événement métier.
5. **Quotas** : PandaScore gratuit = **1 000 req/h partagées entre tous les jeux**. Lire `x-rate-limit-remaining` / `x-rate-limit-used`, ralentir les jobs non prioritaires au-delà de 70 %. Le rythme rapide est réservé aux matchs **en direct qui ont des abonnés**.
6. **Limites du plan gratuit PandaScore** : pas de score en rounds par carte, pas de nom de carte, pas de stats joueurs (403). L'UI affiche le **score de série** (« 2-0 ») et le **gagnant de chaque carte**.
7. **Sources** : officielles et gratuites en priorité ; API non officielles (ESPN, LoL Esports) **uniquement en secours**, derrière le cache, avec une source officielle en repli ; **aucun scraping** (VLR.gg, SofaScore, FlashScore…).
8. **Attributions** : Liquipedia (CC-BY-SA) sous les contenus concernés et dans Réglages → Sources ; open data publique (Licence ouverte 2.0) avec la source affichée.
9. **Politique = neutralité stricte** : données officielles uniquement, noms officiels des groupes, phrases par gabarits (pas de texte généré librement), lien vers la source. **Recalculer la position d'un groupe à partir des voix** (le champ `positionMajoritaire` de l'open data AN n'est pas fiable).
10. **Sans spoil** : l'API renvoie les scores, **l'appli les masque** selon les réglages ; les **notifications appliquent le réglage côté serveur**.
11. **Client Dart généré** depuis OpenAPI : ne jamais écrire les modèles d'API à la main côté Flutter.
12. **Design** : couleurs et rayons uniquement via le fichier de thème (tokens de `docs/02`). Or `#FFC940` = mon équipe / mes suivis ; rouge `#FF4655` = en direct / « tu es ici » ; vert `#30D158` = victoire / qualifié. Catégories distinguées par l'icône, pas par la couleur.
13. **Mouvement** : pas d'animation sur ce qu'on voit plusieurs fois par jour ; entrées ease-out `cubic-bezier(0.23,1,0.32,1)` < 300 ms, `transform`/`opacity` uniquement ; respecter `MediaQuery.disableAnimations`.
14. **Garder le code simple** : pas d'abstraction non demandée. Mais ne pas retirer ce que `docs/03` prévoit explicitement (monorepo, adaptateurs, BullMQ, `provider_ref`…) sans me demander.

## Façon de travailler

- **Un jalon à la fois.** Avant de coder, proposer un plan court (fichiers, étapes, tests) et **attendre ma validation**.
- Textes visibles par l'utilisateur **en français** ; code, noms de tables et identifiants **en anglais** (comme dans `docs/03`).
- Tests : Jest côté NestJS (normalisation des adaptateurs testée sur les JSON de `tests-pandascore/samples*`), `flutter_test` côté appli.
- Commits courts au format conventionnel, en français : `feat(worker): adaptateur PandaScore`.
- **Fin de jalon** : cocher les critères dans `docs/04-jalons.md`, ajouter les décisions prises dans `docs/00-vision-feuille-de-route.md` (section 7), mettre à jour « État actuel » ci-dessus et la section « Commandes ».
- Si une info manque ou contredit les docs : **demander** plutôt que deviner.

## Commandes

```bash
# Installation
pnpm install

# Base et cache (dev)
docker compose -f infra/docker-compose.dev.yml up -d

# Migrations Prisma (lit .env à la racine)
pnpm db:migrate       # migration dev + génère le client
pnpm db:generate      # régénère juste le client Prisma

# Lancer l'API / le worker (chacun charge .env à la racine)
pnpm api:dev
pnpm worker:dev

# Tests et vérification de types, tous packages
pnpm -r test
pnpm -r lint

# Inspecter la base pendant le dev
pnpm --filter @news/db exec prisma studio

# Spec OpenAPI + client Dart généré (packages/api_client_dart, gitignoré)
pnpm generate:client       # openapi.json + client Dart + build_runner en un coup
pnpm generate:openapi      # juste la spec, dans openapi.json à la racine
```

`.env` doit contenir `PANDASCORE_TOKEN` (voir `.env.example`) pour que le worker ingère de vraies données. `pnpm generate:client` a besoin de Java (openapi-generator) et du SDK Dart.

## Maquettes (Figma)

- Fichier : https://www.figma.com/design/1GfSNwpyE1WoWEdUzT638L — 26 écrans V2 (iPhone 390×844, thème sombre, Inter).
- **Quota MCP Figma presque épuisé** (plan Starter, ~20 appels/mois) : **ne pas appeler le MCP Figma sans demande explicite.** S'appuyer sur `docs/02` et sur les captures dans `docs/maquettes/` (voir le README de ce dossier).

## Outils conseillés

- Plugin **Ponytail** (code minimal) dès le début ; **Graphify** à partir du J3 quand le code grossit.
- MCP **Context7** (docs à jour NestJS, Prisma, BullMQ, Riverpod, drift) et **MCP Dart/Flutter** (analyse, tests).
