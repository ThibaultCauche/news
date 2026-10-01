# Séance de test J16 : écrans à contrôler

Les écrans ci-dessous n'ont pas été vus à l'écran pendant la revue du 2026-10-01 (Accueil, Agenda, Compétitions, Jeux, Profil, Réglages, page Valorant, page de ligue, fiche équipe, groupe d'amis et écran d'un match programmé ou terminé sont déjà vérifiés). Compter 20 minutes.

**Avant de commencer** : `pnpm dev` lancé, `adb reverse tcp:3000 tcp:3000`, `flutter run -d <appareil>` depuis `apps/mobile`.

## Points à regarder partout
- Titres de page et de section en Cinzel laiton, accents corrects (É, À, Ç).
- Le laiton ne remplace jamais l'or de « mon équipe / mes suivis », ni le rouge du direct, ni le vert de la victoire.
- Aucun contour gris resté sur une carte (les cartes ont le cadre fin à pointes).
- Aucun texte coupé ni débordement, sur un petit écran aussi (360 dp de large).
- Mouvement réduit activé (Android → Accessibilité) : rien ne bouge en continu.

## 1. Tampon « EN DIRECT » et match en direct
Prérequis : un match réellement en direct, sinon en créer un de test (`pnpm --filter @news/db exec prisma studio`, table `event`, ajouter un match `status = live` avec deux `event_participant` et des scores, **le supprimer ensuite** : le worker ne le met pas à jour).
- [ ] Écran du match : tampon « EN DIRECT » rouge avec point, légèrement incliné ; score en Cinzel.
- [ ] Accueil : bandeau en direct sur carte rouge, cadre rouge.
- [ ] Cadre renforcé (second filet) si le nom du match contient « final », « elimination » ou « decider ».

## 2. Grande finale
Prérequis : un match dont le nom contient « final », dans les 7 prochains jours (sinon en créer un comme ci-dessus).
- [ ] Accueil : carte « Grande finale » au cadre renforcé, bouton « M'alerter » en contour laiton.
- [ ] Écran du match : « Qui sera proclamé vainqueur ? » sous le nom de la compétition.

## 3. Onboarding (premier lancement)
Prérequis : effacer les données de l'appli (Android → Applications → Keryx → Stockage → Effacer les données), puis se reconnecter ensuite.
- [ ] Premier écran : monogramme et « KERYX » en tête, titre avec filet.
- [ ] Le bouton « Continuer » reste au même endroit d'un écran à l'autre.
- [ ] Case des jeux et tuiles de catégories au bon style.

## 4. Forum
Prérequis : `FORUM_OPEN=true` dans `.env` (redémarrer l'API), ou `app_user.forum_beta = true` pour le compte de test.
- [ ] Carte « Discussion » sous le match : cadre fin, titre en laiton.
- [ ] Fil de messages : réactions, champ d'envoi, curseur et soulignement en laiton.
- [ ] Fil « Direct » pendant un match en direct.
- [ ] Feuille de signalement et de modération : bord laiton, poignée laiton.

## 5. Glossaire et « pourquoi ce match compte »
- [ ] Sur un match à enjeu, toucher un mot souligné : feuille avec titre Cinzel laiton et bord laiton.
- [ ] Icône « ? » (laiton) sur la page jeu et l'écran d'un match.

## 6. Autres
- [ ] Écrans vides : monogramme atténué avec le message (Suivis sans match prévu, onglet sans donnée).
- [ ] Création de compte et connexion : boutons en contour laiton, aucune erreur technique à l'écran.
- [ ] Notification reçue : nom de l'appli « Keryx » dans la barre.
- [ ] Icône « Keryx » dans le lanceur d'applications (icône adaptative, mode icône thématique).

## Défauts trouvés
À noter ici au fil de la séance (écran, ce qui ne va pas, capture).

-
