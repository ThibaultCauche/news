# Écran 01 — Valorant, saison

Rôle (`docs/02`) : frise horizontale « ici », carte « Maintenant », étapes
jouées repliées. Valeurs communes (marge 16, rayon de carte 22, tab bar,
couleurs) : voir [commun.md](commun.md), non répétées ici.

## Header

| Élément | Mesure | Style texte |
|---|---|---|
| Retour | "‹ Suivis", x=16, y=80 (baseline) | 17/400/0 %, blanc 85 % — **one-off**, pas dans l'échelle commune |
| Bouton suivi (pilule) | x=301,y=60, 73×28, rx=14, fond `#FFC940` à 14 % | "✓ Suivi" 313,79 → `captionStrong` (13/600), couleur or plein |
| Titre de page | "Valorant", x=16, y=140,86 | `display` (34/700/−2,5 %) |
| Sous-titre | "E-sport · saison VCT 2026", x=16,y=165,46 | `bodyLarge` (15/400/−0,6 %), blanc 55 % |

## Contrôle segmenté

Piste : x=16,y=189, 358×34, rx=10, fond blanc 8 %. Pastille active : x=18,
y=191, 88,5×30, rx=8, fond blanc 16 %. 4 segments égaux (largeur piste/4 ≈
89,5) : **Saison** (actif, `captionStrong` 13/600 blanc), **Tournoi /
Équipes / Agenda** (13/500/0 %, blanc 60 % — variante `caption` en 500 au
lieu de 400, one-off à garder identique).

## Carte "Saison 2026" (frise)

Carte 358×155, rx=22 (`AppRadii.card`), bord blanc 8 %.
- Badge "SAISON 2026" (eyebrow, 12/600/+4 %, blanc 50 %) + "86 %" à droite
  (`captionStrong` 13/600, blanc 50 %).
- Badge rouge "CHAMPIONS · ICI" : rect 95×15 rx=6 fond `#FF4655` plein,
  texte 9/700/+6 % blanc — **one-off plus petit que `eyebrow`** (mini-badge
  de frise, à garder tel quel, pas à fusionner avec `eyebrow`).
- Points de la frise : puces 8×8 (jouées, blanc 85 %) et 12,88×12,88
  (étapes majeures, même opacité) sur une ligne à y≈314-318 ; puce "ici"
  cerclée rouge 24×24 (`#FF4655` 22 %) avec centre `#16171B` 9×9.
- Labels d'étape (Kickoff, Masters, Stage 1…) : 10/500/0 %, blanc 50 %,
  sauf "Pause" (à venir) en blanc 30 %.
- Phrase de bas de carte "Dernière ligne droite…" : `body` (14/400), blanc
  70 %.

## Carte "Maintenant" (événement en avant)

Carte 358×213, rx=22, bord blanc 8 %.
- Eyebrow rouge "MAINTENANT" (12/600/+4 %, `#FF4655`).
- Titre "Champions Shanghai" : **22/700/−1,5 %** — one-off, un cran
  au-dessus de `title` (20) pour un titre de carte évènement plein-écran ;
  à garder distinct de `title` (section) et de `cardTitle` (19, carte
  "grand rendez-vous" de l'Accueil).
- Sous-titre "Phase finale · titre le 18 octobre" : `body` (14/400), blanc
  55 %.
- Séparateur plein largeur (moins la marge intérieure) : rect 324×2, blanc
  8 %, à x=33 (marge intérieure de carte = 33−16 = **17**, cohérent avec un
  padding carte ≈ 16-17).
- 2 lignes de match (Fnatic–Heretics, G2–Paper Rex) : point de statut 8×8
  (rouge pour en direct), nom d'équipe `bodyLargeStrong` (15/600/−0,6 %),
  score/heure aligné à droite en `bodyLargeStrong` coloré (rouge si score,
  or si heure), légende dessous en `caption` (13/400) blanc 50 %, chevron
  "›" 18/400 blanc 30 % à droite.
- Logo d'équipe : cercle 32×32 rx=16, teinté couleur d'équipe à 16 %
  d'opacité (rouge pour Heretics, or pour G2) + initiales en `bodyLargeStrong`.

## Carte "Déjà joué"

Carte 358×187, rx=22. Eyebrow "DÉJÀ JOUÉ" (12/600/+4 %, 50 %). 2 lignes
(Masters Londres, Masters Santiago) : nom en `bodyLargeStrong` blanc plein
(pas de point de statut, tournoi terminé), légende "Vainqueur : …" en
`caption` blanc 50 %, séparateur 324×2 blanc 8 %, chevron 18/400 blanc 30 %.

## Pied de carte / lien liste complète

"Tout voir" : 15/500/−0,6 %, blanc 85 % — **one-off**, entre `bodyLarge`
(400) et `bodyLargeStrong` (600) ; légende "5 étapes terminées" en
`caption` blanc 50 %.

## Tab bar

Onglet actif = **Suivis** (3ᵉ, pastille à x=195, cohérent avec
[commun.md](commun.md)). Libellés `tabLabel`/`tabLabelActive`.
