# Étape 1 — Données : sources Valorant

> Recherche du 2026-09-24, tests PandaScore réels le 2026-09-25 (voir « Résultats des tests »). Les prix et conditions changent : revérifier avant tout engagement payant.

## En bref

- **Colonne vertébrale du MVP : PandaScore, plan gratuit « Fixtures » — confirmé par les tests du 2026-09-25.** Calendrier, résultats, gagnant de chaque carte, brackets et classements, 1 000 requêtes/h, 0 €. C'est la seule source propre, gratuite et structurée qui couvre le besoin « à venir / en cours / terminé ».
- **Complément : Liquipedia.** Formats, contexte, historique. La licence (CC-BY-SA, attribution obligatoire) et les limites (très basses) en font une source d'enrichissement mise en cache, pas une source temps réel.
- **Source officielle (Riot via GRID) :** c'est la cible à long terme, mais l'accès se fait sur dossier, orienté B2B/équipes, prix non publics. On ne l'utilise pas pour le MVP.
- **À éviter en production :** le scraping de VLR.gg et l'API cachée de valorantesports.com (aucune licence, cassables sans préavis).
- **Coût au lancement : 0 €.** Premier palier payant probable : Liquipedia Basic (49 $/mois) si l'appli est monétisée, ou PandaScore Historical (400 €/mois) si on veut les stats joueurs.

## Ce dont l'appli a besoin (rappel)

| Besoin produit | Données nécessaires |
|---|---|
| Agenda à venir / en cours / terminé | Matchs, dates, statut, score final |
| Arbre de tournoi, grilles de poules | Brackets (liens entre matchs), classements |
| Carte de saison « tu es ici » | Structure de la saison (Kickoff → Masters → Stages → Champions) |
| Notifications | Début/fin de match avec une faible latence |
| « Pourquoi ce match compte », onboarding | Contexte : enjeu, qualification, points Champions |
| Jeu « quel joueur a ces stats ? » | Stats joueurs post-match (plus tard) |

