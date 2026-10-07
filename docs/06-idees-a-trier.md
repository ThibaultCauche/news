# Idées à trier — brainstorm du 2026-10-03/04

> Recueil des retours (test par le père de Thibault, usage sur téléphone) et des idées discutées dans la session de brainstorm du 3-4 octobre 2026, après le J20. **Trié le 2026-10-04** : voir « Tri décidé » en fin de document.
>
> Repères : **#C3** = thème C, idée 3. Le « # » les distingue des codes de jalons (J21…) et de ceux du J19 (A1, B6, C8…).
>
> Effort estimé : **S** = quelques heures, **M** = un à deux jours, **L** = un jalon entier ou plus.
> Les références de code renvoient à l'état du dépôt au J20.

---

## A. Lisibilité et passage à l'échelle (beaucoup de jeux et de sports)

Constat de départ : « on ne comprend pas de quoi parlent les cartes ». Avec 20 jeux et 40 sports, ça deviendrait le chaos. Il faut penser l'appli pour cette échelle, quitte à ce qu'elle paraisse vide pour l'instant.

| # | Idée | Détail | Effort |
|---|---|---|---|
| #A1 | **Ligne de contexte complète sur chaque carte** | Aujourd'hui `EventCard` affiche `event.competition.name`, c'est-à-dire le nom de l'**étape** (« Group C · BO3 »), sans jeu ni tournoi. Afficher `[logo du jeu] Champions 2026 · Groupe C` (`competition.game` + compétition parente via `parentId`). | S |
| #A2 | **Carte compacte** (ligne de 56 à 64 px) | Heure ou statut, deux équipes avec logos, score. Utilisée dans les listes (Accueil, Agenda, Compétitions). La grande `EventCard` reste pour l'écran du match et « Maintenant pour toi ». Objectif : 8 à 10 matchs visibles par écran au lieu de 2. | M |
| #A3 | **Regroupement par compétition avec en-tête collant** | Les lignes compactes sous un en-tête qui reste collé en haut pendant le défilement (`[logo] Champions 2026 · Groupe C`), comme Apple Sports ou Flashscore. | M |
| #A4 | **Suivre toute une structure** (G2, KC, Fnatic…) | Table `organization` + `entity.organizationId`, remplie à la main pour les grosses structures (PandaScore ne donne aucun lien équipe → organisation), Liquipedia plus tard. Suivre une organisation s'étend à ses équipes, y compris celles ajoutées plus tard. Sur la fiche équipe : « Suivre G2 Valorant » / « Suivre toute G2 (5 équipes) ». **À trancher** : les camps du forum restent par jeu (suivre toute G2 ne donne pas de badge G2 partout). | M |

## B. Onglet Discussion (remplace « Bientôt »)

Le 4ᵉ onglet est vide depuis le J11. On réutilise le forum du J13 plutôt que de créer un second système. L'onglet Jeux reste à côté.

| # | Idée | Détail | Effort |
|---|---|---|---|
| #B1 | **Mes discussions** | Fils où j'ai écrit + fils suivis (`ForumThreadFollow`), triés par activité récente, avec compteur de non-lus. | M |
| #B2 | **Fil de groupe** | Un `ForumThread` réservé aux membres d'un groupe d'amis : réactions, réponses, spoiler, flou sans spoil et modération récupérés tels quels. Privé, donc ouvrable même si le forum public reste en bêta fermée. | M |
| #B3 | **Messages privés** | Fil privé à deux, même modèle. **Limité aux personnes qui ont un groupe en commun** (même règle que `canSeeFriendsPicks`) : pas de harcèlement par des inconnus, exigences des stores allégées. | M |
| #B4 | **Rechercher et rejoindre** | Discussions libres et fils d'équipe, de compétition ou de jeu. | S |
| #B5 | **Partager un événement** | Nouveau type de message `event` / `competition` / `prediction` qui ne contient qu'un identifiant : compatible avec « texte seul, pas de lien libre ». L'appli dessine la carte avec les données en direct (mise à jour seule, sans spoil propre à chaque lecteur). Bouton « Partager » sur un match → feuille « Envoyer à… » (groupes, messages privés, fils). | M |
| #B6 | Temps réel | Le rechargement toutes les 5 s du tchat suffit pour commencer ; WebSocket seulement si le besoin se fait sentir. | — |

