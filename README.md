# News (nom de travail)

Une appli pour **suivre les événements qui comptent pour toi** — e-sport, sport, politique, streams… — et **comprendre où on en est en quelques secondes**, sans être noyé sous l'info.

Pensée pour les curieux qui veulent s'intéresser à une scène sans en être experts : arbre de tournoi lisible d'un coup d'œil, « pourquoi ce match compte » en une phrase, glossaire au toucher, mode sans spoil.

**Premier terrain de jeu : l'e-sport Valorant.**

Projet **open source, gratuit et non commercial**.

## Stack

Flutter · NestJS (TypeScript) · PostgreSQL · Redis · BullMQ · Firebase Cloud Messaging · Docker Compose

## Documentation

| Document | Contenu |
|---|---|
| [Vision et feuille de route](docs/00-vision-feuille-de-route.md) | Vision, principes, décisions |
| [Données — Valorant](docs/01-donnees-sources-valorant.md) | PandaScore, Liquipedia, tests |
| [Données — e-sport et sport](docs/01b-donnees-elargissement-esport-sport.md) | Autres jeux, sports, stratégie 100 % gratuite |
| [Données — politique](docs/01c-donnees-politique.md) | Open data Assemblée, Sénat, Légifrance, élections |
| [Maquettes](docs/02-design-maquettes-mobiles.md) | 26 écrans, tokens, mouvement |
| [Architecture](docs/03-architecture-backend.md) | Modèle de données, ingestion, API, notifications, hébergement |
| [Jalons](docs/04-jalons.md) | Plan de développement J1 → J7 |
| [Déploiement](docs/05-deploiement.md) | Mise en ligne : NAS, Tailscale Funnel, CI/CD, sauvegardes |
| [Politique de confidentialité](docs/politique-confidentialite.md) | Données collectées, sous-traitants, droits RGPD |

## Sources de données et crédits

Données e-sport : PandaScore. Contexte : Liquipedia (CC-BY-SA 3.0). Données publiques : Assemblée nationale, Sénat, Légifrance, ministère de l'Intérieur (Licence ouverte 2.0). Les logos d'équipes et de compétitions appartiennent à leurs propriétaires respectifs.

## Démarrer

À compléter au jalon J1.
