# Étape 4 — Jalons de développement

> Découpage du développement, tiré de `03-architecture-backend.md` (§13) et des points ouverts des documents 00 à 03. Chaque jalon a un résultat visible et des critères d'acceptation vérifiables. **On ne passe au jalon suivant que quand tous les critères sont cochés** (ou explicitement reportés, avec la raison).

## Vue d'ensemble

| Jalon | Contenu | Résultat visible | Statut |
|---|---|---|---|
| J1 | Monorepo, Compose de dev, schéma de base, adaptateur PandaScore (Valorant) | Les matchs Valorant arrivent en base | **À faire** |
| J2 | API `home`, `agenda`, `events/:id`, `competitions/:id` + client Dart généré | L'API répond avec de vraies données | À faire |
| J3 | Appli Flutter : accueil, agenda, page Valorant, prochain match | Première version utilisable | À faire |
| J4 | Compte anonyme, abonnements, notifications push | « Suivre G2 » fonctionne de bout en bout | À faire |
| J5 | Brackets (`event_link`) + arbre radial + repêchage + groupes | Écrans 02, 05, 06, 07 sur de vraies données | À faire |
| J6 | Liquipedia, « pourquoi ce match compte », glossaire, sans spoil, onboarding | Expérience complète pour les nouveaux venus | À faire |
| J7 | Mise en ligne : NAS, Cloudflare Tunnel, CI, sauvegardes, bêta testeurs | Des amis utilisent l'appli | À faire (ajouté) |
| Ensuite | Temps réel V2, autres jeux, jeu du jour, politique, sport, web | — | Plus tard |

**Calendrier à garder en tête**
- Valorant Champions 2026 se termine le **18 octobre 2026** : c'est la meilleure fenêtre pour tester le direct sur Valorant. Après, il restera LoL Worlds (jusqu'au ~3 novembre) et CS2, que PandaScore couvre avec le même token.
- **Présidentielle 2027 : 1er tour le 18 avril, 2d tour le 2 mai.** Proposition : une version politique/élections prête avant.

---

## J1 — Fondations et ingestion Valorant

**Objectif** : les matchs Valorant (Champions 2026 en priorité) arrivent en base via le worker, proprement et sans gaspiller le quota.

**Périmètre**
- Monorepo pnpm : `apps/api`, `apps/worker`, `packages/domain`, `packages/db`, `packages/providers` (structure de `docs/03` §1).
- `infra/docker-compose.dev.yml` : PostgreSQL 16 + Redis 7.
- **Trancher Prisma ou Drizzle** (Prisma proposé) et le noter dans les décisions.
- Schéma : `category`, `competition`, `entity`, `event`, `event_participant`, `event_link`, `standing`, `provider_ref`, `provider_payload` (les tables utilisateurs viendront au J4).
- Adaptateur `pandascore` (interface `Provider` de `docs/03` §3) : ligues → séries → tournois → matchs, équipes.
- Jobs BullMQ : catalogue (6 h), calendrier J-1 → J+14 (10 min), matchs en cours (30 s).
- Upsert idempotent via `provider_ref` + `payload_hash` ; réponses brutes gardées 7 jours dans `provider_payload`.
- Compteur de quota par fournisseur (lecture des en-têtes `x-rate-limit-*`, ralentissement au-delà de 70 %).
- Logs structurés (pino).
- `.env.example` à la racine.

**Critères d'acceptation**
- [ ] `docker compose -f infra/docker-compose.dev.yml up` puis le worker → les tournois et matchs de Champions 2026 sont en base, avec équipes, statuts, score de série et gagnant de chaque carte.
- [ ] Relancer l'ingestion sans changement côté source n'écrit rien (vérifié par un test ou un log).
- [ ] Tests unitaires de normalisation sur les JSON réels de `tests-pandascore/samples/` (matchs à venir, en cours, terminés, brackets, classements).
- [ ] Le quota consommé est visible dans les logs et reste sous ~400 req/h.
- [ ] Journaliser, pour chaque match terminé, l'écart entre `end_at` et le moment où le worker le détecte (**mesure de la latence réelle**, point ouvert de `docs/01`).
- [ ] Section « Commandes » de `CLAUDE.md` remplie.

**Hors périmètre** : API publique, Liquipedia, autres jeux (le modèle doit les permettre, mais on ne les active pas encore).

---

## J2 — API et client Dart

**Objectif** : l'API sert les écrans principaux avec de vraies données, et Flutter dispose d'un client généré.

**Périmètre**
- Endpoints (`docs/03` §4) : `GET /v1/home` (version sans utilisateur : grands rendez-vous + en direct + à venir), `GET /v1/agenda`, `GET /v1/events/:id`, `GET /v1/competitions/:id`, `GET /health`.
- Chaque réponse porte `source_updated_at`.
- Cache Redis 15–60 s + `Cache-Control` court + **`ETag` / `304`**.
- Événements métier publiés par le worker (`EventStarted`, `ScoreChanged`, `EventFinished`…) et consommateur « cache » qui invalide les clés.
- Spec OpenAPI générée ; **client Dart généré** (ex. `openapi-generator` en `dart-dio`) dans un package consommé par l'appli ; script de régénération.
- Validation des entrées (DTO + `class-validator`), limitation de débit.