## C. Page Tournoi (bugs et oublis)

| # | Idée | Détail | Effort |
|---|---|---|---|
| #C1 | **Défilement auto calé à la fin quand tout est joué** | `nextMatchId` (`bracket_model.dart`) renvoie `null` quand il n'y a ni match en direct ni à venir, donc la vue retombe au début. Renvoyer le dernier match terminé (ou la case « Qualifiés » / finale). | S |
| #C2 | **Scores dans les cercles** (poules et phase finale) | `radial_bracket.dart` ne dessine le score que si `slot.live`. L'afficher aussi pour les matchs terminés, petit sous le nœud, masqué en sans spoil. | S |
| #C3 | **Cercle final en vert** | **Décidé (2026-10-04)** : le laiton reste sur les cercles des équipes (décision du J20) ; seul le **cercle final** (« Qualifiés » d'une poule, centre de la phase finale) passe au **vert** une fois le groupe ou le tournoi terminé (règle de la palette : vert = qualification, validé). | S |

À faire de préférence **avant le 7 octobre** (premiers matchs des playoffs de Champions).

## D. Agenda

| # | Idée | Détail | Effort |
|---|---|---|---|
| #D1 | **Bascule Mes suivis / Tout** | Sur « Mes suivis » par défaut dès qu'on suit quelque chose. | S |
| #D2 | **Lien d'agenda personnel** (webcal/.ics) | À la place d'« ajouter ses propres événements » (jugé de trop : concurrence Google Agenda sans valeur ajoutée). Un lien à ajouter une fois dans Google ou Apple Agenda, synchronisé avec les suivis. Endpoint à créer ; complète le bouton « Ajouter à l'agenda » match par match. | M |
| #D3 | **Filtres à sélection multiple** | E-sport et Sport en même temps. `category` passe à une liste (appli et API). | S |
| #D4 | **Choisir une date** | Bouton icône calendrier → calendrier du mois, avec un point sur les jours où un suivi joue. La fenêtre est fixe aujourd'hui (14 jours en arrière) : charger autour de la date choisie. | M |
| #D5 | **Catégories en icônes** | Icône seule quand le filtre est inactif, icône + nom quand il est actif. À grande échelle, le vrai filtre utile est le 2ᵉ niveau (quel jeu, quel sport), déjà présent pour l'e-sport avec les ligues. | S |

## E. Page détail du match

| # | Idée | Détail | Effort |
|---|---|---|---|
| #E1 | **Score dans la carte** | Fusionner `_Participants` et `_StatusDisplay` dans la carte, en gardant le flou et l'appui long. | S |
| #E2 | **Bouton retour sans « Group X »** | Le libellé vient de `competition.name` dans `leading`. Flèche seule, ou nom du tournoi parent (« Champions 2026 »). | S |
| #E3 | **Bouton Regarder** | `streams_list` est dans le plan gratuit PandaScore (lien officiel, `official: true`, vérifié dans `tests-pandascore/samples`). Avant et pendant le match. Voir aussi H. | S |
| #E4 | **Nom des cartes et score en rounds** | `_MapsSection` n'affiche que le gagnant de chaque carte. Piste : **LPDB Liquipedia** (`match2`), offre gratuite applicable (appli non commerciale, MIT), avec attribution. | M |
| #E5 | Autres infos | Confrontations passées (notre base), place du match dans le tableau, raccourci vers les fils Direct et Discussion. | S-M |

## F. Accueil

« Tout est trop gros. » Ordre proposé, de haut en bas :

