# Étape 4 — Jalons de développement

> Découpage du développement, tiré de `03-architecture-backend.md` (§13) et des points ouverts des documents 00 à 03. Chaque jalon a un résultat visible et des critères d'acceptation vérifiables. **On ne passe au jalon suivant que quand tous les critères sont cochés** (ou explicitement reportés, avec la raison).

## Vue d'ensemble

| Jalon | Contenu | Résultat visible | Statut |
|---|---|---|---|
| J1 | Monorepo, Compose de dev, schéma de base, adaptateur PandaScore (Valorant) | Les matchs Valorant arrivent en base | **Fait (2026-09-25)** |
| J2 | API `home`, `agenda`, `events/:id`, `competitions/:id` + client Dart généré | L'API répond avec de vraies données | **Fait (2026-09-25)** |
| J3 | Appli Flutter : accueil, agenda, page Valorant, prochain match | Première version utilisable | **Fait (2026-09-26)** |
| J4 | Compte anonyme, abonnements, notifications push | « Suivre G2 » fonctionne de bout en bout | **Fait (2026-09-26)** |
| J5 | Brackets (`event_link`) + arbre radial + repêchage + groupes | Écrans 02, 05, 06, 07 sur de vraies données | **Fait (2026-09-26)** |
| J6 | Liquipedia, « pourquoi ce match compte », glossaire, sans spoil, onboarding | Expérience complète pour les nouveaux venus | **Fait (2026-09-27)** |
| J7 | Mise en ligne : NAS, Tailscale Funnel, CI, sauvegardes, bêta testeurs | Des amis utilisent l'appli | **Fait (2026-09-27)** |
| J8 | Polissage UI/UX Valorant : retour optimiste, repères visuels, navigation Agenda | L'appli est plus lisible et plus réactive pour un néophyte | **Fait (2026-09-28)** |
| J9 | Onglet Compétitions : navigation catégorie → jeu → compétition, favoris de jeux, recherche | On retrouve n'importe quel jeu ou compétition en 2 taps, sans passer par l'Accueil | **Fait (2026-09-29)** |
| J10 | Polissage des pages existantes et retours d'usage : cartes de match, Suivis, familles de compétitions et « tout sauf une », onglet Ligues, rafraîchissement automatique | Les écrans existants te correspondent et l'appli reste à jour toute seule | **Fait (2026-09-30)** |
| J11 | Comptes avec pseudo, page de profil (badges, score de pronostics, stats), pronostics en points fictifs, groupes d'amis (façon MPP) | On parie sur ses matchs et on se compare à ses amis, gratuitement | **Fait (2026-09-30)** |
| J12 | Section apprentissage Valorant : tutos écrits (jeu, rôles, cartes) | Un néophyte comprend comment on joue | **Fait (2026-10-01)** |
| J13 | Forum (bêta fermée) : discussion et tchat du direct par match, fils par équipe, compétition, jeu et libres, badge de camp, modération | On discute d'un match sans que ça dégénère | **Fait (2026-10-01)** |
| J14 | Pronostics entre amis : choix des amis, rappels, classement par jeu, partage | Se comparer à ses amis | **Fait (2026-10-01)** |
| J15 | Finitions d'interface : skeletons, retour instantané, parcours d'accueil, erreurs lisibles | L'appli paraît plus rapide et ne montre jamais d'erreur technique | À planifier |
| J16 | Identité de l'app : nom, logo, personnalité visuelle « solennelle » (laiton mat, capitales fines, tampons), icône, écran de lancement | L'app a une vraie personnalité et un nom à elle | À planifier |
| J17 | Versions Windows et Web de l'app | On suit ses compétitions depuis un ordinateur | À planifier |
| J19 | Rattrapage des reportés (jalon intermédiaire) : vérifications en réel, petits défauts, démarches et décisions, guide des compétitions, résumé du matin | Plus rien de flou dans les « reportés » : chaque ligne est faite, abandonnée ou rangée dans « Ensuite », avec la raison | À planifier (proposé 2026-10-02) |
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
- [x] `docker compose -f infra/docker-compose.dev.yml up` puis le worker → les tournois et matchs de Champions 2026 sont en base, avec équipes, statuts, score de série et gagnant de chaque carte. Vérifié le 2026-09-25 : 68 compétitions, 34 événements dont 4 vrais matchs Champions 2026 terminés.
- [x] Relancer l'ingestion sans changement côté source n'écrit rien (vérifié par un test ou un log). Vérifié par `shouldUpsert` (test unitaire) et en réel : un 2ᵉ passage catalogue+calendrier donne des compteurs identiques et aucun nouveau log.
- [x] Tests unitaires de normalisation sur les JSON réels de `tests-pandascore/samples/` (matchs à venir, en cours, terminés). **Brackets et classements reportés au J5** : `event_link`/`standing` ne sont pas encore alimentés (tables créées, vides) — le adaptateur ne lit pas encore `/brackets` ni `/standings`, donc il n'y a pas encore de normalisation à tester ; ça viendra avec la construction des brackets au J5.
- [x] Le quota consommé est visible dans les logs et reste sous ~400 req/h. Ratio de quota loggé à chaque passage (`QuotaTracker`), très en-dessous du seuil dans les tests réels.
- [x] Journaliser, pour chaque match terminé, l'écart entre `end_at` et le moment où le worker le détecte (**mesure de la latence réelle**, point ouvert de `docs/01`). Log `"match terminé détecté"` avec `latencyMs`, vérifié sur les 4 vrais matchs.
- [x] Section « Commandes » de `CLAUDE.md` remplie.

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
- [x] Les 4 endpoints renvoient des données réelles de Champions 2026. Vérifié le 2026-09-25 avec l'API branchée sur le Postgres de dev réel : `/v1/home` (20 matchs à venir, 10 grands rendez-vous), `/v1/agenda` (32 événements), `/v1/events/:id` (GE vs VIT), `/v1/competitions/:id` (Playoffs). Un bug a été trouvé et corrigé au passage : `highlights` filtrait sur `event.importance` (jamais renseigné par l'ingestion du J1) au lieu de `competition.importance` (le seul alimenté, via le tier PandaScore).
- [x] Un deuxième appel identique renvoie `304` grâce à l'`ETag`. Vérifié en direct sur un vrai événement (200 puis 304).
- [x] Un changement de score côté worker invalide le cache (la réponse suivante est à jour). Vérifié par un test e2e qui reproduit l'action du worker (écriture Prisma + publication Redis sur le vrai canal) contre le Postgres/Redis de dev. Aucun match Champions 2026 n'était en direct au moment de la vérification pour un scénario avec un vrai changement de score ; le worker démarre et se câble sans erreur sur ce canal (smoke-test de démarrage au 2026-09-25).
- [x] Le client Dart se régénère avec une seule commande et compile. `pnpm generate:client` régénère `openapi.json` + `packages/api_client_dart` (openapi-generator + `build_runner`) ; `dart analyze` : 0 erreur.
- [x] Tests e2e des endpoints (Supertest). 7/7 verts contre le vrai Postgres/Redis de dev.

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
- [x] Les 4 écrans s'affichent avec les données de l'API locale, en thème sombre, conformes aux maquettes (comparaison avec `docs/maquettes/`). Vérifié le 2026-09-26 dans le navigateur (build web) et sur un téléphone Android réel (`flutter run`, via `adb reverse`), branché sur l'API locale : Accueil (grands rendez-vous, bandeau en direct), Agenda (semaine, filtres, liste par jour), Saison Valorant (frise réelle des 9 étapes VCT 2026, étape en cours recentrée automatiquement), Prochain match (compte à rebours, alerte, sans spoil). **Fidélité pixel-perfect aux maquettes reportée** : la structure, les sections et les couleurs sont alignées après plusieurs allers-retours, mais une passe dédiée à la typographie et aux espacements exacts est repoussée après la suite du développement fonctionnel, à la demande du produit.
- [x] Mode avion : l'appli s'ouvre et montre les dernières données. Vérifié en conditions réelles sur le téléphone : données rechargées, avion activé, appli fermée puis rouverte → dernières données affichées (cache `drift` + repli de l'intercepteur `ETag` sur erreur réseau).
- [x] Mouvement réduit respecté (`MediaQuery.disableAnimations`). Test automatisé (`live_dot_test.dart`) : le point « en direct » s'anime en continu par défaut et reste fixe (pas de `FadeTransition`) quand `disableAnimations` est activé.
- [x] Tests de widgets sur les états d'un match (à venir, en direct, terminé, reporté). `event_card_test.dart`, 4/4 verts.
- [ ] À partir d'ici : installer **Graphify** et générer le graphe du dépôt. **Reporté** : l'extension est installée mais le graphe n'a pas encore été généré ; non bloquant pour la suite.

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
- [x] Suivre G2 depuis l'appli → rappel, début et résultat reçus sur un vrai téléphone. Vérifié le 2026-09-26 sur un téléphone Android physique, projet Firebase réel : « début » et « résultat » reçus en conditions réelles sur un vrai match Champions 2026 (LOUD vs EDG) suivi depuis l'appli ; « rappel T-15 » vérifié par un test contrôlé (départ d'un match existant avancé à +15-20 min le temps du test, remis à sa vraie valeur ensuite) faute de vrai match dans la fenêtre T-15 au moment du test. Le tap sur la notification ouvre directement l'écran du match (`eventId` dans le payload `data`).
- [x] Une même notification n'est jamais envoyée deux fois (test). `notification-dispatch.service.spec.ts` : deux appels du même événement métier ne créent qu'une ligne `notification_log` et n'appellent `FcmService.send` qu'une fois.
- [x] Sans spoil activé → la notification de fin ne contient pas le score. Vérifié par un test unitaire (`packages/domain`) et en conditions réelles sur le téléphone : « Terminé LOUD vs EDG est terminé. », sans score ni gagnant (réglage par défaut).
- [x] Désinstaller/réinstaller ne casse rien (jeton invalide nettoyé). Vérifié par un test d'intégration qui simule un jeton FCM invalide et confirme la suppression de l'appareil correspondant (pas de vraie désinstallation faite en conditions réelles).

**Ajouts par rapport au périmètre initial** : `GET /v1/subscriptions` (non listé dans `docs/03` §4, nécessaire à l'écran Suivis) ; bandeau "à suivre" sur l'accueil quand rien n'est en direct (repli sur `home.upcoming`, docs/02 point 1 "en direct ou imminente") ; `Device.timezone` remplacé par `Device.utcOffsetMinutes` (décalage UTC en minutes plutôt qu'un fuseau IANA, pour éviter une dépendance Flutter supplémentaire côté calcul des heures calmes).

**Reporté au J5** : le type de notification « qualification/élimination » (dépend du bracket, `event_link`, pas encore alimenté).

**iOS** : reporté après la sortie de l'appli (décision produit), Android seul pour l'instant — le compte Apple Developer et la clé APNs restent un point ouvert pour plus tard.

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
- [x] Les playoffs de Champions 2026 s'affichent en arbre radial, matchs « TBD » compris. Vérifié en conditions réelles le 2026-09-26 sur téléphone Android physique : 14 nœuds/20 liens, rounds corrects, tout en TBD (les playoffs n'ont pas encore commencé, encore en phase de groupes). **Le remplissage à la fin d'un vrai match n'a pas pu être observé** (mécanisme `BracketAdvanced` + resynchro à chaque fin de match vérifié architecturalement, mais aucun match de playoffs ne s'est encore terminé) : **à revérifier en conditions réelles** à partir du 18 octobre.
- [x] Le repêchage indique « perdant de… » et se met à jour. Vérifié en réel : « Perdant de Upper Bracket Quarterfinal 1... » etc. sur le vrai bracket des playoffs.
- [x] Les groupes GSL de Champions s'affichent avec le bon bilan recalculé. Vérifié en réel sur les 4 groupes (ex. Groupe C : G2/Paper Rex 1-0 qualifiés, Team Liquid/TYLOO 0-1) ; un groupe pas encore commencé affiche « Pas encore commencé » plutôt qu'une carte vide.
- [x] Tests unitaires des calculs de bracket (double élimination, GSL) sur les JSON de `tests-pandascore/samples/`. 37 tests dans `packages/domain`, sur 3 vrais brackets récupérés depuis PandaScore (poule GSL, playoffs Champions 2026 en double élim, Kickoff EMEA 2026 en triple élim).
- [ ] L'arbre reste fluide (60 i/s) sur un téléphone moyen. **Non mesuré formellement** (pas de profilage DevTools) : le `CustomPaint` ne redessine que sur changement de données (pas d'animation continue), risque de saccade jugé faible. **À revérifier en conditions réelles** avec un profilage dédié.

**Reporté** : la fidélité visuelle exacte à la maquette (symétrie gauche/droite de l'arbre, trophée au centre, labels d'anneau, lignes en coude, panneaux sous l'arbre) — la structure (rounds, TBD, liens, mise à jour) est correcte et testée, l'habillage pixel-perfect attend une passe dédiée, comme au J3. Type de notification « qualification/élimination » (reporté du J4) finalement câblé pendant ce jalon, voir `docs/00` §7.

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
- [x] Chaque match de phase finale a sa phrase d'enjeu, juste et à jour. Calculée par des règles à partir du bracket (`packages/domain/context.ts`), un lien de bracket ne suffit pas à lui seul : un `event_link` de type "loser" existe aussi pour une poule GSL (vers le "Decider Match"), sans en faire une grande finale — un bug trouvé en vérifiant sur les vraies données (le "Winners Match" de Group C se voyait attribuer la phrase "vainqueur sacré champion") et corrigé en filtrant sur `competition.format` (formats à élimination seulement). Vérifié en direct sur un vrai quart de finale des playoffs Champions 2026.
- [x] L'attribution Liquipedia apparaît partout où son contenu est utilisé. Seul usage actuel : le texte de contexte sous la frise de la page Saison (écran 01), avec « Source : Liquipedia (CC-BY-SA) » toujours affiché en dessous. Un deuxième bug trouvé en vérifiant en conditions réelles : le job worker cherchait la page Liquipedia à partir du nom de l'étape à bracket ("Group C", bien trop générique — tombait sur un tournoi 2021 sans rapport) plutôt que du tournoi parent ("Champions 2026", un nom spécifique) ; corrigé en remontant à la compétition parente avant la recherche.
- [ ] Test utilisateur avec 2–3 personnes qui ne suivent pas Valorant. **Reporté** : seul le compte du projet a testé en conditions réelles sur téléphone (onboarding, glossaire, forme récente, sans spoil, fiche équipe, réglages, attribution Liquipedia — tout fonctionne, un bug de session expirée trouvé et corrigé au passage, voir `docs/00` §7). Pas de test formel avec 2–3 personnes externes qui ne suivent pas Valorant à ce stade.

**Reporté** : granularité du sans spoil par catégorie (écran 22 en montre une par catégorie — Valorant, Top 14 — resté un seul réglage global tant qu'une 2e catégorie n'a pas de vraies données, `docs/00` §7) ; envoi réel du résumé du matin (le réglage existe, pas encore de job worker pour l'envoyer, faute de contenu "l'essentiel en 3 points" à générer) ; "Transferts et effectif" de la fiche équipe et détail par carte ("Carte 1 · Ascent") du dernier match (aucune source de roster branchée, et le nom/gagnant de chaque carte n'est pas résolu vers notre `entityId` à l'ingestion) ; logos des équipes dans Sources et crédits (pas encore de logo ingéré). Comme pour la fidélité visuelle des J3/J5, la structure et le fonctionnement priment sur l'exhaustivité de la maquette.

---

## J7 — Mise en ligne (ajouté)

**Objectif** : l'appli tourne 24 h/24 et de premiers testeurs l'utilisent.

**Périmètre** (`docs/03` §8–10)
- `infra/docker-compose.yml` de production : `api`, `worker`, `postgres`, `redis`, `backup` (+ `uptime-kuma` en option), avec limites CPU/RAM.
- **Exposition** via Tailscale Funnel (décision du J7, `docs/00` §7), aucun port ouvert.
- GitHub Actions : tests, build de l'image, publication sur GHCR.
- Sauvegardes : `pg_dump` nocturne, 7 jours sur le NAS + copie chiffrée hors site ; **une restauration testée**.
- Supervision : `/health`, tableau de bord fournisseurs, alertes (ingestion arrêtée > 15 min, quota > 80 %, push en échec > 5 %), Sentry côté API et appli.
- Distribution bêta : TestFlight et/ou test interne Google Play.
- Politique de confidentialité, licence open source du dépôt.

**Critères d'acceptation**
- [x] L'appli d'un testeur fonctionne hors du réseau de la maison. Vérifié le 2026-09-27.
- [x] Une coupure simulée du NAS : l'appli reste utilisable en hors ligne, l'alerte arrive. Vérifié le 2026-09-27 en coupant réellement le NAS : deux bugs trouvés et corrigés au passage (Dio sans délai, spinner bloqué indéfiniment plutôt que de basculer sur le cache ; puis, une fois le délai ajouté, `ETagCacheInterceptor` ne traitait pas un 502 renvoyé par Tailscale Funnel — reachable, backend mort — comme une coupure). L'alerte `ALERT_WEBHOOK_URL` tourne **dans le worker** : elle ne peut détecter qu'un problème d'ingestion pendant que le worker tourne encore, pas une coupure totale du NAS (le worker s'arrête aussi) — un moniteur externe (UptimeRobot) couvre ce dernier cas, vérifié en coupant réellement le NAS.
- [x] Restauration d'une sauvegarde réussie. Vérifiée le 2026-09-27 sur le vrai NAS : restauration d'un dump réel dans une base jetable (`news_restore_test`), nombre de lignes identique à la base de prod (44 = 44) avant de la supprimer.

**Vérifié en conditions réelles** sur le NAS (TrueNAS SCALE) : image construite et publiée sur GHCR par CI, `docker compose` de prod démarré avec Postgres/Redis/api/worker/backup, migrations Prisma automatiques au démarrage, exposition via Tailscale Funnel (l'API cohabite avec d'autres applis sous `/news` sur le port 443 déjà partagé, `PUBLIC_PATH_PREFIX` reste vide car Tailscale retire lui-même le préfixe avant de relayer). Deux bugs supplémentaires trouvés en le faisant : une fausse alerte "ingestion arrêtée" se déclenchait dès que PandaScore n'avait simplement rien de nouveau à rapporter (`provider_ref.last_synced_at` ne bouge que sur un vrai changement, règle 4 de `CLAUDE.md`) — corrigé par un battement dédié dans Redis, mis à jour à chaque poll réussi ; et le healthcheck Postgres (10 tentatives, ~50s) abandonnait trop tôt après un arrêt interrompu (~72s de rejeu du WAL constaté en vrai), faisant échouer le démarrage de `api`/`worker`. Un troisième bug, plus ancien (J2), trouvé en revérifiant les tests après 18h d'ingestion continue : `home.highlights` ("les grands rendez-vous") ne triait que par date croissante sans exclure les matchs déjà `finished`, qui finissaient par remplir les 10 places à mesure que l'historique s'accumule — corrigé.

**Reporté** : distribution bêta Google Play (compte retrouvé, application pas encore publiée sur la piste de test interne) ; copie de sauvegarde hors site (règle 3-2-1, aucune destination choisie) ; licence open source du dépôt ; nom de domaine dédié (pas nécessaire avec Tailscale Funnel pour l'instant, contrepartie acceptée) ; nom de l'appli et logo/icône définitifs ; écrire à PandaScore pour l'attribution exigée.

---

## J8 — Polissage UI/UX Valorant (ajouté)

**Objectif** : cinq retours utilisateur sur l'appli déjà en test (latence perçue, écrans peu lisibles pour un néophyte, Agenda bloqué sur aujourd'hui, écran Suivis trop pauvre, petits problèmes de mise en page) corrigés en un seul jalon de polissage, sans nouvelle fonctionnalité.

**Périmètre**
- Bouton « Suivre » : retour optimiste (le bouton change avant la réponse réseau).
- Accueil : `SafeArea` autour de l'en-tête, pastille active de la tab bar recentrée.
- Agenda : navigation ±14 jours (flèches précédent/suivant sur le bandeau de semaine).
- Suivis : logo d'équipe et statut « encore en course »/« éliminée ».
- Agenda : phrase d'enjeu courte sous le nom d'une poule GSL (« Group A »/« Group B »… tous identiques sans ça).

**Critères d'acceptation**
- [x] Le bouton « Suivre »/« Suivi » change d'état immédiatement au tap, avant la réponse réseau, et revient en arrière si l'appel échoue. Vérifié par 3 tests unitaires (`apps/mobile/test/follows_controller_test.dart`) et en conditions réelles sur téléphone Android physique.
- [x] L'Accueil affiche la date sous la barre de statut (plus de chevauchement) et la pastille active de la tab bar reste bien centrée sur l'icône/le libellé, y compris le 1er et le dernier onglet. Vérifié en conditions réelles.
- [x] L'Agenda permet de naviguer au moins 14 jours avant et après aujourd'hui via des flèches, désactivées aux bornes. Vérifié par 3 tests widget et en conditions réelles sur téléphone Android physique.
- [x] L'écran Suivis affiche le logo de l'équipe (repli sur les initiales) et un statut « encore en course »/« éliminée » pour un suivi d'équipe. Vérifié par un test e2e Supertest (`apps/api/src/auth.e2e.spec.ts`, contre le vrai Postgres de dev) et 3 tests widget Flutter ; **non revérifié à l'œil sur l'écran Suivis en conditions réelles** faute d'un chemin de navigation existant vers la fiche d'une équipe suivie dans l'appli actuelle (voir « Reporté »).
- [x] Dans l'Agenda, un match de poule GSL affiche une courte phrase précisant que la poule mène à la suite du tournoi. Vérifié par un test domaine unitaire et en conditions réelles sur les vraies données Champions 2026.

**Vérifié en conditions réelles** sur un téléphone Android physique (4 des 5 lots — le lot Suivis via tests automatisés seulement, voir ci-dessus) : un vrai bug de débordement trouvé en testant l'Agenda sur cet écran (360 de large logique) — les deux flèches de navigation plus les 7 pastilles de jour ne tenaient pas dans la largeur disponible, débordement de 32 px — corrigé en réduisant la cible tactile des flèches (32×32 plutôt que le minimum Material 48×48) et la largeur des pastilles de jour (36 plutôt que 40). Un deuxième point trouvé en vérifiant : la phrase d'enjeu des poules n'apparaissait pas tant que le serveur API de développement (démarré avant ce jalon) n'avait pas été redémarré avec le nouveau code — pas un bug de l'appli, rappel que `pnpm api:dev` ne recharge pas à chaud.

**Reporté** : vérification visuelle du logo/statut sur l'écran Suivis en conditions réelles (l'onglet « Équipes » de la page Valorant et les lignes de classement du tableau des groupes ne mènent pas encore à la fiche d'une équipe — lacune préexistante, pas causée par ce jalon, mais qui empêche d'atteindre un suivi d'équipe autrement que par un match dont les participants sont affichés) ; granularité éventuelle de la phrase d'enjeu par format autre que GSL (hors périmètre, aucun autre format n'en a besoin pour l'instant).

---

## J9 — Onglet Compétitions et hiérarchie de navigation (ajouté)

**Objectif** : remplacer l'unique point d'entrée vers la page Valorant (une ligne sur l'Accueil) par une vraie navigation catégorie → jeu → compétition, qui tiendra quand d'autres jeux et sports arriveront. Décidé en discussion le 2026-09-29 ; la logique complète se cadre avant d'implémenter.

**Périmètre**
- **5ᵉ onglet « Compétitions »** dans la tab bar, centré et mis en avant. L'écran contient : une barre de recherche en haut (jeux et compétitions uniquement, filtrage côté appli sur le catalogue déjà chargé) ; un raccourci « Favoris » (jeux mis en favori) ; les catégories en accordéon (Esport, Sport…) qui déroulent la liste des jeux/sports. **Une catégorie sans donnée n'est pas affichée** : au départ, seulement Esport avec Valorant.
- **Page jeu** (ex-« Valorant · saison VCT 2026 ») avec trois onglets : **Compétitions** (frise d'avancement de la saison, compétitions en cours puis passées), **Équipes** et **Agenda**, ces deux derniers filtrés sur le jeu.
- **Page compétition** (ex-Champions 2026) : le tournoi seul (« Maintenant », bracket, matchs), sans onglets. « Suivre »/« M'alerter » restent au niveau compétition, équipe et match.
- **Favori de jeu** : raccourci d'accès uniquement, **aucune notification**. Vocabulaire « Favori » réservé aux jeux entiers ; « Suivre » ne change pas ailleurs. À stocker à part des abonnements (`subscription` est hiérarchique : un abonnement sur la ligue racine notifierait tous les matchs du jeu).
- Retirer de l'Accueil la ligne d'accès à la page Valorant.

**À vérifier au cadrage** : le bouton « Suivi » actuel de l'écran Valorant est-il un vrai abonnement sur la ligue racine (donc notifie pour tout le jeu) ? Si oui, le migrer vers le favori. Mettre à jour `docs/02` (nouvelle tab bar et écrans) avant d'implémenter.

**Cadrage (2026-09-29)** : le modèle n'avait aucune notion de « jeu » (les racines sont des ligues : VCT, Esports World Cup…) → colonne `competition.game` (slug, renseignée à l'ingestion, rattrapée en migration). Favoris dans `favorite_game`, séparés de `subscription`. Le bouton « Suivi » de l'ancien écran Valorant était bien un abonnement sur la ligue racine : remplacé par l'étoile « Favori » (pas de migration des abonnements existants, un seul compte concerné). L'onglet **Équipes** est inclus au périmètre (`GET /v1/entities?game=`). Recherche : jeux, ligues et séries du catalogue, côté appli.

**Hors périmètre** : recherche d'équipes et de joueurs (plus tard, demandera un endpoint dédié) ; catégories Sport/Politique (pas encore de données).

**Critères d'acceptation**
- [x] Depuis n'importe quel écran, l'onglet Compétitions mène à un jeu en 2 taps (catégorie, jeu).
- [x] La recherche trouve un jeu ou une compétition par son nom (insensible à la casse et aux accents).
- [x] Mettre un jeu en favori l'ajoute au raccourci, sans créer d'abonnement ni de notification.
- [x] La page jeu affiche la frise de saison, les compétitions en cours/passées, Équipes et Agenda filtrés sur le jeu.
- [x] La page compétition ne montre plus la frise ni les compétitions passées.
- [x] Vérifié en conditions réelles sur téléphone Android physique.

---

**Fait (2026-09-29).** Vérifié : tests API (25, dont 4 e2e pour catalogue/favoris/équipes par jeu), Flutter (widgets, bracket, suivis), `flutter analyze` propre, puis conditions réelles sur téléphone Android physique.

**Reporté** : golden de la tab bar à régénérer via la CI (le widget a changé, procédure du `CLAUDE.md` ; échoue déjà sous Windows à cause de la police) ; page dédiée à la ligue (VCT) pour y afficher son logo en grand (le logo de ligue n'apparaît pour l'instant que dans la recherche) ; recherche d'équipes et de joueurs ; catégories Sport/Politique (pas de données) ; logos de jeux autres que Valorant (un SVG par jeu à ajouter dans `apps/mobile/assets/games/<slug>.svg`).

---

**J10 (polissage) passe avant les options communautaires** : les écrans existants sont affinés avant d'y ajouter du nouveau. Son périmètre se fixe au `/jalon 10` à partir de la liste des écrans que le porteur du projet veut retoucher ; candidats déjà connus, reportés des jalons précédents : fidélité pixel-perfect aux maquettes (J3, J5), fiche d'équipe atteignable depuis un suivi (J8), fluidité de l'arbre à 60 i/s et remplissage en vrai (J5).

**Ordre décidé le 2026-09-29** (voir `docs/00` §7) : J11, J12, J13 ci-dessus, chacun cadré dans sa propre discussion (`/jalon <n>`). Le forum vient ensuite par étapes (fils par équipe, tournoi, jeu, puis création libre), toujours sur Valorant seul : les autres jeux attendent que Valorant soit complet. Les options communautaires sont **facultatives** pour l'utilisateur : l'appli reste utilisable pour les seuls résultats. Sont déjà connus : passer du compte anonyme à un compte avec pseudo (J11), et prévoir avant toute ouverture publique du forum signalement, blocage, conditions d'utilisation, suppression des messages avec le compte (RGPD).

## J10 — Polissage des pages existantes (ajouté)

**Objectif** : affiner les écrans déjà en place pour qu'ils correspondent au porteur du projet. Parti de retours sur l'Accueil et Suivis (2026-09-29), le jalon a absorbé au fil des essais sur téléphone plusieurs ajouts assumés (familles de compétitions et sourdine, onglet Ligues, rafraîchissement automatique, ordre stable des équipes).

**Retours par page**

*Accueil (« Aujourd'hui »)*
- Icône de recherche : à retoucher (ce qui ne va pas reste à préciser).
- « Grands rendez-vous » : n'afficher que les finales (grande finale via `event_link`), avec la raison pour laquelle c'est un grand rendez-vous. La section disparaît hors phase finale.
- Cartes des matchs à venir : bouton « Suivre » visible ; logos des équipes à la place du seul gros nom ; davantage d'informations (à préciser : compétition et phase, format BO, heure locale, phrase « pourquoi ce match compte »). La couleur des cartes ne représente pas celle des équipes : PandaScore ne fournit pas de couleurs, choix à faire entre couleur neutre et couleur dominante extraite du logo.
- Compte à rebours en gros à la place du « VS », mis à jour à la minute (secondes seulement dans la dernière minute), sans animation (règle 13).

*Suivis*
- Le nom d'une compétition suivie mène à sa page ; proposé aussi : le nom d'une équipe suivie mène à sa fiche (écran 10).
- Retirer le « x » qui désabonne directement : le désabonnement se fait depuis la page de la compétition (ou de l'équipe), dont le bouton « Suivi » doit donc y être bien visible (à vérifier sur la fiche d'équipe).
- État vide : à décider (invitation vers l'onglet Compétitions ou inchangé).

**Candidats reportés des jalons précédents** : fidélité pixel-perfect aux maquettes (J3, J5) — **abandonnée** (voir ci-dessous) ; fluidité de l'arbre à 60 i/s et remplissage en vrai (J5).

**Cadrage (2026-09-29)** : liste des pages figée à Accueil et Suivis (aucune autre page à retoucher pour l'instant). Décisions : l'icône de recherche ouvre l'onglet Compétitions avec le champ de recherche focalisé ; couleur dominante du logo sur les cartes de l'Accueil (comme `EventCard`), sans la bande grise au milieu du dégradé ; bouton cloche (icône seule) directement sur toute carte de match à venir, qui alerte sans ouvrir la page du match ; « Grands rendez-vous » = carte dédiée à la **grande finale de la phase finale uniquement, dans les 7 prochains jours** (avec phrase de contexte), qui disparaît sinon ; page compétition avec bouton « Suivre » (n'existait pas hors onboarding) avant de retirer le « x » de Suivis. **Retrait de « Tes suivis » de l'Accueil** (décidé le 2026-09-30) : les matchs suivis y doublonnaient « À suivre » et l'écran Suivis ; l'Accueil montre le moment (en direct, à suivre, grande finale), Suivis la liste complète. Logos des cartes agrandis (56 px en tuile réduite, 68 px sinon). Compte à rebours en HH:MM:SS à deux-points clignotants (demande du 2026-09-30, dérogation à la règle 13 « pas d'animation sur ce qu'on voit souvent » : limitée au seul compte à rebours de l'Accueil et coupée en mouvement réduit). Couronne dorée du vainqueur sur les matchs terminés (l'or est aussi « mes suivis » : distingué ici par la forme). **Page de ligue** (VCT…) ajoutée le 2026-09-30 (`league_screen.dart`, construite depuis le catalogue, sans nouvel endpoint) : logo, « Suivre »/« Suivi » (c'est là qu'on se désabonne d'une ligue), liste de ses compétitions ; atteinte depuis Suivis et depuis la recherche. Une catégorie ne peut pas être suivie depuis l'appli (l'onboarding ne suit que des équipes) : pas de désabonnement à prévoir. **« Sans spoil » désactivé par défaut** (décidé le 2026-09-30, l'option reste dans Réglages) : nouveau défaut de `user_setting.spoiler_free` (migration `20260930010000`), y compris pour le texte des notifications d'un compte sans réglage. Les comptes existants gardent leur valeur (à basculer dans Réglages) ; l'appli garde `sans spoil` par précaution tant que le réglage n'est pas chargé. **Familles et « tout sauf une »** (demandé le 2026-09-30, ajouté au J10) : « Suivre » sur une page de ligue ouvre un choix (« Toute la ligue » + une case par famille sans l'année : Champions, Masters…, « Valider » suit directement, c'est aussi là qu'on se désabonne). Nouvelle table `competition_family` (nom = nom de la série sans l'année, `Masters <ville>` regroupé en « Masters »), nouveau type d'abonnement `competition_family` (les éditions futures sont couvertes dès leur ingestion), sourdine `subscription.muted` sur une série (**la règle la plus proche du match l'emporte** : série en sourdine > famille > ligue ; la sourdine ne coupe pas une équipe ou un match suivi). Les pages compétition affichent « Suivi via VCT » avec « Ne pas m'alerter » / « Réactiver les alertes ». **Rafraîchissement automatique** (bug remonté le 2026-09-30 : app laissée ouverte la nuit, l'Agenda restait sur la veille et l'Accueil/Suivis gardaient des matchs déjà en direct) : `AutoRefresh` recharge l'Accueil, les Suivis et les pages de match chaque minute au premier plan (l'Agenda aussi quand son onglet est affiché), tout au retour au premier plan et au changement d'onglet ; la date du jour (`todayProvider`) est resynchronisée, l'Agenda n'a plus de dates `static` ; l'ancien contenu reste affiché pendant le rechargement. **Onglet « Ligues »** sur la page jeu (Compétitions · Ligues · Équipes · Agenda, demandé le 2026-09-30) : la page de ligue n'était atteignable que par Suivis et la recherche. Chaque ligne : logo, nom, nombre de compétitions, point rouge « En cours » (`LiveDot`, figé en mouvement réduit) si une compétition de la ligue est en cours (calculé par les dates des séries, le fournisseur ne donne pas de statut de série) ; les ligues en cours d'abord. Le **bouton d'explications des compétitions** (façon guide officiel VCT) est **reporté à un jalon dédié** : contenu éditorial à rédiger avec nos propres phrases (pas de recopie du site officiel, qui ne sert que de source de vérification), stocké en base comme le glossaire, relu avant mise en base. **Ordre des équipes stable** (retour du 2026-09-30 : les équipes changeaient de côté d'une carte à l'autre) : `event_participant.side` (0 = gauche, 1 = droite), jamais écrit jusque-là, est désormais renseigné à l'ingestion (ordre des adversaires du fournisseur) et rattrapé pour l'existant depuis le nom du match ; l'API trie par `side`. **Carte en direct** de l'Accueil refaite sur la carte de match commune (`EventCard(banner: true)` : logos, scores, teinte rouge, « EN DIRECT ») avec la ligne dorée « Ensuite » conservée, seulement si le match suivant a lieu aujourd'hui (un match de demain n'est pas « ensuite »). Fidélité pixel-perfect aux maquettes et fluidité de l'arbre : reportées.

**Critères d'acceptation**
- [x] Plus de gris entre les deux couleurs d'une carte de match, y compris dans l'en-tête de l'écran du match (dégradé et logo d'équipe partagés dans `widgets/match_visuals.dart`, logos contenus dans leur case).
- [x] Une carte de match à venir a une cloche qui alerte sans ouvrir la page du match (retour optimiste, message d'erreur si l'appel échoue) ; pas de cloche en direct/terminé.
- [x] L'Accueil ne répète plus les suivis (section « Tes suivis » retirée) et n'utilise plus de carte maison : « À suivre » et le bandeau en direct sont basés sur `EventCard`.
- [x] Toute carte de match à venir dans les 24 h (Accueil, Agenda, Suivis…) affiche un compte à rebours HH:MM:SS à la place du « VS », deux-points clignotants (fixes en mouvement réduit, règle 13) ; au-delà, le « VS » seul.
- [x] « Grands rendez-vous » n'affiche que la grande finale en phase finale, si elle a lieu dans les 7 prochains jours, avec le nom du tournoi, sa phrase « pourquoi ça compte » et « M'alerter » ; « Adversaires à déterminer » si les équipes ne sont pas connues ; section absente hors phase finale.
- [x] Suivis : nom de compétition → page compétition, nom d'équipe → fiche, plus de « x » ; le désabonnement se fait depuis la page compétition (bouton « Suivre »/« Suivi » en haut) ou la fiche équipe ; état vide avec bouton « Explorer les compétitions ».
- [x] Sur une carte de match terminé, une couronne dorée surmonte le logo du vainqueur ; jamais quand le score est masqué (sans spoil).
- [x] Une ligue suivie (VCT) mène à sa page depuis Suivis ; on s'en désabonne depuis cette page.
- [x] Le libellé « Compétitions » de la tab bar tient sur une ligne sur un écran de 360 dp.
- [x] Suivre une famille (« Champions ») couvre aussi ses éditions futures sans rien refaire ; « Masters » regroupe toutes les villes. Vérifié par les tests du moteur (`notification-dispatch-family.spec.ts`) et de l'API.
- [x] « Tout sauf une » : une série en sourdine n'alerte plus alors que la ligue reste suivie ; une équipe suivie continue d'alerter. Sa page affiche « Suivi via VCT » puis « Réactiver les alertes ».
- [x] « Suivre » sur la page de ligue ouvre le choix (cases, « Valider » suit directement, décocher tout se désabonne).
- [x] Une app laissée ouverte reste à jour : la date de l'Agenda et de l'Accueil change à minuit, un match qui passe en direct est rechargé sans intervention (minuterie de 60 s, retour au premier plan, changement d'onglet), sans spinner.
- [x] La page jeu a un onglet « Ligues » : ses ligues, un point rouge « En cours » sur celles qui ont une compétition en cours, un tap ouvre la page de la ligue.
- [x] Les équipes d'un match gardent le même côté partout (Accueil, Agenda, Suivis, écran du match, tableau) ; la carte en direct de l'Accueil est une carte de match rouge avec « Ensuite ».
- [x] L'icône de recherche de l'Accueil ouvre la recherche de l'onglet Compétitions, clavier ouvert.
- [x] Vérifié en conditions réelles sur téléphone Android physique (2026-09-30) : Accueil (compte à rebours entre les logos), Suivis, page de ligue, Agenda. Deux défauts trouvés et corrigés : libellé « Compétitions » qui passait à la ligne, compte à rebours trop large qui chevauchait un logo. Couronne du vainqueur non vue à l'écran (aucun match terminé affiché), couverte par test.

**Fait (2026-09-30).** Vérifié : lint propre ; tests domaine 50, providers 13, API 33 (suites e2e exécutées l'une après l'autre), worker 12 ; `flutter analyze` propre, 87 tests Flutter ; CI verte, goldens inclus (le golden de la tab bar, reporté du J9, passe sans régénération ; celui d'`EventCard` a été régénéré via la CI). En conditions réelles : téléphone Android physique (Accueil, Suivis, page de ligue, Agenda, cartes de match, couronne du vainqueur, sourdine « tout sauf une », rafraîchissement après une nuit avec l'appli ouverte) et émulateur (fenêtre de choix par famille, onglet Ligues, carte en direct) ; base et API de dev contrôlées (55 participants avec un `side`, aucun inversé ; familles Champions et Masters à 2 éditions).

**Abandonné** : fidélité pixel-perfect aux maquettes (J3, J5) — jamais validable, l'écart se corrige au fil des retours d'usage plutôt que par un jalon.

**Reporté** : guide d'explications des compétitions (jalon dédié : contenu éditorial, textes propres relus avant mise en base) ; fluidité de l'arbre à 60 i/s et remplissage en vrai (J5, attendre les playoffs) ; « Ensuite » = prochain match du jour seulement, pas de notion de « juste après » (à revoir si besoin).

---

## J11 — Comptes avec pseudo, profil, pronostics et groupes d'amis (ajouté)

**Objectif** : première couche communautaire, **optionnelle** (l'appli reste utilisable pour les seuls résultats) : pronostiquer des matchs en points fictifs, se comparer à ses amis, avoir une page de profil. Décidé le 2026-09-29 (`docs/00` §7).

**Périmètre**
- **Compte avec pseudo** : passage du compte anonyme (J4) à un compte identifiable, **sans perdre les abonnements existants** (l'utilisateur anonyme qui « crée son profil » garde ses suivis). Le compte anonyme reste possible pour qui ne veut pas de la couche communautaire.
- **Pronostics** en points fictifs : pronostiquer le vainqueur (et éventuellement le score de série) d'un match, jusqu'à son début ; points attribués à la fin du match. Pas de gain réel, pas de lot, pas d'achat de points (reste hors « jeu d'argent »). Tables génériques (`prediction`, `quiz_answer` de `docs/03`), aucune table propre à un jeu (règle 3).
- **Groupes d'amis** façon Mon Petit Prono : créer un groupe, rejoindre par code d'invitation, classement du groupe.
- **Page de profil** : pseudo, résumé des badges par jeu/sport (les badges eux-mêmes servent surtout au J13), score de pronostics, quelques statistiques.
- Compatible **sans spoil** : un pronostic ne révèle pas le résultat d'un match pour un utilisateur qui masque les scores.

**À trancher au cadrage** : méthode de connexion (lien magique par e-mail, Google…) ; unicité et règles du pseudo (pseudos injurieux) ; barème des pronostics ; ce que contiennent exactement les « petites stats » du profil ; suppression du compte avec ses données (RGPD, `DELETE /v1/me` existe déjà).

**Hors périmètre** : forum (J13) ; pronostics sur autre chose que des matchs (compétition entière, etc.) au début.

**Décisions du cadrage (2026-09-30)** : voir `docs/00` §7. Invité en lecture seule ; compte e-mail + mot de passe (Firebase Auth) ; pseudo unique ; barème 3 + 2 ; groupes à code de 8 caractères ; onglet Suivis retiré ; anciens comptes anonymes supprimés.

**Actions manuelles** : console Firebase → Authentication → Sign-in method → activer **E-mail/Mot de passe** ; `FIREBASE_*` dans le `.env` lu par l'API (en prod, le même `.env` que le worker).

**Critères d'acceptation**
- [x] Un invité navigue (Accueil, Agenda, Compétitions, match) sans compte ; toute action réservée (suivre, alerter, favori, réglage, pronostic) propose de créer un compte, puis continue après la connexion.
- [x] Inscription par e-mail + mot de passe, e-mail de vérification reçu, connexion, déconnexion, mot de passe oublié.
- [x] Pseudo unique (casse et accents ignorés), refusé s'il est trop court, avec caractères spéciaux ou interdit ; changement limité à un par 30 jours ; exige un e-mail vérifié.
- [x] Un pronostic se pose et se modifie jusqu'au début du match, puis se verrouille ; les points sont attribués une seule fois à la fin du match (3, +2 avec le score exact).
- [x] Deux comptes forment un groupe par code et se voient classés ; groupe complet et code inconnu refusés ; le créateur supprime, les autres quittent.
- [x] Sans spoil respecté : points, stats et classements masqués (appui long pour révéler). *Le score d'un match est désormais flouté (J11) ; le masquage des points, stats et classements est couvert par des tests de widgets, vérifié à l'œil sur téléphone pour les scores seulement.*
- [x] Suppression du compte complète (Firebase, pronostics, groupes, suivis), pseudo libéré.
- [x] L'avatar est le logo d'une équipe, choisi par jeu ; le profil d'un joueur s'ouvre depuis le classement d'un groupe (membres d'un groupe commun seulement) ; le code d'invitation s'affiche derrière une icône d'invitation, avec un bouton de copie.
- [x] L'onglet Jeux mène à Pronostics ; les matchs à pronostiquer se filtrent par jeu du catalogue. *Filtre par jeu non visible tant que Valorant est le seul jeu (les puces n'apparaissent qu'à partir de deux jeux), couvert par la construction de la requête seulement.*
- [x] Onglet Suivis retiré (4ᵉ onglet vide) ; « Tes suivis » sur l'Accueil ; profil ouvert depuis l'avatar de l'Accueil, réglages depuis le rouage du profil.
- [x] **Vérifié en conditions réelles** sur téléphone Android : inscription, e-mail de vérification reçu, pseudo, pronostic sur un vrai match, points reçus à la fin, groupe à deux comptes. *Réserve : le règlement des points est vérifié sur le **vrai worker** avec un match simulé (5 / 3 / 0 points, « pronostics réglés » journalisé, règlement unique), pas sur un match PandaScore réel ; le pronostic réel de `Wylfram` se réglera par le même chemin à la fin de son match.*

**Fait (2026-09-30).** Vérifié : lint propre ; tests domaine 58, API 49 (suites e2e l'une après l'autre), worker 15 ; `flutter analyze` propre, tests Flutter verts ; CI verte sur une branche jetable (backend + mobile). Goldens : les 9 échecs locaux ne viennent que du rendu Windows, la CI régénère des images **identiques** à celles du dépôt (rien à recommiter). En conditions réelles sur téléphone Android et émulateur : invité, garde de compte, inscription avec e-mail de vérification, pseudo et changement, avatar (logo d'équipe), groupe à deux comptes, profil d'un joueur, invitation, suppression de compte, sans spoil (score flouté, appui long), pronostic posé sur un vrai match. Règlement des points vérifié sur le vrai worker avec un match simulé.

**Reporté** : **points d'un vrai match PandaScore** (le pronostic réel de `Wylfram` se réglera à la fin de son match) ; **modèles d'e-mails Firebase et page « Your email has been verified »** (avec l'identité de l'app, voir « Points ouverts ») ; **classement de groupe par jeu** (global pour l'instant) ; **lien Google / Apple** pour les comptes (Apple obligatoire à la sortie iOS) ; **pronostic directement sur les cartes de match** (seulement sur l'écran du match) ; **liste de mots interdits** du pseudo minimale, à étoffer (le forum du J13 aura sa modération).

---

## J12 — Apprentissage Valorant (ajouté)

**Objectif** : donner envie de jouer aux néophytes qui regardent une compétition, avec des tutos écrits à la main en français (comment marche le jeu, les rôles, les cartes), dans l'esprit du glossaire de J6.

**Périmètre**
- Section « Apprendre » dans l'espace Valorant, contenu éditorial versionné dans le dépôt (comme le glossaire du seed, `pnpm db:seed`, ou fichiers embarqués : à choisir au cadrage).
- Divulgation progressive : l'essentiel d'abord, le détail si on le cherche.

**Hors périmètre (reporté)** : meilleures compositions par carte, stats par arme, stats joueurs. Le plan gratuit PandaScore n'a ni noms de cartes ni stats (règle 6), l'API officielle de Riot exige une clé de production validée, et le scraping est interdit (règle 7). À revoir plus tard, source par source.

**Décidé au cadrage** : contenu **embarqué dans l'appli** (`apps/mobile/assets/learn/<jeu>.json`), pas en base ; textes **écrits par nous**, vérifiés contre les pages officielles mais **jamais recopiés** ; **aucune image du jeu** (la politique « Legal Jibber Jabber » de Riot exclut les projets publiés sur Google Play ou l'App Store sans licence écrite ou clé d'API Riot) : illustrations dessinées avec des widgets et les tokens du thème.

**Critères d'acceptation**
- [x] Un onglet « Apprendre » dans la page Valorant liste 5 tutos en français (le jeu, un round, les rôles, les cartes, comprendre un match), chacun avec un résumé visible d'emblée.
- [x] Un article montre l'essentiel d'abord, puis des sections courtes (texte + schéma) qu'on peut replier ; les mots du glossaire s'ouvrent au toucher.
- [x] Une icône « ? » jaune mène directement au tuto qui explique la page (page jeu, compétition, écran d'un match), avec un bouton « Toutes les règles · Valorant » vers la liste.
- [x] Les tuiles d'un schéma ont toutes la même taille ; aucun débordement sur un écran de 360 de large (test automatisé sur chaque article).
- [x] Le contenu est disponible hors ligne (fichier embarqué).
- [x] Un nouveau jeu s'ajoute en écrivant son fichier JSON (schémas décrits en données : tuiles, étapes, gros chiffres), sans code Dart de contenu.
- [x] Exemple en 3 cartes de la maquette 04 dans la feuille glossaire « BO3 » (manquait depuis le J6).
- [x] **Vérifié en conditions réelles** sur émulateur Android (Pixel Tablet) : liste, articles, « ? », rendu des tuiles validé à l'œil.
- [x] **Complément du 2026-10-01** : glossaire étendu (11 termes cliquables dans les tutos), 7 tutos Valorant (+ « Le circuit pro », « Envie d'essayer ? »), guide `app` (pronostics, sans spoil, fiche équipe), « ? » sur la page ligue / fiche équipe / Pronostics / Réglages, carte « Nouveau sur Valorant ? » sur l'Accueil et bouton dans l'onboarding, mini-quiz « Teste-toi », libellés d'accessibilité sur les schémas.
- [x] **Progression liée au compte** : table `learn_progress`, `GET /v1/me/learn` et `PUT /v1/me/learn/:guide/:articleId` ; tutos lus et quiz réussis, synchronisés (et gardés en local pour l'invité), affichés sur le profil (« Mes tutos »). Simple compteur, **sans points**.
- [ ] *Reporté :* relu par un néophyte externe (seul le compte du projet a testé).

**Fait (2026-10-01).** Vérifié : `flutter analyze` propre ; 96 tests Flutter verts, dont 4 tests du J12 ; les seuls échecs locaux sont 4 goldens (`event_card`, `follow_button` ×2, `glass_tab_bar`), simple écart de rendu Windows déjà connu, sur des widgets non touchés par ce jalon. Aucun changement backend (pas de migration, pas d'endpoint, pas de client Dart à régénérer).

**Reporté** : **relecture par un néophyte externe** ; **vérification sur téléphone Android physique** (émulateur seulement) ; **onglet « Apprendre » et « ? » pour les autres jeux** (`_learnGames` dans `game_screen.dart` est figé sur `valorant`, à déduire de la présence du fichier JSON) ; **images du jeu** (nécessitent une licence ou une clé d'API Riot) ; **guide des compétitions** (Kickoff, Masters, Champions, formats), item suivant d'« Ensuite ».

---

## J13 — Forum par match, bêta fermée (ajouté) — **Fait (2026-10-01)**

**Objectif** : permettre de discuter d'un match sans que ça dégénère. Optionnel, comme le reste de la couche communautaire. **Prérequis : J11** (comptes avec pseudo).

**Périmètre**
- Un **fil de discussion créé automatiquement pour chaque match**, **texte seul** (ni images ni liens libres).
- **Pas de cloisonnement par équipe** : tout le monde lit tout. Le suivi d'une équipe donne un **badge visible** à côté du pseudo, **selon le jeu ou le sport du forum** (équipe Valorant dans un forum Valorant). Un seul « camp » actif par jeu/sport, modifiable avec un délai (par exemple 1 fois par semaine).
- **Modération de base** : signalement, masquage d'un utilisateur, mode lent, filtre de mots, ancienneté minimale du compte avant de pouvoir écrire, outil pour retirer un message rapidement.
- **Bêta fermée** avant toute ouverture publique.

**À prévoir avant l'ouverture publique** : conditions d'utilisation, retrait rapide des contenus signalés, blocage d'utilisateur, suppression des messages avec le compte (RGPD), exigences des stores pour le contenu généré par les utilisateurs.

**Hors périmètre (étapes suivantes)** : fils par équipe, tournoi et jeu, puis création libre de discussions ; autres jeux (Valorant doit être complet d'abord).

**Décisions du cadrage (2026-10-01)** : pas de mode lent (inutile) ; conditions d'utilisation rédigées dès maintenant (`apps/mobile/lib/features/forum/forum_terms.dart`, version 1, à relire avant l'ouverture publique) ; étapes suivantes construites d'emblée : **réponses** (une profondeur), **réactions** (5, une par personne), **notification de réponse**, **fils par match, équipe, compétition, jeu** et **discussions libres** (5 par jour et par compte). **Réponses imbriquées** (profondeur 6 max, une réponse à une réponse crée un niveau de plus ; supprimer un message du milieu fait remonter ses réponses), **repli par appui long** (« Voir les N réponses ») avec repère vertical façon Reddit, **titre complet** en tête du fil, **pseudo cliquable** vers le profil du joueur (ouvert à qui écrit sur le forum, avec ses camps). **Fil du direct** distinct de la discussion d'avant et d'après match (écriture ouverte seulement pendant le match), qui se comporte comme un **tchat à la Twitch** : liste à plat, avatar + pseudo + texte, un tap pour répondre en citant le message (pas de fil), appui long pour signaler, bloquer ou modérer, rechargement toutes les 5 s, ni réactions ni spoiler ni épingle, **modification** dans les 5 minutes, **spoiler par message**, **plafond de 10 messages par minute**, **journal de modération**, **mentions @pseudo** et **discussions suivies** avec notifications, **tri** des discussions (récentes, actives, populaires) et **messages épinglés** (2 au plus, modérateurs). **Pas de pièces jointes** (contredit « texte seul », demanderait stockage et modération d'images). Bêta fermée : `FORUM_OPEN=true` ouvre à tous, sinon `app_user.forum_beta` posé à la main ; modérateur = `app_user.is_moderator` posé à la main.

**Critères d'acceptation**
- [x] Fil créé automatiquement à la première ouverture (match, équipe, compétition, jeu), un seul par cible ; discussions libres créables.
- [x] Texte seul : liens, mots interdits, messages vides ou trop longs refusés (code d'erreur stable).
- [x] Écrire exige compte + pseudo + conditions acceptées + 24 h d'ancienneté + non exclu ; lire est ouvert aux invités une fois le forum ouvert.
- [x] Badge de camp par jeu, choisi parmi les équipes suivies, un changement par semaine, retiré si l'équipe n'est plus suivie.
- [x] Signalement (3 signalements distincts masquent), blocage, suppression de son message, file et outils de modération (masquer, rejeter, exclure, verrouiller).
- [x] Suppression du compte : ses messages disparaissent (RGPD), les réponses des autres restent.
- [x] Sans spoil : fil flouté, appui long pour afficher.
- [x] Notification « quelqu'un t'a répondu » (réglable, heures calmes, sans aperçu si sans spoil).
- [x] Tests : 10 unitaires (domaine) et 27 e2e API (forum), 14 (profil, groupes).
- [x] Vérifié en conditions réelles sur téléphone Android (2026-10-01) : ouverture des fils, conditions, envoi, réponses imbriquées et repli, réaction, flou sans spoil, spoiler par message, modification, épingle, mention, camp (badge), signalement, blocage et déblocage, file de modération (« Rejeter »), tchat du direct (affichage, réponse par tap), notifications (réponse et discussion suivie, appli en arrière-plan, un tap ouvre le fil), barre de la page tournoi sur 360 px. Deux vrais bugs trouvés en route : récursion infinie dans le flou (appli figée) et onglets de la page jeu illisibles à six onglets (capsule désormais défilable).
- **Reporté** (vérifié par les tests e2e de l'API seulement, pas à l'écran) : « Masquer » et « Exclure » depuis l'appli, tri et filtres de l'onglet Discussions, journal de modération, appui long et rechargement toutes les 5 s du tchat, flou sans spoil sur le tchat.
- [ ] **Reporté à l'ouverture publique** : conditions d'utilisation relues, contact de modération indiqué (les conditions renvoient vers « la fiche de l'application »), exigences des stores (contenu généré par les utilisateurs) vérifiées.

---

## J14 — Pronostics entre amis : choix des amis, rappels, classement par jeu, partage (ajouté) — **Fait (2026-10-01)**

**Objectif** : rendre les pronostics du J11 plus vivants entre amis, sans changer le modèle de données ni le barème. Idées du 2026-10-01 (après la clôture du J11). **Prérequis : J11** (pronostics, groupes), notifications du J4 et du J13 (réponse, heures calmes, sans spoil).

**Périmètre — lot A (à faire en premier)**
- **Choix des amis après le coup d'envoi** : sur la page d'un match commencé, « 3 amis sur 5 ont choisi G2 », avec les pseudos, pour les membres de **tes groupes** seulement. **Jamais avant le coup d'envoi, et le masquage se fait côté serveur** (pas seulement dans l'appli), pour éviter la copie. Compatible sans spoil : le choix d'un ami ne révèle pas le résultat.
- **Rappel « tu n'as pas pronostiqué ce match »** : notification (une heure avant, à confirmer au cadrage) pour les matchs de tes suivis sans pronostic. Dans le moteur de notifications existant : déduplication, heures calmes, réglage par l'utilisateur, texte sans spoil (un match à venir n'a pas de score à cacher).
- **Classement de groupe par jeu ou par compétition** : filtre « Tous / jeu / compétition » sur le classement d'un groupe, avec les mêmes puces de jeu que l'écran Pronostics (aujourd'hui le classement est global). Le jeu d'un pronostic se déduit de l'événement (`competition.game`), aucune colonne en plus.
- **Partage natif du code d'invitation** : bouton « Partager » dans la feuille d'invitation (message prêt, code inclus), sans backend.

**Périmètre — lot B (après un premier retour d'usage du lot A)**
- **Pronostic directement sur les cartes de match** (Accueil, Agenda) : choisir le vainqueur d'un tap, sans ouvrir le match (reporté du J11).
- **Pronostic sur une compétition entière** (« qui gagne Champions ? »), posé avant le début, avec un barème plus fort (à fixer au cadrage).
- **Joker hebdomadaire** : doubler les points d'un match choisi, un par semaine.
- **Badges** (série de 5, score exact, premier du groupe), liés au profil ; à concevoir avec ceux du forum (J13).

**À trancher au cadrage** : qui voit les choix d'un ami (recommandation : membres d'un groupe commun, jamais avant le coup d'envoi) ; heure du rappel (une heure fixe au début, réglable ensuite ?) ; le rappel suit-il les suivis seulement ou tous les matchs de l'onglet Pronostics ; filtre du classement par jeu seulement ou aussi par compétition ; barème du pronostic de compétition et règle du joker (lot B).

**Hors périmètre** : classement public mondial (modération et pseudos à protéger, la couche communautaire reste optionnelle et apaisée) ; pronostic sur les rounds ou les cartes (le plan gratuit PandaScore n'a ni score par carte ni nom de carte, règle 6 de `CLAUDE.md`) ; quiz des tutos (voir « Ensuite », point 0).

**Décisions du cadrage (2026-10-01)** : choix des amis visibles pour les membres d'un groupe commun, jamais avant le coup d'envoi (liste vide côté serveur) ; rappel de pronostic **30 minutes** avant le match, pour les suivis (équipe, match, compétition) sans pronostic ; classement filtré par **jeu** seulement ; partage via `share_plus` ; **réglages de notifications par type** dans Réglages (rappel T-15, début, résultat, qualification/élimination, rappel de pronostic), en plus des options de chaque suivi (`user_setting.notify_*`, migration `j14`). Le lot B est reporté (retour d'usage du lot A d'abord) ; le pronostic sur les cartes de match n'est pas inclus.

**Critères d'acceptation (lot A)**
- [x] Avant le coup d'envoi, `GET /v1/events/:id/friends-picks` renvoie une liste vide (même en l'appelant directement) ; après, seuls les membres d'un groupe commun apparaissent, sans points (e2e API).
- [x] Rappel de pronostic envoyé une seule fois, 30 minutes avant, aux suivis sans pronostic ; pas pour qui a déjà pronostiqué, a coupé le rappel ou n'a pas de pseudo (test d'intégration du worker).
- [x] Réglage par type de notification : chaque interrupteur coupe son type (règle `isTypeEnabled`, test du moteur d'envoi). **Les 5 interrupteurs vérifiés à l'écran** (écrivent en base, remis ensuite).
- [x] Classement de groupe filtré par jeu : points et bons pronostics recalculés, « Tous » redonne le total (e2e API) ; puces dans l'écran du groupe.
- [x] Partage natif du code d'invitation (feuille Android vue sur téléphone, avec le message et le code).
- [x] Tests : domaine 73, API 83 (e2e), worker 19, appli 91 (hors goldens Windows) ; lint et `flutter analyze` propres.
- [x] **Vérifié en conditions réelles (2026-10-01) avec deux vrais comptes** (Wylfram sur téléphone Android, Chewlin sur émulateur, un match de test créé puis supprimé) : rappel « Pas encore de pronostic… commence dans 30 minutes » reçu avec l'appli en arrière-plan (au premier plan, Android n'affiche pas une notification Firebase) et un tap ouvre l'écran du match ; avant le coup d'envoi aucun choix d'ami n'apparaît, une fois le match en direct chacun voit le choix de l'autre et le pronostic est verrouillé ; feuille de partage ouverte avec le message. Le rappel avait aussi déjà tourné sur un vrai match (XLG–NS) pour les deux comptes.
- **Reporté** : vérification à l'écran des puces de jeu du classement (une seule catégorie de jeu au catalogue, elles n'apparaissent qu'à partir de deux ; filtre couvert par l'e2e API) ; « TYLOO » qui passe sur deux lignes dans « Forme récente » de l'écran du match (défaut d'affichage antérieur au J14).

---

## J15 — Finitions d'interface : cinq défauts à éviter (ajouté) — **Fait (2026-10-02)**

**Objectif** : passer l'appli au crible de cinq défauts courants d'interface, décidés le 2026-10-01 après lecture d'une liste de bonnes pratiques. Aucune nouvelle fonctionnalité : on **audite d'abord** chaque écran, puis on corrige.

**Périmètre**
1. **Skeletons plutôt que spinners** : l'appli compte aujourd'hui une trentaine de `CircularProgressIndicator`, sur la plupart des écrans, et aucun skeleton. Remplacer, là où on sait ce qui va s'afficher (cartes de match, listes, profil, forum, classements), par un gabarit qui reprend la mise en page réelle. Le spinner reste acceptable pour une action ponctuelle (envoi d'un message). Mouvement : pas d'animation, ou un fondu discret (règle 13), jamais d'effet qui tourne en continu sur ce qu'on voit plusieurs fois par jour. **Teinte (J16)** : skeletons en laiton très atténué plutôt qu'en gris, pour rester dans l'identité Keryx.
2. **Pas de « dark patterns »** : l'appli n'a pas d'abonnement payant, donc rien à corriger aujourd'hui. Ça devient une **règle à tenir** : se désabonner, quitter un groupe, supprimer son compte ou masquer un utilisateur ne doivent jamais demander plus qu'une confirmation claire. À vérifier lors de l'audit.
3. **Retour instantané sur chaque bouton** : le bouton « Suivre » le fait depuis J8. Auditer les autres (favori de jeu, pronostic, réaction et envoi dans le forum, rejoindre un groupe, révéler un spoil, modération) : état visuel immédiat au tap, retour arrière propre si l'appel échoue, pas de double envoi possible.
4. **Actions principales toujours à la même place** dans l'onboarding, la connexion, la création de compte et les étapes de profil : le bouton « Continuer » ne change pas d'emplacement d'un écran à l'autre.
5. **Jamais d'erreur technique à l'écran** : aucun code HTTP, message brut, trace ni texte d'exception visible (y compris les erreurs de Firebase Auth, de l'API et du forum). Message simple en français qui dit quoi faire, avec un bouton « Réessayer », et l'erreur réelle journalisée (Sentry côté appli à envisager). Le repli hors ligne de J3/J7 reste la référence.

**Méthode** : un audit écran par écran (liste dans le plan), puis corrections par lot, avec un test widget pour chaque nouveau composant partagé (skeleton, état d'erreur). Pas de composant en plus du strict nécessaire (règle 14) : un skeleton générique configurable, un seul widget d'erreur.

**Hors périmètre** : fidélité aux maquettes, nouvelles fonctionnalités, refonte des écrans.

**À trancher au cadrage** : les écrans où le spinner est volontairement gardé ; si les erreurs doivent partir vers Sentry côté appli.

**Critères d'acceptation** (cadrage du 2026-10-02)
*Code écrit puis **vérifié sur émulateur Android le 2026-10-02** (voir « Vérification sur émulateur » plus bas). Une partie du jalon reste à voir sur un téléphone physique (voir la dernière case).*
- [x] Audit écran par écran ci-dessous.
- [x] Plus de spinner d'écran ni de liste, sauf exceptions : boutons en cours d'envoi et feuille du glossaire (`glossary_sheet`, court, sans mise en page connue). `Skeleton`/`SkeletonCards`/`AsyncView` (`widgets/async_view.dart`) : laiton à 10 %, sans animation, jamais affiché pendant un rechargement quand une valeur existe (test). Dans une zone de hauteur limitée, seules les cartes qui tiennent s'affichent (débordement trouvé par les tests de l'Agenda). Vu à l'écran (onboarding, Pronostics, page Valorant).
- [x] Un seul `ErrorState` avec « Réessayer » sur chaque écran et liste ; `accountErrorMessage` sans code ni texte brut (l'erreur réelle part dans `debugPrint`), `apiErrorMessage` limité aux refus voulus (400, 403, 404, 409) (tests). **Sentry côté appli non ajouté** (décision du plan : jalon à part).
- [x] Boutons : retour instantané + retour arrière + message pour Suivre, favori de jeu (échec silencieux corrigé), cloche de discussion, interrupteurs des Réglages (`_ToggleRow`), carte de suggestion de l'onboarding, **pronostic** (`pendingPicksProvider`, choix et score affichés tout de suite) et **réactions du forum** (`ForumMessagesNotifier.showReaction`, compteur recalculé en local puis resynchronisé) ; garde contre le double envoi pour les actions du forum (par message), la vérification e-mail, la suppression de compte et « quitter/supprimer un groupe ».
- [x] Bouton principal : connexion/inscription ancré en bas (`bottomNavigationBar`), mêmes éléments dans les deux modes, « Mot de passe oublié » remonté sous le champ ; messages d'erreur sous le bouton dans les feuilles « pseudo » et « créer/rejoindre un groupe ». Onboarding déjà conforme. Vu à l'écran, clavier ouvert (voir ci-dessous).
- [x] Confirmations : une seule partout ; ajout de `confirmAction` avant « Exclure du forum » (menu du fil, tchat du direct, « Masquer et exclure » de la file).
- [x] Tests : `async_view_test` (skeleton, rechargement, échec avec valeur, erreur + « Réessayer »), `error_messages_test` ; `flutter analyze` propre ; `flutter test` : tout passe sauf les goldens (rendu Windows, voir `CLAUDE.md`). Vérifié sur émulateur avec l'API coupée et avec une API ralentie à 4 s.

- [ ] **Reportés** (avec raison) : Sentry côté appli (nouvelle dépendance, RGPD) ; suggestions d'onboarding demandées en parallèle (aujourd'hui l'une après l'autre, jusqu'à 24 s avant l'erreur sans API) ; écran de lancement long (mesuré le 2026-10-02 : ~11 s sur l'émulateur en debug **avec ou sans** API, donc sans lien avec l'API ; à re-mesurer en release sur un vrai téléphone) ; bouton « Ajouter à l'agenda » de l'écran du match (« bientôt disponible », à retirer ou à faire) ; vérification sur téléphone physique et des notifications ; goldens à régénérer par la CI si un widget couvert change (aucun ne l'a été ici).

### Audit (2026-10-02, lecture du code ; rien vérifié à l'écran)

**1. Chargement et erreurs.** 33 `CircularProgressIndicator` dans 22 fichiers, 0 skeleton. 5 sont des boutons en cours d'envoi (garder) : `auth_screen`, `groups_screen` (`_GroupPrompt`), `profile_screen` (`_PseudoForm`), plus 2 petits indicateurs de liste à vérifier (`group_bracket_tree`, `learn_screen:338`). Les ~28 autres sont des chargements d'écran. **Aucun écran n'a de bouton « Réessayer »** : toutes les branches d'erreur sont un `Text("Impossible de charger …")` isolé, réécrit à chaque écran (25 variantes). Aucune fuite de texte technique dans ces branches (le texte est fixe).

| Écran | Chargement | Erreur |
|---|---|---|
| Accueil, Agenda | spinner plein écran | texte seul |
| Match (`next_match`), Équipe, Réglages, Profil | spinner | texte seul (Équipe/Réglages/Profil gardent la valeur si elle existe) |
| Compétition, arbre, repêchage, Kickoff 3 vies | spinner | texte seul (arbre/repêchage : `_EmptyMessage`) |
| Page jeu (saison, équipes), Compétitions | spinner | texte seul |
| Suivis, Onboarding (suggestions) | spinner | texte seul |
| Forum (liste, fil), Groupes, Profil joueur | spinner | texte seul |
| Tutos (liste), Glossaire (feuille) | spinner | texte seul (glossaire : « Définition indisponible. ») |
| Modération (file, journal, liste), choix de jeu/avatar | spinner | texte seul |
| Pronostics | spinner si la liste est vide | aucune branche d'erreur visible |

**Piège à traiter avec les skeletons** : `AutoRefresh` (`core/auto_refresh.dart`) invalide chaque minute et au retour au premier plan `homeProvider`, `followsProvider`, `predictionsProvider`, `eventProvider`, `agendaProvider`, `catalogProvider`, `competitionDetailProvider`, `bracketProvider`, `entityProvider`, `valorantSeasonProvider`, `gameTeamsProvider`. Seuls 8 écrans testent `hasValue` pour garder l'ancien contenu ; les autres (arbre, compétitions, page jeu, Kickoff…) n'ont qu'un `_ =>` et **repassent donc en spinner à chaque rechargement**. Le skeleton ne doit s'afficher que si `isLoading && !hasValue`. À vérifier à l'écran, le Réglages l'a aussi : `SettingsController.update` fait `invalidate(userSettingProvider)` après chaque interrupteur, donc probable flash de tout l'écran.

**2. Messages d'erreur (texte technique).**
- `accountErrorMessage` (`core/auth/account.dart:97`) : le cas par défaut affiche `Connexion impossible (${error.code})` → code Firebase brut visible.
- `apiErrorMessage` renvoie le `message` du corps de l'API quel qu'il soit : les messages métier du J11/J13 sont en français, mais les erreurs génériques de NestJS (« Unauthorized », « Forbidden resource », 429 du limiteur, « Internal server error ») sortiraient en anglais.
- Toute `DioException` donne « Serveur injoignable » (`account.dart:100`), même pour un 400, un 403 ou un 500 : message faux et sans action.
- `forumErrorMessage` empile les deux. Les 4 `catch (_) {}` de `learn_screen` avalent l'erreur sans rien dire (acceptable : la progression est secondaire, à journaliser).
- Rien n'est journalisé : aucun `debugPrint` sur ces erreurs (Sentry non présent côté appli).

**3. Retour instantané des boutons.**

| Bouton | Optimiste | Retour arrière + message | Double envoi | Écart |
|---|---|---|---|---|
| Suivre (`FollowsNotifier`) | oui | oui | non géré | OK. Carte d'équipe de l'onboarding : `follow` appelé sans `catch` → échec silencieux |
| Cloche « M'alerter », suivi de compétition | oui | snackbar | non géré | OK |
| Favori de jeu (étoile) | oui | **restaure puis `rethrow` sans `catch` à l'appel** | non géré | échec silencieux (l'étoile revient, aucun message) |
| Pronostic (`_TeamChoice`, score) | **non** (attend le réseau puis recharge) | snackbar | **non** | le choix n'apparaît qu'après l'aller-retour |
| Réaction forum | **non** (attend + recharge le fil) | snackbar | **non** | latence visible, double tap = bascule deux fois |
| Envoi/édition d'un message | n/a | texte conservé, snackbar | oui (`_sending`) | OK |
| Suivre une discussion (cloche) | **non** | `catchError(_toast)` | **non** | latence |
| Signaler, bloquer, supprimer son message | n/a | snackbar | **non** | pas de retour avant la fin de l'appel |
| Modération (masquer, exclure, verrouiller) | n/a | snackbar | **non** | **« Exclure du forum » s'exécute sans confirmation** |
| Créer/rejoindre un groupe, pseudo, connexion | n/a | message en ligne | oui (`_busy`) | OK |
| Quitter/supprimer un groupe, supprimer le compte | n/a | snackbar | **non** | pas de garde pendant l'appel |
| Vérification e-mail (« J'ai vérifié », « Renvoyer ») | n/a | message | **non** | « Renvoyer » deux fois → `too-many-requests` Firebase |
| Interrupteurs des Réglages (`SettingsController.update`) | **non** | **aucun `catch`** | **non** | échec silencieux : l'interrupteur ne bouge simplement pas |
| Révéler un spoil | local | n/a | n/a | OK |

**4. Bouton principal.** Onboarding : « Continuer » (page 1) et « C'est parti » (page 2) sont collés en bas, pleine largeur, au même emplacement ; « Passer » en haut à droite sur les deux. **OK.** À l'inverse :
- **Connexion / inscription (`auth_screen`)** : le bouton est dans un `ListView`, juste sous les champs, **pas ancré en bas**. Il bouge entre les deux modes (le texte d'aide « 6 caractères minimum » n'existe qu'à l'inscription) et chaque fois qu'un message d'erreur ou d'info apparaît. **Écart à corriger.**
- **Pseudo, créer/rejoindre un groupe** (feuilles) : bouton sous le champ, déplacé par le message d'erreur. Mineur.
- **Vérification e-mail (carte du Profil)** : boutons sous un message qui change. Mineur.
- Conditions du forum (`forum_terms`) : à voir à l'écran.

**5. « Dark patterns ».** Rien d'anormal : se désabonner et masquer ne demandent aucune confirmation, quitter/supprimer un groupe et supprimer le compte en demandent **une** (dialogue clair, « Annuler » aussi visible que « Supprimer »), se déconnecter n'en demande pas, bloquer n'en demande pas (annulable via la liste des blocages). Le seul point sensible est l'inverse : « Exclure du forum » sans aucune confirmation. Hors périmètre sans rapport : le bouton « Ajouter à l'agenda » de l'écran du match (`next_match_screen:224`) affiche « bientôt disponible », à retirer ou à implémenter.

### Vérification sur émulateur (2026-10-02, Pixel 7 API 35, appli en debug)

Profil remis à zéro (`pm clear`), API coupée (`adb reverse --remove`) ou ralentie par un petit proxy à 4 s, session de test locale injectée dans les préférences de l'appli (utilisateur créé en base de dev, jetons signés avec le secret local, **aucun compte Firebase réel créé** ; utilisateurs et discussion de test supprimés ensuite).
- **Skeletons** : 3 cartes laiton à l'onboarding, 3 cartes sous « Matchs à pronostiquer », aucun spinner. Le cache hors ligne affiche toujours les données déjà vues (Agenda, Compétitions) quand l'API est coupée.
- **ErrorState** : « Impossible de charger la saison. Vérifie ta connexion, puis réessaie. » avec monogramme sur la page Valorant (API coupée), « Impossible de charger les suggestions. » à l'onboarding ; « Réessayer » recharge bien les données une fois l'API rétablie.
- **Messages d'erreur** : « E-mail ou mot de passe incorrect. » (identifiants faux, vrai Firebase), « Pas de connexion au serveur. Vérifie ton réseau puis réessaie. » partout ailleurs, jamais de code.
- **Boutons** : interrupteur des Réglages qui se déplace tout de suite avec l'API lente, retour arrière + message avec l'API coupée ; étoile de favori de jeu : retour arrière + message ; cloche de discussion : état actif tout de suite ; création de groupe : message sous le bouton.
- **Confirmations** : « Exclure Troll… ? » (menu d'un message, « Masquer et exclure » de la file) avec Annuler aussi visible ; « Supprimer mon compte ? » en une seule étape, puis retour en invité.
- **Bouton principal** : « Créer mon compte » / « Me connecter » à la même hauteur (y identique sur les deux captures), au-dessus du clavier.

**Deuxième passe avec un vrai compte de test (Chewlin, connecté par l'utilisateur ; données réelles gardées intactes, tout ce qui a été créé a été supprimé)** : pronostic changé pendant que l'API répond en 4 s → le nouveau choix et le score s'affichent à 0,7 s (avant : 8 s) et le pronostic d'origine (KC 2-1) a été remis ; réaction 👍 retirée à 0,8 s avec l'API lente, puis resynchronisée ; message posté puis supprimé via son menu ; groupe créé (message d'erreur sous le bouton sans le déplacer avec l'API coupée) puis supprimé avec une seule confirmation ; Suivis, page équipe et écran du match chargent. Deux écarts trouvés et corrigés : le pronostic et les réactions n'étaient pas instantanés (voir la case « Boutons »), et les dialogues « supprimer un groupe/mon compte » n'utilisaient pas le même composant (`confirmAction`) que les autres.

**Trois bugs trouvés grâce à l'émulateur (corrigés)** :
1. Onboarding : avec l'API coupée, la liste affichait « Aucune suggestion pour l'instant » (les erreurs réseau étaient avalées par le `catch` de chaque équipe) ; seules les 404 sont maintenant ignorées, le reste affiche l'erreur avec « Réessayer ».
2. Connexion : le bouton ancré en `bottomNavigationBar` passait sous le clavier ; il est maintenant dans le corps de l'écran.
3. Feuilles « pseudo » et « créer un groupe » : l'erreur sous le bouton le faisait monter ; zone d'erreur de hauteur fixe.

**Pas vérifié** : l'envoi réel d'un compte (création Firebase), l'apparence sur un petit téléphone physique, les notifications. L'écran de démarrage reste affiché tant que le premier appel API n'a pas abouti ou échoué (8 s si l'API est coupée) : hors périmètre, à noter. Les 3 suggestions de l'onboarding sont demandées l'une après l'autre (jusqu'à 24 s avant l'erreur avec l'API coupée) : à passer en parallèle un jour.

---

## J16 — Identité de l'app (ajouté) — **Fait (2026-10-02)**

**Objectif** : donner à l'app un nom, un logo et une personnalité visuelle propres, en reprenant ce qui était resté en suspens depuis J7 (nom, logo et icône définitifs). Direction décidée le 2026-10-01 : **ambiance solennelle** inspirée de l'univers des finales (cérémonie, tension, ferveur), **sans rien reprendre d'une œuvre existante**. Planche de style de départ : `docs/maquettes/planche-de-style.html`.

**Périmètre**
- **Personnalité** : fond charbon, or mat vieilli, capitales fines et pointues pour les grands titres, filets et cadres en pointes, petits tampons rouges. Solennité plutôt que combat, pour que l'identité tienne aussi pour le sport et la politique (neutralité stricte, règle 9).
- **Couleurs** : **deux ors, deux rôles**. L'or vif `#FFC940` garde son sens fonctionnel (« mon équipe / mes suivis », règle 12). Un **laiton mat décoratif** (autour de `#B79B62`) sert aux titres, filets et cadres de grandes finales. Rouge direct `#FF4655` et vert `#30D158` inchangés. Contrastes à vérifier (lisibilité sur fond sombre).
- **Typographie** : police d'affichage **Cinzel**, **réservée aux titres** (**Grenze Gotisch écartée le 2026-10-01** : « ne colle pas du tout » ; **Cinzel retenue le 2026-10-01**, seule police d'affichage, avec Inter pour le reste ; Pirata One testée à côté de Cinzel et écartée : trois polices faisaient fouillis et Pirata One devient peu lisible en petit, à vérifier : licence libre de Cinzel et rendu des accents français). Inter reste pour le texte ; **depuis la passe de finitions du 2026-10-01, le « VS » et les scores/gros chiffres sont aussi en Cinzel blanc** (`AppTextStyles.score`), le reste des chiffres reste en Inter.
- **Nom de travail : « Keryx » retenu le 2026-10-01** (grec κῆρυξ, « héraut » : celui qui proclamait le nom des vainqueurs), **sous réserve de vérifier sa disponibilité comme marque (INPI, EUIPO) et comme nom de domaine**. Il avait été choisi après examen d'« Agon », d'« Héraut » et de « Sigr » (résultats ci-dessous). Planche de style refaite avec ce nom, pistes de logo dans `docs/maquettes/planche-de-style.html`.
- **« Agon » (mot grec pour « concours, épreuve ») envisagé le 2026-10-01, écarté.** Recherche web du même jour : **plusieurs applis s'appellent déjà « Agon »** sur Google Play et l'App Store, dont des applis de **sport** (Agon, réseau social pour trouver des partenaires de sport ; Agon Rec, parties de sport entre amateurs), plus d'autres (fitness, entraînement, Agon Manager). Risque de confusion dans la même catégorie ; la disponibilité comme marque (INPI, EUIPO) et comme nom de domaine **n'a pas été vérifiée**. Décision à prendre : garder « Agon » avec un complément de nom, ou chercher un autre nom (et le vérifier de la même façon). **Autres pistes recherchées le 2026-10-01** (recherche web seulement, ni marque ni domaine vérifiés) : **Keryx** (grec, « héraut qui proclamait les vainqueurs ») : plusieurs petites applis du même nom, aucune de sport ni d'e-sport (calendrier scolaire, cartes de catastrophe, lecteur RSS, portefeuille crypto), et une société pharmaceutique homonyme, d'un autre secteur ; la piste la plus nette. **Héraut** : homophone de « Hérault » (le département), ce qui noie les recherches, et une appli d'actualités locale néerlandaise « De Heraut » existe ; piste peu distinctive. **Sigr** (norrois, « victoire ») : peu de collisions directes mais bruit de recherche (SIG, SIGR copropriété), prononciation difficile en français. **Idée abandonnée le 2026-10-01** : donner des noms grecs aux sections de l'app, car ils perdraient le nouveau venu ; les libellés des sections restent en français. Le nom **ne contient ni « Valorant », ni « VCT », ni « Riot »**, ne dépend pas d'un jeu précis.
- **Icône retenue le 2026-10-01 : losange laiton sur fond charbon avec un « K » en Cinzel** (piste 3 de la planche de style). Le héraut dessiné « comme une fresque grecque » a été essayé (silhouette, bâton à deux serpents) : trop raide en SVG et illisible en petit ; il pourra revenir plus tard comme illustration de grande taille, faite par un dessinateur. **Logo, icône, écran de lancement** : monogramme ou sceau dans le style tampon, version icône d'appli (Android adaptive icon) et écran de lancement.
- **Ornements** dessinés pour l'appli (filets, cadres de grande finale, tampons de badges), en SVG embarqués.
- Mise à jour de `docs/02` (tokens), du thème Flutter (`apps/mobile/lib/theme`), et des goldens à régénérer par la CI (voir « Goldens Flutter » de `CLAUDE.md`).

**À trancher au cadrage** : le nom ; choix de la police d'affichage ; où le laiton remplace l'or actuel (titres de pages, cadre de grande finale…) ; ampleur des ornements (garder la sobriété, règle 13 : pas d'animation sur ce qu'on voit plusieurs fois par jour).

**Hors périmètre** : refonte des écrans ; images, logos ou polices de Riot ou d'un autre éditeur.

**Critères d'acceptation**
- [x] Cinzel embarquée, utilisée uniquement pour les titres de page et de section, accents français corrects (test widget).
- [x] Laiton `#B79B62` en token, contraste ≥ 4,5:1 sur le fond charbon (test, 7,4:1).
- [x] Carte de grande finale en laiton avec coins de cadre, filet sous « Les grands rendez-vous » ; l'or reste réservé à « mes suivis ».
- [x] Nom « Keryx », icône adaptative (losange laiton, K) et écran de lancement vus sur émulateur Android.
- [~] Modèles d'e-mails Firebase (validation, mot de passe, changement d'adresse) **écrits** dans `docs/emails/`, mais **non appliqués** : le champ Message est grisé dans la console (« pour éviter le spam »), le SMTP Gmail ne le débloque pas. Domaine `keryx.thibaultcauche.com` envoyé à Firebase pour vérification (DNS Namecheap ajouté) : reste à voir s'il débloque le champ, sinon texte standard avec objet et expéditeur en français, ou envoi depuis l'API.
- [x] Goldens régénérés par la CI (branche jetable `regen-goldens`, 8 images sur 9 changées). Séance de test des écrans non encore vus : `docs/seance-test-j16.md`.
- [x] Séance de test sur émulateur (`docs/seance-test-j16.md`) : tampon en direct, forum, onboarding, scores.
- [ ] **Reportés** (avec raison) : marque (INPI, EUIPO) et nom de domaine à vérifier par l'utilisateur ; icône iOS (iOS reporté après la sortie, décision J4) ; application des modèles d'e-mails (voir ci-dessus) ; vérification à l'écran de l'icône dans le lanceur et du glossaire ; remise de `forum_beta` des comptes de test à leur valeur d'origine.

---

## J18 — Fiabilité avant la bêta (ajouté 2026-10-02) — **En cours : code fait, vérification à l'écran restante**

**Objectif** : faire de J15 une base solide avant d'ouvrir la bêta : savoir ce qui plante chez les testeurs, ne jamais montrer de données anciennes sans le dire, petits défauts restants. Idées proposées après J15, validées par l'utilisateur le 2026-10-02 (« je pense que les 10 sont de bonnes idées »).

**Critères d'acceptation**
- [x] **Bandeau « Hors ligne · données de 10 h 42 »** (`offlineProvider`, `widgets/offline_banner.dart`, signal levé par `ETagCacheInterceptor` quand le cache remplace une API injoignable, retiré à la première vraie réponse) + rechargement immédiat au retour du réseau (`connectivity_plus` dans `AutoRefresh`, sert seulement à relancer un chargement). Test : `test/resilience_test.dart` (intercepteur + bandeau). **À voir à l'écran.**
- [x] **Sentry côté appli** (`sentry_flutter` 9, `main.dart`) : actif seulement avec `--dart-define=SENTRY_DSN=...` au build, pas de données personnelles, erreurs réseau/4xx (`DioException`) ignorées, les erreurs « inconnues » de `accountErrorMessage` sont envoyées. **Il faut un DSN dédié au Flutter** (projet Sentry de type Flutter ; le projet « news » actuel est de type NestJS). Non vérifié avec un vrai DSN.
- [x] **Suggestions d'onboarding en parallèle** (`Future.wait`, 404 ignorés, autres erreurs remontées).
- [x] **« Annuler »** après avoir arrêté de suivre ou bloqué (`showUndo`, `scaffoldMessengerKey`, 5 s). Test : `resilience_test.dart`. **À voir à l'écran.**
- [x] **Fondu de 200 ms** quand le skeleton laisse place au contenu (`AsyncView`, opacité seule, aucun en mouvement réduit, aucun pour un rechargement) ; label « Chargement en cours » pour les lecteurs d'écran. Tests : `async_view_test.dart`.
- [x] **« Ajouter à l'agenda »** : ouvre l'agenda du téléphone avec le match pré-rempli (`add_2_calendar`, titre « A – B », compétition en description, 2 h ; plugin natif : réinstaller l'appli). Test du contenu : `resilience_test.dart`. **À voir sur téléphone.**
- [x] **Envoi de message de forum instantané** : le texte part de la saisie, s'affiche grisé au-dessus, revient dans la saisie avec son spoiler et sa réponse en cas d'échec. **À voir à l'écran** (pas de test automatisé).
- [x] **Test d'intégration** `integration_test/resilience_test.dart` (2 tests, passent sur émulateur contre l'API du NAS en lecture seule) : API lente → skeletons puis contenu ; API coupée avec cache → repli et appli déclarée hors ligne ; API coupée sans cache → erreur en français + « Réessayer » ; API rétablie → le bouton recharge et l'appli repasse en ligne. Commande : `flutter test integration_test/resilience_test.dart -d <appareil> --dart-define=API_BASE_URL=https://<machine>.<tailnet>.ts.net/news` (ou API locale + `adb reverse`). **Il a trouvé un vrai défaut de J15** : Riverpod 3 relance par défaut un provider en échec jusqu'à 10 fois (attente doublée, ~40 s) en le laissant « en chargement », donc l'erreur n'apparaissait qu'après ~40 s de skeleton ; corrigé par `appProviderRetry` (`main.dart`) : un seul nouvel essai après 1 s.
- [x] **Accessibilité** : label des skeletons, test grande police (×1,2) sur écran de 320 px pour la connexion, l'erreur et le skeleton (`resilience_test.dart`).
- [x] Tests : 120 passent hors goldens (`flutter test -j 1`), `flutter analyze` propre.
- [x] **Vérification sur téléphone physique (OnePlus CPH2359, build release, API du NAS, 2026-10-02)** :
  - bandeau « Hors ligne · données de … » : vu par l'utilisateur, OK ;
  - « Annuler » : la barre apparaissait mais **ne se fermait jamais** (depuis Flutter 3.29 une barre avec une action reste ouverte : `persist: false` ajouté, test ajouté) ; revérifié : « Suivi retiré. Annuler » apparaît puis disparaît seule. Elle n'apparaît qu'après la réponse du serveur (3-4 s sur le NAS) car on attend la confirmation avant de proposer d'annuler ;
  - « Ajouter à l'agenda » : **ne faisait rien** (Android 11+ cache les applis d'agenda sans déclaration `<queries>` pour l'intent `INSERT` : le plugin renvoyait « introuvable » ; ajouté à `AndroidManifest.xml`) ; revérifié : Google Agenda s'ouvre avec « G2 – TL », samedi 3 octobre 11 h–13 h (non enregistré) ;
  - démarrage en release : l'Accueil avec ses données s'affiche ~1,8 s après le lancement (les 11 s étaient propres au debug sur l'émulateur) ;
  - **non vérifié** : envoi de message de forum instantané (la carte « Discussion » n'apparaît pas sur le NAS : forum fermé, `FORUM_OPEN` absent ; vérifié seulement sur émulateur au J15 pour les réactions), connexion avec clavier ouvert sur téléphone (vu sur émulateur), Sentry avec un vrai DSN.
  - Au passage : la connexion échouait (« Une erreur est survenue ») parce que **l'API du NAS datait d'avant le J11** (route `/v1/auth/firebase` absente, 404) : mise à jour du NAS faite par l'utilisateur ; message d'erreur pour un 404 clarifié (« Le service n'est pas encore à jour »).

**Aussi corrigé pendant le jalon** : `android/gradle.properties` réservait 8 Go de tas + 4 Go de métaspace pour Gradle (valeur par défaut du modèle Flutter), ce qui, avec l'émulateur et Android Studio, saturait les 15,8 Go du PC ; ramené à 3 Go + 1 Go, démon Kotlin à 1,5 Go (les compilations suivantes n'ont plus figé la machine).

**Machine de développement** (diagnostic du 2026-10-02, voir `CLAUDE.md` « Commandes ») : 15,8 Go de RAM, émulateur 4 Go + Android Studio + navigateur proches de la saturation, image d'émulateur « tablette Play Store » (Google Play s'y met à jour en tâche de fond et plante), pilote graphique ancien (juin 2025) et `LiveKernelEvent` réguliers.

---

## J17 — Versions Windows et Web (ajouté)

**Objectif** : permettre de suivre ses compétitions depuis un ordinateur (application Windows et site web).

**Décision (2026-10-01)** : tout en **Flutter**, une seule base de code pour Android, Windows et Web. Cela **lève la décision antérieure** « pas de plateforme web dans le projet Flutter » (`docs/00` §7) : les plateformes `windows` et `web` sont ajoutées au projet. Le **site Next.js** pour le référencement (pages publiques en lecture seule : résultats, compétitions, classements) reste prévu **plus tard, comme jalon séparé** (voir « Ensuite »), pas dans J17. Limite connue de Flutter web : très peu visible sur Google et chargement initial lourd ; assumé pour J17.

**Points à vérifier au cadrage** : prise en charge de **Firebase Auth** et des **notifications push** sur Windows et sur le web (le plugin `firebase_messaging` n'est pas disponible sur toutes les plateformes) ; cache local **drift** sur le web ; mise en page adaptée aux grands écrans (l'appli est conçue pour 390 px de large) ; distribution Windows (Microsoft Store ou installateur) ; CORS et CSP côté API pour le web.

**Hors périmètre** : macOS et Linux ; le site Next.js pour le SEO.

**Critères d'acceptation** : à rédiger au cadrage (`/jalon 17`). **À planifier après J16** : le nom et l'identité s'appliquent à toutes les versions.

---

## J19 — Rattrapage des reportés (ajouté 2026-10-02, jalon intermédiaire)

**Objectif** : solder tout ce qui a été mis de côté depuis J1 : le vérifier, le faire, ou le ranger explicitement (abandonné, ou laissé dans « Ensuite » avec la raison). Inventaire relu dans `docs/04`, `docs/00` et `docs/05` le 2026-10-02 et validé par l'utilisateur (aucun reporté supplémentaire connu de sa part ; guide des compétitions inclus ; résumé du matin à faire ; démarches incluses dans le jalon).

**Calendrier** : le lot 1 (A1, A2) dépend des **playoffs de Champions 2026, fin le 18 octobre 2026** ; à faire en premier. Après, il faudra attendre 2027 pour un vrai bracket.

**Principe** : le jalon ne se clôt pas sur « fait » seulement. Une ligne peut finir **faite**, **abandonnée** ou **laissée en Ensuite**, mais jamais « oubliée ». Les démarches du lot 3 que seul l'utilisateur peut signer ou envoyer (licence, mail, marque) sont **préparées par Claude** (brouillons, textes), **faites par l'utilisateur** ; elles comptent comme faites quand l'utilisateur le confirme.

### Lot 1 — Vérifications à l'écran ou en réel (peu de code)
- [ ] **A1** Remplissage de l'arbre radial à la fin d'un vrai match de playoffs + fluidité 60 i/s (J5, J10). **Avant le 18 oct.**
- [x] **A2** Points d'un vrai match PandaScore (J11) : **déjà réglés en base de dev le 2026-10-01** par le vrai worker sur deux vrais matchs (`pandascore:1685231` TYLOO–TL : Wylfram 3, Chewlin 5 = 3 + 2 pour le score exact ; `pandascore:1685234` XLG–NS : Chewlin 3, Wylfram 0). Constaté le 2026-10-02 par requête, rien à refaire.
- [x] **A3** Forum (J13, J18), **vérifié le 2026-10-02 sur l'émulateur contre l'API locale (`FORUM_OPEN=true`)** avec deux comptes de test (supprimés ensuite) : envoi instantané (texte grisé avec indicateur, saisie vidée), « Masquer (modération) » (message retiré de la liste), « Exclure du forum » (une seule confirmation, `forum_banned_at` posé), journal de modération (les deux décisions listées), tris et filtres de la liste des discussions, tchat du direct (rechargement sans action en moins de 9 s, flou « Sans spoil » levé par appui long, appui long sur une ligne = feuille d'actions). Rien vérifié sur le téléphone (forum fermé sur le NAS). Constat : l'onglet « Discussions » de la page jeu est rogné (« D ») quand la barre d'onglets déborde, voir ci-dessous.
- [~] **A4** Sentry côté appli (J15, J18) : projet Sentry Flutter `keryx-mobile` créé par l'utilisateur le 2026-10-02 ; **build release avec `SENTRY_DSN` installé sur le téléphone** ; un événement de test envoyé depuis le PC avec ce DSN a été **accepté (HTTP 200)**, donc le DSN et le projet sont valides. **Reste** : voir arriver une vraie erreur de l'appli (les erreurs réseau et 4xx sont filtrées exprès ; seules les erreurs « inconnues » et les plantages partent, donc rien à provoquer à la main : à constater au premier vrai bug, ou en vérifiant Issues dans Sentry).
- [~] **A5** Connexion avec clavier ouvert et notifications, sur téléphone physique (J15, J18) : **build release J19 installé sur le téléphone le 2026-10-02** (API du NAS, app en ligne, icône de notification et guide inclus). Notifications vues sur l'**émulateur** (vrai FCM : résumé du matin avec icône Keryx). **Reste sur le téléphone** : recevoir une vraie notification (suivre un match, attendre le rappel T-15 ou le résumé du matin) et vérifier la connexion avec le clavier ouvert.
- [~] **A6** Séance à l'écran (J16) : **icône du lanceur vue sur l'émulateur** (K dans un losange laiton, OK) ; `Mes tutos` et le glossaire dans les articles (mots en gras) s'affichent. **Reste** : « 1 » de Cinzel face à « I » (les scores `1`/`0` de la carte du direct se lisent bien en Inter, mais Cinzel `versus`/`score` à revoir sur un chiffre `1` isolé), contraste du laiton sur cartes colorées.
- [ ] **A7** Logo et statut qualifié/éliminé de l'écran Suivis en réel ; vérifier si la fiche d'une équipe suivie est atteignable (J8). Revérifier aussi les logos d'équipes dans « Sources et crédits » (ingérés depuis le J8).
- [ ] **A8** Puces de jeu du classement de groupe (J14) : **laissées** tant que le catalogue n'a qu'un jeu (couvert par l'e2e API) ; à revérifier avec le 2ᵉ jeu.
- [ ] **A9** Remettre `forum_beta` des comptes de test à leur valeur d'origine (J16).

### Lot 2 — Petits défauts et finitions de code
- [x] **B1** « TYLOO » coupé en deux lignes dans « Forme récente » (J14) : colonne du nom 48 → 64, une ligne, points de suspension ; test `next_match_screen_test.dart`.
- [x] **B2** `_learnGames` figé sur `valorant` (J12) : remplacé par `learnGamesProvider` (`AssetManifest`, présence de `assets/learn/<slug>.json`), le « ? » de la page jeu passe aussi le slug. Test `learn_screen_test.dart`. Vu à l'écran : le « ? » s'affiche toujours sur la page Valorant.
- [x] **B3** Icône de notification Android (J16) : `drawable/ic_stat_keryx.xml` (losange blanc, K évidé) + `default_notification_icon`/`default_notification_color` (laiton) dans le manifeste. **Vu sur l'émulateur** : la notification porte l'icône Keryx sur pastille laiton, pas un carré blanc.
- [x] **B4** **Résumé du matin** (réglage `user_setting.morning_digest` du J6, jamais envoyé jusque-là) : `MorningDigestService` (`apps/worker/src/notifications`), appelé par le job `starting-soon` de chaque minute. Entre **8 h et 11 h locales** (décalage UTC du téléphone), un seul message par jour local (déduplication par `notification_log`, type `morning_digest`, clé = premier match du jour), **rien s'il n'y a aucun match suivi** ; les heures calmes l'emportent (on réessaie jusqu'à 11 h). Suivis pris en compte : match, équipe, compétition, famille, catégorie, avec le niveau « grands moments ». Texte : « 3 matchs de tes suivis, le premier à 11 h : A vs B. » (heure locale, jamais de score). Fonctions pures `buildMorningDigestText`/`localDayBounds` dans `packages/domain`. Tests : domaine (3) + intégration Jest (4 : une seule fois, hors fenêtre, sans suivi/réglage/heures calmes, après les heures calmes). **Vérifié de bout en bout sur l'émulateur** : vrai worker, vrai FCM, notification reçue (« 1 match de tes suivis : … à 13 h 04. »). Limite connue (`ponytail:` dans le code) : un match ajouté plus tôt dans la journée peut déclencher un 2ᵉ résumé ; la sourdine d'une compétition est ignorée sans la règle « la plus proche l'emporte ».
- [x] **B5** **Graphify** (J3) : **abandonné** (décision du 2026-10-02) : le code a grossi sans, et ça ne sert pas les testeurs.
- [x] **B7** (trouvé pendant A3) Barre d'onglets de la page jeu : avec 6 onglets (Discussions, Apprendre), l'onglet choisi au bord restait rogné (« D »). La capsule défile maintenant jusqu'à l'onglet choisi (`Scrollable.ensureVisible`). Test `game_screen_test.dart` (écran de 360).
- [x] **B8** (retour de l'utilisateur sur l'émulateur, 2026-10-02) Bandeau « Hors ligne » : l'heure changeait d'une page à l'autre (15 h 35, 15 h 51…) parce qu'il affichait l'heure du cache de chaque écran. Il affiche maintenant **une seule heure, celle de la dernière connexion réussie**, figée tant qu'on reste hors ligne : « Hors ligne · dernière connexion à 15 h 51 » (`OfflineNotifier`, `widgets/offline_banner.dart`). Test dans `resilience_test.dart`.
- [x] **B9** (retour de l'utilisateur sur le téléphone, 2026-10-02) « Les actions liées au NAS ne sont pas instantanées » : **mesuré** avec un journal des durées (`--dart-define=HTTP_TRACE=true`, `core/http_trace_interceptor.dart`, lire avec `adb logcat -s flutter`). Résultat : toutes les lectures prennent 40 ms à 1 s, mais **chaque `PUT /v1/predictions` prend 3 à 5,3 s** (7 mesures), suivi d'un `GET` de 40-200 ms : ce n'est pas le réseau, c'est **l'écriture en base sur le NAS** (voir C9). Côté appli, deux corrections : (1) un nouvel appui sur un pronostic pendant un envoi en cours était ignoré (garde anti double envoi) : il s'affiche maintenant tout de suite et le dernier choix part dès que l'envoi en cours est fini (`prediction_panel.dart`, test `prediction_panel_test.dart`) ; (2) le changement d'avatar n'avait aucun retour instantané : le logo choisi s'affiche tout de suite (Profil et Accueil, `pendingAvatarProvider`) et revient à l'ancien en cas d'échec. À vérifier aussi : réactions du forum, interrupteurs de Réglages, suivis (déjà à retour instantané depuis le J15).
- [x] **B6** **Guide d'explications des compétitions** : **décision du 2026-10-02 : stocké comme les tutos du J12** (`assets/learn/valorant-competitions.json`, embarqué, sans endpoint ni base ; le « ? » et la progression existants servent), à la place de la base prévue au départ. 6 articles écrits par nous (Une saison de VCT, Le Kickoff, Le Stage, Les Masters, Champions, Les formats) avec schémas en données et mini-quiz ; mots du glossaire `[[triple élimination]]`, `[[groupes GSL]]`, `[[BO5]]`… ; entrée par une carte « Comprendre les compétitions » sous la carte de saison de la page Valorant. Faits vérifiés dans nos données (16 équipes, 4 groupes GSL, playoffs à 8 en double élimination, grande finale en BO5, Masters Santiago/Londres) et recoupés avec le résumé web du format VCT 2026 (Kickoff en triple élimination, Stages en poules puis playoffs, Play-Ins avec challengers). Vu à l'écran sur l'émulateur (liste, article Champions). Test : le guide passe le test de complétude des tutos. **Relu par l'utilisateur le 2026-10-02** : textes validés ; seul retour, le schéma « Une saison de VCT » (6 étapes) coupait les mots, il se range maintenant sur 2 rangées de 3 (`_Flow` : par rangées de 3 au-delà de 4 étapes, test dans `learn_screen_test.dart`).

### Lot 3 — Démarches et décisions (préparées par Claude, faites par l'utilisateur)
- [ ] **C1** **Licence open source** du dépôt : choix (MIT, AGPL…) puis fichier `LICENSE` et mention dans le README (J7). Claude prépare le comparatif en 5 lignes.
- [ ] **C2** **Écrire à PandaScore** : usage du plan gratuit et attribution exigée (J7). Claude rédige le brouillon du mail ; l'attribution est ensuite ajoutée dans Réglages → Sources si la réponse l'exige.
- [ ] **C3** **Marque et domaine « Keryx »** : vérification INPI, EUIPO, nom de domaine (J16).
- [ ] **C4** **Modèles d'e-mails Firebase** (`docs/emails/`) : les appliquer quand la vérification du domaine `keryx.thibaultcauche.com` débloque le champ Message, sinon décider (J16).
- [ ] **C5** **Copie de sauvegarde hors site** (règle 3-2-1) : choisir une destination, la brancher au script de sauvegarde, tester une restauration depuis cette copie (J7).
- [ ] **C6** **Bêta Google Play** (piste de test interne) et visuels de la fiche (icône, bandeau, captures) dans l'identité (J7, J16).
- [ ] **C7** **Forum avant ouverture publique** : conditions relues (`forum_terms.dart`, version 2 si modifiées), contact de modération indiqué (les conditions renvoient vers « la fiche de l'application »), exigences des stores pour le contenu généré par les utilisateurs vérifiées (J13).
- [ ] **C8** **Test avec 2-3 néophytes externes** (onboarding, glossaire, tutos Apprendre, guide des compétitions) : relevé des retours dans ce document (J6, J12).

- [~] **C9** **Écritures lentes sur le NAS** (trouvé par B9) — **cause confirmée le 2026-10-02** : `insert` mesuré sur le NAS à 2,6 / 3,7 / 3,7 / 5,4 / 3,7 s ; correctif `command: postgres -c synchronous_commit=off` dans `infra/docker-compose.yml`, appliqué à chaud avec `ALTER SYSTEM` ; **reste à remesurer après application** : une écriture en base met 3 à 5 s alors qu'une lecture met < 200 ms. Hypothèse : latence de `fsync` du stockage du NAS (Postgres attend la confirmation du disque à chaque commit ; cohérent avec les « 72 s pour rejouer le WAL » du J7). **À mesurer sur le NAS** (commande dans la réponse du 2026-10-02 : `	iming` sur des `insert`), puis si confirmé régler `synchronous_commit=off` sur le service `postgres` de `infra/docker-compose.yml` (la base répond avant la confirmation disque ; en cas de coupure brutale on perd au plus ~0,6 s de dernières écritures, jamais de corruption : acceptable pour des pronostics et des suivis). Autre point repéré : la limite de 60 requêtes/minute est comptée **par IP vue par l'API**, et derrière Tailscale Funnel c'est probablement l'IP du relais, donc partagée entre tous les utilisateurs ; `trust proxy` n'est pas réglé (`apps/api/src/main.ts`). Pas la cause des 5 s mesurées, mais à traiter avant la bêta à plusieurs.

### Laissés dans « Ensuite » (décisions du 2026-10-02, avec la raison)
- **Détail par carte et roster** de la fiche équipe (J6) : le plan gratuit PandaScore n'a pas ces données (règle 6).
- **Sans spoil par catégorie** (J6) : attendre une 2ᵉ catégorie avec de vraies données.
- **Lien de compte Google/Apple** (J11) : Apple dépend de iOS.
- **Images officielles du jeu** (J12) : demande de licence ou clé d'API à Riot.
- **iOS** (compte Apple Developer, APNs, icône iOS) : après la sortie, décision J4.
- **Chantiers de fond** : lot B du J14, quiz avec points, suite de l'identité Keryx (podium, cérémonie du vainqueur, carte de partage), autres jeux, temps réel V2, politique, streams, sport, site Next.js, Start.gg.
- **Abandonnée** : fidélité pixel-perfect aux maquettes (décision du 2026-09-30).

**Critères d'acceptation** : chaque case ci-dessus est cochée, ou barrée avec la raison de l'abandon ; `flutter analyze`, tests Flutter et `pnpm -r test` verts ; CI verte, goldens régénérés par la CI si un widget couvert change (B1, B6 les concernent peut-être) ; `docs/00` §7 mise à jour ; « État actuel » du `CLAUDE.md` mis à jour.

---

## Ensuite (par ordre de priorité proposé)

0. **Quiz des tutos avec points et classement** (idée du 2026-10-01, version « plus grosse » du compteur du J12) : points pour les quiz réussis, éventuellement dans les classements de groupe. Demande que **le serveur connaisse les bonnes réponses** (aujourd'hui dans les JSON embarqués de l'appli, donc « quiz réussi » est déclaré par le client), une règle claire pour ne pas mélanger ces points à ceux des pronostics (classement séparé ?), un seul passage compté par question, et une table de résultats par question plutôt que par tuto.

0 bis. **Suite de l'identité Keryx** (idées du 2026-10-02, après le J16), à piocher par petits lots :
   - **Icône de notification Android** : silhouette blanche monochrome (K dans un losange) + couleur d'accent laiton, à la place de l'icône par défaut (sinon carré blanc dans la barre). Rapide, visible dès la première notification.
   - **Visuels de la fiche Google Play** (bêta) : icône, bandeau et captures d'écran dans l'identité.
   - **Podium des classements de groupe** : médailles / tampons laiton, argent, bronze pour le top 3.
   - **Cérémonie du vainqueur** : quand une équipe suivie gagne, carte « proclamée vainqueur » au cadre renforcé, affichée une seule fois (règle 13).
   - **Carte de partage** : image du résultat ou du pronostic aux couleurs de Keryx, à envoyer à un ami.
   - **Skeletons teintés laiton** : à intégrer dans le J15 (skeletons à la place des spinners), pas un lot à part.
   - Vérifier plus tard : le « 1 » de Cinzel ressemble à un « I » (lisibilité des scores) ; contraste du laiton sur les cartes colorées ; glossaire et icône du lanceur à voir à l'écran.

1. **Guide d'explications des compétitions** (idée du 2026-09-30) — **repris dans le J19 (B6)** : page « Comprendre les compétitions » (Kickoff, Stage, Masters, Champions, formats, qualification), ouverte depuis un « ? » de la page jeu. Textes propres écrits pour un néophyte, relus avant mise en base (pas de recopie du site officiel VCT, qui ne sert qu'à vérifier les faits), stockés en base comme le glossaire, avec un petit endpoint.
2. **Autres jeux PandaScore** (LoL, CS2, Dota 2, R6, Rocket League…) : même adaptateur, filtrage par tier. Nouveaux formats à dessiner : **phase suisse**, **classement de lobby** (battle royale). Vérifier le gagnant par carte pour CS, Dota 2 et LoL sur du tier S.
3. **Temps réel V2** : flux SSE `GET /v1/live/events/:id`, **Live Activities** iOS (écran 13).
4. **Autres jeux de l'onglet Jeux** (écran 16) : « devine le score », quiz (`quiz_answer`). Les pronostics (`prediction`) sont faits depuis le J11.
5. **Politique** avant avril 2027 : adaptateurs `assemblee` (zips quotidiens), `senat`, `legifrance` (PISTE), `elections` (data.gouv, rythme rapide le soir d'élection). Écrans 19 (loi façon colis) et 25 (soirée électorale). Jeu « Qui a voté ? » à partir de `politique-quiz/`. Tester le flux de résultats en direct sur un scrutin partiel **avant** la présidentielle.
6. **Streams** : API Twitch (écran 23).
7. **Sport par vagues** (`docs/01b`) : football (football-data.org + openfootball), F1 (Jolpica), puis rugby/basket.
8. **Site web Next.js (SEO)** : pages publiques en lecture seule (résultats, compétitions, classements), à côté de l'appli Flutter web du J17 ; vise surtout à être trouvé sur Google.
9. **Start.gg** pour les jeux de combat.

## Points ouverts à trancher en chemin

| Point | Quand |
|---|---|
| Compte Apple Developer (99 $/an) | Avant J4 (iOS) |
| Nom de l'appli (« News » est un nom de travail) — nom de domaine réglé au J7 (Tailscale Funnel, pas de domaine nécessaire pour l'instant) | Avant J7 |
| Logo et icône d'app définitifs | Avant J7 (reporté, toujours ouvert) |
| **Identité de l'app** (nom, logo, domaine) → à ce moment-là : modèles d'e-mails Firebase Auth (vérification, réinitialisation : expéditeur, objet, texte en français) et **page de validation « Your email has been verified »**, hébergée par Firebase, à remplacer par une page à nous | Avec le nom et le logo (reporté du J7, pas rattaché à un jalon) |
| Écrire à PandaScore : usage du plan gratuit et attribution exigée | Avant J7 |
| Licence open source du code (MIT, AGPL…) | Avant J7 |
| ~~**Supprimer l'onglet Suivis**~~ **Fait au J11** (idée du 2026-09-30) : réintégrer les suivis dans l'Accueil (« Tes suivis », prévu par `docs/02` écran 17, retiré au J10 car doublon tant que Suivis existe) pour libérer un onglet quand les options communautaires (J11-J13) en demanderont. Un seul des deux doit exister, pas les deux | À l'arrivée du J11 |
