# Écran 03 — Prochain match G2 – PRX

Rôle (`docs/02`) : compte à rebours, alerte, « pourquoi ce match compte »,
forme récente. Valeurs communes : voir [commun.md](commun.md).

## Header

Retour "‹ Champions" (17/400, blanc 85 %, comme l'écran 01). Bouton "œil"
(spoil toggle) : pilule 34×30 rx=15, fond blanc 10 %.
Bandeau "DEMI-FINALE · BO3" centré : `eyebrow` (12/600/+4 %), blanc 50 %.

## Face-à-face

Logos ronds 70-72×70-72 rx=35/36 : celui de l'équipe suivie (G2) a un
anneau plein `#FFC940` (fond `#FFC940` 16 %) ; l'adversaire a un simple
fond blanc 7 % + bord blanc 16 % (pas de couleur — neutre). Codes d'équipe
("G2"/"PRX") au-dessus des logos ou en watermark : **20/700/−1 %**
— one-off "code d'équipe court", à comparer avec les tailles de code
d'équipe des écrans d'arbre (02/05/07, souvent plus petites, 8-11 px) : ici
c'est un contexte de vedette (2 seules équipes, gros logos), taille plus
grande justifiée.
"vs" central : 15/500/0 %, blanc 30 %.
- Nom complet ("G2 Esports"/"Paper Rex") : `bodyLargeStrong`
  (15/600/−0,6 %).
- Sous-texte ("Ton équipe" or / "Pacific" blanc 50 %) : `label` (12/500).

## Compte à rebours

"02:14:36" : **48/700/−3 %** — one-off massif, écran dédié uniquement à
ce compte à rebours (pas dans l'échelle commune, à traiter comme un style
local au widget compte-à-rebours). Légende "Aujourd'hui, 11 h 55 · heure de
Paris" : `body` (14/400), blanc 55 %.

## Boutons d'action

- "M'alerter au début du match" : bouton plein-largeur 358×49 rx=16, fond
  blanc plein, texte **16/600/−0,4 %** `#08090B` — one-off "libellé de
  bouton primaire" (entre `title` 20 et `bodyLarge` 15, distinct des deux).
- "Ajouter à l'agenda" : lien texte, 15/500/0 %, blanc **75 %** — encore
  une variante "500" comme "Gérer"/"Tout voir", mais ici sans tracking et à
  75 % (pas 85 %) : les liens secondaires de l'appli n'ont donc pas une
  opacité strictement unique, à harmoniser à l'étape 3 plutôt que de
  multiplier les cas.

## Carte "Pourquoi ce match compte"

358×168 rx=22, bord blanc 8 %. Eyebrow "POURQUOI CE MATCH COMPTE"
(`eyebrow`, blanc 50 %). Paragraphe en `bodyLarge` (15/400/−0,3 % — tracking
légèrement différent de `bodyLarge` standard −0,6 %, bruit d'export),
blanc 85 %, avec des **mots-liens en 600** (même taille 15, poids 600, même
couleur blanche — c'est le soulignement, pas la couleur, qui signale le
lien vers le glossaire : "tableau principal", "repêchage", "BO3"). Légende
"Touche un mot souligné pour l'explication." en 12/400, blanc 40 % — plus
petite que `label` (12/500) et opacité inédite, one-off d'aide contextuelle.

## Carte "Forme récente"

358×159 rx=22. Eyebrow "FORME RÉCENTE" + "5 derniers" à droite (`label`,
blanc 40 %). Par équipe : code (14/700/0 %, coloré si suivie sinon blanc —
distinct du "20/700" du header, plus petit) + 5 pastilles résultat 30×26
rx=7 (victoire `#30D158` 16 %, défaite blanc 6 %), lettre V/D en 12/700
(vert si victoire, blanc 45 % si défaite).

## Carte "Face-à-face" (bas d'écran, sous la tab bar dans le flux scrollable)

"Face-à-face" en `body` (14/400) blanc 55 %, score global "G2 3 – 2 PRX" en
`bodyStrong` (14/600) blanc — visible en bas de la capture, coupé par la
tab bar flottante (contenu scrollable derrière elle).

## Tab bar

Onglet actif = **Suivis** (pastille x=195, cf. commun.md).