1. Ligne de résumé (J20), conservée.
2. **En direct** : rangée horizontale de pastilles avec score (façon stories).
3. **Maintenant pour toi** : une seule carte, la seule grande de l'écran (la carte de grande finale devient son état spécial).
4. **Aujourd'hui dans tes suivis** : liste verticale de cartes compactes (#A2), regroupées par compétition (#A3).
5. **Les grands rendez-vous** : carrousel horizontal de mini-cartes de compétition (logo, nom, phase, « en cours » ou date).
6. **Apprendre / découvrir** : « Nouveau sur Valorant » réduit à une puce qu'on peut fermer.

Principe : défilement horizontal pour le secondaire, liste verticale pour ce qu'on suit. Effort : **M**, dépend de #A1-#A3.

## G. Notifications

Aujourd'hui, pour un match suivi : rappel T-15, début, résultat, plus qualification/élimination et rappel de pronostic à T-30 ; un interrupteur par type, plafond 3/h.

| # | Idée | Détail | Effort |
|---|---|---|---|
| #G1 | **Une notification par match qui évolue** | `fcm.service.ts` ne pose ni `android.notification.tag` ni `apns-collapse-id`. Tag `event-<id>` : « dans 15 min » → « c'est parti » → « terminé » se remplacent. La correction la plus rentable. | S |
| #G2 | **Fusionner les rappels** | Sans pronostic, le rappel T-15 le dit (« commence dans 15 min, tu n'as pas encore pronostiqué ») au lieu d'une notification de plus à T-30. | S |
| #G3 | **Réglages par défaut** | Début + résultat pour une équipe suivie, résultat seul pour une compétition entière, T-15 seulement sur demande (doublon avec « c'est parti »). | S |
| #G4 | **Regroupement Android** | « 3 matchs commencent » au lieu de 3 notifications. | S |
| #G5 | Notification permanente avec le score en direct | Équivalent Android des Live Activities. Plus tard. | M |

## H. Diffusion et co-streamers

| # | Idée | Détail | Effort |
|---|---|---|---|
| #H1 | **Lien vers la diffusion sur la carte** | Petite icône avec le nombre de streams en direct ; un tap ouvre une feuille : officiel d'abord, puis co-streamers français. Lien vers Twitch plutôt que lecteur intégré (l'intégration web impose de déclarer le domaine). | S-M |
| #H2 | **Co-streamers sous licence** (Hyp pour Valorant, Skyyart pour LoL…) | Aucune API ne les liste : table `broadcast(competition ou event, plateforme, chaîne, langue, type officiel/co-stream, vérifié)`, remplie **par compétition**. | M |
| #H3 | **API Twitch Helix** (gratuite) | Savoir si la chaîne est en direct + nombre de spectateurs ; n'afficher que ceux qui streament, français en premier. | M |
| #H4 | **Demande des streamers** | Formulaire « Je diffuse cette compétition », connexion Twitch pour prouver la propriété de la chaîne, validation manuelle. **Uniquement les co-streamers sous licence** (règles de co-streaming de Riot) : jamais de restream pirate. | M |
| #H5 | Intérêt pour les streamers | « Regarder avec Hyp » sur la carte, groupe de pronos de leur communauté affiché en stream : canal d'acquisition (cf. conseil du 2026-10-01, co-streams Karmine Corp). | — |

## I. Nouveaux contenus