**Critères d'acceptation**
- [ ] Les 4 endpoints renvoient des données réelles de Champions 2026.
- [ ] Un deuxième appel identique renvoie `304` grâce à l'`ETag`.
- [ ] Un changement de score côté worker invalide le cache (la réponse suivante est à jour).
- [ ] Le client Dart se régénère avec une seule commande et compile.
- [ ] Tests e2e des endpoints (Supertest).

---

## J3 — Première version de l'appli

**Objectif** : une appli Flutter utilisable qui affiche de vraies données, fidèle à la V2 des maquettes.

**Périmètre**
- Projet Flutter (emplacement `apps/mobile` proposé, à confirmer).
- **Thème** : un seul fichier de tokens (couleurs, rayons, typo Inter avec tracking, courbes d'animation) repris de `docs/02`.
- Couches `data` (client généré + cache **drift**) / `domain` / `ui`, état avec **Riverpod**.
- Hors ligne d'abord : affichage du cache puis rafraîchissement.
- Écrans : **17 Accueil**, **09 Agenda**, **01 Page Valorant (saison)**, **03 Prochain match**.
- Tab bar V2 en verre flottante : Aujourd'hui · Agenda · Suivis · Jeu (Suivis et Jeu en placeholder).
- Rafraîchissement 15–30 s **uniquement** sur les écrans en direct, avec `ETag`.
- Mention « Mise à jour en attente » si les données ont plus de 15 min pendant un direct.

**Critères d'acceptation**
- [ ] Les 4 écrans s'affichent avec les données de l'API locale, en thème sombre, conformes aux maquettes (comparaison avec `docs/maquettes/`).
- [ ] Mode avion : l'appli s'ouvre et montre les dernières données.
- [ ] Mouvement réduit respecté (`MediaQuery.disableAnimations`).
- [ ] Tests de widgets sur les états d'un match (à venir, en direct, terminé, reporté).
- [ ] À partir d'ici : installer **Graphify** et générer le graphe du dépôt.

---

## J4 — Comptes, abonnements, notifications

**Objectif** : « Suivre G2 » fonctionne de bout en bout, jusqu'à la notification sur le téléphone.

**Prérequis** : projet Firebase ; **compte Apple Developer (99 $/an)** et clé APNs pour iOS (on peut commencer par Android).

**Périmètre**
- Tables `app_user`, `device`, `subscription`, `user_setting`, `notification_log`.
- Compte **anonyme** créé au premier lancement : JWT court + jeton de rafraîchissement. Pas d'inscription.
- `PUT /v1/devices/me`, `POST/DELETE /v1/subscriptions`, `GET/PATCH /v1/me/settings`, `DELETE /v1/me` (RGPD).
- `/v1/home` personnalisé (Maintenant pour toi, Tes suivis).
- Moteur de notifications (`docs/03` §6) : abonnements directs et hiérarchiques, heures calmes, sans spoil appliqué côté serveur, **déduplication** (`user` + `event` + `type`), max 3 notifications/h hors équipe suivie en direct, suppression des jetons invalides.
- Types : rappel T-15 min, début, résultat, qualification/élimination.
- Côté appli : bouton « Suivre » partout, écran Suivis, permission de notification demandée au bon moment.

**Critères d'acceptation**
- [ ] Suivre G2 depuis l'appli → rappel, début et résultat reçus sur un vrai téléphone.
- [ ] Une même notification n'est jamais envoyée deux fois (test).
- [ ] Sans spoil activé → la notification de fin ne contient pas le score.
- [ ] Désinstaller/réinstaller ne casse rien (jeton invalide nettoyé).

---

## J5 — Brackets et arbre radial

**Objectif** : la signature visuelle de l'appli, sur de vraies données.

**Périmètre**
- Construction de `event_link` à partir de `previous_matches` (gagnant/perdant) ; calculs de bracket dans `packages/domain`.
- Classements : recalcul des victoires/défaites et de la différence de cartes à partir des matchs (le `standings` gratuit ne donne que le rang).
- `GET /v1/competitions/:id/bracket` (nœuds, liens, rounds, slots, indices de mise en page).
- Job « structure » (5 min + à chaque fin de match) et événement `BracketAdvanced`.
- Appli : **02 arbre radial** (`CustomPainter`, chemin de l'équipe suivie en or, compte à rebours au centre), **05 repêchage** en liste par tours, **06 groupes** (mini-grilles, trait de qualification), **07 arbre terminé**. **14 « 3 vies »** (triple élimination du Kickoff) sur des données historiques.

**Critères d'acceptation**
- [ ] Les playoffs de Champions 2026 s'affichent en arbre radial, matchs « TBD » compris, et se remplissent quand les matchs se terminent.
- [ ] Le repêchage indique « perdant de… » et se met à jour.
- [ ] Les groupes GSL de Champions s'affichent avec le bon bilan recalculé.
- [ ] Tests unitaires des calculs de bracket (double élimination, GSL) sur les JSON de `tests-pandascore/samples/`.
- [ ] L'arbre reste fluide (60 i/s) sur un téléphone moyen.

---

## J6 — Expérience néophyte

**Objectif** : quelqu'un qui ne connaît rien à Valorant comprend ce qu'il regarde.

**Périmètre**
- Adaptateur **Liquipedia** (API MediaWiki) : User-Agent avec contact, 1 req/2 s, 1 parse/30 s, cache ≥ 24 h. Contexte et formats des compétitions.
- **« Pourquoi ce match compte »** calculé par règles à partir du bracket (`docs/03` §7), stocké dans `context_snippet`.
- **Glossaire** (BO3, repêchage, triple élimination…) + feuille **04** ; mots soulignés dans le texte.
- **Sans spoil** par suivi (écran **15** : score masqué, appui long pour révéler).
- **Onboarding** (écrans **11–12** : sujets, puis 3 équipes suggérées avec leur raison).
- **Réglages** (écran **22**) : sans spoil, résumé du matin, heures calmes, **Sources et crédits** (attribution Liquipedia CC-BY-SA, PandaScore, logos des équipes), charte de neutralité.
- Fiche équipe (écran **10**).

**Critères d'acceptation**
- [ ] Chaque match de phase finale a sa phrase d'enjeu, juste et à jour.
- [ ] L'attribution Liquipedia apparaît partout où son contenu est utilisé.
- [ ] Test utilisateur avec 2–3 personnes qui ne suivent pas Valorant : elles savent dire qui est encore en course et ce que signifie le prochain match.

---

## J7 — Mise en ligne (ajouté)

**Objectif** : l'appli tourne 24 h/24 et de premiers testeurs l'utilisent.

**Périmètre** (`docs/03` §8–10)
- `infra/docker-compose.yml` de production : `api`, `worker`, `postgres`, `redis`, `cloudflared`, `backup` (+ `uptime-kuma` en option), avec limites CPU/RAM.
- **Nom de domaine** choisi et Cloudflare Tunnel (`api.<domaine>`), aucun port ouvert.
- GitHub Actions : tests, build de l'image, publication sur GHCR.
- Sauvegardes : `pg_dump` nocturne, 7 jours sur le NAS + copie chiffrée hors site ; **une restauration testée**.
- Supervision : `/health`, tableau de bord fournisseurs, alertes (ingestion arrêtée > 15 min, quota > 80 %, push en échec > 5 %), Sentry côté API et appli.
- Distribution bêta : TestFlight et/ou test interne Google Play.
- Politique de confidentialité, licence open source du dépôt.

**Critères d'acceptation**
- [ ] L'appli d'un testeur fonctionne hors du réseau de la maison.
- [ ] Une coupure simulée du NAS : l'appli reste utilisable en hors ligne, l'alerte arrive.
- [ ] Restauration d'une sauvegarde réussie.

---

## Ensuite (par ordre de priorité proposé)

1. **Autres jeux PandaScore** (LoL, CS2, Dota 2, R6, Rocket League…) : même adaptateur, filtrage par tier. Nouveaux formats à dessiner : **phase suisse**, **classement de lobby** (battle royale). Vérifier le gagnant par carte pour CS, Dota 2 et LoL sur du tier S.
2. **Temps réel V2** : flux SSE `GET /v1/live/events/:id`, **Live Activities** iOS (écran 13).
3. **Jeu du jour** (écran 16) : « devine le score », pronostics (`prediction`, `quiz_answer`).
4. **Politique** avant avril 2027 : adaptateurs `assemblee` (zips quotidiens), `senat`, `legifrance` (PISTE), `elections` (data.gouv, rythme rapide le soir d'élection). Écrans 19 (loi façon colis) et 25 (soirée électorale). Jeu « Qui a voté ? » à partir de `politique-quiz/`. Tester le flux de résultats en direct sur un scrutin partiel **avant** la présidentielle.
5. **Streams** : API Twitch (écran 23).
6. **Sport par vagues** (`docs/01b`) : football (football-data.org + openfootball), F1 (Jolpica), puis rugby/basket.
7. **Site web** Next.js (SEO).
8. **Start.gg** pour les jeux de combat.

## Points ouverts à trancher en chemin

| Point | Quand |
|---|---|
| Prisma ou Drizzle | J1 |
| Emplacement du projet Flutter (`apps/mobile` ?) | J3 |
| Compte Apple Developer (99 $/an) | Avant J4 (iOS) |
| Nom de l'appli et nom de domaine (« News » est un nom de travail) | Avant J7 |
| Logo et icône d'app définitifs | Avant J7 |
| Écrire à PandaScore : usage du plan gratuit et attribution exigée | Avant J7 |
| Licence open source du code (MIT, AGPL…) | Avant J7 |
