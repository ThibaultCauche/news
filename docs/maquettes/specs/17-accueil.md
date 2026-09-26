# Écran 17 — Accueil refondu

Rôle (`docs/02`) : Maintenant pour toi, tes suivis, grands rendez-vous, à
découvrir. Valeurs communes : voir [commun.md](commun.md).

## Header

Pas de retour (écran racine). Avatar rond 36×36 rx=18 à x=338 (fond blanc
90 %, initiale "T" en 15/700 `#08090B` — texte sombre sur avatar clair) ;
bouton recherche 36×36 rx=18 à x=294 (fond blanc 10 %, icône loupe).
- Sous-titre date "Vendredi 25 septembre" : `bodyLarge` (15/400/−0,6 %),
  blanc 55 %.
- Titre "Aujourd'hui" : `display` (34/700/−2,5 %).

## Carte "Maintenant pour toi" (héros, dégradé)

358×169, rx=**24** (un cran au-dessus du rayon de carte standard 22 — carte
héros la plus grande de l'écran), fond dégradé `#3B1219 → #16171B`, bord
blanc **10 %** (`AppColors.surfaceBorderHighlight`, pas 8 %).
- Badge "EN DIRECT" : pilule 87×18 rx=9, fond `#FF4655` à 20 %, texte
  **10/700/+6 %** rouge plein — variante du badge mini-eyebrow (comparer à
  "CHAMPIONS · ICI" 9/700/+6 % de l'écran 01 : même famille, taille liée à
  la hauteur du badge, pas un troisième style à ajouter à l'échelle).
- Suivi du badge sur la même ligne : "Valorant · Champions" en `label`
  (12/500), blanc 60 %.
- Score en avant "Fnatic 1–0 Heretics" : **`heroScore`** (26/700/−2 %).
- Paragraphe "Demi-finale, carte 2. Le vainqueur file en finale du haut."
  (2 lignes) : `body` (14/400), blanc 70 %, interligne mesuré 17 (×1,21,
  cohérent avec `AppTypography.lineHeight` = 1,2).
- Séparateur 320×2 blanc 8 % à y=264.
- Ligne "Ensuite : G2 – Paper Rex" + heure "11:55" : `bodyStrong`
  (14/600), couleur or plein (`AppColors.gold`) — pas `body` (le poids 600
  la distingue du paragraphe au-dessus).

## Section "Tes suivis"

Titre `title` (20/700/−1,5 %) + lien "Gérer" à droite : 14/500/0 %, blanc
50 % — **one-off**, même famille que "Tout voir" (écran 01) : taille body
(14) en graisse 500, ni `body` (400) ni `bodyStrong` (600). Sous ce
libellé, garder ce troisième poids "medium" comme convention pour les
liens d'action secondaires plutôt que d'ajouter un token dédié.

3 cartes stats en rangée (150 large, écart 10 = `AppSpacing.cardGap`) :
- 16,378 → 150×97 ; 176,378 → 150×**112** (carte du milieu plus haute,
  contenu sur 2 lignes) ; 336,378 → 150×97. Rayon **20** (pas 22 : plus
  petites que les cartes pleine largeur, cf. commun.md).
- Titre carte "Valorant" / "Top 14" / "Assemblée" : `bodyLargeStrong`
  (15/600/−0,6 %). État "En direct" en `label` (12/500) rouge, ou méta
  "Toulouse – Toulon, 21:05" / "Vote solennel mardi" en `label` blanc 50 %
  (2 lignes pour la carte du milieu, interligne mesuré 15, ×1,25).

## Section "Les grands rendez-vous"

Titre `title` + "Tout voir" (même style que "Gérer"). 2 cartes 270 large
(écart 10) à dégradé, rayon 22, bord blanc **10 %** (highlight, comme la
carte héros) :
- "Worlds de League of Legends" (270×158, dégradé bleu `#1C2B4D→#121622`) :
  titre **`cardTitle`** (19/700/−1,2 %, 2 lignes, interligne mesuré 23,
  ×1,21), légende "Dans 12 jours · 1 mois de compétition" en `label` blanc
  65 %, bouton "Suivre" (pilule 68×30 rx=15 fond blanc 90 %, texte
  `captionStrong` 13/600 `#08090B`).
- "Prix Nobel 2026" (270×135, dégradé or `#3D3316→#15140F`) : même
  structure, titre `cardTitle` sur une ligne.

## Section "À découvrir"

Titre `title`. Carte 358×196 rx=22 : icône 40×40 rx=12 (squircle, blanc
7 %), titre `bodyLargeStrong` (15/600), raison "Parce que tu suis Valorant"
en `caption` (13/400) blanc 50 %, bouton rond "+" 30×30 rx=15 (blanc 10 %).

## Tab bar

Onglet actif = **Aujourd'hui** (1ᵉʳ, pastille à x=23, cf. commun.md).