| # | Idée | Détail | Effort |
|---|---|---|---|
| #I1 | **League of Legends** | Même adaptateur PandaScore. **Worlds en cours** (finale début novembre), porte d'entrée citée par le conseil. Compléter `isMajorEvent`, dessiner la **phase suisse**, vérifier le gagnant par carte en tier S. | L |
| #I2 | **Super Smash Bros. Ultimate** (remplace TFT) | **Choisi (2026-10-04)**. TFT écarté : absent de PandaScore (`01b`), seulement sur Liquipedia. Critères : données sûres + schéma de compétition différent, pas forcément Riot. **Smash Ultimate via start.gg** (ex-smash.gg, tous les tournois Smash y sont) : duels 1 contre 1 entre **joueurs** (pas d'équipe, utile plus tard pour le tennis ou la F1), double élimination à des centaines d'inscrits (poules puis top 8), BO3 puis BO5 en top 8 ; scène française forte (Glutonny). API GraphQL officielle gratuite (80 req/min), nouvel adaptateur (« Ensuite » n° 9) qui servira ensuite à Street Fighter 6 et Tekken 8. **À vérifier** : conditions d'utilisation de l'API start.gg ; personnage joué par manche pas toujours saisi par les organisateurs. **Nintendo** : aucun logo, image ou personnage du jeu (comme la règle Riot), tutos illustrés avec nos widgets. Alternative moins chère écartée pour l'instant : Dota 2 (PandaScore). Écartés : CS2 (phase suisse déjà couverte par LoL), battle royale Fortnite/Apex (Liquipedia seulement). | L |
| #I3 | **Football** | Championnat + classement, coupes à élimination. football-data.org + openfootball (`01b`). | L |
| #I4 | **F1** | Saison, week-ends de course, classements pilotes/constructeurs : meilleur test du modèle générique. Jolpica + OpenF1. | L |
| #I5 | **Basket** | Saison régulière puis playoffs au meilleur des 7. NBA reprend fin octobre. Source à choisir (`01b` léger sur ce point). | L |
| #I6 | **Politique** | Maquettes Figma 19 (loi façon colis) et 25 (soirée électorale). Module à part au ton neutre, aucun pronostic électoral, blocage codé en dur des résultats avant 20 h (L52-2). Base : `politique-quiz/` + open data Assemblée. | L |
| #I7 | **Un tuto « l'essentiel en une page » par nouveau jeu** | La promesse néophyte vaut pour chaque jeu ; commencer par un tuto + le glossaire plutôt que sept. | M par jeu |
| #I8 | **Onboarding multi-jeux** | Les tuiles « Bientôt » deviennent un vrai choix, équipes suggérées venant de plusieurs jeux. | M |

Conseil d'ordre : refonte de la densité (A, F) **avant** d'ajouter des jeux, puis LoL, puis un sport très différent (F1), puis le reste.

## J. Tests avec les amis et suivi

| # | Idée | Détail | Effort |
|---|---|---|---|
| #J1 | **Version web** (J17 déjà prévu, Flutter web + Windows) | Permet aux amis **sur iPhone** de tester (iOS reporté). À prévoir : notifications web (service worker, clé VAPID ; sur iPhone seulement en PWA ajoutée à l'écran d'accueil), CORS sur l'API (Tailscale Funnel), domaine autorisé dans Firebase Auth. | L |
| #J2 | **Liens qui ouvrent le web** | Une invitation de groupe ou un événement partagé ouvre le site si l'appli n'est pas installée. | M |
| #J3 | Bêta fermée Google Play | En parallèle, pour les amis sur Android (compte retrouvé, pas encore publiée). | S |
| #J4 | **Bouton « Donner mon avis »** | Avec capture d'écran (formulaire de retour Sentry), pour éviter les retours en vrac. | S |
| #J5 | **Mesures minimales** | Actifs à 7 et 30 jours, arrivées par invitation, sans outil intrusif : signaux fixés par le conseil (J30 ≥ 20 %, > 30 % par invitation). | M |

## L. Mises à jour de l'appli et fiabilité (ajouté le 2026-10-04)

| # | Idée | Détail | Effort |
|---|---|---|---|
| #L1 | **Vérification de version au lancement** | Endpoint `GET /v1/app/version` → `{ latest, minSupported, notes }` (ou Firebase Remote Config), comparé à la version de l'appli (`package_info_plus`). **Deux niveaux** : mise à jour conseillée (bandeau qu'on peut fermer) et **obligatoire** (écran bloquant quand l'API a changé de façon incompatible avec le client Dart généré). Doit être dans **la toute première version donnée aux amis** : une version installée sans ce mécanisme ne pourra jamais être prévenue. | S |
| #L2 | **Mise à jour selon la plateforme** | Android Play : API In-App Updates (`in_app_update`, souple ou immédiate). APK installé à la main / bêta : lien de téléchargement, ou **Firebase App Distribution** qui prévient les testeurs tout seul. Web : le service worker détecte la nouvelle version → « Nouvelle version disponible, recharger ». Windows : lien de téléchargement. | M |
| #L3 | **« Quoi de neuf »** | Feuille affichée une seule fois après une mise à jour (règle 13), 3 points max en français, tirés de `notes`. Utile pour faire découvrir les nouveautés aux testeurs. | S |
| #L4 | **Message de service** | Même endpoint : champ `message` facultatif (« Données en retard, on s'en occupe ») pour prévenir d'un incident, l'API étant hébergée sur le NAS. | S |
| #L5 | **Sauvegarde hors site** | Reportée depuis le J7 : `pg_dump` nocturne sans copie ailleurs que sur le NAS. À régler **avant l'arrivée des amis** (comptes, pronostics, groupes, messages). | S |
| #L6 | **Relecture légale avant ouverture** | Conditions du forum (version 1 à relire), politique de confidentialité, contact de modération, exigences des stores pour le contenu des utilisateurs : déjà notés comme reportés au J13. | S |

