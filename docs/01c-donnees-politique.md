# Étape 1c — Données : politique (France d'abord)

> Recherche du 2026-09-25. Contexte : appli **open source et gratuite** (décision du 2026-09-25). Bonne nouvelle : la politique est la catégorie la mieux servie en données ouvertes, **tout est gratuit et officiel**.

## En bref

- **Tout est en open data officiel, sous Licence ouverte 2.0 (Etalab)** : réutilisation libre, y compris commerciale, avec une simple mention de la source. Pas de clé payante, pas de zone grise.
- **Assemblée nationale** : dossiers législatifs, scrutins (votes par groupe et par député), amendements, députés, agenda. Fichiers JSON mis à jour chaque jour (vérifié : dossiers mis à jour le 25/09/2026).
- **Sénat** : dossiers législatifs, amendements, scrutins, sénateurs (CSV / dumps PostgreSQL).
- **Légifrance (API PISTE)** : lois promulguées, Journal officiel. Gratuit après inscription.
- **Élections** : résultats officiels du ministère de l'Intérieur sur data.gouv.fr, **y compris en direct le soir de l'élection** (bureau par bureau).
- **Grand rendez-vous à préparer : la présidentielle, 1er tour le 18 avril 2027, 2d tour le 2 mai 2027.** Si l'appli sort avant, c'est le meilleur moment pour attirer des utilisateurs.
- **Europe** : Parlement européen (API officielle) + HowTheyVote.eu (votes, CSV hebdo sur GitHub).
- **Le vrai défi n'est pas la donnée mais la neutralité et la lisibilité** : les données officielles sont denses et en jargon parlementaire. C'est exactement la valeur ajoutée de l'appli.

## Principes voulus (2026-09-25)

- **Ultra neutre, uniquement des faits officiels** : quelles lois sont passées, qui a voté pour ou contre, qui a proposé quoi.
- **Limpide et visuel** : graphiques, schémas, dessins plutôt que des textes à rallonge.
- **Aller plus loin à la demande** : liens vers les documents officiels et « clés de compréhension » (glossaire, explication des étapes) pour que chacun puisse lire les sources lui-même.

### Traduction visuelle proposée

| Info | Visuel |
|---|---|
| Où en est une loi | Suivi façon colis (étapes cochées, étape en cours en surbrillance) |
| Résultat d'un vote | Hémicycle en points colorés (pour / contre / abstention / absent), puis barre par groupe |
| Qui a proposé | Carte « auteur » : groupe, nombre de cosignataires, date de dépôt |
| Activité de la semaine | Frise : textes déposés, votés, promulgués |
| Aller plus loin | Liens « Texte officiel », « Scrutin », « Dossier complet » + feuille glossaire |

## Jeu politique « Qui a… ? » (intérêt confirmé par des amis)

Trois familles de questions, toutes générées à partir des données officielles :

1. **Qui a proposé cette loi ?** → auteur et groupe (AN dossiers législatifs).
2. **Qui a voté pour ou contre ?** → position majoritaire de chaque groupe (AN scrutins).
3. **Qui a dit ça ?** → citation tirée des comptes rendus officiels des séances (AN « comptes rendus », Sénat). Risque de sortie de contexte : afficher la phrase précédente et suivante et le lien vers le compte rendu au moment de la réponse.

**Garde-fous de neutralité :** tirage équilibré entre groupes (quotas), mêmes formulations pour tous, noms officiels, source affichée à chaque réponse, pas de commentaire sur le fond.

## Besoins produit → données

