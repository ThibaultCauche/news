# Étape 1b — Données : élargir à tout l'e-sport et au sport

> Recherche du 2026-09-25. Suite de `01-donnees-sources-valorant.md`. Les prix changent : revérifier avant de payer.

## En bref

- **E-sport : PandaScore couvre déjà une quinzaine de jeux avec le même format de données.** Une fois l'adaptateur Valorant écrit, ajouter LoL, CS2, Dota 2, Overwatch, Rainbow Six, Rocket League, etc. coûte surtout de l'affichage, pas de l'ingestion. Le test multi-jeux (`tests-pandascore/test-multijeux.mjs`) confirme que le plan gratuit couvre les 15 jeux avec un seul token.
- **Jeux de combat : start.gg**, l'API officielle de la plateforme où se déroulent la plupart des tournois (gratuite, 80 req/min).
- **Longue traîne (Fortnite, Apex, TFT, échecs, jeux mobiles…) : Liquipedia.** C'est la seule source qui couvre presque tout (76 jeux), mais l'API structurée coûte **49 $/mois par type de données et par jeu** en usage commercial. On ne l'active que jeu par jeu, quand il y a de la demande.
- **Sport : pas d'équivalent de PandaScore gratuit et multi-sports.** Il faut assembler une source par sport ou payer un agrégateur. Le plus rentable : **API-Sports** (football, basket, rugby, handball, F1, hockey, volley, MMA, NFL, NBA… mais **ni tennis ni cyclisme**), complété par des sources spécialisées.
- **Budget réaliste au lancement « e-sport large + sport principal » : 0 à 60 €/mois.** Le tennis et le cyclisme sont les plus chers (sources spécialisées, sur devis).

## Principe d'architecture (déjà compatible avec l'étape 3)

Le modèle `competition` / `event` / `entity` + `provider_ref` supporte déjà plusieurs sources. Élargir, c'est **un adaptateur par fournisseur**, pas un par jeu ou par sport :

| Adaptateur | Couvre |
|---|---|
| `pandascore` | ~15 jeux e-sport |
| `startgg` | Jeux de combat (+ tournois communautaires) |
| `liquipedia` | Contexte e-sport, puis jeux absents ailleurs |
| `apisports` | ~12 sports (une clé, une API par sport, même format) |
| `jolpica` | F1 (calendrier, résultats, classements) |
| spécialistes | Tennis, cyclisme (plus tard) |

**Règle de priorité :** on ajoute d'abord ce qui est gratuit ou déjà branché et qui intéresse le plus d'utilisateurs. Chaque ajout de catégorie passe par une mini-fiche : source, coût, licence, format visuel.

## E-sport

### PandaScore — tous les jeux du plan gratuit

- **Jeux annoncés :** 13 titres majeurs dont LoL, CS2, Dota 2, Valorant, Rainbow Six Siege, Rocket League, Overwatch, StarCraft II, PUBG, Call of Duty, EA FC, Mobile Legends, LoL Wild Rift, King of Glory.
- **Prix :** la page de tarifs indique « 0 €/mois **par jeu** » pour Fixtures. Notre token gratuit ouvre bien tous les jeux (voir le test ci-dessous).
- **Même quota partagé :** 1 000 req/h pour tous les jeux. Avec une quinzaine de jeux, le worker doit interroger les listes globales (`/matches/running`, `/matches/upcoming`) plutôt que jeu par jeu, et ne rafraîchir vite que les matchs suivis.
- **Formats visuels à prévoir :** LoL et CS2 ont des phases suisses (Worlds, Majors), les jeux battle royale (PUBG, et plus tard Fortnite/Apex) n'ont pas de matchs en face-à-face mais des **classements par manche**. Il faudra un format « classement de lobby » dans le modèle.

## Résultats du test multi-jeux PandaScore (2026-09-25)

Script `test-multijeux.mjs`, 30 appels. **Les 15 jeux sont accessibles avec le même token gratuit** (tournois, matchs, brackets). Rapport complet : `tests-pandascore/rapport-multijeux.md`.