## M. Nouvelles idées du 2026-10-04 (2ᵉ vague), avec avis

| # | Idée | Détail et avis | Effort |
|---|---|---|---|
| #M1 | **Classement global d'une compétition** | Toutes les équipes, y compris les éliminées : statut (en course / éliminée en… / championne), bilan, et **gain déjà assuré** (« au moins 50 000 $ ») puis gain final. `computeStandings` existe déjà. Gains : PandaScore ne donne qu'une dotation totale ; la **répartition par place** est dans LPDB (Liquipedia, table des placements) ; l'adaptateur actuel ne lit que l'infobox. Utile pour la phase suisse des Worlds (bilans 3-0, 2-1…). | M |
| #M2 | **Pick'em de tout le tableau** (barème validé) | Reprend l'idée 8 du J20 et le lot B du J14. Remplir le tracé avant le début, verrouillé. **Avis sur le barème** : arrêter les récompenses à la première erreur ferait décrocher la plupart des joueurs dès le 2ᵉ match. Proposé : points croissants par tour (quart 1, demie 2, finale 4) **plus** un bonus « série parfaite » qui, lui, s'arrête à la première erreur. Choix des autres visibles après verrouillage seulement (même règle serveur que `canSeeFriendsPicks`), partage dans un groupe (type de message `prediction`, #B5). | L |
| #M3 | **Pick'em de groupe** | Le choix du groupe à chaque étape = vote majoritaire des membres ; classement entre groupes. Crée l'esprit d'équipe. Après #M2. | M |
| #M4 | **Jeu de cartes à collectionner** | Boosters **par type de carte, pas par sport**, pour tomber sur une légendaire d'un sport inconnu et s'y intéresser : excellent levier de découverte. **Garde-fous** : boosters **jamais payants ni échangeables contre de l'argent** (boîtes à butin : interdites en Belgique, encadrées en France par la loi sur les jeux à objets numériques monétisables) ; **pas de photos de joueurs** (droit à l'image, accords des ligues : voir Sorare qui paie des licences) — cartes dessinées avec nom et statistiques, à faire valider juridiquement. Boosters gagnés par l'activité (pronostics, tutos, suivis). Gros chantier, après plusieurs catégories. | L |
| #M5 | **Étude de monétisation** | Point de départ : le conseil du 2026-10-01 (`05`) : ~1 €/utilisateur actif/an en pub, abonnement « Supporter », sponsoring, **paris exclus**, coûts du direct complet 100-200 k€/an, SAS avant le premier revenu. **À étudier** : alternatives à PandaScore (GRID, Abios, Bayes Esports ; sport : API-Football, Sportmonks…), seuils d'utilisateurs où chaque coût tombe, cosmétiques (thèmes, cadres d'avatar, dos de cartes), **premium gagnable par quêtes** (bonne idée). **À éviter** : tout avantage payant dans les pronostics ou classements (les groupes deviendraient injustes). Embaucher pour saisir des données : seulement pour des niches, la saisie manuelle coûte cher. Étude, pas un jalon. | M |
| #M6 | **Appli modulée selon l'utilisateur** | Accueil et filtres par défaut ordonnés selon les suivis et l'usage réel ; ouverture sur la catégorie favorite. **Garder la barre d'onglets stable** (des onglets qui bougent désorientent) : on module l'ordre des sections, pas la navigation. Suggestion d'une autre catégorie de temps en temps, avec sa raison (« À découvrir » de la vision), fréquence plafonnée. | M |
| #M7 | **Retours utilisateurs** | Complète #J4 : bug ou idée, capture d'écran, infos de l'appareil jointes automatiquement, suivi du statut. Voir #M9. | S |
| #M8 | **Pages créées par les utilisateurs → réseau social d'événements** | **Vision long terme retenue (2026-10-04)** : à terme, Keryx devient un réseau social où l'on trouve **tout événement qui a une date** (film, événement de sa ville, page d'entreprise ou d'association avec ses sections…). **Le sport et l'e-sport sont la porte d'entrée, le réseau social est l'avenir.** Écart assumé avec le recentrage du conseil (`05`), à revalider au moment venu. **Pour ne fermer aucune porte dès maintenant** : garder le modèle générique « tout est un événement » ; prévoir qu'une page (`entity`) puisse avoir un propriétaire et des sections. **Prérequis quand on s'y mettra** : modération et signalement à l'échelle (#M10), obligations d'hébergeur (DSA), vérification des pages officielles. **Point sensible** : pour une page syndicale, politique ou religieuse, les abonnés ne doivent pas être visibles publiquement (appartenance = donnée sensible au sens du RGPD, article 9). Concurrents à étudier alors : Facebook Événements, Meetup, Luma, Eventbrite. | L+ |
| #M9 | **Sondages et tableau des idées** | Sondage = nouveau type de message du forum ; tableau des idées = fils `feature` avec réactions comme votes et statut (proposée, prévue, en cours, faite, refusée) pour éviter les doublons et affiner les demandes. Réutilise le forum (J13) et #B. Ne rien promettre sans statut. | M |
| #M10 | **Interface d'administration** | Web (Flutter web ou AdminJS sur NestJS) : utilisateurs, signalements et modération (déjà dans l'appli, à regrouper), diffuseurs (#H2), organisations (#A4), version et message de service (#L1, #L4), sondages (#M9), listes `isMajorEvent`, glossaire. **Devient nécessaire dès #A4 et #H2** (tables remplies à la main). | M-L |
| #M11 | **Notifications plus visuelles** | Logo des équipes en grande icône ou image (FCM `notification.image` sur Android, ou affichage local avec `flutter_local_notifications`), score en gras, en respectant le sans spoil. À faire avec #G1. | S-M |
| #M12 | **Analytics** | Complète #J5 : écrans et catégories les plus vus. **RGPD** : Firebase Analytics demande un consentement ; une mesure anonyme auto-hébergée sur le NAS (Umami, PostHog auto-hébergé ou une table d'événements maison) peut en être exemptée si elle respecte les conditions de la CNIL. | M |
| #M13 | **Concevoir une seule économie de récompenses** (validé) | Points de pronostics, progression des tutos, pick'em, cartes, quêtes, premium par quêtes : autant de systèmes qui risquent de se marcher dessus. Les dessiner ensemble (une monnaie ou des points ? ce que chacun débloque) **avant** de coder #M2, #M4 et les quêtes. | S (réflexion) |

