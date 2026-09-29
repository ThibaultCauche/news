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
| J10 | Comptes avec pseudo, page de profil (badges, score de pronostics, stats), pronostics en points fictifs, groupes d'amis (façon MPP) | On parie sur ses matchs et on se compare à ses amis, gratuitement | À planifier |
| J11 | Section apprentissage Valorant : tutos écrits (jeu, rôles, cartes) | Un néophyte comprend comment on joue | À planifier |
| J12 | Forum par match (bêta fermée) : badge d'équipe selon le jeu/sport du forum, modération de base | On discute d'un match sans que ça dégénère | À planifier |
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

**Ordre décidé le 2026-09-29** (voir `docs/00` §7) : J10, J11, J12 ci-dessus, chacun cadré dans sa propre discussion (`/jalon <n>`). Le forum vient ensuite par étapes (fils par équipe, tournoi, jeu, puis création libre), toujours sur Valorant seul : les autres jeux attendent que Valorant soit complet. Les options communautaires sont **facultatives** pour l'utilisateur : l'appli reste utilisable pour les seuls résultats. Sont déjà connus : passer du compte anonyme à un compte avec pseudo (J10), et prévoir avant toute ouverture publique du forum signalement, blocage, conditions d'utilisation, suppression des messages avec le compte (RGPD).

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
| Compte Apple Developer (99 $/an) | Avant J4 (iOS) |
| Nom de l'appli (« News » est un nom de travail) — nom de domaine réglé au J7 (Tailscale Funnel, pas de domaine nécessaire pour l'instant) | Avant J7 |
| Logo et icône d'app définitifs | Avant J7 |
| Écrire à PandaScore : usage du plan gratuit et attribution exigée | Avant J7 |
| Licence open source du code (MIT, AGPL…) | Avant J7 |