| Jeu | Slug | Activité au 25/09/2026 | Remarque |
|---|---|---|---|
| Counter-Strike | `cs-go` | Très forte (160 des 300 prochains matchs, 26 tournois en cours) | Beaucoup de tiers C/D : filtrer par tier |
| LoL | `league-of-legends` | Worlds 2026 en cours | Bracket lié ✅ |
| Dota 2 | `dota-2` | BLAST Slam en cours | Bracket lié ✅ (10/14) |
| Valorant | `valorant` | Champions 2026 en cours | Bracket lié ✅ |
| Rainbow 6 Siege | `r6-siege` | Actif | Bracket lié ✅ |
| Rocket League | `rl` | RLCS Worlds terminé le 18/09 | Bracket lié ✅ |
| Mobile Legends | `mlbb` | Actif (Asian Games) | — |
| King of Glory | `kog` | Actif | — |
| StarCraft 2 | `starcraft-2` | Actif | — |
| Overwatch, Call of Duty, EA FC | `ow`, `cod-mw`, `fifa` | Hors saison, tournois récents en 2026 | Couverts |
| StarCraft Brood War | `starcraft-brood-war` | Dernier tournoi : sept. 2025 | Couverture faible |
| LoL Wild Rift | `lol-wild-rift` | Dernier tournoi : janv. 2025 | **Plus couvert en pratique** |
| PUBG | `pubg` | Dernier tournoi : 2020 | **Plus couvert** : passer par Liquipedia |

**À vérifier :**

- Le gagnant de chaque carte est rempli pour Valorant, MLBB et King of Glory, mais **0 sur 3 pour CS, Dota 2 et LoL** dans l'échantillon. Il faut vérifier sur des matchs de tier S terminés si c'est une limite du plan gratuit pour ces jeux.
- Le bracket CS testé (petit tournoi) n'avait aucun lien entre matchs : à revérifier sur un Major.

**Jeux absents de PandaScore** : Fortnite, Apex, TFT, jeux de combat, Deadlock, Marvel Rivals… → start.gg (combat) et Liquipedia (le reste).

### start.gg — jeux de combat et tournois communautaires

