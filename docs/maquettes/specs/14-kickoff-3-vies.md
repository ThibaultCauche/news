# Écran 14 — Kickoff EMEA, "3 vies"

Rôle (`docs/02`) : triple élimination expliquée (3 vies, 3 tableaux, 3
tickets). Valeurs communes : voir [commun.md](commun.md). Header et tab bar
identiques aux autres écrans Valorant.

## Carte "Chaque équipe a 3 vies"

358×114 rx=22. Titre **17/600/−0,6 %** — one-off "sous-titre explicatif",
distinct de `title` (20/700) et `bodyLargeStrong` (15/600) : un palier
intermédiaire à garder tel quel plutôt que d'être absorbé par un des deux.
3 puces de vie (●●●) à droite du titre — petits cercles pleins/vides
(non capturés précisément par l'extracteur, à mesurer à l'œil : probablement
6-8 px de diamètre). Paragraphe `body` (14/400) blanc 70 %.

## Tickets pour les Masters

Eyebrow "TICKETS POUR LES MASTERS" (`eyebrow`, blanc 50 %). 3 cartes
114×66 rx=**16** (ni 18/20/22 : rayon dédié aux cartes "ticket", plus
petites), écart 8 (`AppSpacing.sm`, pas `cardGap` ici — à vérifier : 138−
(16+114)=8) :
- Ticket gagné : fond `#30D158` 12 %, bord vert 40 %, code d'équipe
  **17/700/0 %** vert plein.
- Ticket vacant : fond `#16171B`, bord blanc 12 %, "?" **17/700, blanc
  30 %**.
- Légende sous chaque ticket ("1er ticket"…) : **11/500/+1 %, blanc 50 %**
  — même famille que `tabLabel` (10/500/+1 %) mais 1 px plus grand ; à
  garder comme variante plutôt que de forcer 10 px ici.

## Cartes de tableau ("Tableau principal" / "2e chance" / "Dernière chance")

358 large, hauteurs variables selon le nombre d'équipes (114/138/183),
rx=22. En-tête : `eyebrow` (blanc 50 %) + compteur de vies ("3 vies"/"2
vies"/"1 vie") aligné à droite en **12/500/0 %, blanc 40 %** — même style
que "5 derniers" (écran 03).

Lignes d'équipe (séparateur 328×2 blanc 8 % entre chaque) :
- Avatar 26×26 rx=13 fond blanc 7 %, code **8-9/700** (même famille que les
  écrans 02/05/07).
- Nom d'équipe : **15/500/−0,6 %** — troisième variante de taille 15 après
  `bodyLargeStrong` (600) et le corps normal (400) : ici un poids
  "medium" pour une liste neutre, sans mise en avant particulière.
- Tag "Qualifié" (si applicable) : **12/600/0 %, `#30D158`** — proche de
  `captionStrong` (13/600) mais 12 px, one-off coloré.
- Puces de vies restantes (●●●) à droite, mêmes petits cercles qu'en haut
  de l'écran, à mesurer à l'œil.

## Tab bar

Onglet actif = **Suivis** (pastille x=195, cf. commun.md).
