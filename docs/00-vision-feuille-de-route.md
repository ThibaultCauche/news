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