Rappel du format 2026 : 48 équipes dans 4 ligues internationales. Le Kickoff se joue en triple élimination, les Stages en round-robin puis double élimination, et Champions a lieu à Shanghai (jusqu'au 18 oct. 2026). **Aucune phase ne tient dans un simple arbre à élimination directe**, donc la source doit exposer les liens entre matchs, pas seulement des listes.

## Fiches sources

### 1. PandaScore — recommandé (socle)

- **Contenu :** tournois, séries, ligues, matchs, équipes, rosters par tournoi. **Brackets** via `previous_matches` (match précédent + gagnant/perdant, ce qui suffit pour dessiner double et triple élimination) et **classements** via l'endpoint standings. Tiers S/A/B/C/D, pratiques pour filtrer VCT et Challengers.
- **Live (plan gratuit) :** début et fin de match et score final, « synchronisés avec les streams publics ». Liens de streams inclus.
- **Prix :** Fixtures 0 € (1 000 req/h) · Historical dès 400 €/mois/jeu (stats post-match, 10 000 req/h) · Live Basic dès 1 000 €/mois (WebSocket) · Live Pro sur devis. Remise de 10 % à l'année, engagement d'un mois.
- **Licence / restrictions :** les plans stats sont interdits aux usages liés aux paris. Les CGU publiques ne sont pas accessibles en ligne (404) : **les droits d'usage commercial du plan gratuit et l'attribution sont à confirmer.**
- **Tests :** brackets et classements sont **inclus en gratuit** ; le score de chaque carte (13-7) ne l'est pas, seul le gagnant l'est. Voir « Résultats des tests ».
- **Risque restant :** l'usage commercial du plan gratuit et l'attribution ne sont pas encore confirmés.

### 2. Liquipedia — complément (contexte et historique)

- **Contenu :** la base la plus complète de la scène (formats, qualifications, historique sur 15 ans et plus, transferts, 76 jeux).
- **Deux accès :**
  - *API MediaWiki* : gratuite, **1 requête / 2 s** et **1 parse / 30 s**.
  - *LiquipediaDB API (données structurées)* : gratuite **uniquement** pour les projets open source, éducatifs ou non commerciaux (60 req/h, durée limitée). Sinon **Basic 49 $/mois** (1 000 req/h) ou **Premium 199 $/mois** (5 000 req/h), **par type de données et par jeu**, avec 12 % de remise à l'année.
- **Licence :** CC-BY-SA 3.0, **attribution obligatoire**. Les « répliques de Liquipedia » et les usages liés aux paris sont interdits.
- **Règles techniques :** User-Agent personnalisé avec contact (sinon blocage), gzip, cache obligatoire.
- **Usage prévu :** ingestion lente, en tâche de fond, mise en cache (fiches de compétition, textes de contexte, historique). Pas de temps réel.

### 3. Riot Games / GRID — officiel, pour plus tard

- **Riot Developer API :** VAL-CONTENT, VAL-MATCH, VAL-RANKED, VAL-STATUS. **Rien sur l'e-sport.** Utile plus tard pour du contenu (agents, cartes). Une clé de production est nécessaire pour une appli publique.
- **Données e-sport officielles :** distribuées par **GRID** (riotesportsdata.com, VALORANT Data Portal). L'accès passe par un formulaire, d'abord réservé aux équipes VCT (lancement en février 2023). Prix non publics, orientation B2B (médias, paris, intégrité).
- **Usage prévu :** candidater une fois qu'on aura de vrais utilisateurs. C'est la meilleure garantie de légitimité à long terme.

### 4. API cachée valorantesports.com — à éviter en production

- L'endpoint `esports-api.service.valorantesports.com/persisted/val/...` est utilisé par le site officiel, avec une clé publique partagée. Il donne ligues et calendrier.
- **Aucune documentation, aucune licence, aucune garantie.** À la rigueur, on peut s'en servir pour recouper le calendrier officiel pendant le développement.

### 5. VLR.gg (et les API non officielles vlrggapi, vlresports) — à éviter en production

- Données très riches : stats joueurs, matchs, classements, actus. Pas d'API officielle. Un modérateur dit sur le forum qu'on « peut scraper », mais il n'existe aucune politique écrite.
- `vlrggapi` (MIT, maintenue, 600 req/min) : l'instance publique est **hors service** (quota Vercel dépassé), il faut l'auto-héberger.
- **Risques :** fragilité (tout changement HTML casse le scraper), aucun droit de redistribution, dépendance à un site tiers. Correct pour prototyper ou explorer les stats, pas comme socle.

### 6. Abios (Sportradar), Bayes, Oddin — hors cible

- Fournisseurs B2B orientés bookmakers, avec contrats sur devis. Surdimensionnés et chers pour notre usage.

## Comparatif

| Critère | PandaScore (gratuit) | Liquipedia | GRID / Riot officiel | valorantesports (caché) | VLR.gg (scraping) |
|---|---|---|---|---|---|
| Calendrier / résultats | ✅ | ✅ | ✅ | ✅ (calendrier) | ✅ |
| Brackets exploitables | ✅ `previous_matches` (testé) | ⚠️ à parser | ✅ | ⚠️ partiel | ⚠️ à parser |
| Live (début/fin/score) | ✅ niveau match + gagnant par carte (testé) | ❌ | ✅ très fin | ⚠️ | ⚠️ |
| Stats joueurs | 💶 400 €/mois | ✅ partiel | ✅ | ❌ | ✅ |
| Contexte / formats | ⚠️ léger | ✅✅ | ⚠️ | ⚠️ | ⚠️ |
| Prix au lancement | 0 € | 0 € (non commercial) / 49 $ | Devis | 0 € | 0 € |
| Limites | 1 000 req/h | 1 req/2 s ; LPDB 60–5 000 req/h | ? | ? | à soi de s'autolimiter |
| Licence claire | ⚠️ à confirmer | ✅ CC-BY-SA + attribution | ✅ contrat | ❌ | ❌ |
| Stabilité | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Verdict** | **Socle MVP** | **Complément** | **Plus tard** | Dev uniquement | Prototype uniquement |

## Recommandation

1. **MVP = PandaScore Fixtures + Liquipedia (MediaWiki, en cache), 0 €.** L'attribution Liquipedia doit apparaître dans l'appli (écran « Sources » et mention sous les fiches de compétition).
2. **Le backend est obligatoire**, comme prévu dans l'architecture : avec 1 000 req/h, chaque téléphone ne peut pas interroger PandaScore directement. Le polling se fait côté serveur (toutes les 5 à 15 min hors live, toutes les 30 à 60 s pendant un match suivi), avec le cache Redis.
3. **Couche d'abstraction « fournisseur »** dans le modèle générique (Événement / Entité / Compétition) : on stocke `provider` + `external_id`, ce qui permettra de basculer vers GRID sans toucher l'appli.
4. **Déclencheurs pour passer au payant :**
   - l'appli génère des revenus → Liquipedia Basic (49 $/mois) ou confirmation écrite de PandaScore ;
   - on veut les stats joueurs (jeu « quel joueur ? ») → PandaScore Historical (400 €/mois) ;
   - on veut du live au round près → Live Basic (1 000 €/mois) ou GRID.

## Résultats des tests PandaScore (2026-09-25, plan gratuit)

Script : `tests-pandascore/test-pandascore.mjs` (token dans `.env`, jamais versionné). Rapport : `rapport-pandascore.md`, réponses brutes dans `samples/`. Test fait pendant Champions 2026 (Shanghai), en direct sur NS vs NRG.

| Endpoint | Gratuit ? |
|---|---|
| Ligues, séries, tournois (en cours, tier S) | ✅ |
| Détail d'un tournoi, rosters | ✅ |
| **Brackets** `/tournaments/{id}/brackets` | ✅ |
| **Classement** `/tournaments/{id}/standings` | ✅ |
| Matchs en cours / à venir / terminés | ✅ |
| Équipes, joueurs | ✅ |
| Stats joueurs d'un match | 🔒 403 (payant, comme prévu) |

**Ce qu'on obtient vraiment :**

- **Structure de saison :** Ligue (VCT) → Série (« Champions 2026 », « Masters London 2026 ») → Tournois (« Group A…D », « Playoffs ») → Matchs. Cela suffit pour la carte de saison. La Coupe du monde de l'e-sport (Esports World Cup) est aussi en tier S : il faudra filtrer par ligue.
- **Brackets :** chaque match a `previous_matches` avec `winner`/`loser`. Exemple du groupe C de Champions (format GSL) : Winners Match ← gagnants des 2 matchs d'ouverture, Elimination Match ← perdants, Decider ← perdant du Winners + gagnant de l'Elimination. Les matchs futurs existent déjà en « TBD vs TBD », donc on peut dessiner l'arbre complet avant qu'il soit joué.
- **Classement :** `rank`, `team`, `last_match`. C'est minimal : pas de victoires/défaites ni de différence de cartes, qu'il faudra recalculer à partir des matchs.
- **Matchs :** statut, BO, score de la série (`results`), gagnant, `games` (gagnant et durée de chaque carte), liens de stream (Twitch, plusieurs langues), logos d'équipe (clair et sombre), `rescheduled` et `original_scheduled_at`.
- **Pas en gratuit :** le score en rounds de chaque carte, le nom de la carte, les stats joueurs. `live.supported` vaut `false`.
- **Fraîcheur :** l'écart entre la fin d'un match (`end_at`) et sa dernière mise à jour (`modified_at`) va de quelques secondes à environ 1 h. C'est un indice, pas une mesure de latence : à surveiller en conditions réelles.
- **Quota :** en-têtes `x-rate-limit-remaining` / `x-rate-limit-used` disponibles, ce qui permet au worker de réguler son rythme.

**Conséquences produit :** afficher « 2-0 » et le gagnant de chaque carte (pas « 13-7 » ni le nom de la carte) ; recalculer le bilan V/D en poules ; utiliser les logos PandaScore avec une mention des marques des équipes.

## À valider ensuite

- [x] Brackets, classements et tournois accessibles en gratuit : **oui** (2026-09-25).
- [x] Score par carte en gratuit : **gagnant seulement**, pas de score en rounds.
- [ ] Mesurer la latence réelle début/fin de match en suivant un match en direct (au jalon J1, via le worker).
- [ ] Écrire à PandaScore : usage commercial du plan gratuit et attribution exigée.
- [ ] Tester l'API Liquipedia avec un User-Agent conforme sur la page de Champions 2026.
- [ ] (Facultatif) Remplir le formulaire GRID pour connaître les conditions.

## Sources

- [PandaScore — Pricing](https://www.pandascore.co/pricing)
- [PandaScore — Introduction (docs)](https://developers.pandascore.co/docs/introduction)
- [PandaScore — Tournaments in-depth](https://developers.pandascore.co/docs/tournaments-in-depth)
- [PandaScore — Stats](https://www.pandascore.co/stats)
- [Liquipedia — API Terms of Use](https://liquipedia.net/api-terms-of-use)
- [Liquipedia — esports API (plans)](https://liquipedia.net/api)
- [Riot Developer Portal — Valorant](https://developer.riotgames.com/docs/valorant)
- [Official Riot Esports Data — Product overview](https://riotesportsdata.com/en-us/product-overview/)
- [GRID — VALORANT Data Portal](https://grid.gg/get-valorant/)
- [Valorant Esports — Riot & GRID launch data portal](https://valorantesports.com/en-US/news/riot-games-and-grid-launch-new-valorant-data-portal/)
- [MMM-VALORANTESPORTS-SCHEDULES (API cachée)](https://github.com/xadamxk/MMM-VALORANTESPORTS-SCHEDULES)
- [vlrggapi (GitHub)](https://github.com/axsddlr/vlrggapi)
- [VLR.gg — fil « VLR API »](https://www.vlr.gg/75529/vlr-api)
- [Abios — Packaging](https://abiosgaming.com/packaging)
- [2026 Valorant Champions Tour (Wikipedia)](https://en.wikipedia.org/wiki/2026_Valorant_Champions_Tour)
