# Écran 07 — Arbre terminé

Rôle (`docs/02`) : vainqueur au centre, grande finale, parcours de G2 en 4
lignes. Valeurs communes : voir [commun.md](commun.md). Header et tab bar
identiques aux écrans 01/05/06 — non répétés.

## Arbre radial (`CustomPainter`)

Diagramme circulaire (centre ≈ x=195, rayon ≈148, zone 296×296) : lignes et
cercles dessinés au canvas, **pas des rects/text HTML** — mesures utiles
uniquement pour les libellés :
- 8 codes d'équipe autour du cercle, avatars implicites (pas de fond
  visible ici, juste le texte) : **11/700/0 %** pour les 2 finalistes
  encore "en vie" dans le chemin gagnant (G2 or, TH blanc plein) et
  **10/700/0 %, blanc 40 %** pour les équipes déjà éliminées de ce côté du
  tableau (DRX, TL, SEN, PRX, FNC, EDG) — encore une fois le **poids/taille
  encode le statut** (comme l'écran 06), pas une couleur séparée.
- Centre : cercle avec trophée, "G2" en **20/700/−1 %** or (même style que
  le code d'équipe en vedette de l'écran 03 — confirmé comme un vrai style
  réutilisé, pas un one-off isolé) + "CHAMPION" en **8/700/+10 %, or 80 %**
  — plus petit et plus espacé que `eyebrow` (12/600/+4 %), style dédié au
  badge de couronnement, à ne pas fusionner.

## Carte "Grande finale"

358×163 rx=22. Eyebrow "GRANDE FINALE · BO5" (`eyebrow`, blanc 50 %).
2 lignes équipe (avatar 24,5×24,5 rx≈12,25 pour le vainqueur avec anneau or,
26×26 rx=13 fond blanc 7 % pour le perdant ; code d'avatar en 9/700, même
famille que l'écran 05) :
- Nom : `bodyLargeStrong` (15/600) or si vainqueur suivi, ou **15/400/−0,6 %
  blanc plein** pour le perdant (ici pas grisé : le perdant de la grande
  finale reste bien visible, contrairement aux perdants de tour du
  repêchage).
- Score : 15/700 blanc plein (vainqueur) / blanc 40 % (perdant).
- Légende explicative sous les 2 lignes : `caption` (13/400) blanc 50 %.

## Carte "Le parcours de G2"

358×208 rx=22. Eyebrow "LE PARCOURS DE G2" (`eyebrow`). 4 lignes (Quart,
Demi, …), séparateur 324×2 blanc 8 % entre chaque :
- Étiquette de round ("Quart", "Demi") : **14/500/0 %, blanc 55 %** — même
  famille "medium 500" que "Gérer"/"Tout voir"/"Ajouter à l'agenda", ici en
  usage de libellé statique (pas un lien).
- Résultat ("2–1 contre Team Liquid") aligné à droite : `bodyStrong`
  (14/600) blanc plein.

## Tab bar

Onglet actif = **Suivis** (pastille x=195, cf. commun.md).
