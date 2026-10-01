# E-mails Firebase aux couleurs de Keryx (J16)

Trois modèles HTML à coller dans la console Firebase, **Authentication → Modèles** (Templates). Fond charbon, laiton `#B79B62`, capitales à empattement pour le titre, bouton en contour laiton. Un client de messagerie ne charge pas Cinzel : le titre retombe sur Georgia. Pas d'image (il faudrait l'héberger quelque part) : le logo est un « ◆ KERYX ◆ » en texte.

| Modèle Firebase | Fichier | Objet |
|---|---|---|
| Validation de l'adresse e-mail | `verification.html` | `Confirme ton adresse e-mail pour Keryx` |
| Réinitialisation du mot de passe | `reinitialisation.html` | `Nouveau mot de passe pour Keryx` |
| Modification de l'adresse e-mail | `changement-adresse.html` | `Ton adresse e-mail Keryx a changé` |

## Pas à pas

1. Console Firebase → **Authentication** → onglet **Modèles** → choisir le modèle.
2. Clic sur le crayon : **Nom de l'expéditeur** `Keryx`, **Objet** (colonne ci-dessus). Laisser « De » en `noreply@…firebaseapp.com`.
3. Remplacer le **Message** par le contenu du fichier (le champ accepte le HTML). Les marqueurs `%LINK%` et `%NEW_EMAIL%` sont remplacés par Firebase ; ne pas les modifier.
4. Enregistrer, puis s'envoyer un vrai e-mail (créer un compte de test, « mot de passe oublié ») et regarder le rendu dans Gmail, mobile compris.

Le modèle « Notification d'activation de l'authentification multifacteur » n'est pas utilisé (pas de double authentification).

## Limites

- Le lien ouvre la **page de validation hébergée par Firebase** (anglais/neutre, sans notre identité). La personnaliser demande de l'héberger nous-mêmes (Firebase Hosting ou un domaine) : reporté avec le nom de domaine.
- Les clients en mode sombre forcé (Gmail mobile) peuvent réajuster les couleurs. Le fond étant déjà sombre, l'écart reste faible.
- Une adresse d'expédition à notre nom (`@keryx…`) demande un domaine : reporté.
