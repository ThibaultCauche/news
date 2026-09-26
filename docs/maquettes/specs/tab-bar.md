# Tab bar en verre flottante

Composant identique au pixel près sur les 9 écrans mesurés (01, 02, 03, 05,
06, 07, 09, 14, 17) — voir la section « Verre (tab bar) » de
[commun.md](commun.md) pour le détail des mesures. Widget actuel :
[glass_tab_bar.dart](../../../apps/mobile/lib/widgets/glass_tab_bar.dart).

## Géométrie

| Élément | Mesure |
|---|---|
| Position | x=16, y=762 (390−358 marge, 844−64−18 du bas) |
| Taille | 358 × 64 |
| Rayon | 32 (pilule, `rx = hauteur/2`) → `AppRadii.pill` |
| Padding vertical interne | 7 px (pastille active 50 haut sur 64 de barre) |
| Marge basse jusqu'au bord de l'écran (mock) | 18 px — **à ne pas coder en dur** : positionner via `SafeArea`/`MediaQuery.padding.bottom`, pas une distance fixe (l'inset home indicator standard est 34, la maquette flotte volontairement un peu plus bas) |

## Matériau

| Élément | Mesure | Token |
|---|---|---|
| Fond | `#1C1C21` à 72 % | `AppColors.glass` + `AppColors.glassOpacity` |
| Flou d'arrière-plan | 24 | déjà correct dans `glass_tab_bar.dart` (`ImageFilter.blur(sigmaX: 24, sigmaY: 24)`) |
| Contour | blanc 12 % | `AppColors.glassBorder` (plus marqué que le contour de carte 8 %) |

## Onglet actif

Pastille derrière l'icône + le libellé de l'onglet actif : 86×50, rayon 25
(pilule), fond blanc 12 %, décalée de 7 px du haut de la barre. Position
mesurée selon l'onglet actif (4 onglets, largeur de piste 358) :

| Onglet | x mesuré |
|---|---|
| Aujourd'hui (1ᵉʳ) | 23 |
| Agenda (2ᵉ) | 109 |
| Suivis (3ᵉ) | 195 |
| Jeu (4ᵉ) | non mesuré dans l'échantillon (aucun écran capturé avec Jeu actif), symétrique attendu ≈ 281 |

**Écart avec le code actuel** : `glass_tab_bar.dart` ne dessine aucune
pastille pour l'onglet actif — seule la couleur de l'icône/texte change
(`AppColors.textPrimary` vs `textTertiary`). C'est le principal écart
visuel de ce composant à corriger à l'étape 3 (brique commune "tab bar en
verre"), pas seulement une histoire de tokens.

## Texte

`tabLabel` (10/500/+1 %, blanc 55 %) pour les onglets inactifs,
`tabLabelActive` (10/600/+1 %, blanc plein) pour l'onglet actif — voir
`app_theme.dart` (`AppTextStyles`).
