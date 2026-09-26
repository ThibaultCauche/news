# Écran 06 — Champions, Groupes

Rôle (`docs/02`) : grille 2×2, trait entre qualifiés et éliminés. Valeurs
communes : voir [commun.md](commun.md).

## Header

Retour "‹ Valorant" (17/400/85 %). Bouton aide "?" rond 30×30 rx=15, fond
blanc 10 %, glyphe 15/600/80 %.
Titre "Champions" `display` (34/700). Sous-titre "Shanghai · phase de
groupes" `bodyLarge` (15/400/55 %).

## Contrôle segmenté

Même composant que l'écran 01 (piste 358×34 rx=10 blanc 8 %, pastille
active rx=8 blanc 16 %) : **Groupes** (actif) / Phase finale / Repêchage,
même styles `captionStrong` / `caption`-500-60 %.

## Bandeau de statut

Icône check verte (cercle 28×28 rx=14, fond `#30D158` 16 %, glyphe
`captionStrong` vert). Titre "Terminée · 8 qualifiés" : `bodyLargeStrong`
(15/600/−0,6 %). Description "4 groupes de 4, les 2 premiers passent.
Format en double élimination." : `caption` (13/400) blanc 50 %, avec le
segment lien **"double élimination" en blanc 85 %** (même mécanique de lien
glossaire que l'écran 03 : seule l'opacité change ici, pas le poids).

## Grille 2×2 de groupes

4 cartes 174×150 rx=**18** (pas 22 : plus petites, cf. commun.md), écart 10
(`AppSpacing.cardGap`) horizontal et vertical, bord blanc 8 %.

Par carte : eyebrow "GROUPE A/B/C/D" (`eyebrow`, blanc 50 %). Puis 4 lignes
classement :
- Rang ("1","2","3","4") : **11/500/0 %, blanc 35 %** — one-off "index de
  classement", à distinguer de `label` (12/500).
- Code équipe : **14/600** pour les 2 premiers (qualifiés — couleur or si
  équipe suivie, sinon blanc plein) vs **14/400 blanc 35 %** pour les 2
  derniers (éliminés) — **le poids ET l'opacité encodent le statut** dans
  la maquette, pas une couleur dédiée. Important pour l'étape 4 : la brique
  "ligne de classement" doit prendre un paramètre "qualifié" qui change à
  la fois `fontWeight` et l'opacité, pas juste une couleur.
- Score ("2–0"…) aligné à droite : 12/500, blanc **60 %** si qualifié,
  blanc **30 %** si éliminé — mêmes deux paliers que le poids ci-dessus.
- Trait de séparation qualifiés/éliminés : rect 148×1 blanc 12 % entre la
  2ᵉ et la 3ᵉ ligne (à mi-hauteur de la carte).

Légende de bas de page "Au-dessus du trait : qualifiés pour la phase
finale." : `caption` (13/400), blanc 45 % (palier proche de 50 %, écart
mineur).

## Tab bar

Onglet actif = **Suivis** (pastille x=195, cf. commun.md).
