# 07 — Économie de récompenses (J25, #M13)

> Statut : **proposé le 2026-10-09, à valider par l'utilisateur.** Le pick'em du J25 est déjà codé selon ce document ; une décision différente se corrige sans toucher aux données (les points sont réglés match par match).

## 1. Principe

**Une seule monnaie visible : les points.** Ils mesurent l'exactitude des pronostics, rien d'autre. On ne les dépense pas : ce n'est pas un solde, donc rien à acheter ni à échanger, et aucune valeur monétaire.

Tout le reste (tutos, quêtes, cartes, cosmétiques, badges) s'obtient par l'**activité** et ne touche jamais aux points. Ainsi un classement de groupe reste juste : on ne peut ni gagner ni acheter de l'avance autrement qu'en ayant eu raison.

## 2. Ce qui rapporte des points

| Source | Barème | Réglé quand | Stockage |
|---|---|---|---|
| Pronostic d'un match (J11) | 3 pour le bon vainqueur, +2 pour le score de série exact | fin du match | `prediction.points` |
| Pick'em de tableau (J25) | par match du tableau : **1** (tours ordinaires), **2** (finale du haut, finale du repêchage), **4** (grande finale) si le vainqueur choisi est le bon | fin de chaque match | `bracket_pick.points` |
| Bonus « tableau parfait » (J25) | **+5**, si tous les matchs du tableau sont choisis et justes | fin du dernier match | `bracket_pick_bonus` (`kind` = `perfect`) |
| Bonus « champion » (J25) | **+3**, si le choix sur la grande finale était le bon (même sans tableau parfait) | fin de la finale | `bracket_pick_bonus` (`kind` = `champion`) |
| Pronostic de phase suisse (J23, points au J25) | **1 par équipe qualifiée bien devinée**, sur les équipes choisies | quand chaque équipe est qualifiée ou éliminée | `stage_pick.points` |
| Pronostic d'un match du tournoi après le début (J25) | comme un pronostic de match (3 + 2) : le tableau fermé, on pronostique les prochains matchs un par un | fin du match | `prediction.points` |

Règles communes :
- Un point n'est écrit **qu'une fois** (`settledAt`, clé unique), jamais recalculé. Un tournoi annulé ou un match sans vainqueur ne rapporte rien et ne retire rien.
- **Verrouillage décidé par le serveur**, jamais par l'appli : un match pour le pronostic, le **premier match du tableau** (ou de la phase suisse) pour le pick'em. Un tableau déjà commencé n'est plus ouvert au pick'em (les matchs à venir restent pronostiquables un par un).
- **Les choix des autres sont invisibles avant le verrouillage**, même en appelant l'API directement. Un tableau partagé dans une discussion montre le nombre de choix, jamais le champion ni les points avant le début.
- Le choix du pick'em est le vainqueur de chaque match : si je pronostique la finale, je marque ses points même si mon chemin vers elle était faux.

## 3. Où les points se lisent

- **Profil et classement d'un groupe** : somme des pronostics de match, du pick'em (matchs et bonus) et de la phase suisse ; filtrable par jeu (la compétition porte le jeu).
- **« Je suis en vie »** (tableau commencé) : « N points + encore jusqu'à M possibles ». M compte les matchs à venir dont le choix peut encore se réaliser, plus les bonus encore possibles. Masqué en sans spoil.
- **Pick'em de groupe (#M3)** : à chaque match, le choix du groupe est le **vote majoritaire** de ses membres (à égalité, le choix du membre le plus ancien du groupe). Le groupe marque le poids du match quand son choix est juste. Ces points de groupe **ne s'ajoutent pas** aux points personnels : ils servent seulement à classer **mes groupes entre eux** sur une compétition. Pas de défi direct entre deux groupes (écarté).
- **Onglet Jeux** : « Mes pick'em » (en cours, verrouillés, terminés avec leurs points).

## 4. Ce qui reste séparé des points

| Système | Se gagne par | Débloque | Lien avec les points |
|---|---|---|---|
| Badges (J25) | activité : premier tableau, trois tableaux, champion trouvé, tableau parfait, phase suisse parfaite | cosmétiques, affichés au profil | aucun ; **déduits** des données (pas de table), jamais achetés |
| Tutos (J12) | lire, réussir un quiz | progression | aucun |
| Quêtes (plus tard) | activité (suivre, pronostiquer, apprendre) | cosmétiques, boosters | une quête peut demander « marquer N points », mais ne les consomme pas |
| Cartes (#M4, plus tard) | boosters gagnés par quêtes | collection | aucun ; **jamais payant ni échangeable** contre de l'argent, avis juridique avant de coder |
| Premium (#M5) | quêtes ou soutien | **cosmétiques seulement** (thèmes, cadres d'avatar) | aucun avantage dans les pronostics ni les classements |

## 5. Rappel

Un rappel part **2 h avant le premier match** d'un tournoi à tableau, aux personnes qui suivent la compétition ou une de ses équipes et n'ont pas rempli tout leur tableau (même réglage que le rappel de pronostic, heures calmes respectées, une seule fois par personne et par tournoi). Un tap ouvre le pick'em.

## 6. Questions ouvertes (non bloquantes)

1. **Poules GSL** : hors pick'em de tableau (leurs matchs « décisifs » ont des liens de perdant qui ne forment pas un arbre simple). Elles se jouent par le pronostic de match.
2. **Triple élimination** : prise en charge comme la double (distance à la finale), sans test sur un vrai tableau.
3. **Badges** : liste volontairement courte (cinq). À étoffer avec les quêtes.
