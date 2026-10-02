# J19 — Lot 3 : démarches et décisions

> Brouillons préparés par Claude le 2026-10-02. **Rien n'a été envoyé ni signé** : chaque point demande ton action. Cocher dans `docs/04` (J19, lot 3) une fois fait.

## C1 — Licence open source du code

Le projet est déclaré « open source, gratuit, non commercial » et n'a pas de fichier `LICENSE` : sans licence, le code est légalement **tous droits réservés**, même public.

| | MIT | AGPL-3.0 |
|---|---|---|
| Idée | Faire presque tout, y compris en code fermé | Tout dérivé, **même hébergé en service web**, doit rester ouvert |
| Pour | Simple, la plus répandue, aucun frein à l'adoption | Empêche qu'un tiers reprenne l'appli et son API en service fermé |
| Contre | Un tiers peut en faire un produit commercial fermé | Plus lourde ; certains contributeurs et les stores s'en méfient |
| Brique de l'appli | Compatible avec Flutter, NestJS, Prisma (toutes MIT/BSD/Apache) | Idem |

**Recommandation : MIT**, cohérente avec « gratuit, non commercial » et la simplicité. Si tu veux empêcher une reprise commerciale fermée, **AGPL-3.0**.
Attention, indépendamment du choix : la licence couvre **ton code**, pas les contenus tiers (logos d'équipes PandaScore, textes Liquipedia CC-BY-SA, polices Cinzel/Inter sous OFL, icône et nom « Keryx »). Les mentionner dans le README (« Crédits »).

À faire : choisir, puis je crée `LICENSE` (avec ton nom légal et l'année) et la section du README.

## C2 — Mail à PandaScore (usage du plan gratuit et attribution)

À envoyer depuis ton compte PandaScore. À compléter : `[nom]`, `[lien du dépôt]`.

> **Objet : Question sur l'usage du plan gratuit et l'attribution (appli open source non commerciale)**
>
> Bonjour,
>
> Je développe **Keryx**, une application mobile gratuite, open source et non commerciale, qui aide les curieux à suivre les compétitions e-sport (Valorant pour l'instant). Je l'alimente avec l'API PandaScore (plan gratuit) : l'application ne contacte jamais PandaScore directement, seul mon serveur le fait, avec un cache, et je surveille le quota (1 000 requêtes par heure).
>
> Avant d'ouvrir une bêta à quelques dizaines de testeurs, j'aimerais confirmer deux points :
> 1. L'usage du plan gratuit est-il bien autorisé pour une application publiée sur Google Play, gratuite et sans publicité ?
> 2. Quelle **attribution** exigez-vous (mention, logo, lien), et à quel endroit dans l'application ?
>
> Le code est ici : [lien du dépôt]. Merci d'avance pour votre réponse.
>
> [nom]

Ensuite : selon la réponse, ajouter l'attribution dans Réglages → Sources (déjà présent pour Liquipedia) ; je m'en charge.

## C3 — Marque et domaine « Keryx »

À vérifier toi-même (gratuit, 20 minutes) :
- **INPI** : base de recherche d'antériorités, classes 9 (logiciels, applications), 38 (communication) et 41 (divertissement). Chercher « Keryx », « Kerux », « Kéryx ».
- **EUIPO** : eSearch plus, mêmes classes.
- **Google Play et App Store** : chercher « Keryx » (nom d'application déjà pris ?).
- **Domaine** : `keryx.thibaultcauche.com` est déjà utilisé (voir C4). Un domaine à soi (`keryx.app`, `.fr`…) est à décider : pas nécessaire tant que Tailscale Funnel sert l'API.
Si une marque identique existe dans ces classes, le plan B du J16 est de changer le nom (les écrans se changent à un seul endroit : libellé Android, titre, textes d'onboarding).

## C4 — Modèles d'e-mails Firebase

Les modèles sont prêts dans `docs/emails/`. Il reste à voir si la vérification DNS de `keryx.thibaultcauche.com` (Namecheap) a débloqué le champ « Message » dans Firebase Console → Authentication → Modèles. **À faire** : te dire ce que la console affiche. Sinon, décision : garder les e-mails par défaut de Firebase (en anglais pour la page de validation) ou héberger notre propre page.

## C5 — Copie de sauvegarde hors site

Aujourd'hui : un `pg_dump` par nuit, 7 jours, **sur le NAS seulement**. Un incendie ou un vol du NAS emporte tout. Options, avec un ajout d'une ligne `rclone` dans `infra/backup/backup.sh` :

| Option | Coût | Remarque |
|---|---|---|
| **Backblaze B2** | ≈ 0 € (10 Go gratuits ; la base est petite) | Recommandé : compatible rclone, chiffrement possible |
| Disque USB chez un proche, rotation mensuelle | 0 € après achat | Manuel, risque d'oubli |
| Dossier sur un autre PC ou NAS via Tailscale | 0 € | Fonctionne tant que l'autre machine est allumée |

**Recommandation : Backblaze B2**, avec un compte et une clé d'application limitée au seul bucket de sauvegarde. À faire : créer le compte et le bucket ; je branche `rclone` et je teste une restauration depuis la copie. **Ne me donne jamais la clé dans le chat** : on la met dans `.env` sur le NAS.

## C6 — Bêta Google Play

À faire dans la Play Console : créer la fiche, la piste de **test interne** (jusqu'à 100 testeurs, sans validation longue), importer un `.aab` signé (`flutter build appbundle --release --dart-define=API_BASE_URL=...`).
À fournir pour la fiche : nom « Keryx », description courte (80 caractères) et longue, icône 512×512 (losange laiton, K), bandeau 1024×500, 2 à 8 captures, catégorie « Actualités et magazines » ou « Sports », **politique de confidentialité en ligne** (`docs/politique-confidentialite.md` doit être publiée sur une URL : page GitHub Pages ou le dépôt), formulaire de **sécurité des données** (e-mail, pseudo, jeton de notification, messages du forum), classification du contenu (forum = contenu généré par les utilisateurs).
Je prépare les textes et la liste des captures ; le téléversement et la clé de signature restent chez toi.

## C7 — Forum : avant l'ouverture publique

1. **Conditions d'utilisation** : relire `apps/mobile/lib/features/forum/forum_terms.dart` (version 1). Si le texte change, passer à la version 2 : les comptes revalident à la prochaine ouverture du forum.
2. **Contact de modération** : les conditions renvoient aujourd'hui vers « la fiche de l'application ». Il faut une adresse réelle. Proposition : une adresse dédiée (ex. `moderation@<ton domaine>`) ou, à défaut, « ouvrir une discussion sur le dépôt GitHub » (déjà la formule de la politique de confidentialité). À décider ; je mets le texte à jour.
3. **Exigences des stores pour le contenu généré par les utilisateurs** (Google Play) : filtrage des contenus (liens et mots interdits, en place), **signalement** (en place), **blocage** (en place), modération avec délai de réaction (journal en place), conditions acceptées à la première utilisation (en place). Reste à confirmer côté fiche Play : coche « l'application contient du contenu généré par les utilisateurs » et décrire le dispositif.

## C8 — Test avec 2-3 néophytes

Trouver 2-3 personnes qui **ne suivent pas Valorant**. Consigne : leur donner le téléphone, ne rien expliquer, leur demander de « comprendre où en est la compétition ». Observer sans aider, 15 minutes chacune.

| À noter | Question |
|---|---|
| Premier écran | Qu'ont-ils touché en premier ? Ont-ils compris « Aujourd'hui » ? |
| Onboarding | « Je ne connais pas Valorant » : utile ? Trop long ? |
| Un match | Savent-ils dire qui joue, quand, et ce que « BO3 » veut dire ? |
| Le guide | Ouvrent-ils « Comprendre les compétitions » ? Comprennent-ils Kickoff / Stage / Masters / Champions ? |
| Sans spoil | Trouvent-ils comment masquer un score ? |
| Blocages | Mot incompris, bouton cherché, écran abandonné |

Résultat à reporter dans `docs/04` (J19) : 3 lignes par personne, et les correctifs qui en sortent.
