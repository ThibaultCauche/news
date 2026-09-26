# Écran 05 — Champions, Repêchage

Rôle (`docs/02`) : tours du repêchage, « perdant de… » qui se remplit,
grande finale. Valeurs communes : voir [commun.md](commun.md). Header,
contrôle segmenté (onglet **Repêchage** actif) et tab bar identiques aux
écrans 01/06 — non répétés ici.

## Carte "Comment ça marche"

358×106 rx=22. Eyebrow "COMMENT ÇA MARCHE" (`eyebrow`, blanc 50 %).
Paragraphe 3 lignes en `body` (14/400), blanc 70 %.

## Cartes "Tour N"

358×175 rx=22, une par tour. En-tête hors-carte : "TOUR 1" (`eyebrow`,
blanc 50 %) + statut "· terminé" / "· demain, 9 h 00" en **12/500/0 %,
blanc 35 %** — one-off, variante `label` en plus discret (35 % au lieu de
50/60/65 %).

Par match (2 lignes équipe séparées par un trait 328×1 blanc 8 % entre les
2 matchs de la carte) :
- Avatar rond 26×26 rx=13, fond blanc 7 %, code d'équipe centré en
  **8-9/700/0 %** blanc (9 px pour 2 caractères type "TL"/"DRX", 8 px pour
  3-4 caractères type "EDG"/"SEN" — la taille s'adapte à la largeur du
  code, garder un seul style "code d'avatar" avec `FittedBox`/auto-taille
  plutôt que deux tokens fixes).
- Nom d'équipe : `bodyLargeStrong` (15/600) blanc plein si l'équipe est
  connue et encore en course sur cette ligne ; **15/400/−0,6 % blanc 35 %**
  si éliminée (barré dans la maquette — à reproduire avec
  `TextDecoration.lineThrough`) ou **blanc 45 %** si "Perdant de G2 – PRX"
  (place pas encore déterminée, texte 400 non barré).
- Score aligné à droite : **15/700/0 %** blanc plein (gagnant) ou blanc
  40 % (perdant) — absent quand le match n'a pas encore de score.
- Case "?" à la place de l'avatar quand l'équipe n'est pas encore connue
  (même style 9/700 que les codes d'équipe).

## Carte "Finale du repêchage"

358×62 rx=22, visible en bas de la capture (coupée par le scroll). Même
gabarit d'en-tête que les tours : `eyebrow` "FINALE DU REPÊCHAGE" + "· 16
oct." en 12/500/35 %.
