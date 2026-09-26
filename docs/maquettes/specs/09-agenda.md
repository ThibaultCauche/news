# Écran 09 — Agenda unifié

Rôle (`docs/02`) : semaine, filtres par catégorie, liste par jour, export
.ics/Google Agenda. Valeurs communes : voir [commun.md](commun.md).

## Header

Pas de retour (accessible par la tab bar). Bouton "Exporter" : pilule
79×28 rx=14, fond blanc 10 %, texte `captionStrong` (13/600) blanc.
- Titre "Agenda" : `display` (34/700/−2,5 %).
- Sous-titre "Tout ce que tu suis, au même endroit" : `bodyLarge`
  (15/400/−0,6 %), blanc 55 %.

## Semaine (strip de 7 jours)

Colonnes espacées de ≈51,7 px (390 − marges, 7 colonnes). Par jour :
initiale (L, M, M, J, V, S, D) en 11/600/+2 %, blanc **45 %** — one-off,
distinct des paliers habituels (50/55/30 %) mais cohérent avec un texte
"discret" de sélecteur ; numéro du jour en **17/700/0 %**, blanc 45 %
(inactif) — one-off propre à cette frise de calendrier, pas dans l'échelle
commune (ni `title` 20 ni `cardTitle` 19, une taille intermédiaire dédiée
au chiffre du jour).
- Jour sélectionné ("V 25") : pastille pleine largeur de colonne 47,71×60
  rx=14, fond **blanc plein**, initiale et numéro en `#08090B` (texte
  sombre sur fond clair) — l'initiale garde une opacité 60 % même sur fond
  clair (nuance à reproduire), le numéro est plein.
- Petit point sous chaque jour (indicateur "a des événements", non capturé
  par l'extracteur de rects/texte — à vérifier à l'œil, probablement une
  puce 3-4 px).

## Filtres catégorie (pilules)

Rangée à y=269, hauteur 28, rx=14 (`AppRadii.chip`) : **Tout** (actif, fond
blanc 90 %, texte `captionStrong` `#08090B`), **E-sport / Sport /
Politique** (fond blanc 8 %, texte `captionStrong` blanc — même taille/
graisse que l'actif, seule la couleur de fond et du texte change).

## Listes par jour

2 cartes 358 large rx=22 bord blanc 8 %, une par jour ("Aujourd'hui ·
ven. 25" 249 haut, "Demain · sam. 26" 129 haut). En-tête de groupe : style
`eyebrow` (12/600/+4 %) blanc 50 % — même style que "SAISON 2026"/"DÉJÀ
JOUÉ" des autres écrans.

Ligne d'événement (répétée, séparateur 324×2 blanc 8 % entre chaque) :
- Heure ("08:30", "09:00"…) : `bodyLargeStrong` (15/600/0 %), colorée selon
  l'état (blanc neutre, rouge `#FF4655` si en direct, or `#FFC940` si une
  alerte est posée).
- Titre de l'événement, même ligne : `bodyLargeStrong` (15/600/−0,6 %),
  blanc plein (pas teinté même si l'heure l'est).
- Statut à droite : `captionStrong` (13/600), teinté comme l'heure
  ("Terminé" blanc 50 %, "1–0" rouge, "Alerte ✓" or).
- Méta ligne du dessous ("Politique · audition", "Valorant · demi-finale
  · carte 2"…) : `caption` (13/400), blanc 50 %.

Padding intérieur de carte ≈ 93−16 = 77 pour la colonne de texte après
l'heure (colonne heure ≈ 60 px de large, alignée à gauche).

## Tab bar

Onglet actif = **Agenda** (2ᵉ, pastille à x=109, cf. commun.md).
