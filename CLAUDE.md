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
| `docs/05-deploiement.md` | Mise en ligne : actions manuelles sur le NAS (J7 et après) |

Ne lis que ce dont la tâche a besoin.

## État actuel

- **Aucun jalon en cours** (J12 fait le 2026-10-01, prochain : à décider ; candidats déjà cadrés : J13 forum par match, guide d'explications des compétitions). Le démarrage du prochain jalon se décide dans une discussion dédiée (`/jalon <numéro>`). Mettre à jour cette ligne à chaque fin de jalon.
- **J1 fait** : monorepo pnpm (`apps/api`, `apps/worker`, `packages/domain`, `packages/db`, `packages/providers`), schéma Prisma, adaptateur PandaScore (ligues → séries → tournois → matchs), jobs BullMQ (catalogue/calendrier/live), upsert idempotent, quota et latence loggés. Vérifié en conditions réelles sur Champions 2026. **Brackets et classements (`event_link`/`standing`) pas encore alimentés, reportés au J5.**
- **J2 fait** : API `/v1` (`home`, `agenda`, `events/:id`, `competitions/:id`) + `/health`, cache Redis (15-60s) avec invalidation par Pub/Sub depuis le worker (`EventScheduled`/`EventStarted`/`EventFinished`/`ScoreChanged`), `ETag`/`304`, validation des entrées (`class-validator`), rate limiting (`@nestjs/throttler`), spec OpenAPI générée et client Dart généré dans `packages/api_client_dart` (gitignoré, régénéré par `pnpm generate:client`). Vérifié en conditions réelles sur Champions 2026 (7 tests e2e Supertest). **`event_moment`/`context_snippet` pas encore créées** (moments du direct, « pourquoi ce match compte ») : reportées après le J1, viendront au J6.
- **J3 fait** : appli Flutter dans `apps/mobile` (Android/iOS, pas de plateforme web dans le projet Flutter, cf. `docs/00` §7), thème V2 (tokens couleurs/rayons/typo Inter), Riverpod + client généré + cache local **drift**, un seul intercepteur Dio pour `ETag`/`304` et le repli hors ligne. Écrans **17 Accueil**, **09 Agenda**, **01 Saison Valorant**, **03 Prochain match** + tab bar en verre flottante. Vérifié en conditions réelles (vraies données Champions 2026) dans le navigateur et sur un téléphone Android physique (`adb reverse tcp:3000 tcp:3000`). Mode avion et mouvement réduit vérifiés (dont un test automatisé, `live_dot_test.dart`). Petit ajout d'API : `parentId` sur `CompetitionResponseDto` pour permettre à l'appli de remonter jusqu'à la ligue racine (nécessaire pour la frise de saison). **Sans abonnements** (comptes = J4) : pas de « Tes suivis » ni « À découvrir » sur l'Accueil ; boutons « M'alerter »/« sans spoil » visuels seulement ; **fidélité pixel-perfect aux maquettes reportée** à une passe dédiée.
- **J4 fait** : compte anonyme (JWT + refresh, sans inscription — **remplacé par Firebase Auth au J11**), tables `app_user`/`device`/`subscription`/`user_setting`/`notification_log`, endpoints `POST /v1/auth/anonymous`, `POST /v1/auth/refresh`, `PUT /v1/devices/me`, `POST/DELETE/GET /v1/subscriptions` (le `GET` est un ajout, nécessaire à l'écran Suivis), `GET/PATCH /v1/me/settings`, `DELETE /v1/me` (RGPD), `/v1/home` personnalisé (« Maintenant pour toi », « Tes suivis », bandeau « à suivre » de repli). Moteur de notifications dans le worker (`apps/worker/src/notifications`) : job T-15 (`EventStartingSoon`), abonnements directs et hiérarchiques, heures calmes, sans spoil côté serveur, déduplication (contrainte unique `user`+`event`+`type`), plafond 3/h hors suivi direct, nettoyage des jetons FCM invalides, envoi via `firebase-admin`. Côté appli : bouton « Suivre »/« M'alerter » partout, écran Suivis, permission de notification demandée au premier suivi, tap sur une notification → écran du match. **Vérifié en conditions réelles** sur un téléphone Android physique avec un vrai projet Firebase : compte créé, abonnements réels, rappel/début/résultat reçus, texte sans spoil confirmé. **iOS reporté après la sortie de l'appli** (décision produit). **Qualification/élimination reportée au J5** (dépend du bracket).
- **J5 fait** : `event_link` construit depuis `previous_matches` (`/tournaments/:id/brackets`), format de bracket détecté par mots-clés dans les noms de match (pas de champ direct côté PandaScore), classements entièrement recalculés depuis nos propres `event`/`event_participant` (`computeStandings`, `packages/domain`, un seul `maxLives` pour simple/double/triple élim et poules GSL). Job worker « structure » (5 min + à chaque fin de match), `GET /v1/competitions/:id/bracket`. Appli : écran à onglets Groupes/Phase finale/Repêchage (`apps/mobile/lib/features/bracket`), premier `CustomPainter` du projet pour l'arbre radial, écran « 3 vies » du Kickoff. Type de notification « qualification/élimination » (reporté du J4) câblé : `notification_log` a désormais deux clés de déduplication, une par match (`userId`+`eventId`+`type`) et une par entité (`userId`+`entityId`+`type`). Point d'entrée vers la page Valorant ajouté sur l'Accueil (absent depuis le J3, aucune page de la saison/du bracket n'était atteignable). **Vérifié en conditions réelles** sur un téléphone Android physique avec les vraies données Champions 2026 (deux bugs d'affichage trouvés et corrigés au passage). **Fidélité visuelle exacte à la maquette reportée** (comme au J3) ; **remplissage de l'arbre à la fin d'un vrai match** et **fluidité 60 i/s** à revérifier en conditions réelles plus tard (playoffs pas encore commencés, pas de profilage fait).
- **J6 fait** : adaptateur **Liquipedia** minimal (recherche + infobox structurée uniquement — jamais le texte libre, resterait en anglais), phrase de contexte par gabarit sur la compétition **parente** d'une étape à bracket (pas l'étape elle-même, son nom est trop générique pour la recherche). « Pourquoi ce match compte » (`packages/domain/context.ts`) calculé par règles à partir du bracket, filtré aux formats à élimination (une poule GSL n'a pas de grande finale malgré un `event_link` de type "loser"). Glossaire (7 termes) écrit à la main dans `context_snippet` (`pnpm db:seed`). Nouveaux endpoints `GET /v1/entities/:id` et `GET /v1/entities/by-short-name/:shortName` (fiche équipe écran 10, suggestions d'équipes de l'onboarding). Appli : glossaire tactile, forme récente/face-à-face, sans spoil réglé côté compte (global, appui long pour révéler un match terminé, masqué aussi dans les listes), onboarding (écrans 11-12), écran Réglages (22). **Vérifié en conditions réelles** sur téléphone Android physique avec les vraies données Champions 2026 ; deux bugs réels trouvés et corrigés en route (phrase d'enjeu fausse sur une poule GSL, recherche Liquipedia sur un nom de compétition trop générique) plus un bug de session (jeton expiré sans filet de secours, `AuthInterceptor` recrée maintenant un compte anonyme à la volée). **Test utilisateur avec 2-3 personnes externes reporté** (seul le compte du projet a testé). **Reportés** : granularité du sans spoil par catégorie, envoi du résumé du matin, roster/détail par carte de la fiche équipe, logos des équipes.
- **J7 fait** : image Docker unique pour `api`/`worker`, `infra/docker-compose.yml` de prod (limites CPU/RAM, healthcheck Postgres), CI GitHub Actions (lint/tests contre un vrai Postgres/Redis de CI, génération du client Dart, `flutter analyze`/`test`) et publication GHCR automatique. **Tailscale Funnel plutôt que Cloudflare Tunnel** (décision du J7, `docs/00` §7 : le NAS expose déjà d'autres applis ainsi) — l'API est montée sous `/news` sur le port 443 partagé, sans nom de domaine dédié. Sauvegardes `pg_dump` nocturnes (7 jours, pas de copie hors site pour l'instant) et alerte de supervision dans le worker (ingestion arrêtée, quota, échecs push) sur webhook texte, complétée par un moniteur externe (UptimeRobot) pour détecter une coupure totale du NAS — le worker qui porte l'alerte s'arrête aussi dans ce cas. Sentry configuré côté API et worker. **Les 3 critères vérifiés en conditions réelles sur le vrai NAS** : appli fonctionnelle hors du réseau de la maison, coupure NAS simulée (hors ligne + alerte reçue), restauration d'une sauvegarde réussie (recomptage identique avant/après). Deux bugs réels trouvés en cours de route : fausse alerte "ingestion arrêtée" quand PandaScore n'a simplement rien de nouveau (battement dédié ajouté, distinct de `provider_ref.last_synced_at`) ; repli hors ligne de l'appli qui ne se déclenchait pas sur un 502 renvoyé par Tailscale Funnel quand l'API est morte (seule une coupure réseau pure était traitée). Un troisième bug, plus ancien (J2), trouvé en revérifiant après 18h d'ingestion continue : les « grands rendez-vous » de l'accueil pouvaient se faire envahir par de vieux matchs terminés faute d'exclure le statut `finished`. **Reportés** : distribution bêta Google Play (compte retrouvé, pas encore publiée), copie de sauvegarde hors site (aucune destination choisie), licence open source, nom de domaine dédié (pas nécessaire avec Tailscale Funnel pour l'instant), nom de l'appli, logo/icône définitifs, écrire à PandaScore pour l'attribution.
- **J8 fait** (jalon de polissage UI/UX, ajouté après des retours utilisateur sur l'appli en test) : bouton « Suivre » à retour optimiste (`FollowsProvider`, `apps/mobile`, passé de `FutureProvider` à `AsyncNotifier` — seul moyen de modifier `state` de l'extérieur dans la version de Riverpod du projet) ; `SafeArea` ajoutée sur l'Accueil (la date chevauchait la barre de statut) et pastille active de la tab bar recentrée (marge fixe plutôt que largeur fixe, qui collait au bord arrondi du 1ᵉʳ/dernier onglet) ; Agenda navigable ±14 jours (fenêtre de requête fixe, flèches sur le bandeau de semaine) ; écran Suivis avec logo d'équipe (`Entity.imageUrl`, ingéré depuis le J1 mais jamais exposé avant) et statut qualifié/éliminé (recalculé depuis `Standing`, table du J5) sur `FollowStateDto` ; phrase d'enjeu fixe pour les poules GSL dans l'Agenda (`buildGroupStakes`, `packages/domain/context.ts`, nouvelle constante partagée `GSL_QUALIFIED_COUNT`). **Vérifié en conditions réelles sur téléphone Android physique** pour 4 des 5 correctifs : un vrai bug de débordement trouvé sur l'écran du téléphone (360 de large logique, les flèches de l'Agenda + les 7 pastilles de jour ne tenaient pas) et corrigé. Le logo/statut de l'écran Suivis reste vérifié par tests automatisés seulement (e2e API + widget Flutter) : l'appli ne permet pas encore d'atteindre la fiche d'une équipe suivie autrement que par un match affichant ses participants (lacune préexistante, pas causée par ce jalon).
- **J9 fait** : 5ᵉ onglet « Compétitions » (cercle or, recherche jeux/ligues/séries côté appli, Favoris, catégories en accordéon), page jeu à 3 onglets (Compétitions/Équipes/Agenda). `competition.game` (slug) et `competition.image_url` (logo de ligue), table `favorite_game` (raccourci, **sans notification**, distincte de `subscription` hiérarchique), endpoints `GET /v1/catalog`, `GET/PUT/DELETE /v1/favorites/games`, `GET /v1/entities?game=`. Logo de jeu = SVG embarqué `apps/mobile/assets/games/<slug>.svg` (Valorant seulement), logo de ligue via PandaScore sur pastille claire. **Vérifié en conditions réelles sur téléphone Android physique.** **Reportés** : golden de la tab bar à régénérer en CI, page dédiée à la ligue (VCT).
- **J10 fait** (polissage devenu large, à force d'essais sur téléphone) : **cartes de match unifiées** (`EventCard` + `widgets/match_visuals.dart` : dégradé direct sans bande grise, logos, `TeamBadge`), cloche « M'alerter » sur les matchs à venir, couronne du vainqueur (masquée sans spoil), compte à rebours HH:MM:SS à la place du « VS » sous 24 h (deux-points clignotants, fixes en mouvement réduit). Accueil : « À suivre » et bandeau en direct sur `EventCard` (« Ensuite » seulement si le match est aujourd'hui), carte de **grande finale** dédiée (`GET /v1/home` renvoie `grandFinals`, 7 prochains jours), « Tes suivis » retiré. Suivis sans « x » (le nom mène à la page). **Page de ligue** + onglet **Ligues** de la page jeu (`CatalogLeagueDto.live`, point rouge). **Familles de compétitions** (`competition_family`, `competition.family_id`, `familyNameOf` dans `packages/domain`, « Masters » regroupé) et abonnement `competition_family` ; **sourdine** `subscription.muted`, **la règle la plus proche du match l'emporte** (`nearestCompetitionRule`) ; fenêtre de choix sur « Suivre » d'une page de ligue, « Suivi via VCT » sur les pages compétition. **Ordre stable des équipes** : `event_participant.side` écrit à l'ingestion, l'API trie par `side`. **`AutoRefresh`** (`apps/mobile/lib/core`) : rechargement chaque minute au premier plan, au retour au premier plan et au changement d'onglet ; `todayProvider` (date du jour). **Sans spoil désactivé par défaut** pour les nouveaux comptes. **Vérifié en conditions réelles** sur téléphone Android physique (dont une nuit d'appli ouverte). **Abandonné** : fidélité pixel-perfect aux maquettes. **Reportés** : guide d'explications des compétitions, fluidité de l'arbre à 60 i/s (playoffs pas commencés).
- **J11 fait** (couche communautaire optionnelle) : **« inscription possible » remplace « pas d'inscription » du J4**. Compte **Firebase Auth e-mail + mot de passe** échangé contre nos JWT (`POST /v1/auth/firebase`, `AuthService.loginWithFirebase`, `FirebaseAuthService` en import dynamique : `firebase-admin` tire `jose` en ESM, que Jest ne charge pas). **Invité en lecture seule** (ni compte ni jeton) ; suivre, alerter, favoris, réglages et pronostics exigent un compte (`ensureAccount`, `signedInProvider`). Comptes anonymes du J4 supprimés (migration `j11`). Pseudo unique (`pseudo_key`), e-mail vérifié exigé, un changement par 30 jours, liste de mots interdits minimale. Tables `prediction`, `friend_group`, `friend_group_member`, colonnes `app_user.firebase_uid`/`email_verified`/`pseudo`/`pseudo_key`/`avatar_entity_id`. Endpoints `GET/PUT /v1/me/profile`, `GET /v1/users/:id/profile` (groupe commun seulement), `GET/PUT /v1/predictions`, `/v1/groups` (créer, rejoindre par code de 8 caractères, classement, quitter, supprimer). Barème **3 points + 2 pour le score de série exact**, règlement idempotent par le worker (`PredictionSettlementService`, à `EventFinished` + rattrapage au démarrage). **Avatar = logo d'équipe** choisi par jeu. Le groupe d'un créateur supprimé passe au membre le plus ancien. Appli : écran Profil (avatar de l'Accueil, rouage vers les Réglages), « Tes suivis » de retour sur l'Accueil, onglet Suivis retiré (4ᵉ onglet vide), onglet **Jeux** → Pronostics (filtre par jeu du catalogue), pronostic sur l'écran du match, **sans spoil = score flouté révélé par appui long** (`SpoilerHold`, écran du match et cartes). Vérifié en conditions réelles sur téléphone Android et émulateur ; **règlement des points vérifié sur le vrai worker avec un match simulé**, pas encore sur un match PandaScore réel (pronostic de `Wylfram` en attente). **Reportés** : modèles d'e-mails Firebase et page de validation (avec l'identité de l'app), classement de groupe par jeu, lien Google/Apple, pronostic sur les cartes, points d'un vrai match.
- **J12 fait** (apprentissage Valorant) : onglet **« Apprendre »** dans la page Valorant, 5 tutos en français dans `apps/mobile/assets/learn/valorant.json` (**embarqués, pas d'endpoint ni de base** ; un fichier par jeu ou sport : `{name, articles[{id,title,summary,essential,icon,visual,gradient,details[{title,body?,visual?}]}]}`). Schémas **décrits en données** (`chips` tuiles, `flow` étapes, `stats` gros chiffres + `duel`/`map`/`bo3` nommés, `features/learn/learn_visuals.dart`), dégradés d'`AppGradients`. **Icône « ? » jaune** (`LearnHelpButton`) sur la page jeu, les pages de compétition et l'écran d'un match, avec bouton « Toutes les règles ». Mots du glossaire **en gras** (`StakesText`), exemple en 3 cartes dans la feuille « BO3 ». **Aucune image du jeu** : la politique de Riot exclut les apps sur les stores sans licence écrite ou clé d'API ; textes écrits par nous, jamais recopiés. Aucun changement backend. Vérifié sur émulateur Android. **Reportés** : relecture par un néophyte externe, onglet/« ? » pour les autres jeux (`_learnGames` figé sur `valorant`), images officielles.
- Déjà présent dans le dépôt :
  - `tests-pandascore/` : scripts de test de l'API PandaScore et **réponses réelles** dans `samples/` et `samples-multijeux/`. Réutilisées comme **fixtures de tests** de l'adaptateur PandaScore.
  - `politique-quiz/` : extraction de l'open data de l'Assemblée (scrutins, députés) pour le prototype du jeu « Qui a voté ? ». `data/` est ignoré par Git (≈ 250 Mo, retéléchargeable).

## Stack

- **Backend** : NestJS (TypeScript strict), monorepo **pnpm**, deux points d'entrée `api` et `worker`.
- **Données** : PostgreSQL 16 + Redis 7, **Prisma** (tranché au J1), **BullMQ** pour les jobs.
- **API** : REST `/v1` pensée par écran, spec **OpenAPI** générée par NestJS → **client Dart généré**.
- **Mobile** : Flutter, Riverpod, cache local **drift**, `CustomPainter` pour l'arbre radial, `firebase_messaging`.
- **Push** : Firebase Cloud Messaging (APNs pour iOS). **Comptes** : Firebase Auth (e-mail + mot de passe, J11).
- **Hébergement** : Docker Compose sur un NAS, exposé par Tailscale Funnel (décision du J7 ; Cloudflare Tunnel envisagé au départ dans `docs/03`). GitHub Actions → GHCR.
- **Web (plus tard)** : Next.js.

## Structure cible

```
apps/api            NestJS — contrôleurs /v1, auth, cache, OpenAPI
apps/worker         NestJS — jobs BullMQ, ingestion, moteur de notifications
apps/mobile         Flutter (Android/iOS ; pas de cible web pour ce projet)
packages/domain     types et règles métier partagés (statuts, formats, calculs de bracket)
packages/db         schéma Prisma, migrations, client
packages/providers  un adaptateur par fournisseur (pandascore, liquipedia, …)
infra/              docker-compose.yml, Dockerfile, scripts de sauvegarde (exposition par Tailscale Funnel, hors Compose)
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
10. **Sans spoil** : l'API renvoie les scores, **l'appli les masque** selon les réglages (score **flouté**, révélé par appui long, J11) ; les **notifications appliquent le réglage côté serveur**.
11. **Client Dart généré** depuis OpenAPI : ne jamais écrire les modèles d'API à la main côté Flutter.
12. **Design** : couleurs et rayons uniquement via le fichier de thème (tokens de `docs/02`). Or `#FFC940` = mon équipe / mes suivis ; rouge `#FF4655` = en direct / « tu es ici » ; vert `#30D158` = victoire / qualifié. Catégories distinguées par l'icône, pas par la couleur.
13. **Mouvement** : pas d'animation sur ce qu'on voit plusieurs fois par jour ; entrées ease-out `cubic-bezier(0.23,1,0.32,1)` < 300 ms, `transform`/`opacity` uniquement ; respecter `MediaQuery.disableAnimations`. Seule dérogation assumée (J10) : les deux-points clignotants du compte à rebours, figés en mouvement réduit.
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
pnpm db:seed          # glossaire (context_snippet), idempotent, à rejouer si le texte change (J6)
# `db:migrate` exige un terminal interactif ; sinon écrire la migration à la main et l'appliquer avec
# `pnpm exec dotenv -e .env -- pnpm --filter @news/db exec prisma migrate deploy` (sans `dotenv`, `prisma` est introuvable ; `pnpm db:generate` se lance de même si besoin).
# `db:generate` échoue (EPERM) tant que `pnpm dev` tourne : l'arrêter avant de régénérer le client Prisma.
# `pnpm dev` lancé depuis un agent : arrêter le parent ne tue pas ses enfants `ts-node` (API, worker), qui gardent `query_engine-windows.dll.node` ouvert (EPERM) : les terminer avant `db:generate`.
# Après un changement de schéma, redémarrer `pnpm dev` : `ts-node` ne recharge pas à chaud (API et worker gardent l'ancien client).

# Lancer l'API + le worker ensemble (à préférer : sans worker, plus d'ingestion et les scores restent figés)
pnpm dev

# Ou séparément (chacun charge .env à la racine)
pnpm api:dev
pnpm worker:dev

# Tests et vérification de types, tous packages
pnpm -r test
pnpm -r lint
# Les e2e de l'API remplacent Firebase par un faux (`apps/api/src/test-utils.ts`, ID token `test:<uid>:<vérifié>`) et suppriment les comptes qu'ils créent (`deleteTestUsers` dans `afterAll`).
# Les suites e2e de l'API partagent Redis et la base : elles tournent l'une après l'autre (`--runInBand`, échec intermittent en CI sinon).
# Ne jamais tuer Jest en cours : `afterAll` ne nettoie pas, des données `test-*` restent en base de dev (catégories/ligues de test visibles dans l'appli).
# Une suite lancée seule peut ne pas rendre la main : ajouter `--forceExit`.

# Inspecter la base pendant le dev
pnpm --filter @news/db exec prisma studio

# Spec OpenAPI + client Dart généré (packages/api_client_dart, gitignoré)
pnpm generate:client       # openapi.json + client Dart + build_runner en un coup
pnpm generate:openapi      # juste la spec, dans openapi.json à la racine

# Appli Flutter (apps/mobile)
# Tutos (J12) : assets/learn/<jeu>.json ; un nouveau fichier demande un redémarrage complet (pas un hot reload) ; dans `flutter test`, charger l'asset via `tester.runAsync` (rootBundle ne se résout pas sous l'horloge factice).
flutter test               # tests de widgets (les goldens échouent en CI si générés sous Windows, voir ci-dessous)
flutter analyze            # analyse statique
# Ne pas lancer `dart format` sur un fichier existant : il reformate tout en largeur 80, le dépôt est écrit en ~140 colonnes.
flutter run -d <device>    # sur un émulateur ou un téléphone en USB (debug)
adb reverse tcp:3000 tcp:3000   # Android (émulateur ou téléphone) : fait pointer son localhost vers l'API locale ; à refaire après un reset de l'émulateur ou un débranchement (`adb -s <id> reverse ...` si deux appareils)

# Mise en ligne (prod, sur le NAS — détails et prérequis dans docs/05-deploiement.md)
docker compose -f infra/docker-compose.yml --env-file .env up -d
docker compose -f infra/docker-compose.yml --env-file .env logs -f api worker
```

`.env` doit contenir `PANDASCORE_TOKEN` (voir `.env.example`) pour que le worker ingère de vraies données, `LIQUIPEDIA_USER_AGENT` (contact réel, exigé par la licence — J6) pour l'enrichissement Liquipedia, `JWT_SECRET`/`JWT_REFRESH_SECRET` (deux chaînes aléatoires, J4) pour l'authentification, et `FIREBASE_PROJECT_ID`/`FIREBASE_CLIENT_EMAIL`/`FIREBASE_PRIVATE_KEY` (clé de compte de service, Paramètres du projet → Comptes de service dans la console Firebase) pour que le worker envoie de vraies notifications — sans ça il journalise sans envoyer — **et, depuis le J11, pour que l'API vérifie les comptes** (sans eux la connexion répond 503, la lecture reste servie). Console Firebase → Authentication → Sign-in method : le fournisseur **E-mail/Mot de passe** doit être activé. Côté Android, `apps/mobile/android/app/google-services.json` (projet Firebase → app Android `com.news.mobile`, gitignoré) est nécessaire pour que l'appli reçoive les notifications ; sans lui, `flutter run` fonctionne quand même (les appels Firebase échouent silencieusement). `pnpm generate:client` a besoin de Java (openapi-generator) et du SDK Dart. `flutter run` a besoin que `pnpm api:dev` et `pnpm worker:dev` tournent déjà (et `adb reverse` sur Android). En prod uniquement (J7, jamais en dev) : `POSTGRES_PASSWORD`, `IMAGE` (`ghcr.io/<compte-github>/news`), `ALERT_WEBHOOK_URL` (alerte de supervision), `SENTRY_DSN` (suivi d'erreurs) et `PUBLIC_PATH_PREFIX` (laisser vide avec Tailscale Funnel, voir `docs/05-deploiement.md`).

## Goldens Flutter (`apps/mobile/test/goldens/golden_files`)

Les images de référence doivent venir du **runner CI (Ubuntu)**, pas de Windows : la police rend différemment et la CI échoue sinon. Après tout changement visuel d'un widget couvert par un golden, les régénérer via la CI : branche jetable où le job `mobile` de `.github/workflows/ci.yml` lance `flutter test --update-goldens` puis `upload-artifact` de `apps/mobile/test/goldens/golden_files` (et `regen-goldens` ajouté à `branches:` du déclencheur `push`), télécharger l'artefact avec `gh run download`, copier les PNG sur `main`, supprimer la branche. Précédents : `c9980e8`, `2b5bdc0`, `cde685c` (J10, `event_card_live_gold.png`). Le golden de la tab bar (reporté du J9) passe en CI sans régénération. **J11** : régénérés par la CI, les 9 goldens sont **identiques** à ceux du dépôt ; leurs échecs en local sous Windows sont un simple écart de rendu, pas une régression.

## Maquettes (Figma)

- Fichier : https://www.figma.com/design/1GfSNwpyE1WoWEdUzT638L — 26 écrans V2 (iPhone 390×844, thème sombre, Inter).
- **Quota MCP Figma épuisé** (plan Starter, ~20 appels/mois — atteint le 2026-09-26) : **ne pas appeler le MCP Figma.** S'appuyer sur `docs/02` et sur les captures (PNG et export SVG) dans `docs/maquettes/` (voir le README de ce dossier).

## Outils conseillés

- Plugin **Ponytail** (code minimal) dès le début ; **Graphify** à partir du J3 quand le code grossit.
- MCP **Context7** (docs à jour NestJS, Prisma, BullMQ, Riverpod, drift) et **MCP Dart/Flutter** (analyse, tests).
