# Specs communes — mesurées sur les SVG

Mesures extraites des exports SVG de `docs/maquettes/svg/` avec
[extract-specs.mjs](extract-specs.mjs) (`node docs/maquettes/specs/extract-specs.mjs <fichier.svg>`),
croisées sur les écrans 01, 03, 06, 09, 17 (grille/cartes/tab bar identiques
sur tous les écrans e-sport). Canevas Figma : 390×844 (iPhone, 1 pt = 1 px
dans le SVG).

## Texte réel (re-export sans « Outline text »)

Les SVG de `docs/maquettes/svg/` ont été ré-exportés depuis Figma avec
« Outline text » décoché : chaque libellé est un vrai `<text>`/`<tspan>`
avec `font-family`, `font-size`, `font-weight`, `letter-spacing` et
`fill`/`fill-opacity`, plus la position de ligne de base (`x`/`y` du
`<tspan>`). `extract-specs.mjs` les lit directement — **toutes les mesures
ci-dessous (géométrie et typographie) sont exactes**, aucune estimation.

## Grille et marges

| Valeur | Mesure |
|---|---|
| Canevas | 390 × 844 |
| Marge latérale (gauche/droite) | **16 px** — toutes les cartes pleine largeur mesurent exactement `358 = 390 − 2×16` |
| Écart entre cartes d'une même rangée | **10 px** (mesuré identique dans la rangée de 3 cartes stats de l'Accueil et la grille 2×2 de Groupes) |
| Espacement avant le titre d'une nouvelle section | **~24–26 px** (mesuré 3 fois sur l'Accueil : bas d'une carte → haut du titre suivant) |
| Espacement titre de section → premier contenu | **~24–27 px** (même ordre de grandeur, pas de token séparé) |
| Zone de contenu sous le header | Les boutons du header (recherche, avatar, filtres) sont tous à **y = 60** |
| Barre d'onglets | flottante, commence à **y = 762** sur tous les écrans (voir plus bas) |

`AppSpacing.md` (16) et `AppSpacing.lg` (24) couvrent déjà la marge et
l'espacement de section : corrects, gardés tels quels. `AppSpacing.cardGap`
(10) a été ajouté pour l'écart entre cartes d'une rangée.

## Cartes de section (surface + contour + reflet)

Confirme `docs/02` : surface + contour blanc ~8 % + reflet intérieur blanc
7 % en haut.