| Besoin (maquettes 16, 19, 25) | Données | Source |
|---|---|---|
| Suivi d'une loi « façon colis » | Étapes du dossier (dépôt, commission, séance, navette, CMP, Conseil constitutionnel, promulgation) | AN dossiers + Sénat Dosleg + Légifrance (JO) |
| Résultat d'un vote + barre par groupe | Scrutins : pour / contre / abstention, par groupe et par député | AN scrutins, Sénat scrutins |
| « Qui a proposé cette loi ? » (jeu) | Auteur d'une proposition de loi, groupe, cosignataires | AN dossiers + députés/groupes |
| « Adoptée ou non ? » (jeu) | Issue du vote et de la navette | AN scrutins + dossiers |
| Dernières lois promulguées | Lois publiées au JO | Légifrance / JORF |
| Résumés jour / semaine / mois / an | Agenda, textes adoptés, scrutins solennels | AN agenda + dossiers + scrutins |
| Soirée électorale (hémicycle, dépouillement) | Résultats par bureau en direct, participation | data.gouv.fr (ministère de l'Intérieur) |
| Fiches députés / groupes | Mandats, groupes, commissions | AN acteurs, Sénat, NosDéputés |

## Fiches sources

### 1. Assemblée nationale — open data (socle)

- **Portail :** data.assemblee-nationale.fr, 17e législature + archives (14e à 16e).
- **Jeux utiles :** dossiers législatifs (projets et propositions, textes adoptés, lois promulguées, rapporteurs, commissions, dates), scrutins (positions de chaque député sur les scrutins publics et solennels), amendements, acteurs (députés, groupes, organes), réunions (agenda), questions au gouvernement.
- **Format :** gros fichiers JSON ou XML zippés, par exemple `…/repository/17/loi/scrutins/Scrutins.json.zip`. **Pas d'API** : le worker télécharge le zip chaque jour, compare et met à jour.
- **Fraîcheur :** quotidienne (dossiers et scrutins mis à jour les 24-25/09/2026). Pas de temps réel pendant une séance.
- **Licence :** Licence ouverte. Contact : opendata@assemblee-nationale.fr.

### 2. Sénat — data.senat.fr

- **Jeux :** Dosleg (documents et dossiers depuis 1977), Ameli (amendements), scrutins, sénateurs, comptes rendus, textes au format Akoma Ntoso (depuis 2019), résultats des sénatoriales.
- **Format :** CSV et dumps PostgreSQL (plus lourd à exploiter que l'AN).
- **Usage :** compléter la navette (étapes au Sénat) et les votes des sénateurs.

### 3. Légifrance — API PISTE (DILA)

- **Contenu :** Journal officiel, lois, codes, textes consolidés. C'est ici qu'on confirme l'étape « Promulguée » et le lien vers le texte officiel.
- **Accès :** gratuit après inscription sur piste.gouv.fr (OAuth), quotas par jeton (détail sur PISTE).
- **Licence :** Licence ouverte 2.0 + CGU de l'API.

### 4. Élections — ministère de l'Intérieur (data.gouv.fr)

- **Historique :** « Données des élections agrégées » sur data.gouv.fr.
- **Soirée électorale :** le ministère publie les résultats officiels **par bureau de vote en temps réel** sur data.gouv.fr (utilisé par exemple par resultat-elections.fr pour les municipales 2026).
- **Présidentielle 2027 :** 1er tour dimanche 18 avril, 2d tour dimanche 2 mai. Liste officielle des candidats publiée par le Conseil constitutionnel peu avant le 1er tour (500 parrainages dans au moins 30 départements). **À tester sur un scrutin partiel avant avril 2027**, pour ne pas découvrir le format le soir même.

### 5. Projets open source (Regards Citoyens et autres)

- **NosDéputés.fr / NosSénateurs.fr (API)** : députés, votes, amendements, interventions, dossiers ; JSON / XML / CSV ; **ODbL + CC-BY-SA**, attribution « NosDéputés.fr par Regards Citoyens ». La doc de l'API mentionne la 16e législature : **il faut vérifier que la 17e est couverte**. Utile surtout comme inspiration et pour l'activité des députés.
- **La Fabrique de la Loi** (Regards Citoyens / médialab Sciences Po) : visualise le parcours complet des lois, avec une API. C'est une **référence directe pour le suivi « façon colis »**. À vérifier : est-elle encore mise à jour ?
- **eurolens** (GitHub) : explique les votes du Parlement européen en langage simple **sans IA générative dans la chaîne** : les explications viennent du texte officiel et d'un glossaire fixe, donc elles ne peuvent pas inventer de fait. **Bon modèle pour notre neutralité.**

### 6. Europe

- **Parlement européen — Open Data Portal** : API officielle (séances, votes, eurodéputés, documents).
- **HowTheyVote.eu** : votes par appel nominal, eurodéputés et groupes, **CSV mis à jour chaque semaine** sur GitHub (dernière version 2026-09-19). Licence à lire sur leur site.

## Neutralité : règles côté données

1. **Uniquement des sources officielles** pour les faits (votes, étapes, résultats), avec le lien affiché à côté de chaque info.
2. **Noms officiels des groupes et partis**, tels que publiés par l'Assemblée et le Sénat. Aucune étiquette maison (« gauche radicale », « extrême… »).
3. **Résumés générés à partir des données, pas d'une opinion** : un gabarit fixe (« Le texte X a été adopté par 312 voix contre 201 ») plus un glossaire, sur le modèle d'eurolens. Si une IA reformule un jour, elle ne travaille que sur le texte officiel et on affiche la source.
4. **Jeu :** équilibre entre groupes dans les questions tirées au sort (quotas par groupe) et source officielle au moment de la réponse.
5. **Charte de neutralité publique** (déjà prévue dans les Réglages) + code open source, ce qui permet à chacun de vérifier.

## Architecture : ce que ça ajoute

- **Nouveaux adaptateurs :** `assemblee` (téléchargement quotidien des zips, calcul des différences), `senat`, `legifrance` (PISTE OAuth), `elections` (data.gouv, rythme rapide le soir d'élection).
- **Formats déjà prévus dans le modèle :** `law_process` (loi façon colis) et `live_feed` (soirée électorale). À ajouter : `vote` (résultat par groupe) comme type d'événement.
- **Rythme :** une fois par jour hors élections ; toutes les 1 à 2 min le soir d'une élection.

## Résultats du premier test (2026-09-25)

Script `politique-quiz/extraire-quiz.mjs` : téléchargement des scrutins (26 Mo) et des députés/groupes (5 Mo) de la 17e législature.

- **8 434 scrutins lus**, 12 groupes, 577 députés. Tout fonctionne sans compte ni clé.
- ⚠️ **Le champ `positionMajoritaire` de l'open data n'est pas fiable** : il ne correspond souvent pas aux voix réelles (ex. scrutin 2957 : RN noté « abstention » alors que 119 députés RN ont voté pour). **Toujours recalculer la position d'un groupe à partir des décomptes** (pour / contre / abstention). Le script a été corrigé.
- **Motions de censure** : seules les voix « pour » sont enregistrées. Un groupe qui ne vote pas n'apparaît qu'en non-votants.
- **Ancien identifiant de groupe** : `PO847173` (absent de la liste des groupes actifs) correspond à l'ancien identifiant de l'UDR ; le groupe actuel est `PO872880`. À confirmer dans le jeu de données historique des organes.
- **Limite des intitulés** : les amendements budgétaires ne disent pas leur sujet dans leur titre (« l'amendement n° 1234 de M. X après l'article 12… »). Aucun vote sur le prix des carburants n'est donc trouvable par le titre : il faudra croiser avec le jeu de données des **amendements** (qui contient leur objet).
- **Démo « Qui a voté ? »** publiée (page partageable) : 12 votes sur les retraites, la censure, l'agriculture (loi Duplomb), la police, la taxe Zucman, l'Ukraine, l'énergie, la fin de vie, la nationalité à Mayotte, les réseaux sociaux, la fast fashion et le budget de la Sécu. 9 groupes interrogés ; bonnes réponses réparties 5 pour, 5 contre, 2 abstention.

## À valider

- [x] Télécharger et analyser `Scrutins.json.zip` (17e) : fait, votes par groupe et par député disponibles (2026-09-25).
- [ ] Analyser `Dossiers_Legislatifs.json.zip` : étapes d'un texte, dates, auteurs (pour le suivi façon colis et « qui a proposé ? »).
- [ ] Croiser avec le jeu de données des amendements pour retrouver le sujet des amendements (carburants, etc.).
- [ ] Créer un compte PISTE et tester une recherche Légifrance sur une loi récente.
- [ ] Vérifier si NosDéputés couvre la 17e législature et si La Fabrique de la Loi est encore à jour.
- [ ] Repérer le jeu de données « résultats en temps réel » sur data.gouv.fr et son format (pour la présidentielle 2027).

## Sources

- [Assemblée nationale — open data](https://data.assemblee-nationale.fr/) · [Scrutins](https://data.assemblee-nationale.fr/travaux-parlementaires/votes) · [Dossiers législatifs](https://data.assemblee-nationale.fr/travaux-parlementaires/dossiers-legislatifs)
- [Sénat — data.senat.fr](https://data.senat.fr/)
- [API Légifrance (data.gouv.fr)](https://www.data.gouv.fr/dataservices/legifrance) · [Open data et API Légifrance](https://www.legifrance.gouv.fr/contenu/pied-de-page/open-data-et-api)
- [Élections — résultats (ministère de l'Intérieur)](https://www.elections.interieur.gouv.fr/resultats) · [Données des élections agrégées (data.gouv.fr)](https://www.data.gouv.fr/datasets/donnees-des-elections-agregees) · [resultat-elections.fr (réutilisation)](https://www.data.gouv.fr/reuses/resultat-elections-fr-carte-interactive-et-soiree-electorale-des-communes)
- [Présidentielle 2027 — dates (info.gouv.fr)](https://www.info.gouv.fr/actualite/presidentielle-2027-date-a-retenir-et-informations-cles)
- [API NosDéputés.fr](https://github.com/regardscitoyens/nosdeputes.fr/blob/master/doc/api.md) · [La Fabrique de la Loi](https://www.regardscitoyens.org/la-fabrique-de-la-loi/)
- [eurolens](https://github.com/tomrenard/eurolens) · [HowTheyVote data](https://github.com/HowTheyVote/data) · [Parlement européen — Open Data API](https://data.europarl.europa.eu/en/developer-corner/opendata-api)
