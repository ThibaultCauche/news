# Étape 3 — Architecture & backend

> Session du 2026-09-25. Choix de départ : **NestJS (TypeScript)**, **auto-hébergé sur le NAS**. S'appuie sur `01-donnees-sources-valorant.md` (sources) et `02-design-maquettes-mobiles.md` (écrans). **Ce document fait foi pour le développement** ; le découpage en jalons est dans `04-jalons.md`.

## En bref

- **Un seul backend NestJS en monorepo, avec deux points d'entrée** : `api` (sert l'appli) et `worker` (va chercher les données et envoie les notifications). Même code, mêmes types, déployés séparément.
- **Modèle générique** : tout ce que l'appli montre est un *Événement* (match, vote, lancement, sortie, stream, keynote) rattaché à une *Compétition* (tournoi, saison, loi, programme) et à des *Entités* (équipe, joueur, parti, fusée…). Les liens vers les sources passent par une table `provider_ref`, ce qui permettra de changer de fournisseur sans toucher à l'appli.
- **Ingestion par adaptateurs** (PandaScore d'abord, Liquipedia en enrichissement), avec un rythme adapté : lent pour le catalogue, rapide seulement pour les matchs en cours **qui ont des abonnés**. Budget PandaScore estimé à moins de 400 requêtes par heure sur les 1 000 permises.
- **Temps réel en 2 temps** : pour le MVP, l'appli rafraîchit toutes les 15 à 30 s sur les écrans en direct, plus des notifications push. Plus tard : un flux SSE et des Live Activities.
- **Hébergement** : Docker Compose sur le NAS (API, worker, PostgreSQL, Redis, `cloudflared`), exposé par **Cloudflare Tunnel** sans ouvrir de port. Coût ≈ 0 €. Il y a un plan de sortie vers un VPS à ~5 €/mois, avec le même fichier Compose.
- **Seul coût obligatoire à prévoir** : le compte Apple Developer (99 $/an) pour publier sur iOS et envoyer des push.

## 1. Vue d'ensemble

```
                         ┌──────────────── Cloudflare ────────────────┐
  App Flutter  ──HTTPS──▶│ DNS api.<domaine> · cache court · Tunnel   │
  (iOS/Android)          └──────────────────────┬─────────────────────┘
      ▲                                         │ (aucun port ouvert)
      │ push                          ┌─────────▼──────── NAS (Docker Compose) ─────────────┐
      │                               │  cloudflared ──▶ api (NestJS, /v1, OpenAPI)          │
  FCM / APNs ◀──── envoi push ────────│                    │  lit                           │
                                      │                    ▼                                │
                                      │   PostgreSQL 16 ◀── worker (NestJS + BullMQ) ──────┼──▶ PandaScore
                                      │   Redis 7 (cache, files de jobs, verrous)           │──▶ Liquipedia
                                      │   sauvegardes (pg_dump + copie hors site)           │──▶ (autres sources)
                                      └─────────────────────────────────────────────────────┘
```

**Principes**
- L'appli ne parle **jamais** aux fournisseurs de données, seulement à notre API.
- La base de données est la source de vérité. Redis sert de cache et de file de jobs, et peut être vidé sans perte.
- Tout ce qui est lent ou externe passe par le worker. L'API ne fait que lire et répondre vite.

**Organisation du code (monorepo pnpm)**

| Dossier | Contenu |
|---|---|
| `apps/api` | Contrôleurs REST `/v1`, auth, cache, génération OpenAPI |
| `apps/worker` | Jobs planifiés (BullMQ), adaptateurs de fournisseurs, moteur de notifications |
| `packages/domain` | Types et règles métier partagés (statuts, formats de compétition, calculs de bracket) |
| `packages/db` | Schéma, migrations et client base de données (Prisma) |
| `packages/providers` | Adaptateurs : `pandascore`, `liquipedia`, puis un par nouvelle source |
| `infra/` | `docker-compose.yml`, config `cloudflared`, scripts de sauvegarde |

## 2. Modèle de données

### Tables principales

| Table | Rôle | Champs clés |
|---|---|---|
| `category` | E-sport, Sport, Politique, Élections, Espace… | `slug`, `name`, `icon` |
| `competition` | Tout ce qui a une structure : saison VCT, Champions, phase finale, Kickoff, Top 14, loi, programme de lancement | `parent_id` (hiérarchie), `category_id`, `kind`, `format`, `status`, `starts_at`, `ends_at`, `structure` (JSONB), `importance` |
| `entity` | Équipe, joueur, streamer, parti/groupe, fusée, studio… | `kind`, `name`, `short_name` (G2, PRX), `parent_id`, `region`, `image_url` |
| `event` | Le cœur : match, vote, lancement, sortie, stream, keynote | `competition_id`, `kind`, `status`, `starts_at`, `ends_at`, `best_of`, `result` (JSONB), `importance`, `spoiler_sensitive` |
| `event_participant` | Qui joue / qui est concerné | `event_id`, `entity_id`, `side`, `score`, `is_winner`, `seed` |
| `event_link` | Liens de bracket (« le vainqueur de A va en B ») | `from_event_id`, `to_event_id`, `outcome` (`winner` / `loser`), `slot` |
| `event_moment` | Fil du direct : carte gagnée, essai, annonce de keynote, étape d'une loi | `event_id`, `at`, `kind`, `payload` (JSONB), `is_key` |
| `standing` | Classements et groupes | `competition_id`, `entity_id`, `rank`, `wins`, `losses`, `lives_left` (triple élim.), `qualified` |
| `context_snippet` | « Pourquoi ce match compte », définitions du glossaire, textes de contexte | `target_type`, `target_id`, `kind`, `text`, `source`, `license`, `generated_by` |
| `provider_ref` | Lien avec les sources externes | `object_type`, `object_id`, `provider`, `external_id`, `last_synced_at`, `payload_hash` — unique (`provider`, `object_type`, `external_id`) |

**Utilisateurs**

| Table | Rôle |
|---|---|
| `app_user` | Compte **anonyme par défaut** (créé au premier lancement). Lien optionnel avec Apple / Google pour synchroniser plusieurs appareils |
| `device` | Jeton push FCM, plateforme, langue, fuseau horaire, jeton Live Activity si actif |
| `subscription` | Suivi : `target_type` (catégorie, compétition, entité, événement), `target_id`, `level` (tout / grands moments), options (début, résultat, rappel) |
| `user_setting` | Sans spoil par catégorie, heures calmes, résumé du matin, mouvement réduit |
| `notification_log` | Ce qui a été envoyé, avec une **clé de déduplication** (`user`, `event`, `type`) |
| `prediction` / `quiz_answer` | Jeu du jour (plus tard) |

### Formats de compétition (`competition.format`)

`single_elim` · `double_elim` · `triple_elim` · `groups_gsl` · `round_robin` · `swiss` · `league_table` (sport) · `law_process` · `launch` · `release_calendar` · `live_feed` (keynote, soirée électorale).

Le champ `structure` (JSONB) décrit la forme propre au format : rounds et slots d'un bracket, nombre de vies, étapes d'une loi, déroulé T–/T+ d'un lancement… L'appli choisit la vue à partir du format : **arbre radial** pour le tableau principal, **liste** pour le repêchage, **« 3 vies »** pour la triple élimination, **suivi façon colis** pour une loi.

### Statuts d'un événement

```
scheduled ──▶ live ──▶ finished
    │           │
    ├──▶ postponed ──▶ scheduled
    └──▶ cancelled
```
Chaque changement de statut produit un **événement métier** (voir §3), qui déclenche le cache, le temps réel et les notifications.

## 3. Ingestion des données

### Adaptateurs

Chaque source implémente la même interface :
```ts
interface Provider {
  listCompetitions(window): Promise<CompetitionDTO[]>;
  listEvents(window): Promise<EventDTO[]>;       // à venir / en cours / récents
  getEvent(externalId): Promise<EventDTO>;        // détail + participants + score
  getStructure?(competitionId): Promise<StructureDTO>; // brackets, standings
}
```
Le worker convertit les DTO dans le modèle générique, puis fait un **upsert** via `provider_ref`. On calcule un hash du contenu normalisé : si rien n'a changé, on n'écrit rien et on ne déclenche rien.

### Rythme de collecte (BullMQ, jobs répétés)

| Job | Fréquence | Coût PandaScore estimé |
|---|---|---|
| Catalogue (tournois, équipes, rosters) | toutes les 6 h | ~20 req / 6 h |
| Calendrier J-1 → J+14 | toutes les 10 min | ~20 req/h |
| Matchs en cours (`/matches/running`, un seul appel pour tous) | toutes les 30 s | 120 req/h |
| Détail d'un match suivi qui commence dans < 30 min ou qui est en direct | toutes les 30–60 s, **seulement s'il a des abonnés** | ~60–180 req/h selon l'affluence |
| Structure (brackets, standings) d'une compétition active | toutes les 5 min, plus à chaque fin de match | ~30 req/h |
| Enrichissement Liquipedia (contexte, formats) | file limitée à 1 req / 2 s et 1 parse / 30 s, cache ≥ 24 h | hors quota PandaScore |

**Total estimé : 250 à 400 req/h**, soit une bonne marge sous les 1 000 req/h du plan gratuit. Un compteur par fournisseur ralentit automatiquement les jobs non prioritaires au-delà de 70 % du quota.

### Événements métier

Quand l'ingestion détecte un changement, elle publie un événement dans une file Redis :
`EventScheduled`, `EventStartingSoon` (T-15 min, programmé à l'avance), `EventStarted`, `ScoreChanged`, `MomentAdded`, `EventFinished`, `BracketAdvanced` (le vainqueur ou le perdant rejoint le match suivant), `StandingChanged`, `CompetitionFinished`.

Trois consommateurs indépendants les lisent :
1. **Cache** : invalide les clés concernées (accueil, compétition, événement).
2. **Notifications** : voir §6.
3. **Contexte** : recalcule « pourquoi ce match compte » à partir du bracket (voir §7).

### Robustesse
- Nouvelles tentatives avec délai croissant et disjoncteur par fournisseur (on arrête d'appeler une source en panne pendant quelques minutes).
- Chaque réponse d'API indique `source_updated_at`. Si les données ont plus de 15 minutes pendant un direct, l'appli affiche « Mise à jour en attente » plutôt qu'un score faux.
- Les réponses brutes des fournisseurs sont gardées 7 jours (table `provider_payload`) pour déboguer.

## 4. API

**REST JSON versionnée (`/v1`)**. NestJS génère la spec OpenAPI, et un client Dart est **généré automatiquement** pour Flutter : pas de modèle à écrire deux fois.

Les endpoints suivent les écrans, pour que l'appli fasse un seul appel par écran :

| Endpoint | Écrans | Contenu |
|---|---|---|
| `GET /v1/home` | 17 Accueil | Maintenant pour toi, tes suivis avec leur état, grands rendez-vous, à découvrir |
| `GET /v1/agenda?from&to&category` | 09 Agenda | Événements par jour, statut, abonné ou non |
| `GET /v1/competitions/:id` | 01, 06, 14, 19 | En-tête, format, frise (sous-compétitions), standings, `structure` |
| `GET /v1/competitions/:id/bracket` | 02, 05, 07 | Nœuds (événements), liens gagnant/perdant, rounds et slots, indices de mise en page |
| `GET /v1/events/:id` | 03, 15, 24, 25, 26 | Participants, score, moments, contexte, forme récente, où regarder |
| `GET /v1/entities/:id` | 10 Fiche équipe | Chiffres clés, dernier et prochain événement |
| `GET /v1/explore`, `GET /v1/search?q` | 18 Explorer | Catégories, tendances, recherche |
| `GET /v1/glossary/:term` | 04 Feuille glossaire | Définition + exemple |
| `POST/DELETE /v1/subscriptions` | Partout (« Suivre ») | Abonnement / désabonnement |
| `PUT /v1/devices/me` | Au lancement | Jeton push, fuseau, langue |
| `GET/PATCH /v1/me/settings` | 22 Réglages | Sans spoil, heures calmes, résumé du matin |
| `POST /v1/predictions` | 16 Jeu | Pronostic, verrouillé au coup d'envoi |

**Sans spoil** : l'API renvoie les scores, et c'est l'appli qui les masque selon les réglages (le masquage est instantané, on peut révéler hors ligne). En revanche, **les notifications appliquent le réglage côté serveur** : sans spoil, la notification dit « G2 – PRX est terminé » sans le score.

**Cache**
- Les données publiques (compétitions, brackets, événements) sont mises en cache 15 à 60 s dans Redis, plus un en-tête `Cache-Control` court pour que Cloudflare absorbe les pics.
- `/v1/home` est personnalisé : on l'assemble à partir de blocs partagés en cache (événements du jour, grands rendez-vous) filtrés par les abonnements de l'utilisateur.
- `ETag` partout : pendant un direct, l'appli redemande souvent, et si rien n'a changé l'API répond `304` presque sans coût.

**Authentification**
- Au premier lancement, l'appli crée un compte anonyme et reçoit un JWT (courte durée) et un jeton de rafraîchissement. Aucune inscription n'est demandée.
- Plus tard, l'utilisateur peut se connecter avec Apple ou Google pour retrouver ses suivis sur un autre téléphone.
- Limitation de débit par appareil et par IP.

## 5. Temps réel

| Phase | Mécanisme | Pourquoi |
|---|---|---|
| **MVP** | Rafraîchissement toutes les 15 à 30 s **uniquement sur les écrans en direct**, avec `ETag`, plus les notifications push | Simple, robuste derrière le tunnel, presque gratuit grâce aux `304` |
| **V2** | Flux **SSE** `GET /v1/live/events/:id` (le serveur pousse les changements) | Traverse Cloudflare Tunnel sans difficulté, plus simple que WebSocket pour un flux dans un seul sens |
| **V2** | **Live Activities** iOS (écran 13) mises à jour par push via FCM | FCM gère l'envoi aux Live Activities. On limite à ~1 mise à jour par minute, sauf moments clés, pour respecter le budget d'iOS |

## 6. Notifications

```
événement métier ──▶ qui est concerné ? ──▶ réglages de chacun ──▶ déduplication ──▶ envoi FCM ──▶ journal
                     (abonnements directs      (heures calmes,         (clé user +       (par lots,     (+ suppression
                      et hiérarchiques)         sans spoil, sourdine)   event + type)     iOS via APNs)  des jetons invalides)
```

**Qui est prévenu ?**
- Abonné à **G2** : tous les matchs de G2 (rappel, début, résultat, qualification).
- Abonné à **Valorant** : seulement les grands moments (finales, champion couronné), sinon ce serait trop.
- Abonné à une **loi** : chaque changement d'étape.
- Tout le monde : le **résumé du matin** (8 h dans son fuseau), s'il est activé.

**Types de notification** : rappel T-15 min, début, résultat, qualification / élimination de ton équipe, étape d'une loi, lancement imminent, résumé du matin.

**Règles** : pas plus de 3 notifications par heure et par utilisateur, hors équipe suivie en direct. Les notifications non urgentes tombées pendant les heures calmes sont regroupées dans le résumé du matin.

**Prérequis iOS** : une clé APNs (compte Apple Developer, 99 $/an) déclarée dans Firebase. FCM est gratuit.

## 7. Contenu et contexte

- **« Pourquoi ce match compte »** est calculé **par des règles** à partir du bracket, pas écrit à la main. Exemple : on suit `event_link`, et si le vainqueur va en finale du haut et le perdant au repêchage, on remplit un modèle de phrase. C'est déterministe, gratuit et toujours juste.
- **Glossaire** : textes écrits une fois (BO3, repêchage, triple élimination…) et stockés dans `context_snippet`.
- **Politique** : uniquement des modèles de phrases neutres et des données officielles, avec la source affichée. Pas de texte généré librement tant que la charte de neutralité n'est pas écrite.
- **Plus tard** : génération assistée par IA pour les résumés, relue avant publication, et marquée `generated_by = 'ai'`.
- **Licences** : chaque texte garde sa `source` et sa `license`. L'appli affiche l'attribution Liquipedia (CC-BY-SA) là où son contenu est utilisé, et dans Réglages → Sources.

## 8. Hébergement sur le NAS

**`docker-compose.yml` (services)**

| Service | Image | RAM estimée |
|---|---|---|
| `api` | image Node 22 construite en CI | ~150–250 Mo |
| `worker` | même image, autre commande | ~150–250 Mo |
| `postgres` | `postgres:16` | ~200–400 Mo |
| `redis` | `redis:7` (persistance AOF) | ~50–100 Mo |
| `cloudflared` | `cloudflare/cloudflared` | ~30 Mo |
| `backup` | cron `pg_dump` + `restic` | faible |
| (option) `uptime-kuma` | supervision | ~100 Mo |

**Total ≈ 0,7 à 1,2 Go de RAM.**

**Exposition** : Cloudflare Tunnel, gratuit, sans aucun port ouvert sur la box. Il gère WebSocket et SSE. Seul `api.<domaine>` est exposé. Une éventuelle interface d'administration passe derrière Cloudflare Access (connexion obligatoire).

**Déploiement** : GitHub Actions construit l'image à chaque push sur `main` et la publie sur GitHub Container Registry. Sur le NAS, `docker compose pull && docker compose up -d` (à la main au début, automatisable ensuite). Les migrations de base tournent au démarrage de l'API.

**Sauvegardes (règle 3-2-1)** : `pg_dump` chaque nuit, 7 jours gardés sur le NAS, plus une copie chiffrée hors site (disque externe ou stockage objet à quelques centimes par mois). **Tester une restauration une fois par mois.**

**Risques propres au NAS et parades**

| Risque | Conséquence | Parade |
|---|---|---|
| Coupure de courant ou d'internet à la maison | API injoignable, push non envoyés | L'appli garde un **cache local** (elle reste utilisable hors ligne avec les dernières données) + alerte de supervision externe |
| NAS saturé par d'autres usages | Lenteurs pendant un direct | Limites CPU/RAM par conteneur dans Compose |
| Croissance (> quelques milliers d'utilisateurs actifs) ou exigence de disponibilité | — | **Plan de sortie** : même Compose sur un VPS (~5 €/mois), restauration du dump, on repointe le tunnel. Environ 1 h de bascule |

## 9. Sécurité et vie privée

- Les secrets (jeton PandaScore, clés Firebase, JWT) sont dans un `.env` hors Git, et ne quittent jamais le serveur.
- **Données minimales** : compte anonyme, pas d'e-mail obligatoire. On ne stocke que les jetons d'appareil, les abonnements et les réglages.
- **RGPD** : endpoint de suppression de compte (`DELETE /v1/me`), politique de confidentialité, pas de traceur publicitaire.
- Limitation de débit, validation stricte des entrées (DTO + `class-validator`), en-têtes de sécurité, CORS fermé (l'appli mobile n'en a pas besoin).
- Mises à jour des images Docker suivies avec Dependabot/Renovate.

## 10. Observabilité

- Logs structurés (pino) avec un identifiant de requête.
- `GET /health` (API, base, Redis) et un **tableau de bord des fournisseurs** : requêtes par heure face au quota, dernière synchro réussie, erreurs.
- **Alertes** : ingestion arrêtée depuis plus de 15 min, quota au-delà de 80 %, échecs d'envoi push au-delà de 5 %.
- Suivi des erreurs avec Sentry (offre gratuite), côté API et côté appli.

## 11. Côté appli Flutter

- **Couches** : `data` (client API généré + cache local **drift**), `domain`, `ui`. **Riverpod** pour l'état.
- **Hors ligne d'abord** : l'appli affiche le cache immédiatement, puis rafraîchit.
- **Vues par format** : un widget par `competition.format`, dont l'arbre radial en `CustomPainter`, le repêchage en liste, les « 3 vies » et le suivi de loi.
- **Design system** : les tokens de la V2 (couleurs, rayons, typo, courbes d'animation) dans un seul fichier de thème. Mouvement réduit via `MediaQuery.disableAnimations`.
- Push : `firebase_messaging`. Live Activities : extension iOS native, en V2.

## 12. Ajouter une catégorie

1. Étudier la source (comme l'étape 1) : contenu, prix, licence, limites.
2. Écrire un adaptateur dans `packages/providers`.
3. Si besoin, ajouter un `format` et sa vue dans l'appli.
4. Ajouter les modèles de notification et le glossaire.

Le reste (accueil, agenda, abonnements, notifications, cache) fonctionne sans modification. Sources par catégorie : voir `01b` (e-sport, sport) et `01c` (politique).

## 13. Plan de mise en œuvre

Détaillé, avec critères d'acceptation, dans **`04-jalons.md`** (J1 → J7).

## Décisions de cette étape

- NestJS en monorepo avec deux points d'entrée (`api`, `worker`), PostgreSQL + Redis, BullMQ pour les jobs.
- Modèle générique Événement / Compétition / Entité, `provider_ref` pour les sources, `format` + `structure` pour les vues.
- REST `/v1` pensé par écran, client Dart généré depuis OpenAPI.
- Temps réel : rafraîchissement avec `ETag` pour le MVP, SSE et Live Activities ensuite.
- Hébergement sur le NAS via Docker Compose + Cloudflare Tunnel, avec un plan de sortie vers un VPS.
- Compte anonyme par défaut, connexion Apple/Google optionnelle.

## Points ouverts

- Brackets et standings PandaScore accessibles en gratuit : **confirmé** (2026-09-25).
- Prisma ou Drizzle pour l'accès aux données. Prisma est proposé pour sa prise en main ; à trancher au J1.
- Nom de domaine de l'appli (nécessaire pour le tunnel et les liens).
- Création du compte Apple Developer (99 $/an) avant les tests de push iOS.
- Nom de l'appli (« News » est un nom de travail).

## Sources

- [Firebase — Live Activity avec FCM](https://firebase.google.com/docs/cloud-messaging/customize-messages/live-activity)
- [Cloudflare Tunnel — documentation](https://developers.cloudflare.com/tunnel/)
- [Cloudflare — WebSockets](https://developers.cloudflare.com/network/websockets/)
- [Cloudflare Community — limite d'upload de 100 Mo via le tunnel](https://community.cloudflare.com/t/100mb-tunnel-limit/901339)
- Sources de données : voir `01-donnees-sources-valorant.md`
