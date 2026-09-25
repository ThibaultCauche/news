# Étape 2 — Maquettes mobiles

> Session du 2026-09-25. Fichier Figma : [News — Maquettes mobiles (Valorant)](https://www.figma.com/design/1GfSNwpyE1WoWEdUzT638L). Disposition du canevas, de haut en bas : V1 (référence) → V2 écrans 01–04 + specs de mouvement → écrans 05–16 (deux rangées, panneau de notes à droite) → écrans 17–22 (accueil et autres catégories) → écrans 23–26 (autres catégories, suite). Captures PNG à placer dans `docs/maquettes/`.
>
> **Décision du 2026-09-25 : la V2 est la direction retenue.** La V1 reste comme référence.

## Cadre

- Écrans iPhone 390×844, **thème sombre**, police Inter.
- **Scénario fictif mais crédible** : VCT 2026, Champions Shanghai en phase finale. Équipe suivie : **G2 Esports**. Les exemples hors e-sport (loi, lancement, sorties, élection, keynote, streamers) sont marqués « exemple fictif ».
- Tab bar V2 : **Aujourd'hui · Agenda · Suivis · Jeu**. Explorer s'ouvre avec la loupe de l'accueil, Réglages avec l'avatar.

## Palette (tokens à reprendre dans Flutter)

| Rôle | V1 | V2 (retenue) |
|---|---|---|
| Fond | `#0B0D12` | `#08090B` |
| Surface | `#151923` / `#1D2230` | `#16171B` + contour blanc 8 % + reflet intérieur blanc 7 % |
| Verre (tab bar, feuilles) | — | `#1C1C21` à 72–94 % + flou d'arrière-plan 24 |
| Texte | `#F2F4F8` / `#8A93A6` / `#565E70` | `#F5F5F7`, puis blanc à 55 % / 30 % |
| En direct, « tu es ici » | `#FF4655` | `#FF4655` |
| **Mon équipe / mes suivis** | `#FFC940` | `#FFC940` |
| Victoire / validé | `#3DDC97` | `#30D158` (défaites en gris neutre) |
| Listes électorales (dataviz uniquement) | — | `#8FB3FF` · `#FFB38F` · `#B8E0A0` · `#D6B8FF` (pastels neutres, sans lien avec un parti) |

Règle : **l'or = ce que je suis**, le **rouge = ce qui se passe maintenant**, le vert = victoire, qualification ou feu vert. Les catégories se distinguent par **leur icône**, pas par une couleur. Exceptions : les grandes cartes « événement » et les vignettes ont un dégradé sombre teinté (en attendant de vrais visuels), et les résultats électoraux utilisent 4 pastels neutres.

## Architecture de l'accueil (écran 17)

Ordre du haut vers le bas, du plus urgent au plus exploratoire :
1. **Maintenant pour toi** : la chose la plus importante en ce moment parmi tes suivis (en direct ou imminente), avec la suivante juste en dessous.
2. **Tes suivis** : une carte par suivi (toutes catégories), chacune avec son état en une ligne.
3. **Les grands rendez-vous** : les énormes événements du moment, même non suivis, avec un bouton « Suivre ».
4. **À découvrir** : des suggestions avec **leur raison**.
5. (plus bas) L'essentiel en 3 points et le jeu du jour (voir écran 08).

## Catégories et leur visualisation phare

| Catégorie | Visualisation phare | Écran |
|---|---|---|
| E-sport | Carte de saison, arbre radial, « 3 vies », grilles | 01–07, 14 |
| Sport | Tableau de score + frise du match (essais au-dessus/au-dessous) | 24 |
| Politique | Suivi de loi façon colis + barre de vote | 19 |
| Élections | Hémicycle des sièges + barres de voix + avancement du dépouillement | 25 |
| Streams | Bulles « en direct » + liste avec vignettes | 23 |
| Espace | Compte à rebours + chances de partir à l'heure + déroulé T–/T+ | 20 |
| Sorties | Liste par jour avec affiches + « ma liste » | 21 |
| Tech | Fil des annonces en direct + « l'essentiel jusqu'ici » | 26 |
| Culture, Science | À dessiner (cérémonie, annonces Nobel) | — |

## Inventaire des écrans V2 (26)

| # | Écran | Rôle |
|---|---|---|
| 01 | Page Valorant — saison | Frise horizontale « ici », carte « Maintenant », étapes jouées repliées |
| 02 | Champions — arbre radial | Tableau principal en cercle, chemin de G2 en or, compte à rebours au centre |
| 03 | Prochain match G2 – PRX | Compte à rebours, alerte, « pourquoi ce match compte », forme récente |
| 04 | Feuille glossaire « BO3 » | Explication avec exemple en 3 cartes |
| 05 | Champions — Repêchage | Tours du repêchage, « perdant de… » qui se remplit, grande finale |
| 06 | Champions — Groupes | Grille 2×2, trait entre qualifiés et éliminés |
| 07 | Arbre terminé | Vainqueur au centre, grande finale, parcours de G2 en 4 lignes |
| 08 | Aujourd'hui (1re version) | Bulles « en direct », à suivre, l'essentiel en 3 points, jeu du jour |
| 09 | Agenda unifié | Semaine, filtres par catégorie, liste par jour, export .ics / Google Agenda |
| 10 | Fiche équipe G2 | 3 chiffres clés, dernier match carte par carte, notifications par équipe |
| 11 | Onboarding — sujets | Tuiles de catégories + choix du jeu |
| 12 | Onboarding — 3 équipes | Chaque équipe suggérée avec sa raison |
| 13 | Écran verrouillé | Live Activity (compte à rebours → score) + notification contextualisée |
| 14 | Kickoff EMEA « 3 vies » | Triple élimination expliquée : 3 vies, 3 tableaux, 3 tickets |
| 15 | Match terminé sans spoil | Score masqué, appui long pour révéler, replay |
| 16 | Jeu du jour | Série, « devine le score », quiz politique neutre avec source |
| 17 | **Accueil refondu** | Maintenant pour toi, tes suivis, grands rendez-vous, à découvrir |
| 18 | Explorer | Recherche, tendances, 10 catégories |
| 19 | Suivi d'une loi (fictif) | En une phrase, étapes façon colis, résultat du vote, sources |
| 20 | Lancement spatial (fictif) | Compte à rebours, chances de partir à l'heure, déroulé T–/T+ |
| 21 | Sorties (titres fictifs) | Par jour, affiches, « + ma liste », le plus attendu de ta liste |
| 22 | Réglages | Sans spoil par suivi, résumé du matin, heures calmes, sources et crédits, charte de neutralité |
| 23 | Streams (noms fictifs) | Bulles en direct, liste avec vignettes et spectateurs, « Bientôt » avec rappel |
| 24 | Rugby en direct (fictif) | Score, frise des 80 minutes avec essais et pénalités, temps forts, « ce que ça change » |
| 25 | Soirée électorale (fictive) | Dépouillement et participation, hémicycle des sièges, voix par liste, source officielle |
| 26 | Keynote tech en direct (fictive) | Progression, l'essentiel jusqu'ici, fil des annonces horodaté |

**Réponses de design aux formats difficiles**
- Double élimination (Stages, Champions) : arbre radial pour le tableau principal et repêchage en liste par tours (écrans 02, 05, 07).
- Triple élimination (Kickoff) : métaphore des **« 3 vies »** au lieu d'un arbre (écran 14).
- Groupes : mini-grilles avec un trait de qualification (écran 06).
- Parcours d'une loi : suivi façon colis (écran 19).
- Événement long en direct (keynote, soirée électorale) : **« l'essentiel jusqu'ici »** en haut, le fil détaillé en dessous.

## V2 — passe « apple-design » + « emil-design-eng » (skills d'Emil Kowalski)

Source : [github.com/emilkowalski/skills](https://github.com/emilkowalski/skills).

- **Matériaux** : tab bar en capsule de verre flottante, feuilles translucides sur un voile.
- **Bordures** : contours blancs semi-transparents (8 %) et reflet intérieur en haut au lieu de traits pleins.
- **Typo** : tracking selon la taille (−2,5 % pour les grands titres, +2 à 4 % pour les petites capitales). Grands titres de navigation à la iOS.
- **Libellés précis** et retour qui indique d'où l'on vient.
- **Divulgation progressive** : l'essentiel d'abord, le reste replié.
- **Glossaire dans le texte** : mots soulignés qui ouvrent une feuille explicative.

**Principes de mouvement** (détail dans les cartes sous 01–04 et dans le panneau de notes 05–16)
- On n'anime pas ce qu'on voit plusieurs fois par jour. Les animations « signature » ne jouent qu'une fois.
- Entrées en ease-out `cubic-bezier(0.23,1,0.32,1)`, moins de 300 ms, uniquement `transform` et `opacity`, jamais depuis `scale(0)`. Retour visuel dès l'appui (scale 0,97).
- Popovers ancrés sur l'élément touché. Feuilles avec un ressort sans rebond, interruptibles, qui suivent le doigt 1:1.
- Mouvement réduit : fondus à la place des glissements.
- Flutter : `Curves` personnalisées, `SpringSimulation`, `MediaQuery.disableAnimations`.

## Points ouverts

- Logo et icône d'app définitifs (le « N » doré est provisoire), iconographie finale, vrais visuels pour les grandes cartes.
- Pages non dessinées : Culture (cérémonie en direct), Science (annonces Nobel), page catégorie générique (ex. « Sport » avec ses compétitions), version web.
- Nouveaux formats issus de `01b` : phase suisse, classement de lobby, classement de championnat, F1.
- Données : chaque nouvelle catégorie demande sa source. À étudier comme l'étape 1.
- Figma plan Starter : ~20 appels MCP par mois. **Environ 18 utilisés au 2026-09-25** : ne pas utiliser le MCP Figma depuis Claude Code sans demande explicite, passer par les captures de `docs/maquettes/`.
