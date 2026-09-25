# Rapport tests PandaScore — Valorant

Généré le 25/09/2026 12:35:38. Réponses brutes dans `samples/` (le token n'y figure pas).

## Endpoints

| Résultat | Test | Endpoint | Éléments | Temps |
|---|---|---|---|---|
| ✅ inclus | Ligues Valorant | `/valorant/leagues?per_page=50` | 50 | 362 ms |
| ✅ inclus | Séries en cours | `/valorant/series/running` | 1 | 80 ms |
| ✅ inclus | Tournois en cours | `/valorant/tournaments/running?per_page=50` | 2 | 43 ms |
| ✅ inclus | Tournois tier S récents | `/valorant/tournaments?filter[tier]=s&sort=-begin_at&per_page=20` | 20 | 288 ms |
| ✅ inclus | Détail du tournoi | `/tournaments/21883` | 1 | 32 ms |
| ✅ inclus | Brackets du tournoi _(clé pour l'arbre)_ | `/tournaments/21883/brackets` | 5 | 41 ms |
| ✅ inclus | Classement du tournoi _(clé pour les poules)_ | `/tournaments/21883/standings` | 4 | 72 ms |
| ✅ inclus | Rosters du tournoi | `/tournaments/21883/rosters` | 1 | 33 ms |
| ✅ inclus | Matchs en cours | `/valorant/matches/running` | 1 | 43 ms |
| ✅ inclus | Matchs à venir | `/valorant/matches/upcoming?per_page=20&sort=begin_at` | 20 | 58 ms |
| ✅ inclus | Matchs terminés | `/valorant/matches/past?per_page=20&filter[finished]=true` | 20 | 102 ms |
| ✅ inclus | Équipes | `/valorant/teams?per_page=5` | 5 | 35 ms |
| ✅ inclus | Joueurs | `/valorant/players?per_page=5` | 5 | 42 ms |
| 🔒 non inclus (403) | Stats joueurs d'un match (attendu payant) | `/valorant/matches/1682153/players/stats` | 1 | 29 ms |

## Observations

- **Tournoi inspecté** : « VCT Champions 2026 — Group C » (id 21883, tier S, type offline, has_bracket=true)
- **Brackets : liens entre matchs** : 5 match(s), 3 avec previous_matches (types : loser, winner)
- **Classement : champs** : last_match, rank, team
- **Match en cours : exemple** : « NS vs NRG » — statut running, BO3, tournoi « Group D » (Champions 2026)
- **Match en cours : score de la série (results)** : 0 – 1
- **Match en cours : détail par carte (games)** : 3 carte(s), 1 avec un gagnant renseigné, sans score par carte (seulement le gagnant)
- **Match en cours : liens de stream** : 4 lien(s) (ex. de https://www.twitch.tv/harmii)
- **Match en cours : champs disponibles** : begin_at, detailed_stats, draw, end_at, forfeit, game_advantage, games, id, league, league_id, live, match_type, modified_at, name, number_of_games, opponents, original_scheduled_at, rescheduled, results, scheduled_at, serie, serie_id, slug, status, streams_list, tournament, tournament_id, videogame, videogame_title, videogame_version, winner, winner_id, winner_type
- **Prochain match** : « KC vs XLG » le 2026-09-25T12:00:00Z
- **Match terminé : exemple** : « TYLOO vs G2 » — statut finished, BO3, tournoi « Group C » (Champions 2026)
- **Match terminé : score de la série (results)** : 0 – 2
- **Match terminé : détail par carte (games)** : 2 carte(s), 2 avec un gagnant renseigné, sans score par carte (seulement le gagnant)
- **Match terminé : liens de stream** : 7 lien(s) (ex. zh https://www.twitch.tv/valorantesports_cn)
- **Match terminé : champs disponibles** : begin_at, detailed_stats, draw, end_at, forfeit, game_advantage, games, id, league, league_id, live, match_type, modified_at, name, number_of_games, opponents, original_scheduled_at, rescheduled, results, scheduled_at, serie, serie_id, slug, status, streams_list, tournament, tournament_id, videogame, videogame_title, videogame_version, winner, winner_id, winner_type

## Quota

- `x-rate-limit-remaining` : 985
- `x-rate-limit-used` : 15
