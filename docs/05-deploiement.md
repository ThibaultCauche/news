# Étape 5 — Déploiement (J7)

> Ce que le code prépare (image Docker, Compose de prod, CI/CD, sauvegardes, alertes, Sentry) est dans le dépôt. Ce document est le reste : les actions manuelles, à faire une fois, pour que tout tourne réellement sur le NAS. Référence : `docs/03-architecture-backend.md` §8–10, `docs/04-jalons.md` J7.

## 1. Prérequis (comptes et matériel)

- Le NAS, avec Docker et Docker Compose installés, accessible en SSH — et déjà membre du tailnet (Tailscale), comme pour les autres applis qui y tournent.
- Un compte GitHub avec ce dépôt : GHCR (GitHub Container Registry) est activé par défaut, aucune inscription séparée.
- Un compte Sentry gratuit (facultatif mais recommandé) : [sentry.io](https://sentry.io).
- Pour la bêta Android : un compte développeur Google Play (déjà payé — le retrouver dans [play.google.com/console](https://play.google.com/console), sinon chercher le reçu du frais de 25 $ dans les e-mails ou l'historique [pay.google.com](https://pay.google.com)).

## 2. Construire l'image et la publier sur GHCR

Automatisé par `.github/workflows/publish.yml` : à chaque push sur `main`, l'image est construite depuis `infra/Dockerfile` et publiée sur `ghcr.io/<compte-github>/news:latest`.

Par défaut, l'image publiée est **privée**. Pour que le NAS puisse la tirer (`docker compose pull`) :
- soit la rendre publique (Settings du package sur GitHub, une fois),
- soit créer un **jeton d'accès personnel** (scope `read:packages`) et faire `docker login ghcr.io -u <compte> -p <jeton>` sur le NAS.

## 3. Exposer l'API avec Tailscale Funnel

Décision du J7 (`docs/00` §7) : le NAS expose déjà d'autres applis via Tailscale, donc l'API suit la même voie plutôt que Cloudflare Tunnel envisagé dans `docs/03` au départ. Contrepartie acceptée : l'URL publique est `https://<machine>.<tailnet>.ts.net`, pas un nom de domaine personnalisé (`api.thibaultcauche.com` n'est pas utilisable ici — Funnel ne prend pas de domaine externe).

**Cas réel de ce déploiement** : les 3 ports Funnel possibles (443, 8443, 10000) sont déjà pris par d'autres services du NAS. Le port 443 sert déjà plusieurs applis sous des chemins différents (`/jam`, `/shares`, `/avatars`, `/download-worker`) — l'API News suit le même principe, montée sous `/news` plutôt que sur un port dédié. Le conteneur Tailscale (`ix-tailscale-tailscale-1`) tourne en réseau `host`, donc il voit directement `127.0.0.1:3000` publié par le service `api`.

Sur l'hôte du NAS (dans le conteneur Tailscale, pas dans Docker Compose du dépôt) :

```bash
docker exec ix-tailscale-tailscale-1 tailscale serve --bg --set-path=/news http://127.0.0.1:3000
```

Tailscale ne retire pas le préfixe `/news` avant de relayer vers `127.0.0.1:3000` (comportement observé sur les chemins déjà en place, `/jam` proxie vers `.../jam`) : l'API doit donc répondre elle-même sous `/news/...`. C'est le rôle de `PUBLIC_PATH_PREFIX=news` dans `.env` (étape 4) — sans lui, l'API répondrait à la racine et 404 sur tout ce qui arrive préfixé.

**Vérifier après coup** (étape 5) : `curl https://truenas-scale.tailc07204.ts.net/news/health`. Si ça 404 malgré tout, c'est que Tailscale a en fait retiré le préfixe avant de relayer (comportement inverse à celui observé sur `/jam`/`/shares`) — retirer `PUBLIC_PATH_PREFIX` du `.env` et redémarrer `api` réglerait ça.

**Si un vrai domaine devient nécessaire plus tard** (par exemple pour un usage plus large que la bêta entre amis) : ajouter Cloudflare (ou tout reverse proxy) devant l'URL `.ts.net`, ou repasser à Cloudflare Tunnel — l'un ou l'autre n'exige de changer que cette étape, le reste (Compose, appli) ne bouge pas.

## 4. Préparer `.env` sur le NAS

Copier `.env.example` en `.env` sur le NAS et remplir, en plus des secrets déjà utilisés en dev :
- `POSTGRES_PASSWORD` (nouveau mot de passe, différent du `news`/`news` de dev).
- `IMAGE=ghcr.io/<compte-github>/news` (sinon l'image est reconstruite localement plutôt que tirée de GHCR).
- `SENTRY_DSN` si un projet Sentry a été créé (un pour l'API/le worker Node, un pour l'appli Flutter).
- `ALERT_WEBHOOK_URL` : une URL `https://ntfy.sh/<sujet-privé-choisi>` suffit (aucune inscription), ou un webhook Discord/Slack.
- `PUBLIC_PATH_PREFIX=news` si l'API est montée sous un chemin plutôt qu'un port dédié (cas réel de ce déploiement, voir étape 3) ; laisser vide sinon.

**Ne jamais commiter ce fichier.**

## 5. Premier démarrage

Depuis la racine du dépôt, sur le NAS :

```bash
docker compose -f infra/docker-compose.yml pull   # si IMAGE pointe vers GHCR
docker compose -f infra/docker-compose.yml up -d
docker compose -f infra/docker-compose.yml logs -f api worker
```

(la commande `tailscale serve` de l'étape 3 est à lancer une fois, séparément — elle ne dépend pas de Compose.)

Les migrations Prisma tournent automatiquement au démarrage du service `api` (`infra/docker-entrypoint-api.sh`). Vérifier `https://<machine>.<tailnet>.ts.net/news/health` (ou `/health` si `PUBLIC_PATH_PREFIX` est vide) → `{"status":"ok"}`.

## 6. Sauvegardes

Le service `backup` (`infra/backup/`) fait un `pg_dump` chaque nuit à 3h, gardé 7 jours dans le volume `backup-data`. **Pas de copie hors site pour l'instant** (aucune destination choisie, voir `docs/04-jalons.md` J7 — à ajouter dans `infra/backup/backup.sh` une fois une destination décidée : disque externe ailleurs, Backblaze B2, etc.).

**Tester une restauration** (à faire une fois, puis une fois par mois) :

```bash
docker compose -f infra/docker-compose.yml exec backup ls /backups
docker compose -f infra/docker-compose.yml exec backup restore.sh /backups/news-<date>.sql.gz
```

⚠️ `restore.sh` écrase la base cible avec le contenu du dump — ne jamais le lancer contre la base de prod pour "tester", seulement contre une base de secours ou juste après une vraie panne.

## 7. Bêta Android

1. Retrouver/ouvrir le compte développeur Google Play (étape 1) et créer l'application.
2. Piste de test **interne** (jusqu'à 100 testeurs, pas de revue longue) : Release → Testing → Internal testing.
3. `flutter build appbundle --dart-define=API_BASE_URL=https://<machine>.<tailnet>.ts.net/news` dans `apps/mobile` (inclure `/news` si `PUBLIC_PATH_PREFIX` est utilisé, étape 3 ; sans `--dart-define`, l'appli pointe vers `localhost`, inutilisable pour un·e testeur·se externe) — uploader le `.aab`.
4. Ajouter les e-mails des testeurs, partager le lien d'inscription.

iOS reste reporté après la sortie de l'appli (décision du J4, `docs/00` §7).

## 8. Vérifier les critères d'acceptation J7

- [ ] Couper le Wi-Fi du téléphone d'un·e testeur·se (hors réseau de la maison) → l'appli fonctionne normalement.
- [ ] Simuler une coupure du NAS (`docker compose -f infra/docker-compose.yml stop`) → l'appli reste utilisable hors ligne (cache local) et l'alerte `ALERT_WEBHOOK_URL` arrive après 15 min (ingestion arrêtée).
- [ ] Restauration testée (étape 6).

## Licence

Point ouvert explicitement reporté lors du J7 (voir `docs/04-jalons.md`, section « Points ouverts ») : la licence open source du dépôt reste à trancher.
