# Projet News — Vision & feuille de route

> Document de référence du projet (copie du projet claude.ai « News » au 2026-09-25, désormais tenu à jour dans ce dépôt). Chaque session le lit en premier et le met à jour en fin de jalon (section « Décisions »). Le détail du développement est dans `04-jalons.md`.

## 1. Vision

Une appli (mobile d'abord, site ensuite) pour **suivre les événements qui comptent pour soi** — e-sport, sport, streams, politique, et plus tard d'autres catégories — et **comprendre où on en est en quelques secondes**, sans être submergé.

Cible prioritaire : **le curieux qui veut s'intéresser à une scène sans en être expert** (ex. : quelqu'un qui veut suivre la scène e-sport Valorant mais ne sait pas où chercher et se noie sous l'info). Les outils existants (VLR.gg, Liquipedia, SofaScore, FlashScore) s'adressent aux initiés.

Objectif : de vrais utilisateurs dès le départ. **Appli open source et gratuite** au lancement ; un modèle payant ne sera envisagé que si l'appli marche vraiment.

## 2. Principes produit

- **Hyper lisible et digeste.** L'essentiel en premier, les explications complexes seulement si on les cherche (divulgation progressive).
- **Une visualisation principale par question**, lisible en ~3 secondes (référence : arbre de tournoi radial, trophée au centre, chemins colorés).
- **Modèle générique** : tout est un *Événement* (date, statut, participants, résultat) rattaché à des *Entités* et *Compétitions*. Ajouter une catégorie = brancher une nouvelle source.

## 3. Fonctionnalités envisagées

**Cœur**
- Abonnements hiérarchiques (jeu → région → compétition → équipe → joueur) + notifications.
- **Accueil** en 4 blocs : Maintenant pour toi → Tes suivis → Les grands rendez-vous → À découvrir (avec la raison de chaque suggestion).
- Agenda unifié « à venir / en cours / terminé », toutes catégories.
- État d'avancement visuel :
  - Élimination directe → arbre radial
  - Poules → mini-grilles (qualifiés au-dessus d'un trait)
  - Saison → « carte de saison » avec point « tu es ici »
  - Triple élimination → « 3 vies »
  - Loi → suivi façon colis (Déposée → Commission → Votée → Promulguée)
  - Lancement spatial → compte à rebours + déroulé T–/T+
  - Sorties → calendrier + « ma liste »
  - Streams → bulles « en live » type stories
- Le chemin de l'équipe suivie s'allume dans l'arbre ; le centre de l'arbre évolue (compte à rebours → prochain match → vainqueur).
- Double élimination : tableau principal en cercle + repêchage en liste par tours.

**Accessibilité aux néophytes**
- Onboarding guidé : choisir ses sujets et un jeu → 3 équipes suggérées avec raison.
- « Pourquoi ce match compte » en une phrase.
- Glossaire au toucher (BO3, lower bracket…).
- Mode sans spoil (par suivi).

**Catégories envisagées** (écran Explorer) : E-sport · Sport · Politique · Élections · Streams · Espace · Sorties (jeux/films/séries) · Tech (keynotes) · Culture (festivals, cérémonies) · Science (Nobel, découvertes).

**Autres pistes**
- Résumés quotidiens/hebdo/mensuels/annuels (notamment politique) ; résumé du matin « l'essentiel en 3 points ».
- Export agenda (.ics / Google Agenda), widgets, Live Activities.
- Abonnements créés par la communauté (niches).

**Jeu (accroche quotidienne / rétention)**
- Politique : « Qui a proposé cette loi ? », « Adoptée ou non ? » — neutralité stricte (équilibre entre partis, sources officielles citées au reveal).
- Sport / e-sport : « Devine le score », « Quel joueur a ces stats ? », pronostics entre amis.
- Quiz transverse tiré du flux d'actu de la semaine.

## 4. Architecture (arrêtée à l'étape 3 — détail dans `03-architecture-backend.md`)

- L'appli ne parle **jamais** directement aux API externes. Le backend ingère, normalise, stocke, sert l'API et déclenche les notifications.
- **Backend : NestJS (TypeScript)** en monorepo pnpm, avec deux points d'entrée : `api` (REST `/v1`, OpenAPI → client Dart généré) et `worker` (BullMQ : ingestion, notifications).
- **Données** : PostgreSQL 16 + Redis 7. Modèle générique `competition` / `event` / `entity`, avec `format` + `structure` pour les vues et `provider_ref` pour les sources.
- **Ingestion** par adaptateurs, un par fournisseur (PandaScore, start.gg, Liquipedia, football-data/openfootball, Jolpica, Assemblée, Sénat, Légifrance, élections…). Le rythme rapide est réservé aux matchs suivis en direct : ~250–400 req/h estimées sur les 1 000 permises par PandaScore.
- **Temps réel** : pour le MVP, rafraîchissement 15–30 s avec `ETag` + push FCM. Ensuite SSE et Live Activities.
- **Hébergement** : NAS, Docker Compose, exposé par Cloudflare Tunnel. Plan de sortie vers un VPS (~5 €/mois).
- **Mobile** : Flutter (Riverpod, cache local drift, CustomPainter pour l'arbre radial).
- **Web (plus tard)** : Next.js pour le SEO.

## 5. Risques principaux

- **Les données sont le vrai produit** : disponibilité, prix, licence, limites d'appels. Voir `01-donnees-sources-valorant.md`, `01b-donnees-elargissement-esport-sport.md` et `01c-donnees-politique.md`. Chaque nouvelle catégorie demande sa propre étude de sources.
- Points ouverts données : brackets et classements **confirmés gratuits** chez PandaScore (tests du 2026-09-25), ainsi que les 15 jeux (test multi-jeux). Reste la latence réelle. Le gratuit ne donne ni le score en rounds de chaque carte ni le nom des cartes.
- Offres gratuites « non commerciales » (Liquipedia LPDB, GRID Open Access, OpenF1) : si l'appli devient payante, il faudra passer aux offres commerciales.
- API non officielles (ESPN, LoL Esports) : utilisables en secours seulement, toujours avec une source officielle en repli. Pas de scraping de sites (CGU, droit des bases de données).
- Hébergement sur le NAS : une coupure à la maison rend l'API injoignable. Parade : cache hors ligne dans l'appli, supervision externe et plan de sortie VPS.
- Trop large → on commence par peu de sources (Valorant d'abord), les autres catégories sont maquettées mais pas prioritaires.
- Neutralité politique du jeu et des résumés : sources officielles, noms officiels des groupes, résumés par gabarits (voir `01c`), charte de neutralité dans les Réglages.

## 6. Feuille de route

| # | Étape | Statut |
|---|---|---|
| 0 | Brainstorm, décisions, jalons (discussion « QG » du projet claude.ai) | En cours |
| 1 | Données : sources (Valorant, puis tout l'e-sport, le sport et la politique) | **Valorant testé (2026-09-25)** ; 15 jeux PandaScore confirmés ; élargissement sport (`01b`) et politique (`01c`) étudiés ; restent les tests open data politique |
| 2 | Maquettes mobiles | **26 écrans V2 faits (2026-09-25)** — Figma + `02-design-maquettes-mobiles.md` ; reste logo, Culture, Science, et les nouveaux formats (phase suisse, classement de lobby, championnat, F1) |
| 3 | Stack & architecture | **Fait (2026-09-25)** — `03-architecture-backend.md` |
| 4 | Développement (backend + app mobile), jalons J1 → J7 | **En cours** — voir `04-jalons.md` |
| 5+ | Autres jeux e-sport, sport, politique (Assemblée, Sénat, élections), jeu, site web | Plus tard — proposition : **viser une version politique/élections prête avant la présidentielle (1er tour le 18 avril 2027)** |

## 7. Décisions

- 2026-09-24 — Cible : de vrais utilisateurs dès le départ ; persona prioritaire = néophyte curieux.
- 2026-09-24 — Mobile d'abord.
- 2026-09-24 — Ordre : données → maquettes → stack/architecture.
- 2026-09-24 — Premier vertical : e-sport Valorant.
- 2026-09-24 — Données (proposition, à confirmer après tests) : socle PandaScore gratuit (Fixtures) + Liquipedia en complément mis en cache (attribution CC-BY-SA) ; 0 € au lancement ; pas de scraping VLR.gg ni d'API cachée en production ; GRID/Riot officiel visé plus tard.
- 2026-09-25 — Maquettes dans Figma, thème sombre par défaut. Code couleur : or = mon équipe, rouge = en direct / tu es ici.
- 2026-09-25 — Double élimination : arbre radial pour le tableau principal + repêchage en liste ; le centre de l'arbre affiche le compte à rebours du prochain match de l'équipe suivie.
- 2026-09-25 — **Direction visuelle : V2** (skills apple-design + emil-design-eng d'Emil Kowalski) : tab bar en verre flottante, bordures semi-transparentes, grands titres iOS, divulgation progressive, glossaire intégré au texte, specs de mouvement (animations rares et courtes, rien sur les actions fréquentes).
- 2026-09-25 — Maquettes « au max » dans Figma avant d'avancer. Accueil en 4 blocs (maintenant, suivis, grands rendez-vous, découvertes). Catégories distinguées par leur icône, pas par une couleur.
- 2026-09-25 — **Backend NestJS** (monorepo, `api` + `worker`, PostgreSQL + Redis + BullMQ), **hébergé sur le NAS** (Docker Compose + Cloudflare Tunnel), compte anonyme par défaut, REST par écran avec client Dart généré.
- 2026-09-25 — **PandaScore gratuit validé comme socle** : brackets (`previous_matches` winner/loser), classements, séries et matchs inclus ; stats joueurs payantes (403). L'UI affiche le score de série et le gagnant de chaque carte, pas le score en rounds.
- 2026-09-25 — **Appli open source et gratuite, non commerciale au départ** ; passage éventuel au payant seulement si l'appli marche vraiment. Ce statut débloque les offres gratuites non commerciales (Liquipedia LPDB, GRID Open Access, OpenF1).
- 2026-09-25 — **Stratégie données 100 % gratuite** en 3 niveaux : sources officielles gratuites (socle), API non officielles publiques en secours seulement, pas de scraping de sites.
- 2026-09-25 — **Politique : open data officiel uniquement** (Assemblée nationale, Sénat, Légifrance, résultats d'élections sur data.gouv.fr ; Parlement européen plus tard), sous Licence ouverte 2.0. France d'abord.
- 2026-09-25 — **Démo « Qui a voté ? »** publiée (page partageable avec présentation du projet) : 12 vrais scrutins de l'Assemblée sur des sujets du quotidien. Position des groupes **recalculée à partir des voix** (le champ `positionMajoritaire` de l'open data n'est pas fiable).
- 2026-09-25 — **Documentation versionnée dans le dépôt** (`docs/`), `CLAUDE.md` à la racine, jalons J1 → J7 dans `04-jalons.md`. Outils Claude Code : Ponytail dès le début, Graphify à partir du J3, pas d'ECC.
- 2026-09-25 — **J1 clôturé.** **Prisma retenu** (contre Drizzle) pour la prise en main et les migrations. Adaptateur PandaScore : catalogue filtré tier S/A + tournois en cours (pas tous les tiers, pour rester dans le budget de quota) ; le calendrier/live ne filtre pas par tier, donc des matchs hors périmètre sont vus puis ignorés (`compétition introuvable`), ce qui est normal. **Brackets et classements (`event_link`/`standing`) reportés au J5** : tables créées mais non alimentées. PandaScore ne renvoie pas d'en-tête `x-rate-limit-limit` (seulement `remaining`/`used`) : le quota se déduit de `used + remaining`. Un jalon à la fois, le passage au suivant se décide dans une discussion dédiée.
- 2026-09-25 — **J2 clôturé.** Invalidation du cache worker → API par **Redis Pub/Sub** (signal transitoire, pas de file BullMQ dédiée) : le TTL court du cache (15-60s) sert de filet en cas de message raté ; une vraie file pourra être introduite au J4 si les notifications ont besoin de fiabilité/rejeu. Client Dart généré dans `packages/api_client_dart` (gitignoré, régénéré par `pnpm generate:client` : OpenAPI → `openapi-generator` dart-dio → `build_runner`), comme le client Prisma. Champs JSON de l'API en camelCase partout, y compris `sourceUpdatedAt` (le `source_updated_at` de `docs/03` était une notation de prose, pas un contrat littéral). Rate limiting via `@nestjs/throttler` (60 req/min/IP par défaut). `home.highlights` (grands rendez-vous) se base sur `competition.importance` (tier PandaScore) et non `event.importance`, jamais renseigné par l'ingestion du J1.
- 2026-09-26 — **J3 clôturé.** Projet Flutter en **`apps/mobile`** (point ouvert tranché), Android/iOS uniquement (pas de plateforme web dans le projet Flutter : un web viendra plus tard en Next.js, `docs/00` §6 — la vérification interne en a utilisé une temporairement, retirée en clôturant le jalon). Petit ajout d'API : `parentId` exposé sur `CompetitionResponseDto` (une ligne, donnée déjà présente côté Prisma) pour que l'appli puisse remonter l'arbre des compétitions jusqu'à la ligue racine depuis un match connu, sans nouvel endpoint — nécessaire pour construire l'écran Saison à partir des vraies séries VCT 2026 (elles mélangent 2025/2026 et EMEA/Americas à plat sous la ligue). Un seul intercepteur Dio gère à la fois l'`ETag`/`304` et le repli hors ligne sur le cache local. Accueil sans « Tes suivis » ni « À découvrir » (attendent les abonnements du J4) : seuls « en direct » et « grands rendez-vous » sont affichés, tirés tels quels de `/v1/home`. Plusieurs éléments visibles sur les maquettes restent volontairement non fonctionnels en l'état — visuels seulement, sans appel réseau ni persistance — en attendant les jalons qui les alimentent : bouton « M'alerter » et bascule « sans spoil » (abonnements/réglages = J4/J6), bloc « pourquoi ce match compte » et « forme récente » (masqués, `context_snippet` et historique par équipe = J6), export `.ics` et ajout à l'agenda (désactivés, hors périmètre J3).
- 2026-09-26 — **J4 clôturé.** Compte anonyme (JWT court + jeton de rafraîchissement, pas d'inscription), abonnements (directs et hiérarchiques via `competition.parentId`/`category`), moteur de notifications complet (heures calmes, sans spoil côté serveur, déduplication par contrainte unique `(userId, eventId, type)`, plafond 3/h hors suivi direct, nettoyage des jetons FCM invalides). **iOS reporté après la sortie de l'appli** (décision produit, pas seulement « on commence par Android ») : compte Apple Developer et clé APNs restent un point ouvert pour plus tard. Type de notification « qualification/élimination » reporté au J5 avec les brackets (`event_link`). `Device.timezone` remplacé par `Device.utcOffsetMinutes` (décalage UTC en minutes, calculé côté appli via `DateTime.timeZoneOffset` — évite une dépendance Flutter supplémentaire rien que pour un nom de fuseau IANA). Petit ajout d'API : `GET /v1/subscriptions` (non listé dans `docs/03` §4, nécessaire à l'écran Suivis). Accueil : bandeau « à suivre » quand rien n'est en direct (repli sur le prochain match à venir, tout le monde, pas seulement les suivis — cohérent avec « les grands rendez-vous, même non suivis » de `docs/02`). Tap sur une notification → ouverture directe de l'écran du match concerné (`eventId` dans le payload `data` FCM). Vérifié en conditions réelles sur un téléphone Android physique et un vrai projet Firebase : compte créé, deux abonnements réels (« Suivre »), les trois types de notification testés (rappel T-15, début, résultat) reçus en arrière-plan, texte sans spoil confirmé à l'écran. Le rappel T-15 a été vérifié par un test contrôlé (départ d'un match existant avancé temporairement) faute de vrai match dans la fenêtre au moment du test.