| Élément | Mesure |
|---|---|
| Remplissage | `#16171B` (exact, confirme `AppColors.surface`) |
| Contour — carte standard | blanc **8 %** (`stroke-opacity="0.08"`, rect de bordure décalée de 0,5 px = anti-aliasing du contour 1 px) |
| Contour — carte à dégradé / mise en avant | blanc **10 %** (légèrement plus visible que la carte standard — nuance non présente dans les tokens actuels) |
| Reflet intérieur | inner-shadow SVG : blanc, alpha **0,07**, décalage 1 px vers le bas, flou 0 → confirme exactement `AppColors.surfaceHighlight` (`0x12FFFFFF` = 7,06 %) |
| Rayon — carte pleine largeur (358 px) | **22** (mesuré 21 fois sur 01/03/06/09/17 : c'est LE rayon de carte dominant) |
| Rayon — carte demi-largeur (174 px, grille 2×2 de Groupes) | **18** |
| Rayon — petite carte (150 px, 3 colonnes de l'Accueil) | **20** |
| Rayon — chip/pastille (hauteur 28-30, pilule) | `rx = hauteur / 2` toujours (14, 15…) → confirme que `AppRadii.pill` (999, auto-clampé par Flutter) est la bonne approche, pas un rayon fixe |

`AppRadii.card` a été corrigé 20 → **22** (c'est la valeur dominante,
utilisée par la carte principale de chaque écran). Les variantes 18/20 pour
les grilles plus petites sont une nuance à garder en tête mais pas
forcément un token séparé (à trancher à l'étape 3 en construisant la brique
« carte de section »).

## Verre (tab bar)

Identique au pixel près sur 01, 03, 06, 09, 17 :

| Élément | Mesure |
|---|---|
| Position | x=16, y=762, largeur 358, hauteur **64** |
| Rayon | 32 (pilule, `rx = hauteur/2`) |
| Remplissage | `#1C1C21` à **72 %** d'opacité (confirme `AppColors.glass`, l'opacité n'est pas encore un token) |
| Flou d'arrière-plan | `data-figma-bg-blur-radius="24"` → confirme le flou 24 de `docs/02` |
| Contour | blanc **12 %** (plus marqué que les cartes, cohérent avec un matériau "verre") |
| Pastille de l'onglet actif | 86 × 50, rayon 25 (pilule), fond blanc **12 %**, décalée de 7 px du haut/bas de la barre (padding vertical (64−50)/2 = 7) |
| Marge basse jusqu'au bord de l'écran | 844 − (762+64) = 18 px — **mesure du mock uniquement** : en Flutter, positionner par rapport à `MediaQuery.padding.bottom` (l'encoche du bas), pas par une distance fixe au bord |

`AppColors.glassOpacity` (0.72) et `AppColors.glassBorder` (12 %) ajoutés à
`tokens.dart` ; `glass_tab_bar.dart` les utilise désormais au lieu de 0,86
en dur. Le flou 24 était déjà correct dans le widget
(`ImageFilter.blur(sigmaX: 24, sigmaY: 24)`).

## Couleurs

Toutes les couleurs de `AppColors` sont confirmées exactes par la mesure
directe des `fill` du SVG : `#08090B` (fond), `#16171B` (surface),
`#1C1C21` (verre), `#FF4655` (direct), `#FFC940` (or/suivi), `#30D158`
(victoire/qualifié). Aucune couleur en dur trouvée dans les SVG qui ne soit
pas déjà dans `tokens.dart`.

Opacités de texte mesurées sur les runs (blanc sur fond sombre) : 100 %
(titres), puis un nuage entre 50 % et 70 % pour le texte secondaire (0,5 /
0,55 / 0,6 / 0,65 / 0,7 selon les écrans — pas un tracé parfaitement
cohérent dans les maquettes elles-mêmes), et 30 % ailleurs (texte tertiaire,
non présent dans l'échantillon mesuré ici). Les 3 paliers actuels de
`AppColors` (100 / 55 / 30 %) restent une approximation raisonnable de ce
nuage — pas de changement proposé, à revalider à l'œil écran par écran.

## Échelle typographique (mesurée sur les 9 écrans, `font-family: Inter` partout)

Une même taille apparaît parfois avec un tracking légèrement différent
(ex. 15/600/−0,6 % vs 15/600/0 %) : bruit d'export Figma (arrondi du
tracking « auto »), pas une intention de design — j'ai gardé la valeur la
plus fréquente par taille/graisse.

Les combinaisons **utilisées sur un seul écran et une poignée de fois**
(codes d'équipe 2-3 lettres dans l'arbre radial, numéros de jour de
l'agenda, chrono du compte à rebours…) ne sont **pas** ajoutées au
`TextTheme` global : elles restent des `TextStyle` locaux au widget
concerné (documentés dans le fichier de l'écran), pour ne pas faire
exploser le thème avec des styles à un seul usage.

| Style proposé | Taille | Graisse | Tracking | Hauteur de ligne mesurée | Utilisation | vs `app_theme.dart` actuel |
|---|---|---|---|---|---|---|
| `display` | 34 | 700 | −2,5 % | — (une ligne) | Titre de page (nav) : "Aujourd'hui", "Valorant", "Champions" | = `headlineLarge` actuel, **inchangé** |
| `heroScore` *(nouveau)* | 26 | 700 | −2 % | — | Accroche de la carte "Maintenant" : "Fnatic 1–0 Heretics" | absent des tokens (j'avais estimé 28 à tort à l'étape précédente, c'est 26) |
| `title` | 20 | **700** | −1,5 % | — | Titres de section : "Tes suivis", "Les grands rendez-vous", "À découvrir" ; grand nom d'équipe | `titleLarge` existe en 600 → **graisse à corriger : 600 → 700** |
| `cardTitle` *(nouveau)* | 19 | 700 | −1,2 % | 23 (×1,21) | Titre des cartes "grands rendez-vous" : "Worlds de League of Legends" | absent des tokens |
| `bodyLarge` | 15 | 400 | −0,6 % | — | Sous-titre de page : "Vendredi 25 septembre", "E-sport · saison VCT 2026" | proche de `bodyMedium` (15/400) mais **sans tracking actuellement** : ajouter −0,6 % |
| `bodyLargeStrong` *(nouveau)* | 15 | 600 | −0,6 % | — | Nom d'équipe / score en avant dans une carte : "Fnatic – Heretics", "1–0" | absent des tokens |
| `body` *(nouveau, taille manquante)* | 14 | 400 | 0 % | 17 (×1,21) | Paragraphe standard dans une carte : "Demi-finale, carte 2. Le vainqueur file en finale du haut." | absent — `bodyMedium` actuel (15) est trop grand pour ce rôle |
| `bodyStrong` *(nouveau)* | 14 | 600 | 0 % | — | Ligne mise en avant, pas un titre : "Ensuite : G2 – Paper Rex", horaire associé | absent des tokens |
| `caption` | 13 | 400 | 0 % | — | Texte tertiaire, petites légendes : "Demi-finale · carte 2", "Parce que tu suis Valorant" | = `bodySmall` actuel (13/400), **inchangé** |
| `captionStrong` *(nouveau)* | 13 | 600 | 0 % | — | Texte de bouton/pill : "Suivre", "Suivi", "86 %" | absent des tokens |
| `label` *(nouveau, le plus utilisé — 31 occurrences)* | 12 | 500 | 0 % | 15 (×1,25) | Méta-info partout : compétition, round, date, lieu… | absent — c'est la taille la plus fréquente des maquettes et elle manque entièrement |
| `eyebrow` | 12 | 600 | **+4 %** | — | Petites capitales / bandeau : "SAISON 2026", "MAINTENANT", "DÉJÀ JOUÉ" | `labelSmall` actuel est 11/600/+3 % → **taille et tracking à corriger : 11→12, +3 %→+4 %** |
| `tabLabel` *(nouveau)* | 10 | 500 (inactif) / 600 (actif) | +1 % | — | Libellés de la tab bar | absent des tokens |

Ligne directrice de hauteur de ligne mesurée sur les 3 blocs multi-lignes
trouvés (14/400 → 17, 19/700 → 23, 12/500 → 15) : ratio **≈ ×1,2** de la
taille de police, constant sur les 3 mesures → à appliquer comme `height`
Flutter uniforme (1.2) plutôt que de mesurer un ratio par style.

**Correction à l'étape précédente** : mon estimation "28/700" pour le score
de la carte "Maintenant" était une approximation (mesure indirecte sur des
tracés de glyphes vectorisés) — la vraie valeur mesurée sur le `<text>` réel
est **26/700/−2 %**.

## Barre de statut (hors périmètre)

"09:41" (16/600), "5G 87 %" (14/600) en haut de chaque écran sont la barre
de statut iOS simulée par Figma — pas un composant de l'appli, le vrai OS la
dessine. Ignorée dans les fichiers par écran ci-dessous.

## État

Fait : les 9 fichiers `docs/maquettes/specs/NN-nom.md` (01, 02, 03, 05, 06,
07, 09, 14, 17) + [tab-bar.md](tab-bar.md), `tokens.dart` (`AppRadii.card`
22, `AppSpacing.cardGap`, `AppColors.glassOpacity`/`glassBorder`,
`AppTypography`) et le `TextTheme`/`AppTextStyles` de `app_theme.dart`
reconstruits sur les valeurs mesurées ci-dessus.

Pas encore fait (étapes suivantes) : les écrans (`home_screen.dart`,
`glass_tab_bar.dart`, etc.) n'ont pas été réécrits pour consommer les
nouveaux styles (`AppTextStyles`, pastille d'onglet actif manquante) — leurs
appels `Theme.of(context).textTheme.xxx` actuels profitent déjà des
corrections de taille/graisse faites dans les slots Material existants,
mais la réécriture brique par brique reste à faire à l'étape 3/4.