## K. Garde-fous à garder en tête

- **Quota PandaScore** : 1 000 requêtes/h partagées entre tous les jeux ; à mesurer à chaque jeu ajouté (le rythme rapide reste réservé aux matchs suivis en direct).
- **Saisonnalité** (risque n°2 du conseil) : afficher le prochain grand rendez-vous (Worlds, Masters, Six Nations, Tour de France…) pour garder les gens entre deux saisons.
- **Images et marques** : la règle Riot (pas d'images du jeu sans licence) s'applique aussi à LoL et TFT.
- **Docs du projet claude.ai** : arrêtées au J7, à resynchroniser depuis `docs/` du dépôt.

---

## Tri décidé (2026-10-04)

Ordre retenu avec Thibault (2ᵉ vague intégrée le même jour). Chaque jalon sera cadré dans sa propre discussion (`/jalon N`), comme d'habitude ; les « # » ne servent plus qu'à retrouver l'origine d'une idée.

| Ordre | Jalon | Contenu | Pourquoi à cette place |
|---|---|---|---|
| 1 | **J21 — Correctifs avant les playoffs** | #C1-#C3, #E1-#E3, #G1-#G4, #J3, #L1 + réserves du J20 (vrai match de playoffs) | Petites corrections visibles ; playoffs de Champions du 7 au 18 octobre ; #L1 doit être dans la première version donnée aux amis |
| 2 | **J22 — Refonte de la densité** | #A1-#A3, #F, #D1, #D3-#D5, #M11 | Prérequis avant tout nouveau jeu (**décidé : avant LoL**) ; notifications plus visuelles avec la passe d'interface |
| 3 | **J23 — League of Legends** | #I1 (+ phase suisse), #I7, #I8, #A4, #M1 | Deuxième jeu ; le classement global sert la phase suisse (bilans 3-0, 2-1) ; organisations remplies par script de seed en attendant l'admin |
| 4 | **J17 — Web pour les amis** (jalon existant) | #J1, #J2, #J4, #J5, #L2-#L6, #M7, #M12, #M10 | **Décidé : après LoL**. Retours et analytics pour les testeurs ; l'interface d'admin profite du build web (écrans réservés aux modérateurs) |
| 5 | **J24 — Discussion** | #B1-#B5, #M9 | Cœur social ; sondages et tableau des idées réutilisent le forum |
| 6 | **J25 — Pick'em et économie de récompenses** | #M13 (conception d'abord), #M2, #M3 | Après le partage dans les groupes (#B5) ; prêt pour la saison 2027 (Kickoff, Masters) |
| 7 | **J26 — Diffusion et co-streamers** | #H1-#H5 (#E3 fait au J21) | Acquisition via les streamers ; table des diffuseurs gérée dans l'admin (#M10) |
| 8 | **J27 — Smash Ultimate** | #I2 (adaptateur start.gg) | Format 1 contre 1, prépare les sports individuels |
| 9 | **J28 — Sport** | #I4 F1 d'abord, puis #I3 foot et #I5 basket, #M6 | Test du modèle générique ; la modulation selon l'utilisateur prend son sens avec plusieurs catégories |
| 10 | **J29 — Politique** | #I6 | Prête avant la présidentielle (1er tour le 18 avril 2027) |
| — | **Études (hors jalon)** | #M5 monétisation | À mener avant tout revenu ; peut se faire en parallèle |
| — | **Plus tard** | #D2, #E4, #G5, #M4 (cartes, après #M13 et avis juridique) | Dépendent d'une source, d'un besoin ou d'une validation |
| — | **Vision long terme** | #M8 réseau social d'événements | Ne rien coder qui l'empêche |

## Discussion : idées pour plus tard (2026-10-08)

Ajoutées après le J24. **Écartées** (voir `docs/idees-non-retenues/`) : messages vocaux, réaction « live » partagée.

| # | Idée | Détail | Effort |
|---|---|---|---|
| #B7 | **Fil automatique par match pour mon groupe** | Dès qu'un match suivi par plusieurs membres d'un groupe commence, un fil éphémère « 100T – G2 » s'ouvre dans le groupe, avec les pronostics des amis dévoilés au coup d'envoi. Relie la Discussion aux pronostics du J14 et au pick'em du J25. | M-L |
| #B8 | **Invitation de groupe par lien** | Un lien plutôt qu'un code de 8 caractères ; utile avec le web du J17. | S-M |
| #B9 | **Images dans les messages** | À **éviter pour l'instant** : même problème que les vocaux (modération, stores, stockage), la règle « texte seul » du J13 le refuse. | L |
| #B10 | **Partage d'un classement ou d'une phase suisse en carte dédiée** | Aujourd'hui le partage d'une compétition ouvre sa page (onglets Classement et Phase suisse compris). Une carte dédiée afficherait le classement lui-même. | M |
