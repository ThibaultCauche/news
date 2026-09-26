# Écran 02 — Champions, arbre radial (phase en cours)

Rôle (`docs/02`) : tableau principal en cercle, chemin de G2 en or, compte
à rebours au centre. Valeurs communes : voir [commun.md](commun.md).
Header, contrôle segmenté (onglet **Phase finale** actif) et tab bar
identiques aux écrans 01/06/07 — non répétés. Comparer avec
[07-arbre-termine.md](07-arbre-termine.md) : même `CustomPainter`, deux
états (en cours vs terminé).

## Arbre radial (`CustomPainter`)

- Codes d'équipe : même règle qu'à l'écran 07 — **11/700** plein (encore en
  vie sur le chemin de G2 : G2 or, TH blanc) vs **10/700, blanc 35-55 %**
  (élimination selon l'ancienneté — DRX/TL à 55 %, SEN/EDG à 35 %, à
  vérifier à l'œil si c'est vraiment 2 paliers voulus ou du bruit).
- Libellés d'anneau "QUARTS"/"DEMIES" : **8/600/+8 %, blanc 30 %** —
  one-off dédié aux labels de cercle du tableau, plus petit et plus espacé
  que `eyebrow` (12/600/+4 %).
- Badge de match en direct "1–0" : **10/700/0 %, `#FF4655`** — mini-badge
  de score, à côté du marqueur "SF" (demi-finale programmée, **9/700, or**,
  pointillé dans le tracé).
- Centre : compte à rebours "2 h 14" en **16/700/−1 %, or** (plus petit que
  le "02:14:36" plein écran de l'écran 03 — les deux sont des one-offs de
  compte à rebours, tailles différentes selon le contexte, pas à unifier)
  + sous-titre "G2 – PRX" en **9/600/+2 %, blanc 50 %**.
- Légende sous le diagramme "En or, le chemin de G2. En rouge, le match en
  direct." : `caption` (13/400) blanc 55 %.

## Carte "2e chance · repêchage"

358×227 rx=22. Eyebrow "2E CHANCE · REPÊCHAGE" (`eyebrow`, blanc 50 %).
Paragraphe `body` (14/400) blanc 70 %. Puis lignes d'équipe qualifiée pour
le repêchage (Team Liquid, DRX) : nom `bodyLargeStrong` (15/600), légende
"A battu EDG 2–0 · attend le perdant G2 / PRX" en `caption` (13/400) blanc
50 %, chevron 18/400 blanc 30 %.

## Tab bar

Onglet actif = **Suivis** (pastille x=195, cf. commun.md).