- **Contenu :** tournois, événements, phases, brackets, sets, classements. Street Fighter 6, Tekken 8, Smash, etc. (EVO, Capcom Pro Tour, Tekken World Tour s'y déroulent en grande partie).
- **Accès :** API GraphQL officielle, token gratuit, **80 requêtes / 60 s**, 1 000 objets max par requête.
- **Licence :** les conditions d'utilisation de l'API n'ont pas pu être lues en ligne. **À vérifier avant la mise en production.**
- **Intérêt :** c'est la source d'origine (les organisateurs saisissent eux-mêmes leurs brackets), donc très fraîche.

### Liquipedia — longue traîne et contexte

- **Couverture :** 76 jeux, y compris Fortnite, Apex, TFT, Hearthstone, Brawl Stars, Clash Royale, échecs, Trackmania, Pokémon…
- **Coût :** API MediaWiki gratuite mais lente (1 req/2 s, texte à analyser) ; LiquipediaDB Basic **49 $/mois par type de données et par jeu** (1 000 req/h). Exemple : matchs + tournois pour 3 jeux de plus = 6 × 49 $ ≈ 294 $/mois.
- **Point de vigilance :** Liquipedia interdit les « répliques ». Une appli qui reprend l'ensemble de leurs pages pourrait être considérée comme telle. On l'utilise pour compléter, pas comme source principale.

### GRID Open Access

- **Gratuit mais limité :** CS2 et Dota 2, **données historiques seulement**, usage communautaire et non commercial. Le live et les autres jeux passent par des contrats sur devis.
- **Usage :** intéressant plus tard pour des stats officielles CS2/Dota 2. Pas utile pour l'agenda.

## Sport

### Priorités proposées (public français)

1. **Football** (Ligue 1, Ligue des champions, grands championnats européens, équipes nationales).
2. **Rugby** (Top 14, Six Nations, Champions Cup).
3. **Formule 1** (et MotoGP plus tard).
4. **Tennis** (Grand Chelem, dont Roland-Garros ; ATP/WTA).
5. **Basket** (NBA, Betclic Élite, EuroLeague).
6. **Cyclisme** (Tour de France), handball, JO : plus tard.

### Sources

| Source | Sports | Gratuit | Payant | Licence / limites |
|---|---|---|---|---|
| **API-Sports** (api-football.com) | Football, basket, rugby, handball, hockey, volley, F1, MMA, NBA, NFL, baseball, AFL | 100 req/jour par sport, **saisons limitées** (à vérifier : la saison en cours peut être exclue) | 19 $ / 29 $ / 39 $ par mois et par sport (7 500 à 150 000 req/jour) | Utilisation dans une appli autorisée, revente interdite. Paris, TV, fantasy et « médias de masse » peuvent nécessiter des licences des ayants droit. |
| **football-data.org** | Football (12 compétitions en gratuit, dont Ligue 1 et Ligue des champions) | 10 req/min, **scores différés** | 12 €/mois avec le live ; 49 € pour 30 compétitions | Bon pour démarrer le football. |
| **Jolpica-F1** | F1 (successeur d'Ergast) | Gratuit, open source (Apache 2.0) | Dons | Calendrier, résultats, classements. Pas de live. |
| **OpenF1** | F1 (télémétrie, positions en direct) | Historique gratuit | Live 9,90 €/mois | **Non commercial** sans accord. |
| **TheSportsDB** | Très large (y compris cyclisme, sports mécaniques, combat) | Clé publique très bridée | 9 $ ou 20 $/mois | Données communautaires (qualité variable). Utile pour logos et calendriers de secours. |
| **Tennis spécialisés** (tennis-api.com, etc.) | ATP, WTA, ITF, Challenger | Rarement | Sur abonnement | Comparatif trouvé rédigé par un fournisseur : à tester soi-même. |
| **CyclingFlash** | Cyclisme pro (courses, étapes, classements, live) | Non | Sur devis | Usages commerciaux prévus. |
| **Sportradar / Sportmonks / Enetpulse** | Tout | Essais | Cher, sur devis | Pour plus tard, si l'appli grossit. |

### Droits sur les calendriers et résultats

- En Europe, la Cour de justice de l'UE a jugé en 2012 (Football Dataco c. Yahoo) qu'un calendrier de matchs n'est **pas protégé par le droit d'auteur** en tant que base de données, sauf création originale. Les fournisseurs rappellent toutefois que certains usages (paris, diffusion, fantasy) demandent des licences des ligues.
- **Pour nous :** afficher calendriers et résultats via un fournisseur sous licence est l'usage normal. Les **logos** de clubs et de compétitions sont des marques : à utiliser pour identifier les équipes, sans les modifier, avec une mention.

## Recommandation

**E-sport (pas cher, rapide)**

1. Brancher **tous les jeux PandaScore** dès que l'adaptateur Valorant marche (0 €).
2. Ajouter **start.gg** pour les jeux de combat (0 €).
3. Liquipedia payant **jeu par jeu**, seulement quand un jeu absent devient demandé.

**Sport (par vagues)**

1. **Vague 1 (0 à 20 €/mois) :** football via football-data.org (gratuit, 12 compétitions), puis API-Football Pro (19 $) pour le live ; F1 via Jolpica (gratuit).
2. **Vague 2 (≈ 40 à 60 €/mois) :** rugby et basket via API-Sports (même format que le football).
3. **Vague 3 (sur devis) :** tennis et cyclisme avec des spécialistes, si les utilisateurs le demandent.

**Formats visuels à ajouter aux maquettes :** phase suisse (LoL, CS2), classement de lobby (battle royale), classement de championnat (football, rugby), classement de pilotes et calendrier de Grands Prix (F1), tableau de tournoi à 128 (tennis, proche de l'arbre radial), étapes et maillots (cyclisme).

## Stratégie 100 % gratuite (ajout du 2026-09-25)

Objectif : une appli accessible et gratuite, faite à la main. **Une version entièrement gratuite est faisable**, à une condition : **rester non commercial** (pas de pub ni d'abonnement), et idéalement **publier le code en open source**. Ce statut débloque plusieurs offres gratuites réservées aux projets communautaires.

### Niveau 1 — Officiel et gratuit (socle, sans risque)

| Source | Couvre | Condition |
|---|---|---|
| PandaScore Fixtures | ~15 jeux e-sport | Usage commercial à confirmer |
| start.gg API | Jeux de combat, tournois communautaires | Token gratuit, 80 req/min |
| **Liquipedia LPDB gratuit** | 76 jeux (dont Fortnite, Apex, TFT…) | **Projet open source ou non commercial**, 60 req/h, accès à durée limitée prolongeable pour les projets communautaires |
| Liquipedia MediaWiki | Idem, texte brut | Gratuit, CC-BY-SA, 1 req/2 s |
| GRID Open Access | CS2, Dota 2 (historique officiel) | Non commercial |
| Twitch API | Streams en direct | Gratuit (compte développeur) |
| football-data.org | 12 compétitions de foot (Ligue 1, C1…) | Scores différés en gratuit |
| **openfootball / football.json** (GitHub) | Calendriers et résultats des grands championnats européens, saisons jusqu'à 2026-27 | **Domaine public (CC0)**, fichiers JSON, mise à jour quotidienne automatique (pas de live) |
| Jolpica-F1 | F1 (calendrier, résultats, classements) | Gratuit, open source |
| OpenF1 | F1 (historique détaillé) | Non commercial ; live payant (9,90 €/mois) |
| Wikidata / Wikipédia | Structure des compétitions, palmarès, contexte (« pourquoi ce match compte ») | CC0 (Wikidata) / CC-BY-SA (Wikipédia), attribution |
| Calendriers .ics publics | Calendriers officiels de clubs, ligues, F1 | Selon l'éditeur ; lecture simple |

### Niveau 2 — API non officielles mais publiques (secours, avec prudence)

Ce sont des adresses JSON utilisées par les sites officiels eux-mêmes et documentées par la communauté sur GitHub. Elles sont gratuites et sans clé, mais **sans autorisation, sans garantie, et peuvent disparaître du jour au lendemain**.

| Source | Couvre | Intérêt |
|---|---|---|
| **API cachée ESPN** (`site.api.espn.com`, doc communautaire Public-ESPN-API) | 17 sports, 139 ligues : foot, **tennis ATP/WTA**, F1, rugby, NBA… | Comble les trous les plus chers (tennis, rugby) avec du quasi-live |
| API cachée LoL Esports (`esports-api.lolesports.com`) | LoL officiel | Recoupement du calendrier officiel |
| API cachée Valorant Esports | Valorant officiel | Idem |

**Règles d'usage :** toujours derrière le cache du backend (jamais depuis l'appli), rythme faible, User-Agent identifiable, et **toujours une source de niveau 1 en repli** pour que l'appli survive si l'adresse est coupée.

### Niveau 3 — Scraping de sites (SofaScore, FlashScore, VLR.gg, WhoScored…) : non retenu

- Les conditions d'utilisation de ces sites l'interdisent, et plusieurs ont des protections anti-robots. On ne les contourne pas.
- **En France, le droit « sui generis » des bases de données** (Code de la propriété intellectuelle, art. L342-1) interdit d'extraire une partie substantielle d'une base sans l'accord de son producteur. Une appli publique qui aspire SofaScore est exactement ce cas.
- Fragile : un changement de page casse tout. Des bibliothèques GitHub existent (soccerdata, ScraperFC, vlrggapi), mais elles servent à l'analyse perso, pas à une appli publique.

### Ce que ça donne

- **E-sport : 0 €** avec PandaScore + start.gg + Liquipedia gratuit (si open source/non commercial) + Twitch.
- **Sport : 0 €** avec football-data.org + openfootball (foot), Jolpica (F1), et ESPN en niveau 2 pour tennis, rugby et basket. Le live « à la seconde » ne sera pas au rendez-vous partout, ce qui est acceptable pour la cible néophyte.
- **Prix à payer :** plus d'adaptateurs à maintenir, des offres gratuites qui peuvent changer, et l'interdiction de monétiser tant qu'on reste sur ces conditions.

## À valider

- [x] Lancer `node test-multijeux.mjs` : **15 jeux accessibles en gratuit** (2026-09-25).
- [ ] Vérifier le gagnant par carte pour CS, Dota 2 et LoL sur des matchs de tier S.
- [ ] Créer une clé API-Sports gratuite et vérifier si la saison 2026-2027 de Ligue 1 est accessible en gratuit.
- [ ] Créer un token start.gg et lire leurs conditions d'utilisation de l'API.
- [ ] Choisir les sports prioritaires (proposition ci-dessus).
- [x] Statut : non commercial + open source (décision du 2026-09-25).

## Sources

- [PandaScore — Pricing](https://www.pandascore.co/pricing) · [PandaScore — docs](https://developers.pandascore.co/docs/introduction)
- [start.gg — API intro](https://developer.start.gg/docs/intro) · [start.gg — rate limits](https://developer.start.gg/docs/rate-limits)
- [Liquipedia — API (plans)](https://liquipedia.net/api) · [Liquipedia — API terms](https://liquipedia.net/api-terms-of-use)
- [GRID — What is Open Access](https://grid.gg/what-is-grid-open-access/) · [GRID — Open Access](https://grid.gg/open-access/)
- [API-Football — Pricing](https://www.api-football.com/pricing) · [API-Football — Terms](https://www.api-football.com/terms)
- [football-data.org — Pricing](https://www.football-data.org/pricing) · [Free tier limits 2026 (TheStatsAPI)](https://www.thestatsapi.com/blog/football-data-org-free-tier-limits-2026)
- [TheSportsDB — Pricing](https://www.thesportsdb.com/pricing) · [TheSportsDB — Documentation](https://www.thesportsdb.com/documentation)
- [OpenF1](https://openf1.org/) · [Jolpica-F1](https://github.com/jolpica/jolpica-f1)
- [Best Tennis APIs 2026 (tennis-api.com)](https://tennis-api.com/news/the-best-tennis-apis-for-developers-in-2026/)
- [openfootball/football.json](https://github.com/openfootball/football.json) · [Public-ESPN-API (doc communautaire)](https://github.com/pseudo-r/Public-ESPN-API) · [lolesports-api-docs](https://github.com/vickz84259/lolesports-api-docs) · [soccerdata](https://soccerdata.readthedocs.io/en/latest/intro.html)
- [CyclingFlash — Developers](https://cyclingflash.com/developers)
- [Football Dataco — pas de protection des calendriers (SCL)](https://www.scl.org/2407-football-dataco-no-database-copyright-protection-for-fixture-lists/)
